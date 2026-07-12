package authn

import (
	"strings"
	"testing"
	"time"
)

func TestTokenLifecycle(t *testing.T) {
	manager, err := NewTokenManager(strings.Repeat("k", 32))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 7, 12, 0, 0, 0, 0, time.UTC)
	manager.now = func() time.Time { return now }
	token, err := manager.Issue(Claims{Subject: 1, SessionID: "session", Type: "access"}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := manager.Parse(token, "access")
	if err != nil {
		t.Fatal(err)
	}
	if claims.Subject != 1 || claims.ExpiresAt != now.Add(time.Hour).Unix() {
		t.Fatalf("claims=%+v", claims)
	}
	if _, err := manager.Parse(token+"x", "access"); err == nil {
		t.Fatal("tampered token accepted")
	}
}
