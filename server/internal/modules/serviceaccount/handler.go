package serviceaccount

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
)

type Handler struct{ service *Service }

func NewHandler(s *Service) *Handler { return &Handler{service: s} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Get("/{code}", h.get)
	r.Put("/{code}/settings", h.settings)
	return r
}
func principal(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return p, ok
}
func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	items, err := h.service.List(r.Context(), p.User.AppID, p.User.ID)
	if err != nil {
		httpx.Error(w, r, 500, "SERVICE_ACCOUNT_LOAD_FAILED", "服务号加载失败")
		return
	}
	httpx.OK(w, r, items)
}
func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	item, err := h.service.Get(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "code"))
	if err != nil {
		httpx.Error(w, r, 404, "SERVICE_ACCOUNT_NOT_FOUND", "服务号不存在")
		return
	}
	httpx.OK(w, r, item)
}
func (h *Handler) settings(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q struct {
		Muted      bool `json:"muted"`
		Subscribed bool `json:"subscribed"`
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	d.DisallowUnknownFields()
	if d.Decode(&q) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return
	}
	if err := h.service.UpdateSettings(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "code"), q.Muted, q.Subscribed); err != nil {
		httpx.Error(w, r, 404, "SERVICE_ACCOUNT_NOT_FOUND", "服务号不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}
