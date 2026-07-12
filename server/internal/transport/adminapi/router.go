package adminapi

import (
	"net/http"

	"bim/server/internal/modules/adminauth"
	"bim/server/internal/modules/adminconfig"
	"bim/server/internal/modules/adminmoments"
	"bim/server/internal/modules/adminops"
	"bim/server/internal/modules/adminportal"
	"bim/server/internal/modules/adminwallet"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

func Router(auth *adminauth.Handler, walletHandler *adminwallet.Handler, configHandler *adminconfig.Handler, momentsHandler *adminmoments.Handler, opsHandler *adminops.Handler, portalHandler *adminportal.Handler) http.Handler {
	router := chi.NewRouter()
	if auth != nil {
		router.Mount("/v1/auth", auth.Routes())
		if walletHandler != nil {
			router.Mount("/v1/wallet", auth.Protect(walletHandler.Routes()))
		}
		if configHandler != nil {
			router.Mount("/v1/config", auth.Protect(configHandler.Routes()))
		}
		if momentsHandler != nil {
			router.Mount("/v1/moments", auth.Protect(momentsHandler.Routes()))
		}
		if opsHandler != nil {
			router.Mount("/v1/ops", auth.Protect(opsHandler.Routes()))
		}
		if portalHandler != nil {
			router.Mount("/v1/portal", auth.Protect(portalHandler.Routes()))
		}
	}
	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		httpx.Error(w, r, http.StatusNotFound, "ADMIN_ROUTE_NOT_FOUND", "管理接口不存在")
	})
	return router
}
