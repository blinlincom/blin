package adminmoments

import (
	"bim/server/internal/modules/adminauth"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"database/sql"
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
	"strconv"
	"strings"
)

type Handler struct{ db *database.DB }

func NewHandler(db *database.DB) *Handler { return &Handler{db: db} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.With(adminauth.Require("moment:read")).Get("/", h.list)
	r.With(adminauth.Require("moment:moderate")).Post("/{id}/decision", h.decision)
	return r
}
func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	if status == "" {
		status = "pending"
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT m.id,m.user_id,u.username,u.nickname,m.content,m.media_json,m.visibility,m.status,m.review_reason,m.created_at FROM moments m JOIN users u ON u.id=m.user_id WHERE m.app_id=? AND m.status=? AND m.deleted_at IS NULL ORDER BY m.id DESC LIMIT 200`, 1, status)
	if err != nil {
		httpx.Error(w, r, 500, "MOMENT_LIST_FAILED", "动态列表加载失败")
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, userID uint64
		var username, nickname, content, visibility, state, reason string
		var media []byte
		var created any
		if err := rows.Scan(&id, &userID, &username, &nickname, &content, &media, &visibility, &state, &reason, &created); err != nil {
			httpx.Error(w, r, 500, "MOMENT_LIST_FAILED", "动态列表加载失败")
			return
		}
		var mediaValue any
		_ = json.Unmarshal(media, &mediaValue)
		items = append(items, map[string]any{"id": id, "user_id": userID, "username": username, "nickname": nickname, "content": content, "media": mediaValue, "visibility": visibility, "status": state, "review_reason": reason, "created_at": created})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) decision(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, r, 400, "INVALID_ID", "动态编号无效")
		return
	}
	var q struct {
		Approve bool   `json:"approve"`
		Reason  string `json:"reason"`
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	d.DisallowUnknownFields()
	if d.Decode(&q) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return
	}
	q.Reason = strings.TrimSpace(q.Reason)
	if !q.Approve && len([]rune(q.Reason)) < 2 {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "拒绝时必须填写原因")
		return
	}
	p, _ := adminauth.PrincipalFromContext(r.Context())
	status := "rejected"
	if q.Approve {
		status = "published"
	}
	err = h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var before string
		if err := tx.QueryRowContext(r.Context(), `SELECT status FROM moments WHERE id=? AND status='pending' FOR UPDATE`, id).Scan(&before); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE moments SET status=?,review_reason=?,reviewed_by=?,reviewed_at=NOW(6),updated_at=NOW(6) WHERE id=?`, status, q.Reason, p.Admin.ID, id); err != nil {
			return err
		}
		beforeJSON, _ := json.Marshal(map[string]any{"status": before})
		afterJSON, _ := json.Marshal(map[string]any{"status": status, "reason": q.Reason})
		_, err := tx.ExecContext(r.Context(), `INSERT INTO admin_audit_logs(admin_id,action,resource_type,resource_id,reason,before_json,after_json,request_id,ip,user_agent,created_at) VALUES(?,'moment.review','moment',?,?,?,?,?,?,?,NOW(6))`, p.Admin.ID, strconv.FormatUint(id, 10), q.Reason, beforeJSON, afterJSON, httpx.RequestID(r.Context()), r.RemoteAddr, r.UserAgent())
		return err
	})
	if err != nil {
		httpx.Error(w, r, 409, "MOMENT_REVIEW_FAILED", "动态状态已变化或不存在")
		return
	}
	httpx.OK(w, r, map[string]any{"status": status})
}
