package wukong

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"

	"bim/server/internal/platform/database"
)

type ChannelDispatcher struct {
	db     *database.DB
	client *Client
	owner  string
}

func NewChannelDispatcher(db *database.DB, client *Client, owner string) *ChannelDispatcher {
	return &ChannelDispatcher{db: db, client: client, owner: owner}
}

func (d *ChannelDispatcher) Run(ctx context.Context) error {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := d.dispatchOne(ctx); err != nil && !errors.Is(err, sql.ErrNoRows) {
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(time.Second):
				}
			}
		}
	}
}

func (d *ChannelDispatcher) dispatchOne(ctx context.Context) error {
	type task struct {
		ID        uint64
		Operation string
		ChannelID string
		Payload   []byte
		Attempts  uint32
	}
	var current task
	err := d.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx, `SELECT id,operation,channel_id,payload_json,attempts FROM wukong_channel_outbox WHERE status IN ('pending','retry') AND next_attempt_at<=NOW(6) ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&current.ID, &current.Operation, &current.ChannelID, &current.Payload, &current.Attempts)
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE wukong_channel_outbox SET status='processing',locked_at=NOW(6),lock_owner=?,updated_at=NOW(6) WHERE id=?`, d.owner, current.ID)
		return err
	})
	if err != nil {
		return err
	}
	var payload struct {
		Members []string `json:"members"`
	}
	if err := json.Unmarshal(current.Payload, &payload); err != nil {
		return d.fail(ctx, current, err)
	}
	err = d.client.ApplyChannelOperation(ctx, ChannelOperation{Operation: current.Operation, ChannelID: current.ChannelID, Members: payload.Members})
	if err != nil {
		return d.fail(ctx, current, err)
	}
	_, err = d.db.ExecContext(ctx, `UPDATE wukong_channel_outbox SET status='done',locked_at=NULL,lock_owner='',last_error='',updated_at=NOW(6) WHERE id=?`, current.ID)
	return err
}

func (d *ChannelDispatcher) fail(ctx context.Context, current struct {
	ID        uint64
	Operation string
	ChannelID string
	Payload   []byte
	Attempts  uint32
}, dispatchErr error) error {
	attempts := current.Attempts + 1
	delay := math.Min(math.Pow(2, float64(attempts)), 300)
	status := "retry"
	if attempts >= 20 {
		status = "dead"
	}
	_, err := d.db.ExecContext(ctx, `UPDATE wukong_channel_outbox SET status=?,attempts=?,next_attempt_at=DATE_ADD(NOW(6),INTERVAL ? SECOND),locked_at=NULL,lock_owner='',last_error=?,updated_at=NOW(6) WHERE id=?`, status, attempts, int(delay), truncateError(dispatchErr), current.ID)
	return errors.Join(fmt.Errorf("dispatch wukong channel operation: %w", dispatchErr), err)
}

func truncateError(err error) string {
	value := err.Error()
	if len(value) > 1000 {
		return value[:1000]
	}
	return value
}
