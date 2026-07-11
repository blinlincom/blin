package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"bim/tron-wallet/internal/tron"
)

type server struct {
	secret string
	seed   []byte
}

type deriveRequest struct {
	AppID  uint32 `json:"appid"`
	UserID uint32 `json:"user_id"`
}

type validateRequest struct {
	Address string `json:"address"`
}

func main() {
	listen := env("TRON_WALLET_LISTEN", "127.0.0.1:9088")
	secret := strings.TrimSpace(os.Getenv("TRON_INTERNAL_SECRET"))
	if len(secret) < 32 {
		log.Fatal("TRON_INTERNAL_SECRET must contain at least 32 characters")
	}
	var seed []byte
	if raw := strings.TrimSpace(os.Getenv("TRON_MASTER_SEED_HEX")); raw != "" {
		parsed, err := tron.ParseSeed(raw)
		if err != nil {
			log.Fatal(err)
		}
		seed = parsed
	}
	s := &server{secret: secret, seed: seed}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("POST /internal/address/derive", s.auth(s.derive))
	mux.HandleFunc("POST /internal/address/validate", s.auth(s.validate))
	httpServer := &http.Server{
		Addr:              listen,
		Handler:           requestLimit(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       8 * time.Second,
		WriteTimeout:      8 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("tron wallet service listening on %s (address derivation enabled=%t)", listen, len(seed) > 0)
	log.Fatal(httpServer.ListenAndServe())
}

func (s *server) validate(w http.ResponseWriter, r *http.Request, body []byte) {
	var request validateRequest
	if err := json.Unmarshal(body, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid validate request"})
		return
	}
	hexAddress, err := tron.ValidateAddress(strings.TrimSpace(request.Address))
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"valid": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"valid": true, "address_hex": hexAddress})
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "address_derivation_enabled": len(s.seed) > 0})
}

func (s *server) derive(w http.ResponseWriter, r *http.Request, body []byte) {
	if len(s.seed) == 0 {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "address derivation is not configured"})
		return
	}
	var request deriveRequest
	if err := json.Unmarshal(body, &request); err != nil || request.AppID == 0 || request.UserID == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid derive request"})
		return
	}
	result, err := tron.Derive(s.seed, request.AppID, request.UserID)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *server) auth(next func(http.ResponseWriter, *http.Request, []byte)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(io.LimitReader(r.Body, 64<<10))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid body"})
			return
		}
		timestamp := r.Header.Get("X-BIM-Timestamp")
		signature := strings.ToLower(strings.TrimSpace(r.Header.Get("X-BIM-Signature")))
		unix, err := strconv.ParseInt(timestamp, 10, 64)
		if err != nil || abs(time.Now().Unix()-unix) > 30 {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "expired request"})
			return
		}
		mac := hmac.New(sha256.New, []byte(s.secret))
		_, _ = fmt.Fprintf(mac, "%s\n%s", timestamp, body)
		expected := hex.EncodeToString(mac.Sum(nil))
		if !hmac.Equal([]byte(expected), []byte(signature)) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "invalid signature"})
			return
		}
		next(w, r, body)
	}
}

func requestLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ContentLength > 64<<10 {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]any{"error": "request too large"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func abs(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}

var _ = errors.New
