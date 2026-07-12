package webhook

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"
)

func TestVerifierAcceptsValidSignatureAndRejectsTamper(t *testing.T) {
	secret := "01234567890123456789012345678901"
	now := time.Unix(1700000000, 0)
	v := NewVerifier(secret, 5*time.Minute, nil)
	v.now = func() time.Time { return now }
	body := []byte(`{"event":"message"}`)
	timestamp := "1700000000"
	nonce := "nonce-1"
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(timestamp + "\n" + nonce + "\n"))
	mac.Write(body)
	signature := hex.EncodeToString(mac.Sum(nil))
	if err := v.Verify(context.Background(), timestamp, nonce, signature, body); err != nil {
		t.Fatal(err)
	}
	if err := v.Verify(context.Background(), timestamp, nonce, signature, []byte(`{}`)); err == nil {
		t.Fatal("tampered body accepted")
	}
}
