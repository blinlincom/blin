package wallet

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"bim/server/internal/platform/authn"
)

type Service struct {
	repository   Repository
	password     authn.PasswordPolicy
	maxAttempts  uint8
	lockDuration time.Duration
	transferTTL  time.Duration
	now          func() time.Time
	verifier     VerificationProvider
}

type VerificationProvider interface {
	Verify(context.Context, uint64, uint64, string, string, string) error
}

func NewService(repository Repository, maxAttempts int, lockDuration time.Duration, verifier ...VerificationProvider) *Service {
	service := &Service{repository: repository, password: authn.DefaultPasswordPolicy(), maxAttempts: uint8(maxAttempts), lockDuration: lockDuration, transferTTL: 24 * time.Hour, now: time.Now}
	if len(verifier) > 0 {
		service.verifier = verifier[0]
	}
	return service
}
func (s *Service) Balance(ctx context.Context, appID, userID uint64) (Balance, error) {
	return s.repository.Balance(ctx, appID, userID)
}
func (s *Service) SetPaymentPassword(ctx context.Context, appID, userID uint64, password, method string, verificationID uint64, verificationCode string) error {
	verified, err := s.repository.HasVerifiedSecurityMethod(ctx, appID, userID)
	if err != nil {
		return err
	}
	if !verified {
		return ErrSecurityMethod
	}
	identifier, err := s.repository.SecurityIdentifier(ctx, appID, userID, method)
	if err != nil || s.verifier == nil || s.verifier.Verify(ctx, appID, verificationID, "payment_password", identifier, verificationCode) != nil {
		return ErrSecurityMethod
	}
	if len(password) < 6 || len(password) > 64 {
		return fmt.Errorf("invalid payment password")
	}
	hash, err := s.password.Hash(password)
	if err != nil {
		return err
	}
	return s.repository.SetPaymentPassword(ctx, appID, userID, hash)
}
func (s *Service) verifyPassword(ctx context.Context, appID, userID uint64, password string) error {
	hash, attempts, lockedUntil, err := s.repository.PaymentCredential(ctx, appID, userID)
	if err != nil {
		return ErrPaymentPassword
	}
	now := s.now().UTC()
	if lockedUntil != nil && lockedUntil.After(now) {
		return ErrPaymentPasswordLock
	}
	ok, verifyErr := s.password.Verify(hash, password)
	if verifyErr != nil || !ok {
		attempts++
		var nextLock *time.Time
		if attempts >= s.maxAttempts {
			value := now.Add(s.lockDuration)
			nextLock = &value
		}
		_ = s.repository.RecordPasswordFailure(ctx, appID, userID, attempts, nextLock)
		if nextLock != nil {
			return ErrPaymentPasswordLock
		}
		return ErrPaymentPassword
	}
	if attempts > 0 || lockedUntil != nil {
		_ = s.repository.ResetPasswordFailures(ctx, appID, userID)
	}
	return nil
}
func (s *Service) VerifyPaymentPassword(ctx context.Context, appID, userID uint64, password string) error {
	return s.verifyPassword(ctx, appID, userID, password)
}
func (s *Service) CreateTransfer(ctx context.Context, appID, senderID, recipientID uint64, amountText, paymentPassword string) (Transfer, error) {
	if senderID == recipientID {
		return Transfer{}, ErrOrderState
	}
	amount, err := ParseAmount(amountText)
	if err != nil {
		return Transfer{}, err
	}
	if err := s.verifyPassword(ctx, appID, senderID, paymentPassword); err != nil {
		return Transfer{}, err
	}
	orderNo, err := newOrderNo("TR")
	if err != nil {
		return Transfer{}, err
	}
	return s.repository.CreateTransfer(ctx, appID, senderID, recipientID, amount, orderNo, s.now().UTC().Add(s.transferTTL))
}
func (s *Service) AcceptTransfer(ctx context.Context, appID, recipientID uint64, orderNo string) (Transfer, error) {
	return s.repository.AcceptTransfer(ctx, appID, recipientID, strings.TrimSpace(orderNo))
}
func (s *Service) RefundExpiredTransfers(ctx context.Context, limit int) (int, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	return s.repository.RefundExpiredTransfers(ctx, limit)
}

func (s *Service) CreateRedPacket(ctx context.Context, appID, senderID uint64, channelID string, channelType uint8, packetType string, designatedUserID *uint64, amountText string, count uint32, greeting, paymentPassword string) (RedPacket, error) {
	amount, err := ParseAmount(amountText)
	if err != nil {
		return RedPacket{}, err
	}
	channelID, packetType, greeting = strings.TrimSpace(channelID), strings.TrimSpace(packetType), strings.TrimSpace(greeting)
	if greeting == "" {
		greeting = "恭喜发财，大吉大利"
	}
	if len([]rune(greeting)) > 100 {
		return RedPacket{}, ErrOrderState
	}
	if channelType == 1 {
		packetType, count = "normal", 1
	} else if channelType != 2 {
		return RedPacket{}, ErrOrderState
	}
	if count == 0 || count > 500 || amount < int64(count) {
		return RedPacket{}, ErrInvalidAmount
	}
	if packetType != "normal" && packetType != "lucky" && packetType != "designated" {
		return RedPacket{}, ErrOrderState
	}
	if packetType == "designated" && (designatedUserID == nil || *designatedUserID == 0) {
		return RedPacket{}, ErrOrderState
	}
	if packetType == "designated" {
		count = 1
	}
	if err := s.verifyPassword(ctx, appID, senderID, paymentPassword); err != nil {
		return RedPacket{}, err
	}
	orderNo, err := newOrderNo("RP")
	if err != nil {
		return RedPacket{}, err
	}
	return s.repository.CreateRedPacket(ctx, appID, senderID, channelID, channelType, packetType, designatedUserID, amount, count, greeting, orderNo, s.now().UTC().Add(24*time.Hour))
}

func (s *Service) ClaimRedPacket(ctx context.Context, appID, userID uint64, orderNo string) (RedPacketClaim, error) {
	return s.repository.ClaimRedPacket(ctx, appID, userID, strings.TrimSpace(orderNo))
}
func (s *Service) RefundExpiredRedPackets(ctx context.Context, limit int) (int, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	return s.repository.RefundExpiredRedPackets(ctx, limit)
}
func newOrderNo(prefix string) (string, error) {
	var raw [15]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return prefix + time.Now().UTC().Format("20060102150405") + base64.RawURLEncoding.EncodeToString(raw[:]), nil
}

var _ = errors.Is
