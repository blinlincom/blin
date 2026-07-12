package authn

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Claims struct {
	Subject        uint64 `json:"sub"`
	AppID          uint64 `json:"app_id"`
	SessionID      string `json:"sid"`
	Platform       string `json:"platform"`
	DeviceID       string `json:"device_id"`
	SessionVersion uint64 `json:"session_version"`
	IssuedAt       int64  `json:"iat"`
	ExpiresAt      int64  `json:"exp"`
	Type           string `json:"type"`
}

type TokenManager struct {
	key []byte
	now func() time.Time
}

func NewTokenManager(key string) (*TokenManager, error) {
	if len(key) < 32 {
		return nil, errors.New("token signing key must contain at least 32 bytes")
	}
	return &TokenManager{key: []byte(key), now: time.Now}, nil
}

func (m *TokenManager) Issue(claims Claims, ttl time.Duration) (string, error) {
	if claims.Subject == 0 || claims.SessionID == "" || ttl <= 0 {
		return "", errors.New("invalid token claims")
	}
	now := m.now().UTC()
	claims.IssuedAt, claims.ExpiresAt = now.Unix(), now.Add(ttl).Unix()
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("encode token: %w", err)
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	return encoded + "." + m.sign(encoded), nil
}

func (m *TokenManager) Parse(token, expectedType string) (Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 || !hmac.Equal([]byte(m.sign(parts[0])), []byte(parts[1])) {
		return Claims{}, errors.New("invalid token signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return Claims{}, errors.New("invalid token payload")
	}
	var claims Claims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return Claims{}, errors.New("invalid token claims")
	}
	if claims.Type != expectedType || claims.ExpiresAt <= m.now().UTC().Unix() {
		return Claims{}, errors.New("token expired or type mismatch")
	}
	return claims, nil
}

func (m *TokenManager) NewSessionID() (string, error) {
	var raw [24]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw[:]), nil
}

func (m *TokenManager) sign(value string) string {
	mac := hmac.New(sha256.New, m.key)
	_, _ = mac.Write([]byte(value))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
