package moments

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
	"strconv"
)

type Handler struct{ service *Service }

func NewHandler(s *Service) *Handler { return &Handler{service: s} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/", h.feed)
	r.Post("/", h.create)
	r.Delete("/{id}", h.delete)
	r.Put("/{id}/like", h.like)
	r.Delete("/{id}/like", h.unlike)
	r.Post("/{id}/comments", h.comment)
	r.Delete("/comments/{id}", h.deleteComment)
	return r
}
func p(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	v, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return v, ok
}
func id(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	v, e := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if e != nil {
		httpx.Error(w, r, 400, "INVALID_ID", "编号无效")
		return 0, false
	}
	return v, true
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func (h *Handler) feed(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	before, _ := strconv.ParseUint(r.URL.Query().Get("before_id"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, e := h.service.Feed(r.Context(), u.User.AppID, u.User.ID, before, limit)
	if e != nil {
		httpx.Error(w, r, 500, "MOMENTS_LOAD_FAILED", "朋友圈加载失败")
		return
	}
	httpx.OK(w, r, items)
}
func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	var q struct {
		Content    string  `json:"content"`
		Visibility string  `json:"visibility"`
		Media      []Media `json:"media"`
	}
	if !decode(w, r, &q) {
		return
	}
	item, e := h.service.Create(r.Context(), u.User.AppID, u.User.ID, q.Content, q.Visibility, q.Media)
	if e != nil {
		httpx.Error(w, r, 400, "MOMENT_CREATE_FAILED", e.Error())
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "动态已提交审核", Data: item, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	v, ok := id(w, r)
	if !ok {
		return
	}
	if e := h.service.Delete(r.Context(), u.User.AppID, u.User.ID, v); e != nil {
		httpx.Error(w, r, 404, "MOMENT_NOT_FOUND", "动态不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
func (h *Handler) like(w http.ResponseWriter, r *http.Request)   { h.setLike(w, r, true) }
func (h *Handler) unlike(w http.ResponseWriter, r *http.Request) { h.setLike(w, r, false) }
func (h *Handler) setLike(w http.ResponseWriter, r *http.Request, value bool) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	v, ok := id(w, r)
	if !ok {
		return
	}
	if e := h.service.Like(r.Context(), u.User.AppID, u.User.ID, v, value); e != nil {
		httpx.Error(w, r, 403, "MOMENT_FORBIDDEN", "动态不可访问")
		return
	}
	httpx.OK(w, r, map[string]bool{"liked": value})
}
func (h *Handler) comment(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	v, ok := id(w, r)
	if !ok {
		return
	}
	var q struct {
		Content       string  `json:"content"`
		ReplyToUserID *uint64 `json:"reply_to_user_id"`
	}
	if !decode(w, r, &q) {
		return
	}
	item, e := h.service.Comment(r.Context(), u.User.AppID, u.User.ID, v, q.Content, q.ReplyToUserID)
	if e != nil {
		httpx.Error(w, r, 400, "COMMENT_FAILED", e.Error())
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "评论成功", Data: item, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) deleteComment(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	v, ok := id(w, r)
	if !ok {
		return
	}
	if e := h.service.DeleteComment(r.Context(), u.User.AppID, u.User.ID, v); e != nil {
		httpx.Error(w, r, 404, "COMMENT_NOT_FOUND", "评论不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
