package calls

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

func enqueueMessage(ctx context.Context, tx *sql.Tx, appID, senderID uint64, channel string, channelType uint8, contentType uint32, payload map[string]any, now time.Time) error {
	rawID := make([]byte, 16)
	if _, err := rand.Read(rawID); err != nil {
		return err
	}
	client := "srv-call-" + hex.EncodeToString(rawID)
	payload["protocol"] = "blin.chat.v1"
	payload["type"] = contentType
	payload["sender_id"] = senderID
	canonical, _ := json.Marshal(payload)
	hash := sha256.Sum256(canonical)
	result, err := tx.ExecContext(ctx, `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'queued',?,?)`, appID, client, channel, channelType, senderID, contentType, canonical, hex.EncodeToString(hash[:]), now, now)
	if err != nil {
		return err
	}
	messageID, _ := result.LastInsertId()
	if _, err := tx.ExecContext(ctx, `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',?,?,?)`, messageID, now, now, now); err != nil {
		return err
	}
	if contentType == 99 {
		return nil
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,0,?,?) ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, senderID, channel, channelType, messageID, now, now); err != nil {
		return err
	}
	if channelType == 1 {
		prefix := "app" + strconv.FormatUint(appID, 10) + "user"
		recipient, err := strconv.ParseUint(stringsTrimPrefix(channel, prefix), 10, 64)
		if err != nil {
			return fmt.Errorf("invalid person channel")
		}
		senderChannel := prefix + strconv.FormatUint(senderID, 10)
		_, err = tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?) ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),unread_count=unread_count+1,hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, recipient, senderChannel, 1, messageID, now, now)
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) SELECT ?,gm.user_id,?,2,?,IF(gm.user_id=?,0,1),?,? FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active' ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),unread_count=unread_count+VALUES(unread_count),hidden_at=NULL,updated_at=VALUES(updated_at)`, appID, channel, messageID, senderID, now, now, appID, channel)
	return err
}
func stringsTrimPrefix(value, prefix string) string {
	if len(value) >= len(prefix) && value[:len(prefix)] == prefix {
		return value[len(prefix):]
	}
	return ""
}
