package bootstrap

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"bim/server/internal/platform/config"
)

func TestRoutesAreSeparated(t *testing.T) {
	cfg := config.Config{
		Server:  config.ServerConfig{Env: "test", Listen: ":0", PublicURL: "https://example.com", Roles: []string{"api"}},
		Gateway: config.GatewayConfig{PathPrefix: "/api/sync", Enabled: true},
		Wallet:  config.WalletConfig{Currency: "CNY", Scale: 2},
	}
	app := New(cfg, slog.New(slog.NewTextHandler(io.Discard, nil)), "test", Dependencies{})
	for _, test := range []struct {
		path   string
		status int
	}{
		{"/health/live", http.StatusOK},
		{"/api/v2/app/info", http.StatusOK},
		{"/admin-api/v1/auth/session", http.StatusNotFound},
		{"/api/sync/health", http.StatusOK},
	} {
		request := httptest.NewRequest(http.MethodGet, test.path, nil)
		response := httptest.NewRecorder()
		app.Handler.ServeHTTP(response, request)
		if response.Code != test.status {
			t.Fatalf("%s status=%d want=%d", test.path, response.Code, test.status)
		}
	}
}
