package messaging

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"time"

	"bim/server/internal/platform/database"
)

type SenderRequest struct {
	FromUID, ChannelID, ClientMsgNo string
	ChannelType                     uint8
	ContentType                     uint32
	Payload                         any
	System                          bool
}
type SenderResponse struct {
	MessageID   string
	MessageSeq  uint64
	ClientMsgNo string
}
type Sender interface {
	Send(context.Context, SenderRequest) (SenderResponse, error)
}

type DispatchItem struct {
	OutboxID    uint64
	MessageID   uint64
	AppID       uint64
	SenderID    uint64
	ClientMsgNo string
	ChannelID   string
	ChannelType uint8
	ContentType uint32
	Payload     map[string]any
	Attempts    uint32
}

type Dispatcher struct {
	db       *database.DB
	sender   Sender
	workerID string
	maxTries uint32
}

func NewDispatcher(db *database.DB, sender Sender, workerID string) *Dispatcher {
	return &Dispatcher{db: db, sender: sender, workerID: workerID, maxTries: 12}
}

func (d *Dispatcher) Run(ctx context.Context) error {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			for i := 0; i < 50; i++ {
				item, ok, err := d.claim(ctx)
				if err != nil {
					return err
				}
				if !ok {
					break
				}
				d.deliver(ctx, item)
			}
		}
	}
}

func (d *Dispatcher) claim(ctx context.Context) (DispatchItem, bool, error) {
	var item DispatchItem
	err := d.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var payloadRaw []byte
		err := tx.QueryRowContext(ctx, `SELECT o.id,o.message_id,m.app_id,m.sender_id,m.client_msg_no,m.channel_id,m.channel_type,m.content_type,m.payload_json,o.attempts FROM message_outbox o JOIN messages m ON m.id=o.message_id WHERE o.status IN ('pending','retry') AND o.next_attempt_at<=NOW(6) ORDER BY o.id LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&item.OutboxID, &item.MessageID, &item.AppID, &item.SenderID, &item.ClientMsgNo, &item.ChannelID, &item.ChannelType, &item.ContentType, &payloadRaw, &item.Attempts)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := json.Unmarshal(payloadRaw, &item.Payload); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE message_outbox SET status='processing',locked_at=NOW(6),lock_owner=?,updated_at=NOW(6) WHERE id=?`, d.workerID, item.OutboxID)
		return err
	})
	if err != nil {
		return DispatchItem{}, false, err
	}
	return item, item.OutboxID != 0, nil
}

func (d *Dispatcher) deliver(ctx context.Context, item DispatchItem) {
	fromUID := fmt.Sprintf("app%duser%d", item.AppID, item.SenderID)
	response, err := d.sender.Send(ctx, SenderRequest{FromUID: fromUID, ChannelID: item.ChannelID, ChannelType: item.ChannelType, ClientMsgNo: item.ClientMsgNo, ContentType: item.ContentType, Payload: item.Payload, System: boolValue(item.Payload["system_message"])})
	if err == nil {
		_, _ = d.db.ExecContext(ctx, `UPDATE messages m JOIN message_outbox o ON o.message_id=m.id SET m.message_id=?,m.message_seq=?,m.status='sent',m.sent_at=NOW(6),m.updated_at=NOW(6),o.status='sent',o.last_error='',o.updated_at=NOW(6) WHERE o.id=? AND o.lock_owner=?`, response.MessageID, response.MessageSeq, item.OutboxID, d.workerID)
		return
	}
	attempts := item.Attempts + 1
	status := "retry"
	if attempts >= d.maxTries {
		status = "failed"
	}
	delay := retryDelay(attempts)
	_, _ = d.db.ExecContext(ctx, `UPDATE message_outbox o JOIN messages m ON m.id=o.message_id SET o.status=?,o.attempts=?,o.next_attempt_at=?,o.last_error=?,o.lock_owner='',o.locked_at=NULL,o.updated_at=NOW(6),m.status=?,m.updated_at=NOW(6) WHERE o.id=? AND o.lock_owner=?`, status, attempts, time.Now().UTC().Add(delay), truncate(err.Error(), 1000), status, item.OutboxID, d.workerID)
}

func retryDelay(attempt uint32) time.Duration {
	power := math.Min(float64(attempt), 8)
	base := time.Duration(math.Pow(2, power)) * time.Second
	jitter := time.Duration(rand.IntN(1000)) * time.Millisecond
	return base + jitter
}
func boolValue(value any) bool { v, ok := value.(bool); return ok && v }
func truncate(value string, max int) string {
	if len(value) <= max {
		return value
	}
	return value[:max]
}
