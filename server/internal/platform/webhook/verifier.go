package webhook

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/platform/redisx"
)

var ErrUnauthorized = errors.New("webhook authentication failed")

type Verifier struct {
	secret []byte
	window time.Duration
	redis  *redisx.Client
	now    func() time.Time
}

func NewVerifier(secret string, window time.Duration, redis *redisx.Client) *Verifier {
	return &Verifier{secret: []byte(secret), window: window, redis: redis, now: time.Now}
}

func (v *Verifier) Verify(ctx context.Context, timestamp, nonce, signature string, body []byte) error {
	seconds, err := strconv.ParseInt(strings.TrimSpace(timestamp), 10, 64)
	if err != nil || strings.TrimSpace(nonce) == "" || len(nonce) > 128 {
		return ErrUnauthorized
	}
	eventTime := time.Unix(seconds, 0)
	delta := v.now().UTC().Sub(eventTime)
	if delta < 0 {
		delta = -delta
	}
	if delta > v.window {
		return ErrUnauthorized
	}
	mac := hmac.New(sha256.New, v.secret)
	_, _ = mac.Write([]byte(timestamp))
	_, _ = mac.Write([]byte("\n"))
	_, _ = mac.Write([]byte(nonce))
	_, _ = mac.Write([]byte("\n"))
	_, _ = mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	provided := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(signature)), "sha256=")
	if !hmac.Equal([]byte(expected), []byte(provided)) {
		return ErrUnauthorized
	}
	if v.redis != nil {
		key := v.redis.Key("webhook", "nonce", nonce)
		ok, err := v.redis.SetNX(ctx, key, "1", v.window).Result()
		if err != nil {
			return fmt.Errorf("reserve webhook nonce: %w", err)
		}
		if !ok {
			return ErrUnauthorized
		}
	}
	return nil
}
