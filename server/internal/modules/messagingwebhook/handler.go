package messagingwebhook

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	webhookauth "bim/server/internal/platform/webhook"
	"github.com/go-chi/chi/v5"
	"github.com/go-sql-driver/mysql"
)

type Publisher interface {
	Publish(context.Context, string, map[string]any) error
}
type Handler struct {
	db        *database.DB
	verifier  *webhookauth.Verifier
	publisher Publisher
	secret    string
}

func NewHandler(db *database.DB, verifier *webhookauth.Verifier, publisher Publisher, secret string) *Handler {
	return &Handler{db: db, verifier: verifier, publisher: publisher, secret: secret}
}
func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Post("/wukong", h.wukong)
	router.Post("/wukong/{secret}", h.wukongNative)
	return router
}

func (h *Handler) wukong(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 2<<20))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_WEBHOOK", "回调内容无效")
		return
	}
	if err := h.verifier.Verify(r.Context(), r.Header.Get("X-BIM-Timestamp"), r.Header.Get("X-BIM-Nonce"), r.Header.Get("X-BIM-Signature"), body); err != nil {
		httpx.Error(w, r, http.StatusUnauthorized, "WEBHOOK_UNAUTHORIZED", "回调校验失败")
		return
	}
	var event struct {
		EventID   string         `json:"event_id"`
		EventType string         `json:"event_type"`
		Message   map[string]any `json:"message"`
	}
	if err := json.Unmarshal(body, &event); err != nil || strings.TrimSpace(event.EventID) == "" || strings.TrimSpace(event.EventType) == "" {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_WEBHOOK", "回调格式无效")
		return
	}
	duplicate, err := h.store(r.Context(), event.EventID, event.EventType, body, event.Message)
	if err != nil {
		httpx.Error(w, r, http.StatusInternalServerError, "WEBHOOK_STORE_FAILED", "回调处理失败")
		return
	}
	if !duplicate && h.publisher != nil {
		_ = h.publisher.Publish(r.Context(), event.EventType, event.Message)
	}
	httpx.OK(w, r, map[string]bool{"duplicate": duplicate})
}

func (h *Handler) store(ctx context.Context, eventID, eventType string, body []byte, message map[string]any) (bool, error) {
	duplicate := false
	err := h.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		_, err := tx.ExecContext(ctx, `INSERT INTO webhook_events(provider,event_id,event_type,payload_json,status,created_at,updated_at) VALUES('wukong',?,?,?,'processed',?,?)`, eventID, eventType, json.RawMessage(body), now, now)
		if err != nil {
			if isDuplicate(err) {
				duplicate = true
				return nil
			}
			return err
		}
		clientMsgNo, _ := message["client_msg_no"].(string)
		if clientMsgNo != "" {
			messageID := stringValue(message["message_idstr"])
			seq := uint64Value(message["message_seq"])
			_, err = tx.ExecContext(ctx, `UPDATE messages SET message_id=COALESCE(NULLIF(?,''),message_id),message_seq=GREATEST(?,message_seq),status='sent',sent_at=COALESCE(sent_at,?),updated_at=? WHERE client_msg_no=?`, messageID, seq, now, now, clientMsgNo)
		}
		return err
	})
	return duplicate, err
}
func isDuplicate(err error) bool {
	var mysqlErr *mysql.MySQLError
	return errors.As(err, &mysqlErr) && mysqlErr.Number == 1062
}
func stringValue(value any) string {
	if result, ok := value.(string); ok {
		return result
	}
	return ""
}
func uint64Value(value any) uint64 {
	switch typed := value.(type) {
	case float64:
		return uint64(typed)
	case json.Number:
		v, _ := typed.Int64()
		return uint64(v)
	}
	return 0
}
