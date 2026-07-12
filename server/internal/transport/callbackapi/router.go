package callbackapi

import (
	"net/http"

	"bim/server/internal/modules/calls"
	"bim/server/internal/modules/messagingwebhook"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

func Router(handler *messagingwebhook.Handler, callHandler *calls.WebhookHandler) http.Handler {
	router := chi.NewRouter()
	if handler != nil {
		router.Mount("/v1", handler.Routes())
	}
	if callHandler != nil {
		router.Post("/v1/livekit", callHandler.ServeHTTP)
	}
	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		httpx.Error(w, r, http.StatusNotFound, "CALLBACK_NOT_FOUND", "回调入口不存在")
	})
	return router
}
