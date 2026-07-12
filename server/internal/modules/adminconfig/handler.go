package adminconfig

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"bim/server/internal/modules/adminauth"
	"bim/server/internal/modules/appconfig"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	service *appconfig.Service
	db      *database.DB
}

func NewHandler(service *appconfig.Service, db *database.DB) *Handler {
	return &Handler{service: service, db: db}
}
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.With(adminauth.Require("config:read")).Get("/applications/{appID}", h.get)
	r.With(adminauth.Require("config:write")).Put("/applications/{appID}", h.update)
	return r
}
func appID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	value, err := strconv.ParseUint(chi.URLParam(r, "appID"), 10, 64)
	if err != nil || value == 0 {
		httpx.Error(w, r, 400, "INVALID_APP_ID", "应用编号无效")
		return 0, false
	}
	return value, true
}
func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	id, ok := appID(w, r)
	if !ok {
		return
	}
	info, err := h.service.PublicInfo(r.Context(), id)
	if err != nil {
		httpx.Error(w, r, 404, "APP_NOT_FOUND", "应用不存在")
		return
	}
	httpx.OK(w, r, info)
}
func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id, ok := appID(w, r)
	if !ok {
		return
	}
	var request struct {
		Auth                   appconfig.AuthPolicy `json:"auth"`
		HistorySyncEnabled     bool                 `json:"history_sync_enabled"`
		ReadReceiptsEnabled    bool                 `json:"read_receipts_enabled"`
		ServiceAccountsEnabled bool                 `json:"service_accounts_enabled"`
		MomentsEnabled         bool                 `json:"moments_enabled"`
		LiveKitEnabled         bool                 `json:"livekit_enabled"`
		Reason                 string               `json:"reason"`
	}
	if !decode(w, r, &request) {
		return
	}
	request.Reason = strings.TrimSpace(request.Reason)
	if len([]rune(request.Reason)) < 2 || len([]rune(request.Reason)) > 500 {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "必须填写修改原因")
		return
	}
	if err := validate(request.Auth); err != nil {
		httpx.Error(w, r, 400, "INVALID_AUTH_CONFIG", err.Error())
		return
	}
	before, err := h.service.PublicInfo(r.Context(), id)
	if err != nil {
		httpx.Error(w, r, 404, "APP_NOT_FOUND", "应用不存在")
		return
	}
	after := appconfig.PublicInfo{Auth: request.Auth, HistorySyncEnabled: request.HistorySyncEnabled, ReadReceiptsEnabled: request.ReadReceiptsEnabled, ServiceAccountsEnabled: request.ServiceAccountsEnabled, MomentsEnabled: request.MomentsEnabled, LiveKitEnabled: request.LiveKitEnabled}
	if err := h.service.Update(r.Context(), id, after); err != nil {
		httpx.Error(w, r, 500, "CONFIG_UPDATE_FAILED", "配置保存失败")
		return
	}
	principal, _ := adminauth.PrincipalFromContext(r.Context())
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(after)
	_, err = h.db.ExecContext(r.Context(), `INSERT INTO admin_audit_logs(admin_id,action,resource_type,resource_id,reason,before_json,after_json,request_id,ip,user_agent,created_at) VALUES(?,'config.update','application',?,?,?,?,?,?,?,NOW(6))`, principal.Admin.ID, strconv.FormatUint(id, 10), request.Reason, beforeJSON, afterJSON, httpx.RequestID(r.Context()), r.RemoteAddr, r.UserAgent())
	if err != nil {
		httpx.Error(w, r, 500, "AUDIT_WRITE_FAILED", "配置已保存但审计记录失败")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func validate(p appconfig.AuthPolicy) error {
	if !p.UsernamePasswordEnabled && !p.PhoneEnabled && !p.EmailEnabled {
		return fmt.Errorf("至少启用一种登录方式")
	}
	if (p.LoginCodeRequired || p.RegisterCodeRequired) && !p.PhoneEnabled && !p.EmailEnabled {
		return fmt.Errorf("启用动态验证码时必须启用手机号或邮箱")
	}
	return nil
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
