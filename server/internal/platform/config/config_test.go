package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLoadResolvesSecretsAndDurations(t *testing.T) {
	t.Setenv("TEST_DATABASE_DSN", "user:pass@tcp(localhost:3306)/bim_v2")
	dir := t.TempDir()
	secretPath := filepath.Join(dir, "secret.key")
	if err := os.WriteFile(secretPath, []byte(strings.Repeat("s", 32)), 0o600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "config.yaml")
	content := strings.ReplaceAll(testConfig, "DATABASE_DSN", "env://TEST_DATABASE_DSN")
	content = strings.ReplaceAll(content, "SECRET_VALUE", "file://secret.key")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Server.ShutdownTimeout.Value() != 15*time.Second {
		t.Fatalf("shutdown timeout = %s", cfg.Server.ShutdownTimeout.Value())
	}
	if cfg.Security.TokenSigningKey != strings.Repeat("s", 32) {
		t.Fatal("secret file was not resolved")
	}
}

func TestLoadRejectsUnknownFields(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(testConfig+"\nunknown: true\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil || !strings.Contains(err.Error(), "field unknown not found") {
		t.Fatalf("expected unknown field error, got %v", err)
	}
}

func TestValidateRejectsRemovedFeatures(t *testing.T) {
	cfg := Config{
		Server:   ServerConfig{Listen: ":8080", PublicURL: "https://example.com", Roles: []string{"api"}},
		Wallet:   WalletConfig{Currency: "CNY", Scale: 2},
		Features: FeaturesConfig{DigitalAssets: true},
	}
	if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "removed") {
		t.Fatalf("expected removed feature error, got %v", err)
	}
}

const testConfig = `
server:
  env: development
  public_url: https://example.com
  listen: 127.0.0.1:8080
  roles: [api]
  shutdown_timeout: 15s
database:
  dsn: DATABASE_DSN
  max_open_conns: 10
  max_idle_conns: 5
  conn_max_lifetime: 30m
redis:
  mode: single
  addresses: [127.0.0.1:6379]
  password: ""
  db: 0
  key_prefix: bim
security:
  token_signing_key: SECRET_VALUE
  request_signing_key: SECRET_VALUE
  field_encryption_key: SECRET_VALUE
  allowed_clock_skew: 30s
  replay_window: 5m
  trusted_proxies: [127.0.0.1/32]
gateway:
  enabled: false
  path_prefix: /api/sync
  heartbeat_interval: 25s
  max_connections: 100
  max_connections_per_ip: 10
  queue_size: 100
  stream_max_len: 1000
  ticket_single_use: true
wukongim:
  base_url: http://127.0.0.1:5001
  manager_token: SECRET_VALUE
  webhook_secret: SECRET_VALUE
  channel_type_person: 1
  channel_type_group: 2
livekit:
  url: ws://127.0.0.1:7880
  api_key: key
  api_secret: secret
  webhook_secret: secret
storage:
  driver: local
  public_base_url: https://example.com/uploads
  local: {root: ./var/uploads}
wallet:
  currency: CNY
  scale: 2
  payment_password_max_attempts: 3
  payment_password_lock: 30m
features:
  moments: true
  service_accounts: true
  platform_wallet: true
  digital_assets: false
  otc: false
`
