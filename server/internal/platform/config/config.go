package config

import (
	"bytes"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server       ServerConfig       `yaml:"server"`
	Database     DatabaseConfig     `yaml:"database"`
	Redis        RedisConfig        `yaml:"redis"`
	Security     SecurityConfig     `yaml:"security"`
	Gateway      GatewayConfig      `yaml:"gateway"`
	WuKongIM     WuKongIMConfig     `yaml:"wukongim"`
	LiveKit      LiveKitConfig      `yaml:"livekit"`
	Storage      StorageConfig      `yaml:"storage"`
	Verification VerificationConfig `yaml:"verification"`
	Wallet       WalletConfig       `yaml:"wallet"`
	Features     FeaturesConfig     `yaml:"features"`
	ConfigDir    string             `yaml:"-"`
}

type ServerConfig struct {
	Env             string   `yaml:"env"`
	PublicURL       string   `yaml:"public_url"`
	Listen          string   `yaml:"listen"`
	Roles           []string `yaml:"roles"`
	ShutdownTimeout Duration `yaml:"shutdown_timeout"`
}

type DatabaseConfig struct {
	DSN             string   `yaml:"dsn"`
	MaxOpenConns    int      `yaml:"max_open_conns"`
	MaxIdleConns    int      `yaml:"max_idle_conns"`
	ConnMaxLifetime Duration `yaml:"conn_max_lifetime"`
}

type RedisConfig struct {
	Mode      string   `yaml:"mode"`
	Addresses []string `yaml:"addresses"`
	Password  string   `yaml:"password"`
	DB        int      `yaml:"db"`
	KeyPrefix string   `yaml:"key_prefix"`
}

type SecurityConfig struct {
	TokenSigningKey    string   `yaml:"token_signing_key"`
	RequestSigningKey  string   `yaml:"request_signing_key"`
	FieldEncryptionKey string   `yaml:"field_encryption_key"`
	AllowedClockSkew   Duration `yaml:"allowed_clock_skew"`
	ReplayWindow       Duration `yaml:"replay_window"`
	TrustedProxies     []string `yaml:"trusted_proxies"`
}

type GatewayConfig struct {
	Enabled             bool     `yaml:"enabled"`
	PathPrefix          string   `yaml:"path_prefix"`
	HeartbeatInterval   Duration `yaml:"heartbeat_interval"`
	MaxConnections      int      `yaml:"max_connections"`
	MaxConnectionsPerIP int      `yaml:"max_connections_per_ip"`
	QueueSize           int      `yaml:"queue_size"`
	StreamMaxLen        int64    `yaml:"stream_max_len"`
	TicketSingleUse     bool     `yaml:"ticket_single_use"`
	AllowedOrigins      []string `yaml:"allowed_origins"`
}

type WuKongIMConfig struct {
	BaseURL           string `yaml:"base_url"`
	ManagerToken      string `yaml:"manager_token"`
	WebhookSecret     string `yaml:"webhook_secret"`
	ChannelTypePerson int    `yaml:"channel_type_person"`
	ChannelTypeGroup  int    `yaml:"channel_type_group"`
}

type LiveKitConfig struct {
	URL           string `yaml:"url"`
	APIKey        string `yaml:"api_key"`
	APISecret     string `yaml:"api_secret"`
	WebhookSecret string `yaml:"webhook_secret"`
}

type StorageConfig struct {
	Driver        string             `yaml:"driver"`
	PublicBaseURL string             `yaml:"public_base_url"`
	Local         LocalStorageConfig `yaml:"local"`
}

type VerificationConfig struct {
	ProviderURL   string   `yaml:"provider_url"`
	ProviderToken string   `yaml:"provider_token"`
	CodeTTL       Duration `yaml:"code_ttl"`
	CaptchaTTL    Duration `yaml:"captcha_ttl"`
}

type LocalStorageConfig struct {
	Root string `yaml:"root"`
}

type WalletConfig struct {
	Currency                   string   `yaml:"currency"`
	Scale                      int      `yaml:"scale"`
	PaymentPasswordMaxAttempts int      `yaml:"payment_password_max_attempts"`
	PaymentPasswordLock        Duration `yaml:"payment_password_lock"`
}

