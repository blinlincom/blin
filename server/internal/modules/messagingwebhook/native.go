package messagingwebhook

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

// wukongNative accepts WuKongIM's native webhook contract. WuKongIM does not
// attach application HMAC headers, so a high-entropy path secret is verified
// in constant time and TLS protects it in transit.
func (h *Handler) wukongNative(w http.ResponseWriter, r *http.Request) {
	provided := chi.URLParam(r, "secret")
	if len(provided) != len(h.secret) || subtle.ConstantTimeCompare([]byte(provided), []byte(h.secret)) != 1 {
		httpx.Error(w, r, http.StatusUnauthorized, "WEBHOOK_UNAUTHORIZED", "回调校验失败")
		return
	}
	eventType := strings.TrimSpace(r.URL.Query().Get("event"))
	if eventType != "msg.notify" && eventType != "msg.offline" && eventType != "user.onlinestatus" {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_WEBHOOK_EVENT", "回调事件无效")
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 2<<20))
	if err != nil || len(body) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_WEBHOOK", "回调内容无效")
		return
	}
	var decoded any
	if json.Unmarshal(body, &decoded) != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_WEBHOOK", "回调格式无效")
		return
	}
	decoded = unwrapNativeData(decoded)
	if eventType == "user.onlinestatus" {
		h.handleNativePresence(r, eventType, body, decoded)
	} else {
		h.handleNativeMessages(r, eventType, body, decoded)
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func (h *Handler) handleNativePresence(r *http.Request, eventType string, body []byte, decoded any) {
	items, _ := decoded.([]any)
	for _, raw := range items {
		item, ok := raw.(string)
		if !ok {
			continue
		}
		presence := nativePresence(item)
		if len(presence) == 0 {
			continue
		}
		h.storeNative(r, eventType, body, presence)
		if h.publisher != nil {
			_ = h.publisher.Publish(r.Context(), "presence", presence)
		}
	}
}

func (h *Handler) handleNativeMessages(r *http.Request, eventType string, body []byte, decoded any) {
	for _, message := range nativeMessageItems(decoded) {
		normalized := normalizeNativeMessage(message)
		if stringValue(normalized["client_msg_no"]) == "" && stringValue(normalized["message_id"]) == "" {
			continue
		}
		h.storeNative(r, eventType, body, normalized)
		if h.publisher != nil {
			_ = h.publisher.Publish(r.Context(), eventType, normalized)
		}
	}
}

func (h *Handler) storeNative(r *http.Request, eventType string, body []byte, message map[string]any) {
	sum := sha256.Sum256(append([]byte(eventType+"\n"), body...))
	_, _ = h.store(r.Context(), fmt.Sprintf("%x", sum[:]), eventType, body, message)
}

func unwrapNativeData(value any) any {
	if object, ok := value.(map[string]any); ok {
		if data, exists := object["data"]; exists {
			return data
		}
	}
	return value
}

func nativeMessageItems(value any) []map[string]any {
	if object, ok := value.(map[string]any); ok {
		if messages, exists := object["messages"].([]any); exists {
			value = messages
		} else {
			return []map[string]any{object}
		}
	}
	list, _ := value.([]any)
	result := make([]map[string]any, 0, len(list))
	for _, item := range list {
		if object, ok := item.(map[string]any); ok {
			result = append(result, object)
		}
	}
	return result
}

func nativePresence(item string) map[string]any {
	parts := strings.Split(item, "-")
	if len(parts) < 6 {
		return nil
	}
	appID, userID := parseNativeUID(parts[0])
	if appID == 0 || userID == 0 {
		return nil
	}
	return map[string]any{
		"app_id": appID, "presence_user_id": userID, "uid": parts[0],
		"device_flag": parts[1], "online": parts[2] == "1", "conn_id": parts[3],
		"device_online_count": parts[4], "total_online_count": parts[5],
		"timestamp": time.Now().UnixMilli(),
	}
}

func normalizeNativeMessage(message map[string]any) map[string]any {
	result := map[string]any{}
	if encoded, ok := message["payload"].(string); ok {
		if raw, err := base64.StdEncoding.DecodeString(encoded); err == nil {
			_ = json.Unmarshal(raw, &result)
		}
	}
	for key, value := range message {
		if key != "payload" {
			result[key] = value
		}
	}
	result["message_id"] = stringValue(message["message_idstr"])
	if result["message_id"] == "" {
		result["message_id"] = stringValue(message["message_id"])
	}
	appID, senderID := parseNativeUID(stringValue(message["from_uid"]))
	result["app_id"], result["sender_id"] = appID, senderID
	if uint64Value(message["channel_type"]) == 1 {
		_, receiverID := parseNativeUID(stringValue(message["channel_id"]))
		result["receiver_id"] = receiverID
	}
	return result
}

func parseNativeUID(uid string) (uint64, uint64) {
	var appID, userID uint64
	if _, err := fmt.Sscanf(uid, "app%duser%d", &appID, &userID); err != nil {
		return 0, 0
	}
	return appID, userID
}
