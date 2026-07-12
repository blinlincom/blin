package identity

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct{ service *Service }

type principalKey struct{}

func PrincipalFromContext(ctx context.Context) (Principal, bool) {
	principal, ok := ctx.Value(principalKey{}).(Principal)
	return principal, ok
}

func (h *Handler) Protect(next http.Handler) http.Handler { return h.requireAccessToken(next) }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }

func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Post("/register", h.register)
	router.Post("/login/password", h.login)
	router.Post("/login/code", h.loginCode)
	router.Post("/token/refresh", h.refresh)
	router.Group(func(protected chi.Router) {
		protected.Use(h.requireAccessToken)
		protected.Get("/me", h.me)
		protected.Post("/logout", h.logout)
		protected.Get("/security", h.security)
		protected.Post("/security/bind", h.bindSecurity)
	})
	return router
}

type authRequest struct {
	AppID            uint64 `json:"app_id"`
	Username         string `json:"username"`
	Nickname         string `json:"nickname"`
	Password         string `json:"password"`
	Platform         string `json:"platform"`
	DeviceID         string `json:"device_id"`
	DeviceName       string `json:"device_name"`
	IdentifierType   string `json:"identifier_type"`
	Identifier       string `json:"identifier"`
	CaptchaID        uint64 `json:"captcha_id"`
	CaptchaCode      string `json:"captcha_code"`
	VerificationID   uint64 `json:"verification_id"`
	VerificationCode string `json:"verification_code"`
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var request authRequest
	if !decodeStrict(w, r, &request) {
		return
	}
	result, err := h.service.Register(r.Context(), RegisterInput{AppID: request.AppID, Username: request.Username, Nickname: request.Nickname, Password: request.Password, Device: request.device(r), IdentifierType: request.IdentifierType, Identifier: request.Identifier, Proof: request.proof()})
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, httpx.Envelope{Code: "OK", Message: "注册成功", Data: result, RequestID: httpx.RequestID(r.Context())})
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var request authRequest
	if !decodeStrict(w, r, &request) {
		return
	}
	result, err := h.service.Login(r.Context(), LoginInput{AppID: request.AppID, Username: request.Username, Password: request.Password, Device: request.device(r), Proof: request.proof()})
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, result)
}

func (h *Handler) loginCode(w http.ResponseWriter, r *http.Request) {
	var request authRequest
	if !decodeStrict(w, r, &request) {
		return
	}
	target := strings.TrimSpace(request.Identifier)
	result, err := h.service.LoginWithCode(r.Context(), CodeLoginInput{
		AppID:  request.AppID,
		Target: target,
		Device: request.device(r),
		Proof:  request.proof(),
	})
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, result)
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var request struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeStrict(w, r, &request) {
		return
	}
	result, err := h.service.Refresh(r.Context(), strings.TrimSpace(request.RefreshToken))
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, result)
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	principal, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "登录状态已失效")
		return
	}
	httpx.OK(w, r, UserView{ID: principal.User.ID, Username: principal.User.Username, Nickname: principal.User.Nickname})
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	principal, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "登录状态已失效")
		return
	}
	if err := h.service.Logout(r.Context(), principal.SessionID); err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"logged_out": true})
}

func (h *Handler) security(w http.ResponseWriter, r *http.Request) {
	principal, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	items, err := h.service.SecurityMethods(r.Context(), principal.User.AppID, principal.User.ID)
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"methods": items})
}

func (h *Handler) bindSecurity(w http.ResponseWriter, r *http.Request) {
	principal, ok := PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	var request struct {
		Method           string `json:"method"`
		Identifier       string `json:"identifier"`
		VerificationID   uint64 `json:"verification_id"`
		VerificationCode string `json:"verification_code"`
	}
	if !decodeStrict(w, r, &request) {
		return
	}
	err := h.service.BindSecurityMethod(r.Context(), principal.User.AppID, principal.User.ID, request.Method, request.Identifier, VerificationProof{VerificationID: request.VerificationID, VerificationCode: request.VerificationCode})
	if err != nil {
		writeIdentityError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"bound": true})
}

func (h *Handler) requireAccessToken(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Fields(strings.TrimSpace(r.Header.Get("Authorization")))
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
			return
		}
		principal, err := h.service.Authenticate(r.Context(), parts[1])
		if err != nil {
			httpx.Error(w, r, http.StatusUnauthorized, "SESSION_REVOKED", "登录状态已失效")
			return
		}
		ctx := context.WithValue(r.Context(), principalKey{}, principal)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (r authRequest) device(request *http.Request) Device {
	ip := request.RemoteAddr
	if forwarded := strings.TrimSpace(request.Header.Get("X-Real-IP")); forwarded != "" {
		ip = forwarded
	}
	return Device{Platform: strings.ToLower(strings.TrimSpace(r.Platform)), ID: strings.TrimSpace(r.DeviceID), Name: strings.TrimSpace(r.DeviceName), IP: ip}
}
func (r authRequest) proof() VerificationProof {
	return VerificationProof{CaptchaID: r.CaptchaID, CaptchaCode: r.CaptchaCode, VerificationID: r.VerificationID, VerificationCode: r.VerificationCode}
}

func decodeStrict(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求只能包含一个 JSON 对象")
		return false
	}
	return true
}

func writeIdentityError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		httpx.Error(w, r, http.StatusUnauthorized, "INVALID_CREDENTIALS", "账号或密码错误")
	case errors.Is(err, ErrUsernameTaken):
		httpx.Error(w, r, http.StatusConflict, "USERNAME_TAKEN", "用户名已被使用")
	case errors.Is(err, ErrSessionRevoked):
		httpx.Error(w, r, http.StatusUnauthorized, "SESSION_REVOKED", "登录状态已失效")
	case errors.Is(err, ErrRegistrationDisabled):
		httpx.Error(w, r, http.StatusForbidden, "REGISTRATION_DISABLED", "注册功能未开放")
	case errors.Is(err, ErrAuthMethodDisabled):
		httpx.Error(w, r, http.StatusForbidden, "AUTH_METHOD_DISABLED", "当前登录或注册方式未开放")
	case errors.Is(err, ErrVerificationRequired):
		httpx.Error(w, r, http.StatusBadRequest, "VERIFICATION_REQUIRED", "验证码错误或已失效")
	default:
		httpx.Error(w, r, http.StatusBadRequest, "IDENTITY_REQUEST_REJECTED", err.Error())
	}
}