type FeaturesConfig struct {
	Moments         bool `yaml:"moments"`
	ServiceAccounts bool `yaml:"service_accounts"`
	PlatformWallet  bool `yaml:"platform_wallet"`
	DigitalAssets   bool `yaml:"digital_assets"`
	OTC             bool `yaml:"otc"`
}

func Load(path string) (Config, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}
	var cfg Config
	decoder := yaml.NewDecoder(bytes.NewReader(content))
	decoder.KnownFields(true)
	if err := decoder.Decode(&cfg); err != nil {
		return Config{}, fmt.Errorf("decode config: %w", err)
	}
	cfg.ConfigDir = filepath.Dir(path)
	if err := cfg.resolveSecrets(); err != nil {
		return Config{}, err
	}
	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c *Config) resolveSecrets() error {
	values := []*string{
		&c.Database.DSN, &c.Redis.Password,
		&c.Security.TokenSigningKey, &c.Security.RequestSigningKey,
		&c.Security.FieldEncryptionKey, &c.WuKongIM.ManagerToken,
		&c.WuKongIM.WebhookSecret, &c.LiveKit.APIKey,
		&c.LiveKit.APISecret, &c.LiveKit.WebhookSecret,
		&c.Verification.ProviderToken,
	}
	for _, value := range values {
		resolved, err := resolveValue(*value, c.ConfigDir)
		if err != nil {
			return err
		}
		*value = resolved
	}
	return nil
}

func resolveValue(value, baseDir string) (string, error) {
	value = strings.TrimSpace(value)
	if strings.HasPrefix(value, "env://") {
		name := strings.TrimPrefix(value, "env://")
		resolved, ok := os.LookupEnv(name)
		if !ok {
			return "", fmt.Errorf("required environment variable %s is missing", name)
		}
		return strings.TrimSpace(resolved), nil
	}
	if strings.HasPrefix(value, "file://") {
		path := strings.TrimPrefix(value, "file://")
		if !filepath.IsAbs(path) {
			path = filepath.Join(baseDir, path)
		}
		content, err := os.ReadFile(filepath.Clean(path))
		if err != nil {
			return "", fmt.Errorf("read secret file %s: %w", path, err)
		}
		return strings.TrimSpace(string(content)), nil
	}
	return value, nil
}

func (c Config) Validate() error {
	var errs []error
	if c.Server.Listen == "" {
		errs = append(errs, errors.New("server.listen is required"))
	}
	if parsed, err := url.Parse(c.Server.PublicURL); err != nil || parsed.Scheme == "" || parsed.Host == "" {
		errs = append(errs, errors.New("server.public_url must be an absolute URL"))
	}
	if len(c.Server.Roles) == 0 {
		errs = append(errs, errors.New("server.roles must not be empty"))
	}
	if c.Features.DigitalAssets || c.Features.OTC {
		errs = append(errs, errors.New("digital assets and OTC are removed and must remain disabled"))
	}
	if c.Wallet.Currency == "" || c.Wallet.Scale != 2 {
		errs = append(errs, errors.New("wallet requires a currency and scale=2"))
	}
	if c.Wallet.PaymentPasswordMaxAttempts < 1 || c.Wallet.PaymentPasswordLock.Value() <= 0 {
		errs = append(errs, errors.New("wallet payment password policy is invalid"))
	}
	if c.Gateway.Enabled && c.Gateway.HeartbeatInterval.Value() <= 0 {
		errs = append(errs, errors.New("gateway.heartbeat_interval must be positive"))
	}
	if c.Server.Env == "production" {
		for name, value := range map[string]string{
			"database.dsn":                  c.Database.DSN,
			"security.token_signing_key":    c.Security.TokenSigningKey,
			"security.request_signing_key":  c.Security.RequestSigningKey,
			"security.field_encryption_key": c.Security.FieldEncryptionKey,
			"wukongim.manager_token":        c.WuKongIM.ManagerToken,
			"wukongim.webhook_secret":       c.WuKongIM.WebhookSecret,
		} {
			if len(strings.TrimSpace(value)) < 32 {
				errs = append(errs, fmt.Errorf("%s is missing or too weak", name))
			}
		}
	}
	return errors.Join(errs...)
}
