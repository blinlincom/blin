package messaging

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

type EventPublisher interface {
	Publish(context.Context, string, map[string]any) error
}

type Service struct {
	repository Repository
	publisher  EventPublisher
}

func NewService(repository Repository, publishers ...EventPublisher) *Service {
	service := &Service{repository: repository}
	if len(publishers) > 0 {
		service.publisher = publishers[0]
	}
	return service
}

func (s *Service) Send(ctx context.Context, input SendInput) (QueuedMessage, error) {
	input.ClientMsgNo = strings.TrimSpace(input.ClientMsgNo)
	input.ChannelID = strings.TrimSpace(input.ChannelID)
	if input.AppID == 0 || input.SenderID == 0 || input.ClientMsgNo == "" || len(input.ClientMsgNo) > 64 || input.ChannelID == "" || len(input.ChannelID) > 128 {
		return QueuedMessage{}, fmt.Errorf("invalid message identity")
	}
	if input.ChannelType != ChannelPerson && input.ChannelType != ChannelGroup {
		return QueuedMessage{}, fmt.Errorf("invalid channel type")
	}
	if err := ValidateContentType(input.ContentType); err != nil {
		return QueuedMessage{}, err
	}
	if _, err := HeaderFor(input.ContentType, input.System); err != nil {
		return QueuedMessage{}, err
	}
	if err := validatePayload(input.ContentType, input.Payload); err != nil {
		return QueuedMessage{}, err
	}
	payload := cloneMap(input.Payload)
	payload["protocol"] = "blin.chat.v1"
	payload["type"] = input.ContentType
	payload["channel_type"] = input.ChannelType
	payload["sender_id"] = input.SenderID
	canonical, err := json.Marshal(payload)
	if err != nil {
		return QueuedMessage{}, fmt.Errorf("encode payload: %w", err)
	}
	sum := sha256.Sum256(canonical)
	input.Payload = payload
	return s.repository.Queue(ctx, input, canonical, hex.EncodeToString(sum[:]))
}

func validatePayload(contentType uint32, payload map[string]any) error {
	if payload == nil {
		return ErrInvalidPayload
	}
	requiresAsset := contentType == TypeImage || contentType == TypeVoice || contentType == TypeVideo || contentType == TypeFile || contentType == TypeGIF || contentType == TypeSticker
	if requiresAsset {
		values, ok := payload["asset_ids"].([]any)
		if !ok || len(values) == 0 || len(values) > 20 {
			return ErrInvalidPayload
		}
		for _, value := range values {
			number, ok := value.(float64)
			if !ok || number < 1 || number != float64(uint64(number)) {
				return ErrInvalidPayload
			}
		}
	}
	if contentType == TypeText {
		content, ok := payload["content"].(string)
		if !ok || strings.TrimSpace(content) == "" || len([]rune(content)) > 10000 {
			return ErrInvalidPayload
		}
	}
	return nil
}

func (s *Service) History(ctx context.Context, input HistoryInput) ([]MessageView, error) {
	if input.Limit <= 0 {
		input.Limit = 30
	}
	if input.Limit > 100 {
		input.Limit = 100
	}
	if input.ChannelType != ChannelPerson && input.ChannelType != ChannelGroup {
		return nil, fmt.Errorf("invalid channel type")
	}
	return s.repository.History(ctx, input)
}

func (s *Service) Conversations(ctx context.Context, appID, userID uint64, limit int) ([]ConversationView, error) {
	if limit <= 0 {
		limit = 100
	}
	if limit > 200 {
		limit = 200
	}
	return s.repository.Conversations(ctx, appID, userID, limit)
}
func (s *Service) ReadReceiptSummary(ctx context.Context, appID, userID, messageID uint64) (ReadReceiptSummary, error) {
	return s.repository.ReadReceiptSummary(ctx, appID, userID, messageID)
}

func (s *Service) MarkRead(ctx context.Context, appID, userID uint64, channelID string, channelType uint8, throughSeq uint64) error {
	channelID = strings.TrimSpace(channelID)
	if throughSeq == 0 || (channelType != ChannelPerson && channelType != ChannelGroup) {
		return fmt.Errorf("invalid read cursor")
	}
	if err := s.repository.MarkRead(ctx, appID, userID, channelID, channelType, throughSeq); err != nil {
		return err
	}
	if s.publisher != nil {
		event := map[string]any{
			"app_id": appID, "sender_id": userID, "channel_id": channelID,
			"channel_type": channelType, "through_seq": throughSeq,
		}
		if err := s.publisher.Publish(ctx, "read_receipt", event); err != nil {
			return fmt.Errorf("publish read receipt: %w", err)
		}
	}
	return nil
}

func (s *Service) HideMessage(ctx context.Context, appID, userID, messageID uint64) error {
	return s.repository.HideMessage(ctx, appID, userID, messageID)
}

func (s *Service) ClearConversation(ctx context.Context, appID, userID uint64, channelID string, channelType uint8) error {
	return s.repository.ClearConversation(ctx, appID, userID, strings.TrimSpace(channelID), channelType)
}

func (s *Service) Recall(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error) {
	return s.repository.Recall(ctx, appID, userID, messageID, strings.TrimSpace(eventClientMsgNo))
}

func (s *Service) BurnAfterRead(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error) {
	return s.repository.BurnAfterRead(ctx, appID, userID, messageID, strings.TrimSpace(eventClientMsgNo))
}

func cloneMap(source map[string]any) map[string]any {
	result := make(map[string]any, len(source)+4)
	for key, value := range source {
		result[key] = value
	}
	return result
}
