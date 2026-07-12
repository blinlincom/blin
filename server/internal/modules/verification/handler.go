package verification

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Post("/captcha", h.captcha)
	r.Post("/code", h.code)
	return r
}
func (h *Handler) captcha(w http.ResponseWriter, r *http.Request) {
	var q struct {
		AppID uint64 `json:"app_id"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.AppID == 0 {
		q.AppID = 1
	}
	value, err := h.service.CreateCaptcha(r.Context(), q.AppID)
	if err != nil {
		httpx.Error(w, r, 500, "CAPTCHA_CREATE_FAILED", "验证码生成失败")
		return
	}
	httpx.OK(w, r, value)
}
func (h *Handler) code(w http.ResponseWriter, r *http.Request) {
	var q struct {
		AppID       uint64 `json:"app_id"`
		Scene       string `json:"scene"`
		Target      string `json:"target"`
		CaptchaID   uint64 `json:"captcha_id"`
		CaptchaCode string `json:"captcha_code"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.AppID == 0 {
		q.AppID = 1
	}
	id, err := h.service.SendCode(r.Context(), q.AppID, strings.TrimSpace(q.Scene), strings.TrimSpace(q.Target), q.CaptchaID, q.CaptchaCode)
	if err != nil {
		if errors.Is(err, ErrInvalidChallenge) {
			httpx.Error(w, r, 400, "INVALID_CAPTCHA", "图片验证码错误或已失效")
			return
		}
		httpx.Error(w, r, 503, "VERIFICATION_SEND_FAILED", "验证码发送失败")
		return
	}
	httpx.OK(w, r, map[string]uint64{"verification_id": id})
}
func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(target); err != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
