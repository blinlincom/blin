package identity

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"bim/server/internal/modules/appconfig"
	"bim/server/internal/platform/authn"
)

var usernamePattern = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_]{4,31}$`)

type Service struct {
	repository Repository
	password   authn.PasswordPolicy
	tokens     *authn.TokenManager
	now        func() time.Time
	accessTTL  time.Duration
	refreshTTL time.Duration
	policy     PolicyProvider
	verifier   VerificationProvider
}

type PolicyProvider interface {
	AuthPolicy(context.Context, uint64) (appconfig.AuthPolicy, error)
}
type VerificationProvider interface {
	Verify(context.Context, uint64, uint64, string, string, string) error
}
type VerificationProof struct {
	CaptchaID        uint64
	CaptchaCode      string
	VerificationID   uint64
	VerificationCode string
}

type RegisterInput struct {
	AppID          uint64
	Username       string
	Nickname       string
	Password       string
	Device         Device
	IdentifierType string
	Identifier     string
	Proof          VerificationProof
}

type LoginInput struct {
	AppID    uint64
	Username string
	Password string
	Device   Device
	Proof    VerificationProof
}

type CodeLoginInput struct {
	AppID  uint64
	Target string
	Device Device
	Proof  VerificationProof
}

type TokenPair struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
	SessionID    string    `json:"session_id"`
	User         UserView  `json:"user"`
}

type UserView struct {
	ID       uint64 `json:"id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
}

type Principal struct {
	User      User
	SessionID string
	Platform  string
	DeviceID  string
}

func NewService(repository Repository, tokens *authn.TokenManager, dependencies ...any) *Service {
	service := &Service{repository: repository, password: authn.DefaultPasswordPolicy(), tokens: tokens, now: time.Now, accessTTL: 15 * time.Minute, refreshTTL: 30 * 24 * time.Hour}
	for _, dependency := range dependencies {
		switch value := dependency.(type) {
		case PolicyProvider:
			service.policy = value
		case VerificationProvider:
			service.verifier = value
		}
	}
	return service
}

func (s *Service) Register(ctx context.Context, input RegisterInput) (TokenPair, error) {
	policy, err := s.authPolicy(ctx, input.AppID)
	if err != nil {
		return TokenPair{}, err
	}
	if !policy.RegistrationEnabled {
		return TokenPair{}, ErrRegistrationDisabled
	}
	input.IdentifierType = strings.ToLower(strings.TrimSpace(input.IdentifierType))
	input.Identifier = strings.ToLower(strings.TrimSpace(input.Identifier))
	if input.IdentifierType == "" {
		input.IdentifierType = "username"
		input.Identifier = input.Username
	}
	if input.IdentifierType == "phone" && !policy.PhoneEnabled || input.IdentifierType == "email" && !policy.EmailEnabled || input.IdentifierType == "username" && !policy.UsernamePasswordEnabled {
		return TokenPair{}, ErrAuthMethodDisabled
	}
	if input.IdentifierType != "username" {
		if err := s.verifyProof(ctx, input.AppID, "register", input.Identifier, input.Proof, policy.RegisterCaptchaRequired, policy.RegisterCodeRequired); err != nil {
			return TokenPair{}, err
		}
		if input.Username == "" {
			input.Username = randomUsername()
		}
		if input.Nickname == "" {
			input.Nickname = randomNickname()
		}
	} else if err := s.verifyProof(ctx, input.AppID, "register", "", input.Proof, policy.RegisterCaptchaRequired, false); err != nil {
		return TokenPair{}, err
	}
	input.Username = strings.ToLower(strings.TrimSpace(input.Username))
	input.Nickname = strings.TrimSpace(input.Nickname)
	if input.AppID == 0 || !usernamePattern.MatchString(input.Username) {
		return TokenPair{}, fmt.Errorf("invalid username")
	}
	if input.Nickname == "" {
		input.Nickname = input.Username
	}
	if err := validateDevice(input.Device); err != nil {
		return TokenPair{}, err
	}
	hash, err := s.password.Hash(input.Password)
	if err != nil {
		return TokenPair{}, err
	}
	sessionID, err := s.tokens.NewSessionID()
	if err != nil {
		return TokenPair{}, err
	}
	refreshToken, refreshHash, err := newRefreshToken(sessionID)
	if err != nil {
		return TokenPair{}, err
	}
	user := User{AppID: input.AppID, Username: input.Username, Nickname: input.Nickname, PasswordHash: hash, SessionVersion: 1, Status: 1}
	user.InvitationCode = randomInvitationCode()
	if input.IdentifierType == "phone" || input.IdentifierType == "email" {
		user.ContactType = input.IdentifierType
		user.ContactIdentifier = input.Identifier
	}
	session := Session{ID: sessionID, AppID: input.AppID, Platform: input.Device.Platform, DeviceID: input.Device.ID, DeviceName: input.Device.Name, RefreshTokenHash: refreshHash, SessionVersion: 1, ExpiresAt: s.now().UTC().Add(s.refreshTTL)}
	created, err := s.repository.CreateUser(ctx, user, session)
	if err != nil {
		return TokenPair{}, err
	}
	return s.issuePair(created, session, refreshToken)
}

