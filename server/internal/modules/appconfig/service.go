package appconfig

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"bim/server/internal/platform/database"
)

type AuthPolicy struct {
	RegistrationEnabled     bool `json:"registration_enabled"`
	UsernamePasswordEnabled bool `json:"username_password_enabled"`
	PhoneEnabled            bool `json:"phone_enabled"`
	EmailEnabled            bool `json:"email_enabled"`
	LoginCaptchaRequired    bool `json:"login_captcha_required"`
	RegisterCaptchaRequired bool `json:"register_captcha_required"`
	LoginCodeRequired       bool `json:"login_code_required"`
	RegisterCodeRequired    bool `json:"register_code_required"`
}

type PublicInfo struct {
	Name                   string     `json:"name"`
	ServerVersion          string     `json:"server_version"`
	Auth                   AuthPolicy `json:"auth"`
	HistorySyncEnabled     bool       `json:"history_sync_enabled"`
	ReadReceiptsEnabled    bool       `json:"read_receipts_enabled"`
	ServiceAccountsEnabled bool       `json:"service_accounts_enabled"`
	MomentsEnabled         bool       `json:"moments_enabled"`
	LiveKitEnabled         bool       `json:"livekit_enabled"`
	DigitalAssetsEnabled   bool       `json:"digital_assets_enabled"`
	OTCEnabled             bool       `json:"otc_enabled"`
}

type storedConfig struct {
	Auth                   AuthPolicy `json:"auth"`
	HistorySyncEnabled     *bool      `json:"history_sync_enabled"`
	ReadReceiptsEnabled    *bool      `json:"read_receipts_enabled"`
	ServiceAccountsEnabled *bool      `json:"service_accounts_enabled"`
	MomentsEnabled         *bool      `json:"moments_enabled"`
	LiveKitEnabled         *bool      `json:"livekit_enabled"`
}

type Service struct {
	version string
	db      *database.DB
}

func New(version string, db *database.DB) *Service { return &Service{version: version, db: db} }

func (s *Service) PublicInfo(ctx context.Context, appID uint64) (PublicInfo, error) {
	if s.db == nil {
		return PublicInfo{Name: "BIM", ServerVersion: s.version, Auth: defaultAuthPolicy(), HistorySyncEnabled: true, ReadReceiptsEnabled: true, ServiceAccountsEnabled: true, MomentsEnabled: true, LiveKitEnabled: true}, nil
	}
	if appID == 0 {
		appID = 1
	}
	var name string
	var status uint8
	var raw []byte
	if err := s.db.QueryRowContext(ctx, `SELECT name,status,config_json FROM applications WHERE id=?`, appID).Scan(&name, &status, &raw); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return PublicInfo{}, fmt.Errorf("application not found")
		}
		return PublicInfo{}, err
	}
	if status != 1 {
		return PublicInfo{}, fmt.Errorf("application disabled")
	}
	config := storedConfig{}
	if err := json.Unmarshal(raw, &config); err != nil {
		return PublicInfo{}, fmt.Errorf("decode application config: %w", err)
	}
	return PublicInfo{
		Name: name, ServerVersion: s.version, Auth: config.Auth,
		HistorySyncEnabled:     boolValue(config.HistorySyncEnabled, true),
		ReadReceiptsEnabled:    boolValue(config.ReadReceiptsEnabled, true),
		ServiceAccountsEnabled: boolValue(config.ServiceAccountsEnabled, true),
		MomentsEnabled:         boolValue(config.MomentsEnabled, true),
		LiveKitEnabled:         boolValue(config.LiveKitEnabled, true),
		DigitalAssetsEnabled:   false, OTCEnabled: false,
	}, nil
}

func defaultAuthPolicy() AuthPolicy {
	return AuthPolicy{RegistrationEnabled: true, UsernamePasswordEnabled: true}
}

func (s *Service) AuthPolicy(ctx context.Context, appID uint64) (AuthPolicy, error) {
	info, err := s.PublicInfo(ctx, appID)
	return info.Auth, err
}

func (s *Service) Update(ctx context.Context, appID uint64, info PublicInfo) error {
	if appID == 0 {
		return fmt.Errorf("invalid app id")
	}
	config := storedConfig{Auth: info.Auth, HistorySyncEnabled: &info.HistorySyncEnabled, ReadReceiptsEnabled: &info.ReadReceiptsEnabled, ServiceAccountsEnabled: &info.ServiceAccountsEnabled, MomentsEnabled: &info.MomentsEnabled, LiveKitEnabled: &info.LiveKitEnabled}
	raw, err := json.Marshal(config)
	if err != nil {
		return err
	}
	result, err := s.db.ExecContext(ctx, `UPDATE applications SET config_json=JSON_MERGE_PATCH(config_json,?),updated_at=NOW(6) WHERE id=?`, raw, appID)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows != 1 {
		return fmt.Errorf("application not found")
	}
	return nil
}

func boolValue(value *bool, fallback bool) bool {
	if value == nil {
		return fallback
	}
	return *value
}
