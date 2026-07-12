package wallet

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strconv"
	"time"
)

func enqueueChatMessage(ctx context.Context, tx *sql.Tx, appID, senderID uint64, channelID string, channelType uint8, contentType uint32, payload map[string]any, now time.Time) (uint64, error) {
	clientMsgNo, err := walletMessageID()
	if err != nil {
		return 0, err
	}
	payload["protocol"] = "blin.chat.v1"
	payload["type"] = contentType
	payload["channel_type"] = channelType
	payload["sender_id"] = senderID
	canonical, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}
	sum := sha256.Sum256(canonical)
	result, err := tx.ExecContext(ctx, `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?, 'queued',?,?)`, appID, clientMsgNo, channelID, channelType, senderID, contentType, canonical, hex.EncodeToString(sum[:]), now, now)
	if err != nil {
		return 0, err
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',?,?,?)`, id, now, now, now); err != nil {
		return 0, err
	}
	if err := upsertChatConversations(ctx, tx, appID, senderID, channelID, channelType, uint64(id), now); err != nil {
		return 0, err
	}
	return uint64(id), nil
}

func upsertChatConversations(ctx context.Context, tx *sql.Tx, appID, senderID uint64, channelID string, channelType uint8, messageID uint64, now time.Time) error {
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,0,?,?) ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, senderID, channelID, channelType, messageID, now, now); err != nil {
		return err
	}
	if channelType == 1 {
		prefix := "app" + strconv.FormatUint(appID, 10) + "user"
		recipientID, err := strconv.ParseUint(channelID[len(prefix):], 10, 64)
		if err != nil {
			return err
		}
		senderChannel := prefix + strconv.FormatUint(senderID, 10)
		_, err = tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?) ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),unread_count=unread_count+1,hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, recipientID, senderChannel, channelType, messageID, now, now)
		return err
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) SELECT ?,gm.user_id,?,2,?,IF(gm.user_id=?,0,1),?,? FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active' ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),unread_count=unread_count+VALUES(unread_count),hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, channelID, messageID, senderID, now, now, appID, channelID)
	return err
}

func walletMessageID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate wallet message id: %w", err)
	}
	return "srv-wallet-" + hex.EncodeToString(value), nil
}

func enqueuePaymentNotice(ctx context.Context, tx *sql.Tx, appID, userID uint64, event string, payload map[string]any, now time.Time) error {
	var serviceUserID uint64
	if err := tx.QueryRowContext(ctx, `SELECT user_id FROM service_accounts WHERE app_id=? AND code='payment' AND status='active'`, appID).Scan(&serviceUserID); err != nil {
		return fmt.Errorf("payment service account unavailable: %w", err)
	}
	payload["event"] = event
	payload["service_account"] = "payment"
	payload["system_message"] = true
	channelID := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(userID, 10)
	_, err := enqueueChatMessage(ctx, tx, appID, serviceUserID, channelID, 1, 5501, payload, now)
	return err
}
