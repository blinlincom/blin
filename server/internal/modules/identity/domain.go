package identity

import (
	"context"
	"errors"
	"time"
)

var (
	ErrInvalidCredentials   = errors.New("invalid credentials")
	ErrUsernameTaken        = errors.New("username already exists")
	ErrSessionRevoked       = errors.New("session revoked")
	ErrRegistrationDisabled = errors.New("registration disabled")
	ErrAuthMethodDisabled   = errors.New("auth method disabled")
	ErrVerificationRequired = errors.New("verification required")
)

type User struct {
	ID                uint64
	AppID             uint64
	Username          string
	Nickname          string
	PasswordHash      string
	SessionVersion    uint64
	Status            uint8
	ContactType       string
	ContactIdentifier string
	InvitationCode    string
}

type Device struct {
	Platform string
	ID       string
	Name     string
	IP       string
}

type SecurityMethod struct {
	Type       string    `json:"type"`
	Identifier string    `json:"identifier"`
	VerifiedAt time.Time `json:"verified_at"`
}

type Session struct {
	ID               string
	AppID            uint64
	UserID           uint64
	Platform         string
	DeviceID         string
	DeviceName       string
	RefreshTokenHash string
	SessionVersion   uint64
	ExpiresAt        time.Time
}

type Repository interface {
	CreateUser(ctx context.Context, user User, session Session) (User, error)
	FindPasswordUser(ctx context.Context, appID uint64, username string) (User, error)
	FindUserByID(ctx context.Context, appID, userID uint64) (User, error)
	ReplacePlatformSession(ctx context.Context, user User, session Session) error
	FindSession(ctx context.Context, sessionID string) (Session, error)
	RotateSession(ctx context.Context, sessionID, refreshHash string, expiresAt time.Time) error
	RevokeSession(ctx context.Context, sessionID string) error
	SecurityMethods(ctx context.Context, appID, userID uint64) ([]SecurityMethod, error)
	BindSecurityMethod(ctx context.Context, appID, userID uint64, method, identifier string) error
}