func (s *Service) Login(ctx context.Context, input LoginInput) (TokenPair, error) {
	input.Username = strings.ToLower(strings.TrimSpace(input.Username))
	policy, err := s.authPolicy(ctx, input.AppID)
	if err != nil {
		return TokenPair{}, err
	}
	target := ""
	method := "username"
	if strings.Contains(input.Username, "@") {
		method = "email"
		target = input.Username
	} else if regexp.MustCompile(`^\+?[0-9]{7,15}$`).MatchString(input.Username) {
		method = "phone"
		target = input.Username
	}
	if method == "username" && !policy.UsernamePasswordEnabled || method == "phone" && !policy.PhoneEnabled || method == "email" && !policy.EmailEnabled {
		return TokenPair{}, ErrAuthMethodDisabled
	}
	if err := s.verifyProof(ctx, input.AppID, "login", target, input.Proof, policy.LoginCaptchaRequired, policy.LoginCodeRequired); err != nil {
		return TokenPair{}, err
	}
	if err := validateDevice(input.Device); err != nil {
		return TokenPair{}, err
	}
	user, err := s.repository.FindPasswordUser(ctx, input.AppID, input.Username)
	if err != nil {
		return TokenPair{}, ErrInvalidCredentials
	}
	ok, verifyErr := s.password.Verify(user.PasswordHash, input.Password)
	if verifyErr != nil || !ok || user.Status != 1 {
		return TokenPair{}, ErrInvalidCredentials
	}
	sessionID, err := s.tokens.NewSessionID()
	if err != nil {
		return TokenPair{}, err
	}
	refreshToken, refreshHash, err := newRefreshToken(sessionID)
	if err != nil {
		return TokenPair{}, err
	}
	session := Session{ID: sessionID, AppID: user.AppID, UserID: user.ID, Platform: input.Device.Platform, DeviceID: input.Device.ID, DeviceName: input.Device.Name, RefreshTokenHash: refreshHash, SessionVersion: user.SessionVersion, ExpiresAt: s.now().UTC().Add(s.refreshTTL)}
	if err := s.repository.ReplacePlatformSession(ctx, user, session); err != nil {
		return TokenPair{}, err
	}
	return s.issuePair(user, session, refreshToken)
}

