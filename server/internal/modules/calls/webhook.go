package calls

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"

	"bim/server/internal/platform/httpx"
	"github.com/golang-jwt/jwt/v5"
)

type WebhookHandler struct {
	service *Service
}

func NewWebhookHandler(service *Service) *WebhookHandler {
	return &WebhookHandler{service: service}
}

func (h *WebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	event, err := h.verify(r)
	if err != nil {
		httpx.Error(w, r, http.StatusUnauthorized, "LIVEKIT_WEBHOOK_INVALID", "回调校验失败")
		return
	}
	room := event.Room.Name
	if room == "" {
		httpx.OK(w, r, map[string]bool{"accepted": true})
		return
	}
	var appID, initiator uint64
	var callNo string
	if err := h.service.db.QueryRowContext(r.Context(), `SELECT app_id,call_no,initiator_id FROM call_sessions WHERE room_name=?`, room).Scan(&appID, &callNo, &initiator); err != nil {
		httpx.OK(w, r, map[string]bool{"ignored": true})
		return
	}
	switch event.Event {
	case "participant_joined":
		if userID := liveKitUserID(appID, event.Participant.Identity); userID > 0 && userID != initiator {
			_, _ = h.service.Accept(r.Context(), appID, userID, callNo)
		}
	case "room_finished":
		_, _ = h.service.End(r.Context(), appID, initiator, callNo, "room_finished")
	}
	httpx.OK(w, r, map[string]bool{"accepted": true})
}

type liveKitWebhookEvent struct {
	Event string `json:"event"`
	Room  struct {
		Name string `json:"name"`
	} `json:"room"`
	Participant struct {
		Identity string `json:"identity"`
	} `json:"participant"`
}

func (h *WebhookHandler) verify(r *http.Request) (liveKitWebhookEvent, error) {
	var event liveKitWebhookEvent
	data, err := io.ReadAll(http.MaxBytesReader(nil, r.Body, 1<<20))
	if err != nil {
		return event, err
	}
	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(r.Header.Get("Authorization"), claims, func(token *jwt.Token) (any, error) {
		return []byte(h.service.config.APISecret), nil
	}, jwt.WithValidMethods([]string{"HS256"}), jwt.WithIssuer(h.service.config.APIKey))
	if err != nil || !token.Valid {
		return event, jwt.ErrSignatureInvalid
	}
	expected, _ := claims["sha256"].(string)
	sum := sha256.Sum256(data)
	actual := base64.StdEncoding.EncodeToString(sum[:])
	if subtle.ConstantTimeCompare([]byte(expected), []byte(actual)) != 1 {
		return event, jwt.ErrSignatureInvalid
	}
	if err := json.Unmarshal(data, &event); err != nil {
		return event, err
	}
	return event, nil
}

func liveKitUserID(appID uint64, identity string) uint64 {
	prefix := "app" + strconv.FormatUint(appID, 10) + "user"
	if !strings.HasPrefix(identity, prefix) {
		return 0
	}
	id, _ := strconv.ParseUint(strings.TrimPrefix(identity, prefix), 10, 64)
	return id
}
