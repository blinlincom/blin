package messaging

import (
	"context"
	"errors"
	"time"
)

var (
	ErrForbidden         = errors.New("message forbidden")
	ErrMuted             = errors.New("sender muted")
	ErrStrangerLimit     = errors.New("stranger message limit reached")
	ErrClientMsgConflict = errors.New("client_msg_no conflict")
	ErrInvalidPayload    = errors.New("invalid message payload")
)

type SendInput struct {
	AppID       uint64
	SenderID    uint64
	ChannelID   string
	ChannelType uint8
	ClientMsgNo string
	ContentType uint32
	Payload     map[string]any
	System      bool
}

type QueuedMessage struct {
	ID          uint64    `json:"id"`
	ClientMsgNo string    `json:"client_msg_no"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	Duplicate   bool      `json:"duplicate"`
}

type MessageView struct {
	ID          uint64         `json:"id"`
	ClientMsgNo string         `json:"client_msg_no"`
	MessageID   string         `json:"message_id"`
	MessageSeq  uint64         `json:"message_seq"`
	SyncSeq     uint64         `json:"sync_seq"`
	SenderID    uint64         `json:"sender_id"`
	ContentType uint32         `json:"content_type"`
	Payload     map[string]any `json:"payload"`
	Status      string         `json:"status"`
	CreatedAt   time.Time      `json:"created_at"`
	ReadAt      *time.Time     `json:"read_at,omitempty"`
}

type ConversationView struct {
	ChannelID     string      `json:"channel_id"`
	ChannelType   uint8       `json:"channel_type"`
	Title         string      `json:"title"`
	AvatarAssetID uint64      `json:"avatar_asset_id"`
	LastMessage   MessageView `json:"last_message"`
	UnreadCount   uint32      `json:"unread_count"`
	Pinned        bool        `json:"pinned"`
	Muted         bool        `json:"muted"`
	UpdatedAt     time.Time   `json:"updated_at"`
}

type ReadReceiptSummary struct {
	ReadCount       uint32 `json:"read_count"`
	TotalRecipients uint32 `json:"total_recipients"`
}
type HistoryInput struct {
	AppID, UserID uint64
	ChannelID     string
	ChannelType   uint8
	BeforeSeq     uint64
	Limit         int
}

type Repository interface {
	Queue(ctx context.Context, input SendInput, canonicalPayload []byte, payloadHash string) (QueuedMessage, error)
	History(ctx context.Context, input HistoryInput) ([]MessageView, error)
	Conversations(ctx context.Context, appID, userID uint64, limit int) ([]ConversationView, error)
	ReadReceiptSummary(ctx context.Context, appID, userID, messageID uint64) (ReadReceiptSummary, error)
	MarkRead(ctx context.Context, appID, userID uint64, channelID string, channelType uint8, throughSeq uint64) error
	HideMessage(ctx context.Context, appID, userID, messageID uint64) error
	ClearConversation(ctx context.Context, appID, userID uint64, channelID string, channelType uint8) error
	Recall(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error)
	BurnAfterRead(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error)
}
