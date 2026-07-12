package bootstrap

import (
	"context"
	"log/slog"
	"net/http"

	"bim/server/internal/modules/adminauth"
	"bim/server/internal/modules/adminconfig"
	"bim/server/internal/modules/adminmoments"
	"bim/server/internal/modules/adminops"
	"bim/server/internal/modules/adminportal"
	"bim/server/internal/modules/adminwallet"
	"bim/server/internal/modules/appconfig"
	"bim/server/internal/modules/calls"
	"bim/server/internal/modules/engagement"
	"bim/server/internal/modules/gateway"
	"bim/server/internal/modules/identity"
	"bim/server/internal/modules/media"
	"bim/server/internal/modules/messaging"
	"bim/server/internal/modules/messagingwebhook"
	"bim/server/internal/modules/moments"
	"bim/server/internal/modules/portal"
	"bim/server/internal/modules/serviceaccount"
	"bim/server/internal/modules/social"
	"bim/server/internal/modules/userprofile"
	"bim/server/internal/modules/verification"
	"bim/server/internal/modules/wallet"
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/health"
	"bim/server/internal/platform/httpx"
	"bim/server/internal/transport/adminapi"
	"bim/server/internal/transport/callbackapi"
	"bim/server/internal/transport/publicapi"
	"bim/server/internal/transport/stream"
	"github.com/go-chi/chi/v5"
)

type Dependencies struct {
	Database              *database.DB
	IdentityHandler       *identity.Handler
	SocialHandler         *social.Handler
	ServiceAccountHandler *serviceaccount.Handler
	UserProfileHandler    *userprofile.Handler
	VerificationHandler   *verification.Handler
	MessageHandler        *messaging.Handler
	MediaHandler          *media.Handler
	MomentsHandler        *moments.Handler
	CallsHandler          *calls.Handler
	CallsWebhookHandler   *calls.WebhookHandler
	EngagementHandler     *engagement.Handler
	PortalHandler         *portal.Handler
	WebhookHandler        *messagingwebhook.Handler
	GatewayService        *gateway.Service
	WalletHandler         *wallet.Handler
	AdminAuthHandler      *adminauth.Handler
	AdminWalletHandler    *adminwallet.Handler
	AdminConfigHandler    *adminconfig.Handler
	AdminMomentsHandler   *adminmoments.Handler
	AdminOpsHandler       *adminops.Handler
	AdminPortalHandler    *adminportal.Handler
	HealthChecks          map[string]health.Check
	Close                 func(context.Context) error
}

type Application struct {
	Config  config.Config
	Logger  *slog.Logger
	Health  *health.Checker
	Handler http.Handler
	Close   func(context.Context) error
}

func New(cfg config.Config, logger *slog.Logger, version string, dependencies Dependencies) *Application {
	checker := health.New()
	for name, check := range dependencies.HealthChecks {
		checker.Register(name, check)
	}
	appConfig := appconfig.New(version, dependencies.Database)
	router := chi.NewRouter()
	router.Use(func(next http.Handler) http.Handler { return httpx.Recover(logger, next) })
	router.Use(func(next http.Handler) http.Handler { return httpx.RequestContext(logger, next) })
	router.Use(httpx.SecurityHeaders)
	router.Get("/health/live", func(w http.ResponseWriter, r *http.Request) {
		httpx.OK(w, r, map[string]string{"status": "alive"})
	})
	router.Get("/health/ready", func(w http.ResponseWriter, r *http.Request) {
		status := checker.Run(r.Context())
		if !status.OK {
			httpx.JSON(w, http.StatusServiceUnavailable, httpx.Envelope{Code: "NOT_READY", Message: "服务尚未就绪", Data: status, RequestID: httpx.RequestID(r.Context())})
			return
		}
		httpx.OK(w, r, status)
	})
	router.Mount("/api", publicapi.Router(appConfig, dependencies.IdentityHandler, dependencies.VerificationHandler, dependencies.UserProfileHandler, dependencies.SocialHandler, dependencies.MessageHandler, dependencies.WalletHandler, dependencies.ServiceAccountHandler, dependencies.MomentsHandler, dependencies.CallsHandler, dependencies.MediaHandler, dependencies.EngagementHandler, dependencies.PortalHandler))
	router.Mount("/admin-api", adminapi.Router(dependencies.AdminAuthHandler, dependencies.AdminWalletHandler, dependencies.AdminConfigHandler, dependencies.AdminMomentsHandler, dependencies.AdminOpsHandler, dependencies.AdminPortalHandler))
	router.Mount("/callbacks", callbackapi.Router(dependencies.WebhookHandler, dependencies.CallsWebhookHandler))
	router.Mount(cfg.Gateway.PathPrefix, stream.Router(cfg.Gateway.Enabled, dependencies.IdentityHandler, dependencies.GatewayService))
	closeFn := dependencies.Close
	if closeFn == nil {
		closeFn = func(context.Context) error { return nil }
	}
	return &Application{Config: cfg, Logger: logger, Health: checker, Handler: router, Close: closeFn}
}
