package calls

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
	r.Post("/", h.initiate)
	r.Get("/{callNo}", h.get)
	r.Post("/{callNo}/accept", h.accept)
	r.Post("/{callNo}/reject", h.reject)
	r.Post("/{callNo}/end", h.end)
	r.Post("/{callNo}/token", h.token)
	return r
}
func principal(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return p, ok
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func fail(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, 409, "CALL_STATE_INVALID", "通话状态已变化")
}
func (h *Handler) initiate(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q struct {
		ChannelID   string   `json:"channel_id"`
		ChannelType uint8    `json:"channel_type"`
		CallType    string   `json:"call_type"`
		InviteeIDs  []uint64 `json:"invitee_ids"`
	}
	if !decode(w, r, &q) {
		return
	}
	v, e := h.service.Initiate(r.Context(), p.User.AppID, p.User.ID, q.ChannelID, q.ChannelType, q.CallType, q.InviteeIDs)
	if e != nil {
		fail(w, r)
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "通话邀请已发出", Data: v, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	v, e := h.service.Get(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "callNo"))
	if e != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, v)
}
func (h *Handler) accept(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	v, e := h.service.Accept(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "callNo"))
	if e != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, v)
}
func (h *Handler) reject(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	if h.service.Reject(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "callNo")) != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, map[string]bool{"rejected": true})
}
func (h *Handler) end(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q struct {
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	v, e := h.service.End(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "callNo"), q.Reason)
	if e != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, v)
}
func (h *Handler) token(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	v, e := h.service.Token(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "callNo"))
	if e != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, v)
}