// LoginWithCode authenticates a verified phone number or email address without
// accepting a reusable password. Verification challenges are single-use.
func (s *Service) LoginWithCode(ctx context.Context, input CodeLoginInput) (TokenPair, error) {
	input.Target = strings.ToLower(strings.TrimSpace(input.Target))
	policy, err := s.authPolicy(ctx, input.AppID)
	if err != nil {
		return TokenPair{}, err
	}
	method := "email"
	if regexp.MustCompile(`^\+?[0-9]{7,15}$`).MatchString(input.Target) {
		method = "phone"
	}
	if method == "phone" && !policy.PhoneEnabled || method == "email" && !policy.EmailEnabled {
		return TokenPair{}, ErrAuthMethodDisabled
	}
	if s.verifier == nil || s.verifier.Verify(ctx, input.AppID, input.Proof.VerificationID, "login", input.Target, input.Proof.VerificationCode) != nil {
		return TokenPair{}, ErrVerificationRequired
	}
	if err := validateDevice(input.Device); err != nil {
		return TokenPair{}, err
	}
	user, err := s.repository.FindPasswordUser(ctx, input.AppID, input.Target)
	if err != nil || user.Status != 1 {
		return TokenPair{}, ErrInvalidCredentials
	}
	sessionID, err := s.tokens.NewSessionID()
	if err != nil {
		return TokenPair{}, err
	}
	refreshToken, refreshHash, err := newRefreshToken(sessionID)
	if err != nil {
		return TokenPair{}, err
	}
	session := Session{ID: sessionID, AppID: user.AppID, UserID: user.ID, Platform: input.Device.Platform, DeviceID: input.Device.ID, DeviceName: input.Device.Name, RefreshTokenHash: refreshHash, SessionVersion: user.SessionVersion, ExpiresAt: s.now().UTC().Add(s.refreshTTL)}
	if err := s.repository.ReplacePlatformSession(ctx, user, session); err != nil {
		return TokenPair{}, err
	}
	return s.issuePair(user, session, refreshToken)
}

func (s *Service) SecurityMethods(ctx context.Context, appID, userID uint64) ([]SecurityMethod, error) {
	return s.repository.SecurityMethods(ctx, appID, userID)
}

func (s *Service) BindSecurityMethod(ctx context.Context, appID, userID uint64, method, identifier string, proof VerificationProof) error {
	method = strings.ToLower(strings.TrimSpace(method))
	identifier = strings.ToLower(strings.TrimSpace(identifier))
	if method != "phone" && method != "email" {
		return ErrAuthMethodDisabled
	}
	if s.verifier == nil || s.verifier.Verify(ctx, appID, proof.VerificationID, "bind_"+method, identifier, proof.VerificationCode) != nil {
		return ErrVerificationRequired
	}
	return s.repository.BindSecurityMethod(ctx, appID, userID, method, identifier)
}

func (s *Service) authPolicy(ctx context.Context, appID uint64) (appconfig.AuthPolicy, error) {
	if s.policy == nil {
		return appconfig.AuthPolicy{RegistrationEnabled: true, UsernamePasswordEnabled: true}, nil
	}
	return s.policy.AuthPolicy(ctx, appID)
}
func (s *Service) verifyProof(ctx context.Context, appID uint64, scene, target string, proof VerificationProof, captchaRequired, codeRequired bool) error {
	if captchaRequired {
		if s.verifier == nil {
			return ErrVerificationRequired
		}
		if err := s.verifier.Verify(ctx, appID, proof.CaptchaID, "captcha", "", proof.CaptchaCode); err != nil {
			return ErrVerificationRequired
		}
	}
	if codeRequired {
		if target == "" || s.verifier == nil {
			return ErrVerificationRequired
		}
		if err := s.verifier.Verify(ctx, appID, proof.VerificationID, scene, target, proof.VerificationCode); err != nil {
			return ErrVerificationRequired
		}
	}
	return nil
}
func randomUsername() string {
	value, _ := randomTokenBytes(8)
	return "bim" + strings.ToLower(hex.EncodeToString(value))[:13]
}
func randomNickname() string {
	value, _ := randomTokenBytes(3)
	return "BIM用户" + strings.ToUpper(hex.EncodeToString(value))
}
func randomInvitationCode() string {
	value, _ := randomTokenBytes(6)
	return strings.ToUpper(hex.EncodeToString(value))
}
func randomTokenBytes(n int) ([]byte, error) {
	value := make([]byte, n)
	_, err := rand.Read(value)
	return value, err
}

