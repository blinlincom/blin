package adminauth

import (
	"bim/server/internal/platform/httpx"
	"context"
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
	"strings"
)

type principalKey struct{}
type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }
func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Post("/login", h.login)
	router.Post("/refresh", h.refresh)
	router.Group(func(protected chi.Router) {
		protected.Use(h.Protect)
		protected.Get("/session", h.session)
		protected.Post("/logout", h.logout)
	})
	return router
}
func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var request struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeAdmin(w, r, &request) {
		return
	}
	result, err := h.service.Refresh(r.Context(), request.RefreshToken)
	if err != nil {
		httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "登录状态已失效")
		return
	}
	httpx.OK(w, r, result)
}
func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decodeAdmin(w, r, &request) {
		return
	}
	result, err := h.service.Login(r.Context(), request.Username, request.Password)
	if err != nil {
		httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "账号或密码错误")
		return
	}
	httpx.OK(w, r, result)
}
func (h *Handler) session(w http.ResponseWriter, r *http.Request) {
	p, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "请先登录")
		return
	}
	httpx.OK(w, r, p.Admin)
}
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	p, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "请先登录")
		return
	}
	if err := h.service.Logout(r.Context(), p.SessionID); err != nil {
		httpx.Error(w, r, http.StatusInternalServerError, "ADMIN_LOGOUT_FAILED", "退出失败")
		return
	}
	httpx.OK(w, r, map[string]bool{"logged_out": true})
}
func (h *Handler) Protect(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Fields(r.Header.Get("Authorization"))
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "请先登录")
			return
		}
		p, err := h.service.Authenticate(r.Context(), parts[1])
		if err != nil {
			httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "登录状态已失效")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), principalKey{}, p)))
	})
}
func PrincipalFromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalKey{}).(Principal)
	return p, ok
}
func Require(permission string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			p, ok := PrincipalFromContext(r.Context())
			if !ok {
				httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "请先登录")
				return
			}
			for _, value := range p.Admin.Permissions {
				if value == permission {
					next.ServeHTTP(w, r)
					return
				}
			}
			httpx.Error(w, r, http.StatusForbidden, "ADMIN_FORBIDDEN", "没有操作权限")
		})
	}
}
func decodeAdmin(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
