package publicapi

import (
	"net/http"
	"strconv"

	"bim/server/internal/modules/appconfig"
	"bim/server/internal/modules/calls"
	"bim/server/internal/modules/engagement"
	"bim/server/internal/modules/identity"
	"bim/server/internal/modules/media"
	"bim/server/internal/modules/messaging"
	"bim/server/internal/modules/moments"
	"bim/server/internal/modules/portal"
	"bim/server/internal/modules/serviceaccount"
	"bim/server/internal/modules/social"
	"bim/server/internal/modules/userprofile"
	"bim/server/internal/modules/verification"
	"bim/server/internal/modules/wallet"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

func Router(appConfig *appconfig.Service, identityHandler *identity.Handler, verificationHandler *verification.Handler, profileHandler *userprofile.Handler, socialHandler *social.Handler, messageHandler *messaging.Handler, walletHandler *wallet.Handler, serviceHandler *serviceaccount.Handler, momentsHandler *moments.Handler, callsHandler *calls.Handler, mediaHandler *media.Handler, engagementHandler *engagement.Handler, portalHandler *portal.Handler) http.Handler {
	router := chi.NewRouter()
	router.Get("/v2/app/info", func(w http.ResponseWriter, r *http.Request) {
		appID := uint64(1)
		if raw := r.URL.Query().Get("app_id"); raw != "" {
			value, err := strconv.ParseUint(raw, 10, 64)
			if err != nil || value == 0 {
				httpx.Error(w, r, http.StatusBadRequest, "INVALID_APP_ID", "应用编号无效")
				return
			}
			appID = value
		}
		info, err := appConfig.PublicInfo(r.Context(), appID)
		if err != nil {
			httpx.Error(w, r, http.StatusServiceUnavailable, "APP_CONFIG_UNAVAILABLE", "应用配置暂不可用")
			return
		}
		httpx.OK(w, r, info)
	})
	if verificationHandler != nil {
		router.Mount("/v2/verification", verificationHandler.Routes())
	}
	if mediaHandler != nil {
		router.Mount("/v2/media", mediaHandler.PublicRoutes())
	}
	if identityHandler != nil {
		router.Mount("/v2/auth", identityHandler.Routes())
		if profileHandler != nil {
			router.Mount("/v2/users", identityHandler.Protect(profileHandler.Routes()))
		}
		if socialHandler != nil {
			router.Mount("/v2/social", identityHandler.Protect(socialHandler.Routes()))
		}
		if messageHandler != nil {
			router.Mount("/v2/im", identityHandler.Protect(messageHandler.Routes()))
		}
		if walletHandler != nil {
			router.Mount("/v2/wallet", identityHandler.Protect(walletHandler.Routes()))
		}
		if serviceHandler != nil {
			router.Mount("/v2/service-accounts", identityHandler.Protect(serviceHandler.Routes()))
		}
		if momentsHandler != nil {
			router.Mount("/v2/moments", identityHandler.Protect(momentsHandler.Routes()))
		}
		if callsHandler != nil {
			router.Mount("/v2/calls", identityHandler.Protect(callsHandler.Routes()))
		}
		if mediaHandler != nil {
			router.Mount("/v2/assets", identityHandler.Protect(mediaHandler.Routes()))
		}
		if engagementHandler != nil {
			router.Mount("/v2/engagement", identityHandler.Protect(engagementHandler.Routes()))
		}
		if portalHandler != nil {
			router.Mount("/v2/portal", identityHandler.Protect(portalHandler.Routes()))
		}
	}
	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		httpx.Error(w, r, http.StatusNotFound, "ROUTE_NOT_FOUND", "接口不存在")
	})
	return router
}
