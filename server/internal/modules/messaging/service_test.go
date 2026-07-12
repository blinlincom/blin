package messaging

import (
	"context"
	"errors"
	"testing"
)

type captureRepo struct {
	hash    string
	payload []byte
}

func (r *captureRepo) History(context.Context, HistoryInput) ([]MessageView, error) { return nil, nil }
func (r *captureRepo) MarkRead(context.Context, uint64, uint64, string, uint8, uint64) error {
	return nil
}
func (r *captureRepo) HideMessage(context.Context, uint64, uint64, uint64) error { return nil }
func (r *captureRepo) ClearConversation(context.Context, uint64, uint64, string, uint8) error {
	return nil
}
func (r *captureRepo) Recall(context.Context, uint64, uint64, uint64, string) (QueuedMessage, error) {
	return QueuedMessage{}, nil
}
func (r *captureRepo) BurnAfterRead(context.Context, uint64, uint64, uint64, string) (QueuedMessage, error) {
	return QueuedMessage{}, nil
}
func (r *captureRepo) Conversations(context.Context, uint64, uint64, int) ([]ConversationView, error) {
	return nil, nil
}
func (r *captureRepo) ReadReceiptSummary(context.Context, uint64, uint64, uint64) (ReadReceiptSummary, error) {
	return ReadReceiptSummary{}, nil
}

func (r *captureRepo) Queue(_ context.Context, _ SendInput, payload []byte, hash string) (QueuedMessage, error) {
	r.hash = hash
	r.payload = payload
	return QueuedMessage{ID: 1}, nil
}
func TestSendCanonicalizesProtocolAndDoesNotMutateInput(t *testing.T) {
	repo := &captureRepo{}
	service := NewService(repo)
	payload := map[string]any{"content": "hello"}
	_, err := service.Send(context.Background(), SendInput{AppID: 1, SenderID: 2, ChannelID: "u_3", ChannelType: ChannelPerson, ClientMsgNo: "m1", ContentType: TypeText, Payload: payload})
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := payload["protocol"]; ok {
		t.Fatal("input payload mutated")
	}
	if repo.hash == "" || len(repo.payload) == 0 {
		t.Fatal("canonical payload missing")
	}
}
func TestSendRejectsUnknownType(t *testing.T) {
	_, err := NewService(&captureRepo{}).Send(context.Background(), SendInput{AppID: 1, SenderID: 2, ChannelID: "u_3", ChannelType: 1, ClientMsgNo: "m1", ContentType: 777, Payload: map[string]any{}})
	if err == nil || errors.Is(err, ErrForbidden) {
		t.Fatalf("error=%v", err)
	}
}
