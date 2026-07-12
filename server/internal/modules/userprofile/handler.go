package userprofile

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"encoding/json"
	"errors"
	"github.com/go-chi/chi/v5"
	"net/http"
)

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/me", h.profile)
	r.Put("/me", h.updateProfile)
	r.Get("/settings", h.settings)
	r.Put("/settings", h.updateSettings)
	r.Get("/devices", h.devices)
	r.Delete("/devices/{sessionID}", h.revokeDevice)
	return r
}
func (h *Handler) principal(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
	}
	return p, ok
}
func (h *Handler) profile(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	value, err := h.service.Profile(r.Context(), p.User.AppID, p.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, value)
}
func (h *Handler) updateProfile(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	var input Profile
	if !decode(w, r, &input) {
		return
	}
	value, err := h.service.UpdateProfile(r.Context(), p.User.AppID, p.User.ID, input)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, value)
}
func (h *Handler) settings(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	value, err := h.service.Settings(r.Context(), p.User.AppID, p.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, value)
}
func (h *Handler) updateSettings(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	var input Settings
	if !decode(w, r, &input) {
		return
	}
	value, err := h.service.UpdateSettings(r.Context(), p.User.AppID, p.User.ID, input)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, value)
}
func (h *Handler) devices(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	items, err := h.service.Devices(r.Context(), p.User.AppID, p.User.ID, p.SessionID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}
func (h *Handler) revokeDevice(w http.ResponseWriter, r *http.Request) {
	p, ok := h.principal(w, r)
	if !ok {
		return
	}
	if err := h.service.RevokeDevice(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "sessionID"), p.SessionID); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"revoked": true})
}
func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		httpx.Error(w, r, http.StatusNotFound, "USER_NOT_FOUND", "用户数据不存在")
	case errors.Is(err, ErrForbidden):
		httpx.Error(w, r, http.StatusForbidden, "OPERATION_FORBIDDEN", "当前操作不允许")
	default:
		httpx.Error(w, r, http.StatusBadRequest, "USER_REQUEST_REJECTED", err.Error())
	}
}
