package adminauth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"bim/server/internal/platform/authn"
)

var ErrUnauthorized = errors.New("admin unauthorized")

type Admin struct {
	ID             uint64   `json:"id"`
	Username       string   `json:"username"`
	PasswordHash   string   `json:"-"`
	Status         uint8    `json:"-"`
	SessionVersion uint64   `json:"-"`
	Permissions    []string `json:"permissions"`
}
type Session struct {
	ID                      string
	AdminID, SessionVersion uint64
	RefreshHash             string
	ExpiresAt               time.Time
}
type Repository interface {
	FindByUsername(context.Context, string) (Admin, error)
	FindByID(context.Context, uint64) (Admin, error)
	CreateSession(context.Context, Session) error
	FindSession(context.Context, string) (Session, error)
	RotateSession(context.Context, string, string, time.Time) error
	RevokeSession(context.Context, string) error
	CreateSuperAdmin(context.Context, string, string) error
}
type Service struct {
	repository Repository
	tokens     *authn.TokenManager
	password   authn.PasswordPolicy
	now        func() time.Time
}
type LoginResult struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
	Admin        Admin     `json:"admin"`
}
type Principal struct {
	Admin     Admin
	SessionID string
}

func NewService(repository Repository, tokens *authn.TokenManager) *Service {
	return &Service{repository: repository, tokens: tokens, password: authn.DefaultPasswordPolicy(), now: time.Now}
}
func (s *Service) Login(ctx context.Context, username, password string) (LoginResult, error) {
	admin, err := s.repository.FindByUsername(ctx, strings.ToLower(strings.TrimSpace(username)))
	if err != nil {
		return LoginResult{}, ErrUnauthorized
	}
	ok, err := s.password.Verify(admin.PasswordHash, password)
	if err != nil || !ok || admin.Status != 1 {
		return LoginResult{}, ErrUnauthorized
	}
	sessionID, err := s.tokens.NewSessionID()
	if err != nil {
		return LoginResult{}, err
	}
	refresh, hash, err := adminRefresh(sessionID)
	if err != nil {
		return LoginResult{}, err
	}
	session := Session{ID: sessionID, AdminID: admin.ID, SessionVersion: admin.SessionVersion, RefreshHash: hash, ExpiresAt: s.now().UTC().Add(12 * time.Hour)}
	if err := s.repository.CreateSession(ctx, session); err != nil {
		return LoginResult{}, err
	}
	expires := s.now().UTC().Add(15 * time.Minute)
	access, err := s.tokens.Issue(authn.Claims{Subject: admin.ID, SessionID: sessionID, SessionVersion: admin.SessionVersion, Type: "admin_access"}, 15*time.Minute)
	if err != nil {
		return LoginResult{}, err
	}
	return LoginResult{AccessToken: access, RefreshToken: refresh, ExpiresAt: expires, Admin: admin}, nil
}
func (s *Service) Authenticate(ctx context.Context, token string) (Principal, error) {
	claims, err := s.tokens.Parse(token, "admin_access")
	if err != nil {
		return Principal{}, ErrUnauthorized
	}
	session, err := s.repository.FindSession(ctx, claims.SessionID)
	if err != nil || session.AdminID != claims.Subject || session.SessionVersion != claims.SessionVersion || session.ExpiresAt.Before(s.now().UTC()) {
		return Principal{}, ErrUnauthorized
	}
	admin, err := s.repository.FindByID(ctx, claims.Subject)
	if err != nil || admin.Status != 1 || admin.SessionVersion != claims.SessionVersion {
		return Principal{}, ErrUnauthorized
	}
	return Principal{Admin: admin, SessionID: session.ID}, nil
}
func (s *Service) Refresh(ctx context.Context, refreshToken string) (LoginResult, error) {
	parts := strings.SplitN(strings.TrimSpace(refreshToken), ".", 2)
	if len(parts) != 2 {
		return LoginResult{}, ErrUnauthorized
	}
	session, err := s.repository.FindSession(ctx, parts[0])
	if err != nil || session.RefreshHash != hashAdminToken(refreshToken) || session.ExpiresAt.Before(s.now().UTC()) {
		return LoginResult{}, ErrUnauthorized
	}
	admin, err := s.repository.FindByID(ctx, session.AdminID)
	if err != nil || admin.Status != 1 || admin.SessionVersion != session.SessionVersion {
		return LoginResult{}, ErrUnauthorized
	}
	next, nextHash, err := adminRefresh(session.ID)
	if err != nil {
		return LoginResult{}, err
	}
	if err := s.repository.RotateSession(ctx, session.ID, nextHash, s.now().UTC().Add(12*time.Hour)); err != nil {
		return LoginResult{}, ErrUnauthorized
	}
	expires := s.now().UTC().Add(15 * time.Minute)
	access, err := s.tokens.Issue(authn.Claims{Subject: admin.ID, SessionID: session.ID, SessionVersion: admin.SessionVersion, Type: "admin_access"}, 15*time.Minute)
	if err != nil {
		return LoginResult{}, err
	}
	return LoginResult{AccessToken: access, RefreshToken: next, ExpiresAt: expires, Admin: admin}, nil
}
func (s *Service) Logout(ctx context.Context, sessionID string) error {
	return s.repository.RevokeSession(ctx, sessionID)
}
func (s *Service) CreateSuperAdmin(ctx context.Context, username, password string) error {
	username = strings.ToLower(strings.TrimSpace(username))
	if len(username) < 5 || len(password) < 12 {
		return errors.New("admin username or password is too weak")
	}
	hash, err := s.password.Hash(password)
	if err != nil {
		return err
	}
	return s.repository.CreateSuperAdmin(ctx, username, hash)
}
func adminRefresh(sessionID string) (string, string, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", "", err
	}
	token := sessionID + "." + base64.RawURLEncoding.EncodeToString(raw[:])
	sum := sha256.Sum256([]byte(token))
	return token, hex.EncodeToString(sum[:]), nil
}
func hashAdminToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
