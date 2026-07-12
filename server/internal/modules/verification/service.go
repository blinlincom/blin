package verification

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
)

var (
	ErrInvalidChallenge = errors.New("invalid verification challenge")
	phonePattern        = regexp.MustCompile(`^\+?[1-9][0-9]{6,14}$`)
	emailPattern        = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)
)

type Service struct {
	db     *database.DB
	secret []byte
	config config.VerificationConfig
	http   *http.Client
}

type Captcha struct {
	ID           uint64 `json:"id"`
	ImageDataURI string `json:"image_data_uri"`
	ExpiresIn    int64  `json:"expires_in"`
}

func NewService(db *database.DB, secret string, cfg config.VerificationConfig) *Service {
	return &Service{db: db, secret: []byte(secret), config: cfg, http: &http.Client{Timeout: 5 * time.Second}}
}

func (s *Service) CreateCaptcha(ctx context.Context, appID uint64) (Captcha, error) {
	code, err := randomCode("ABCDEFGHJKLMNPQRSTUVWXYZ23456789", 5)
	if err != nil {
		return Captcha{}, err
	}
	ttl := s.config.CaptchaTTL.Value()
	if ttl <= 0 {
		ttl = 2 * time.Minute
	}
	result, err := s.db.ExecContext(ctx, `INSERT INTO verification_challenges(app_id,scene,target,code_hash,max_attempts,expire_at,created_at) VALUES(?,'captcha','',?,5,?,NOW(6))`, appID, s.hash("captcha", code), time.Now().UTC().Add(ttl))
	if err != nil {
		return Captcha{}, err
	}
	id, err := result.LastInsertId()
	if err != nil {
		return Captcha{}, err
	}
	svg := `<svg xmlns="http://www.w3.org/2000/svg" width="180" height="64" viewBox="0 0 180 64"><rect width="180" height="64" fill="#f3f5f7"/><path d="M4 12L176 51M11 57L169 8M2 34L178 26" stroke="#c5ccd3" stroke-width="1"/><text x="90" y="42" text-anchor="middle" font-family="monospace" font-size="30" font-weight="700" letter-spacing="7" fill="#18212b">` + html.EscapeString(code) + `</text></svg>`
	return Captcha{ID: uint64(id), ImageDataURI: "data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(svg)), ExpiresIn: int64(ttl.Seconds())}, nil
}

func (s *Service) SendCode(ctx context.Context, appID uint64, scene, target string, captchaID uint64, captchaCode string) (uint64, error) {
	scene = strings.TrimSpace(scene)
	target = strings.TrimSpace(target)
	if err := s.Verify(ctx, appID, captchaID, "captcha", "", captchaCode); err != nil {
		return 0, err
	}
	if !validTarget(target) || !allowedScene(scene) {
		return 0, ErrInvalidChallenge
	}
	code, err := randomCode("0123456789", 6)
	if err != nil {
		return 0, err
	}
	if err := s.deliver(ctx, scene, target, code); err != nil {
		return 0, err
	}
	ttl := s.config.CodeTTL.Value()
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	result, err := s.db.ExecContext(ctx, `INSERT INTO verification_challenges(app_id,scene,target,code_hash,max_attempts,expire_at,created_at) VALUES(?,?,?,?,5,?,NOW(6))`, appID, scene, target, s.hash(scene+":"+target, code), time.Now().UTC().Add(ttl))
	if err != nil {
		return 0, err
	}
	id, err := result.LastInsertId()
	return uint64(id), err
}

func (s *Service) Verify(ctx context.Context, appID, id uint64, scene, target, code string) error {
	if id == 0 || strings.TrimSpace(code) == "" {
		return ErrInvalidChallenge
	}
	return s.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		var expected string
		var attempts, maxAttempts int
		var expires time.Time
		var consumed sql.NullTime
		err := tx.QueryRowContext(ctx, `SELECT code_hash,attempts,max_attempts,expire_at,consumed_at FROM verification_challenges WHERE id=? AND app_id=? AND scene=? AND target=? FOR UPDATE`, id, appID, scene, target).Scan(&expected, &attempts, &maxAttempts, &expires, &consumed)
		if err != nil {
			return ErrInvalidChallenge
		}
		if consumed.Valid || attempts >= maxAttempts || expires.Before(time.Now().UTC()) {
			return ErrInvalidChallenge
		}
		actual := s.hash(scene+func() string {
			if target == "" {
				return ""
			}
			return ":" + target
		}(), strings.TrimSpace(code))
		if !hmac.Equal([]byte(expected), []byte(actual)) {
			_, _ = tx.ExecContext(ctx, `UPDATE verification_challenges SET attempts=attempts+1 WHERE id=?`, id)
			return ErrInvalidChallenge
		}
		_, err = tx.ExecContext(ctx, `UPDATE verification_challenges SET consumed_at=NOW(6) WHERE id=? AND consumed_at IS NULL`, id)
		return err
	})
}

func (s *Service) deliver(ctx context.Context, scene, target, code string) error {
	if strings.TrimSpace(s.config.ProviderURL) == "" {
		return fmt.Errorf("verification provider is not configured")
	}
	body, _ := json.Marshal(map[string]string{"scene": scene, "target": target, "code": code})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.config.ProviderURL, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.config.ProviderToken)
	resp, err := s.http.Do(req)
	if err != nil {
		return fmt.Errorf("send verification code: %w", err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("verification provider status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return nil
}

func (s *Service) hash(scope, code string) string {
	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte(scope))
	mac.Write([]byte{0})
	mac.Write([]byte(strings.ToUpper(strings.TrimSpace(code))))
	return hex.EncodeToString(mac.Sum(nil))
}
func randomCode(alphabet string, n int) (string, error) {
	raw := make([]byte, n)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	for i := range raw {
		raw[i] = alphabet[int(raw[i])%len(alphabet)]
	}
	return string(raw), nil
}
func validTarget(v string) bool { return phonePattern.MatchString(v) || emailPattern.MatchString(v) }
func allowedScene(v string) bool {
	switch v {
	case "login", "register", "bind_phone", "bind_email", "reset_password", "payment_password":
		return true
	}
	return false
}
