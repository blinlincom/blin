package identity

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"bim/server/internal/platform/authn"
)

func TestRegisterHandlerRejectsUnknownFields(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	handler := NewHandler(NewService(newMemoryRepository(), tokens)).Routes()
	request := httptest.NewRequest(http.MethodPost, "/register", bytes.NewBufferString(`{"app_id":1,"username":"alice_01","password":"safe-password","platform":"android","device_id":"phone","admin":true}`))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestRegisterHandlerReturnsTokenPair(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	handler := NewHandler(NewService(newMemoryRepository(), tokens)).Routes()
	payload := map[string]any{"app_id": 1, "username": "alice_01", "nickname": "Alice", "password": "safe-password", "platform": "android", "device_id": "phone"}
	body, _ := json.Marshal(payload)
	request := httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "access_token") {
		t.Fatalf("body=%s", response.Body.String())
	}
}

func TestProtectedIdentityRoutesRequireBearerToken(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	handler := NewHandler(NewService(newMemoryRepository(), tokens)).Routes()
	request := httptest.NewRequest(http.MethodGet, "/me", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}
