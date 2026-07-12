package stream

import (
	"net/http"

	"bim/server/internal/modules/gateway"
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

func Router(enabled bool, identityHandler *identity.Handler, service *gateway.Service) http.Handler {
	router := chi.NewRouter()
	router.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		httpx.OK(w, r, map[string]any{"enabled": enabled, "status": "initializing"})
	})
	if enabled && identityHandler != nil && service != nil {
		router.With(identityHandler.Protect).Post("/ticket", service.TicketHandler)
		router.With(identityHandler.Protect).Post("/presence", service.PresenceHandler)
		router.Handle("/connect", service.WebSocketHandler())
	}
	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		httpx.Error(w, r, http.StatusNotFound, "STREAM_ROUTE_NOT_FOUND", "连接入口不存在")
	})
	return router
}
