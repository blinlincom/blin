package wallet

import (
	"context"
	"errors"
	"time"
)

var (
	ErrInsufficientBalance = errors.New("insufficient balance")
	ErrWalletLocked        = errors.New("wallet locked")
	ErrPaymentPassword     = errors.New("payment password invalid")
	ErrPaymentPasswordLock = errors.New("payment password locked")
	ErrOrderNotFound       = errors.New("order not found")
	ErrOrderState          = errors.New("invalid order state")
	ErrSecurityMethod      = errors.New("verified security method required")
)

type Balance struct {
	Available  int64  `json:"available"`
	Frozen     int64  `json:"frozen"`
	Currency   string `json:"currency"`
	Status     string `json:"status"`
	LockReason string `json:"lock_reason,omitempty"`
}
type Transfer struct {
	ID          uint64    `json:"id"`
	OrderNo     string    `json:"order_no"`
	SenderID    uint64    `json:"sender_id"`
	RecipientID uint64    `json:"recipient_id"`
	Amount      int64     `json:"amount"`
	Status      string    `json:"status"`
	ExpiresAt   time.Time `json:"expires_at"`
	CreatedAt   time.Time `json:"created_at"`
}
type RedPacket struct {
	ID              uint64    `json:"id"`
	OrderNo         string    `json:"order_no"`
	SenderID        uint64    `json:"sender_id"`
	ChannelID       string    `json:"channel_id"`
	ChannelType     uint8     `json:"channel_type"`
	PacketType      string    `json:"packet_type"`
	TotalAmount     int64     `json:"total_amount"`
	TotalCount      uint32    `json:"total_count"`
	RemainingAmount int64     `json:"remaining_amount"`
	RemainingCount  uint32    `json:"remaining_count"`
	Greeting        string    `json:"greeting"`
	Status          string    `json:"status"`
	ExpiresAt       time.Time `json:"expires_at"`
	CreatedAt       time.Time `json:"created_at"`
}
type RedPacketClaim struct {
	RedPacketID uint64    `json:"red_packet_id"`
	OrderNo     string    `json:"order_no"`
	UserID      uint64    `json:"user_id"`
	Amount      int64     `json:"amount"`
	CreatedAt   time.Time `json:"created_at"`
}

type Repository interface {
	Balance(context.Context, uint64, uint64) (Balance, error)
	HasVerifiedSecurityMethod(context.Context, uint64, uint64) (bool, error)
	SecurityIdentifier(context.Context, uint64, uint64, string) (string, error)
	SetPaymentPassword(context.Context, uint64, uint64, string) error
	PaymentCredential(context.Context, uint64, uint64) (string, uint8, *time.Time, error)
	RecordPasswordFailure(context.Context, uint64, uint64, uint8, *time.Time) error
	ResetPasswordFailures(context.Context, uint64, uint64) error
	CreateTransfer(context.Context, uint64, uint64, uint64, int64, string, time.Time) (Transfer, error)
	AcceptTransfer(context.Context, uint64, uint64, string) (Transfer, error)
	RefundExpiredTransfers(context.Context, int) (int, error)
	CreateRedPacket(context.Context, uint64, uint64, string, uint8, string, *uint64, int64, uint32, string, string, time.Time) (RedPacket, error)
	ClaimRedPacket(context.Context, uint64, uint64, string) (RedPacketClaim, error)
	RefundExpiredRedPackets(context.Context, int) (int, error)
}