func (s *Service) Refresh(ctx context.Context, refreshToken string) (TokenPair, error) {
	sessionID, err := refreshSessionID(refreshToken)
	if err != nil {
		return TokenPair{}, ErrSessionRevoked
	}
	session, err := s.repository.FindSession(ctx, sessionID)
	if err != nil || session.RefreshTokenHash != hashToken(refreshToken) || session.ExpiresAt.Before(s.now().UTC()) {
		return TokenPair{}, ErrSessionRevoked
	}
	user, err := s.repository.FindUserByID(ctx, session.AppID, session.UserID)
	if err != nil || user.Status != 1 || user.SessionVersion != session.SessionVersion {
		_ = s.repository.RevokeSession(ctx, session.ID)
		return TokenPair{}, ErrSessionRevoked
	}
	newRefresh, newHash, err := newRefreshToken(session.ID)
	if err != nil {
		return TokenPair{}, err
	}
	refreshExpiresAt := s.now().UTC().Add(s.refreshTTL)
	if err := s.repository.RotateSession(ctx, session.ID, newHash, refreshExpiresAt); err != nil {
		return TokenPair{}, err
	}
	session.RefreshTokenHash = newHash
	session.ExpiresAt = refreshExpiresAt
	return s.issuePair(user, session, newRefresh)
}

func (s *Service) Logout(ctx context.Context, sessionID string) error {
	return s.repository.RevokeSession(ctx, sessionID)
}

func (s *Service) Authenticate(ctx context.Context, accessToken string) (Principal, error) {
	claims, err := s.tokens.Parse(accessToken, "access")
	if err != nil {
		return Principal{}, ErrSessionRevoked
	}
	session, err := s.repository.FindSession(ctx, claims.SessionID)
	if err != nil || session.AppID != claims.AppID || session.UserID != claims.Subject ||
		session.Platform != claims.Platform || session.DeviceID != claims.DeviceID ||
		session.SessionVersion != claims.SessionVersion || session.ExpiresAt.Before(s.now().UTC()) {
		return Principal{}, ErrSessionRevoked
	}
	user, err := s.repository.FindUserByID(ctx, claims.AppID, claims.Subject)
	if err != nil || user.Status != 1 || user.SessionVersion != claims.SessionVersion {
		return Principal{}, ErrSessionRevoked
	}
	return Principal{User: user, SessionID: session.ID, Platform: session.Platform, DeviceID: session.DeviceID}, nil
}

func (s *Service) issuePair(user User, session Session, refreshToken string) (TokenPair, error) {
	expiresAt := s.now().UTC().Add(s.accessTTL)
	access, err := s.tokens.Issue(authn.Claims{Subject: user.ID, AppID: user.AppID, SessionID: session.ID, Platform: session.Platform, DeviceID: session.DeviceID, SessionVersion: user.SessionVersion, Type: "access"}, s.accessTTL)
	if err != nil {
		return TokenPair{}, err
	}
	if refreshToken == "" {
		return TokenPair{}, errors.New("refresh token is empty")
	}
	return TokenPair{AccessToken: access, RefreshToken: refreshToken, ExpiresAt: expiresAt, SessionID: session.ID, User: UserView{ID: user.ID, Username: user.Username, Nickname: user.Nickname}}, nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func newRefreshToken(sessionID string) (string, string, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", "", err
	}
	token := sessionID + "." + base64.RawURLEncoding.EncodeToString(raw[:])
	return token, hashToken(token), nil
}

func refreshSessionID(token string) (string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 || parts[0] == "" || len(parts[1]) < 32 {
		return "", ErrSessionRevoked
	}
	return parts[0], nil
}

func validateDevice(device Device) error {
	device.Platform = strings.TrimSpace(device.Platform)
	device.ID = strings.TrimSpace(device.ID)
	if device.Platform == "" || device.ID == "" || len(device.ID) > 128 {
		return fmt.Errorf("invalid device")
	}
	return nil
}
