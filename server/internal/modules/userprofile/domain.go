package userprofile

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotFound  = errors.New("user not found")
	ErrForbidden = errors.New("operation forbidden")
)

type Profile struct {
	ID                uint64 `json:"id"`
	Username          string `json:"username"`
	Nickname          string `json:"nickname"`
	AvatarAssetID     uint64 `json:"avatar_asset_id,omitempty"`
	BackgroundAssetID uint64 `json:"background_asset_id,omitempty"`
	Bio               string `json:"bio"`
	Gender            uint8  `json:"gender"`
	Region            string `json:"region"`
	Status            uint8  `json:"status"`
}
type Settings struct {
	ReadReceiptsEnabled    bool `json:"read_receipts_enabled"`
	HistorySyncEnabled     bool `json:"history_sync_enabled"`
	BurnAfterReadEnabled   bool `json:"burn_after_read_enabled"`
	NewMessageSoundEnabled bool `json:"new_message_sound_enabled"`
	MomentsVisible         bool `json:"moments_visible"`
}
type DeviceSession struct {
	SessionID  string    `json:"session_id"`
	Platform   string    `json:"platform"`
	DeviceID   string    `json:"device_id"`
	DeviceName string    `json:"device_name"`
	LastSeenAt time.Time `json:"last_seen_at"`
	ExpiresAt  time.Time `json:"expires_at"`
	Current    bool      `json:"current"`
}
type Repository interface {
	Profile(context.Context, uint64, uint64) (Profile, error)
	UpdateProfile(context.Context, uint64, uint64, Profile) (Profile, error)
	Settings(context.Context, uint64, uint64) (Settings, error)
	UpdateSettings(context.Context, uint64, uint64, Settings) (Settings, error)
	Devices(context.Context, uint64, uint64, string) ([]DeviceSession, error)
	RevokeDevice(context.Context, uint64, uint64, string, string) error
}
