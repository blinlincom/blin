package messaging

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/platform/database"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }

func (r *SQLRepository) Queue(ctx context.Context, input SendInput, canonical []byte, payloadHash string) (QueuedMessage, error) {
	var queued QueuedMessage
	err := r.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		var err error
		queued, err = r.queueWithinTx(ctx, tx, input, canonical, payloadHash, true)
		return err
	})
	return queued, err
}

func (r *SQLRepository) queueWithinTx(ctx context.Context, tx *sql.Tx, input SendInput, canonical []byte, payloadHash string, checkPermission bool) (QueuedMessage, error) {
	var existingID uint64
	var existingHash, status string
	var createdAt time.Time
	err := tx.QueryRowContext(ctx, `SELECT id,payload_hash,status,created_at FROM messages WHERE app_id=? AND client_msg_no=? LIMIT 1 FOR UPDATE`, input.AppID, input.ClientMsgNo).Scan(&existingID, &existingHash, &status, &createdAt)
	if err == nil {
		if existingHash != payloadHash {
			return QueuedMessage{}, ErrClientMsgConflict
		}
		return QueuedMessage{ID: existingID, ClientMsgNo: input.ClientMsgNo, Status: status, CreatedAt: createdAt, Duplicate: true}, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return QueuedMessage{}, err
	}
	if checkPermission {
		if err := r.authorize(ctx, tx, input); err != nil {
			return QueuedMessage{}, err
		}
	}
	if err := r.grantMediaAccess(ctx, tx, input); err != nil {
		return QueuedMessage{}, err
	}
	now := time.Now().UTC()
	result, err := tx.ExecContext(ctx, `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`, input.AppID, input.ClientMsgNo, input.ChannelID, input.ChannelType, input.SenderID, input.ContentType, json.RawMessage(canonical), payloadHash, "queued", now, now)
	if err != nil {
		return QueuedMessage{}, err
	}
	id, err := result.LastInsertId()
	if err != nil {
		return QueuedMessage{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',?,?,?)`, id, now, now, now); err != nil {
		return QueuedMessage{}, err
	}
	if err := r.upsertConversations(ctx, tx, input, uint64(id), now); err != nil {
		return QueuedMessage{}, err
	}
	return QueuedMessage{ID: uint64(id), ClientMsgNo: input.ClientMsgNo, Status: "queued", CreatedAt: now}, nil
}

func (r *SQLRepository) grantMediaAccess(ctx context.Context, tx *sql.Tx, input SendInput) error {
	raw, ok := input.Payload["asset_ids"].([]any)
	if !ok || len(raw) == 0 {
		return nil
	}
	ids := make([]uint64, 0, len(raw))
	seen := map[uint64]struct{}{}
	for _, value := range raw {
		number, ok := value.(float64)
		if !ok {
			return ErrInvalidPayload
		}
		id := uint64(number)
		if id == 0 || number != float64(id) {
			return ErrInvalidPayload
		}
		if _, exists := seen[id]; !exists {
			seen[id] = struct{}{}
			ids = append(ids, id)
		}
	}
	for _, id := range ids {
		var allowed int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_assets ma JOIN media_access ac ON ac.asset_id=ma.id AND ac.app_id=ma.app_id WHERE ma.app_id=? AND ma.id=? AND ma.status='ready' AND ac.user_id=?`, input.AppID, id, input.SenderID).Scan(&allowed); err != nil || allowed != 1 {
			return ErrInvalidPayload
		}
		if input.ChannelType == ChannelPerson {
			recipient, err := parsePersonChannel(input.AppID, input.ChannelID)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT IGNORE INTO media_access(asset_id,app_id,user_id,granted_at) VALUES(?,?,?,NOW(6))`, id, input.AppID, recipient); err != nil {
				return err
			}
		} else {
			if _, err := tx.ExecContext(ctx, `INSERT IGNORE INTO media_access(asset_id,app_id,user_id,granted_at) SELECT ?,gm.app_id,gm.user_id,NOW(6) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id AND g.app_id=gm.app_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active'`, id, input.AppID, input.ChannelID); err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *SQLRepository) upsertConversations(ctx context.Context, tx *sql.Tx, input SendInput, messageID uint64, now time.Time) error {
	upsert := func(userID uint64, unread uint32) error {
		_, err := tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE last_message_id=GREATEST(last_message_id,VALUES(last_message_id)),unread_count=unread_count+VALUES(unread_count),hidden_at=NULL,updated_at=VALUES(updated_at)`, input.AppID, userID, input.ChannelID, input.ChannelType, messageID, unread, now, now)
		return err
	}
	if err := upsert(input.SenderID, 0); err != nil {
		return err
	}
	if input.ChannelType == ChannelPerson {
		recipientID, err := parsePersonChannel(input.AppID, input.ChannelID)
		if err != nil {
			return err
		}
		senderChannel := fmt.Sprintf("app%duser%d", input.AppID, input.SenderID)
		_, err = tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?) ON DUPLICATE KEY UPDATE last_message_id=GREATEST(last_message_id,VALUES(last_message_id)),unread_count=unread_count+1,hidden_at=NULL,updated_at=VALUES(updated_at)`, input.AppID, recipientID, senderChannel, ChannelPerson, messageID, now, now)
		return err
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) SELECT ?,gm.user_id,?,2,?,IF(gm.user_id=?,0,1),?,? FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active' ON DUPLICATE KEY UPDATE last_message_id=GREATEST(last_message_id,VALUES(last_message_id)),unread_count=unread_count+VALUES(unread_count),hidden_at=NULL,updated_at=VALUES(updated_at)`, input.AppID, input.ChannelID, messageID, input.SenderID, now, now, input.AppID, input.ChannelID)
	return err
}

func (r *SQLRepository) authorize(ctx context.Context, tx *sql.Tx, input SendInput) error {
	if input.System {
		return nil
	}
	column := "private_muted_until"
	if input.ChannelType == ChannelGroup {
		column = "group_muted_until"
	}
	var muted sql.NullTime
	err := tx.QueryRowContext(ctx, `SELECT `+column+` FROM user_chat_restrictions WHERE app_id=? AND user_id=? LIMIT 1`, input.AppID, input.SenderID).Scan(&muted)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if muted.Valid && (muted.Time.Year() >= 9999 || muted.Time.After(time.Now().UTC())) {
		return ErrMuted
	}
	if input.ChannelType == ChannelGroup {
		return r.authorizeGroup(ctx, tx, input)
	}
	recipientID, err := parsePersonChannel(input.AppID, input.ChannelID)
	if err != nil || recipientID == 0 || recipientID == input.SenderID {
		return ErrForbidden
	}
	var friendship int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM friendships WHERE app_id=? AND user_id=? AND friend_id=? AND status='active'`, input.AppID, input.SenderID, recipientID).Scan(&friendship); err != nil {
		return err
	}
	if friendship > 0 {
		return nil
	}
	if input.ContentType != TypeText {
		return ErrForbidden
	}
	var count uint8
	err = tx.QueryRowContext(ctx, `SELECT sent_count FROM stranger_message_quotas WHERE app_id=? AND sender_id=? AND recipient_id=? FOR UPDATE`, input.AppID, input.SenderID, recipientID).Scan(&count)
	if errors.Is(err, sql.ErrNoRows) {
		_, err = tx.ExecContext(ctx, `INSERT INTO stranger_message_quotas(app_id,sender_id,recipient_id,sent_count,updated_at) VALUES(?,?,?,?,NOW(6))`, input.AppID, input.SenderID, recipientID, 1)
		return err
	}
	if err != nil {
		return err
	}
	if count >= 3 {
		return ErrStrangerLimit
	}
	_, err = tx.ExecContext(ctx, `UPDATE stranger_message_quotas SET sent_count=sent_count+1,updated_at=NOW(6) WHERE app_id=? AND sender_id=? AND recipient_id=?`, input.AppID, input.SenderID, recipientID)
	return err
}

func parsePersonChannel(appID uint64, channelID string) (uint64, error) {
	prefix := fmt.Sprintf("app%duser", appID)
	if !strings.HasPrefix(channelID, prefix) {
		return 0, ErrForbidden
	}
	return strconv.ParseUint(strings.TrimPrefix(channelID, prefix), 10, 64)
}

func (r *SQLRepository) authorizeGroup(ctx context.Context, tx *sql.Tx, input SendInput) error {
	var muted sql.NullTime
	err := tx.QueryRowContext(ctx, `SELECT gm.muted_until FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.user_id=? AND gm.status='active' AND g.status='active' LIMIT 1`, input.AppID, input.ChannelID, input.SenderID).Scan(&muted)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrForbidden
	}
	if err != nil {
		return err
	}
	if muted.Valid && (muted.Time.Year() >= 9999 || muted.Time.After(time.Now().UTC())) {
		return ErrMuted
	}
	return nil
}

func (r *SQLRepository) History(ctx context.Context, input HistoryInput) ([]MessageView, error) {
	var enabled bool
	if err := r.db.QueryRowContext(ctx, `SELECT COALESCE(JSON_EXTRACT(config_json,'$.history_sync_enabled'),true) FROM applications WHERE id=?`, input.AppID).Scan(&enabled); err != nil {
		return nil, err
	}
	if !enabled {
		return []MessageView{}, nil
	}
	before := input.BeforeSeq
	if before == 0 {
		before = ^uint64(0)
	}
	rows, err := r.historyRows(ctx, input, before)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]MessageView, 0, input.Limit)
	for rows.Next() {
		var item MessageView
		var payload []byte
		var readAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.ClientMsgNo, &item.MessageID, &item.MessageSeq, &item.SyncSeq, &item.SenderID, &item.ContentType, &payload, &item.Status, &item.CreatedAt, &readAt); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(payload, &item.Payload); err != nil {
			return nil, err
		}
		if readAt.Valid {
			item.ReadAt = &readAt.Time
		}
		result = append(result, item)
	}
	for left, right := 0, len(result)-1; left < right; left, right = left+1, right-1 {
		result[left], result[right] = result[right], result[left]
	}
	return result, rows.Err()
}

func (r *SQLRepository) historyRows(ctx context.Context, input HistoryInput, before uint64) (*sql.Rows, error) {
	if input.ChannelType == ChannelGroup {
		return r.db.QueryContext(ctx, `SELECT m.id,m.client_msg_no,COALESCE(m.message_id,''),m.message_seq,m.id,m.sender_id,m.content_type,m.payload_json,m.status,m.created_at,ums.read_at FROM chat_groups g JOIN group_members gm ON gm.group_id=g.id AND gm.user_id=? AND gm.status='active' JOIN messages m ON m.app_id=g.app_id AND m.channel_id=g.channel_id AND m.channel_type=2 LEFT JOIN user_message_states ums ON ums.app_id=m.app_id AND ums.user_id=? AND ums.message_id=m.id LEFT JOIN conversation_states cs ON cs.app_id=m.app_id AND cs.user_id=? AND cs.channel_id=g.channel_id AND cs.channel_type=2 WHERE g.app_id=? AND g.channel_id=? AND m.created_at>=gm.joined_at AND m.id<? AND m.id>COALESCE(cs.clear_before_seq,0) AND (m.recalled_at IS NULL OR m.content_type=1006) AND ums.hidden_at IS NULL AND ums.burned_at IS NULL ORDER BY m.id DESC LIMIT ?`, input.UserID, input.UserID, input.UserID, input.AppID, input.ChannelID, before, input.Limit)
	}
	peerID, err := parsePersonChannel(input.AppID, input.ChannelID)
	if err != nil {
		return nil, ErrForbidden
	}
	selfChannel := fmt.Sprintf("app%duser%d", input.AppID, input.UserID)
	peerChannel := fmt.Sprintf("app%duser%d", input.AppID, peerID)
	return r.db.QueryContext(ctx, `SELECT m.id,m.client_msg_no,COALESCE(m.message_id,''),m.message_seq,m.id,m.sender_id,m.content_type,m.payload_json,m.status,m.created_at,ums.read_at FROM messages m LEFT JOIN user_message_states ums ON ums.app_id=m.app_id AND ums.user_id=? AND ums.message_id=m.id LEFT JOIN conversation_states cs ON cs.app_id=m.app_id AND cs.user_id=? AND cs.channel_id=? AND cs.channel_type=1 WHERE m.app_id=? AND m.channel_type=1 AND ((m.sender_id=? AND m.channel_id=?) OR (m.sender_id=? AND m.channel_id=?)) AND m.id<? AND m.id>COALESCE(cs.clear_before_seq,0) AND (m.recalled_at IS NULL OR m.content_type=1006) AND ums.hidden_at IS NULL AND ums.burned_at IS NULL ORDER BY m.id DESC LIMIT ?`, input.UserID, input.UserID, input.ChannelID, input.AppID, input.UserID, peerChannel, peerID, selfChannel, before, input.Limit)
}

func (r *SQLRepository) MarkRead(ctx context.Context, appID, userID uint64, channelID string, channelType uint8, throughSeq uint64) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `INSERT INTO conversation_states(app_id,user_id,channel_id,channel_type,last_read_seq,created_at,updated_at) VALUES(?,?,?,?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE last_read_seq=GREATEST(last_read_seq,VALUES(last_read_seq)),updated_at=NOW(6)`, appID, userID, channelID, channelType, throughSeq); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE user_conversations SET unread_count=0,updated_at=NOW(6) WHERE app_id=? AND user_id=? AND channel_id=? AND channel_type=?`, appID, userID, channelID, channelType); err != nil {
			return err
		}
		if channelType == ChannelPerson {
			peerID, err := parsePersonChannel(appID, channelID)
			if err != nil {
				return err
			}
			selfChannel := fmt.Sprintf("app%duser%d", appID, userID)
			_, err = tx.ExecContext(ctx, `INSERT INTO user_message_states(app_id,user_id,message_id,read_at,created_at,updated_at) SELECT ?,?,m.id,NOW(6),NOW(6),NOW(6) FROM messages m WHERE m.app_id=? AND m.channel_type=1 AND m.sender_id=? AND m.channel_id=? AND m.id<=? ON DUPLICATE KEY UPDATE read_at=COALESCE(read_at,NOW(6)),updated_at=NOW(6)`, appID, userID, appID, peerID, selfChannel, throughSeq)
			return err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO user_message_states(app_id,user_id,message_id,read_at,created_at,updated_at) SELECT ?,?,m.id,NOW(6),NOW(6),NOW(6) FROM messages m WHERE m.app_id=? AND m.channel_id=? AND m.channel_type=2 AND m.sender_id<>? AND m.id<=? ON DUPLICATE KEY UPDATE read_at=COALESCE(read_at,NOW(6)),updated_at=NOW(6)`, appID, userID, appID, channelID, userID, throughSeq)
		return err
	})
}
func (r *SQLRepository) HideMessage(ctx context.Context, appID, userID, messageID uint64) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var senderID uint64
		var channelID string
		var channelType uint8
		if err := tx.QueryRowContext(ctx, `SELECT sender_id,channel_id,channel_type FROM messages WHERE app_id=? AND id=? FOR UPDATE`, appID, messageID).Scan(&senderID, &channelID, &channelType); err != nil {
			return ErrForbidden
		}
		userChannel := channelID
		if channelType == ChannelPerson {
			peerID, err := parsePersonChannel(appID, channelID)
			if err != nil {
				return ErrForbidden
			}
			if senderID == userID {
				userChannel = channelID
			} else if peerID == userID {
				userChannel = fmt.Sprintf("app%duser%d", appID, senderID)
			} else {
				return ErrForbidden
			}
		} else if channelType == ChannelGroup {
			var count int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id AND g.app_id=gm.app_id WHERE gm.app_id=? AND g.channel_id=? AND gm.user_id=? AND gm.status='active'`, appID, channelID, userID).Scan(&count); err != nil || count == 0 {
				return ErrForbidden
			}
		} else {
			return ErrForbidden
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO user_message_states(app_id,user_id,message_id,hidden_at,created_at,updated_at) VALUES(?,?,?,NOW(6),NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE hidden_at=NOW(6),updated_at=NOW(6)`, appID, userID, messageID); err != nil {
			return err
		}
		var lastID uint64
		if channelType == ChannelPerson {
			peerID, _ := parsePersonChannel(appID, userChannel)
			selfChannel := fmt.Sprintf("app%duser%d", appID, userID)
			peerChannel := fmt.Sprintf("app%duser%d", appID, peerID)
			if err := tx.QueryRowContext(ctx, `SELECT COALESCE(MAX(m.id),0) FROM messages m LEFT JOIN user_message_states ums ON ums.app_id=m.app_id AND ums.user_id=? AND ums.message_id=m.id LEFT JOIN conversation_states cs ON cs.app_id=m.app_id AND cs.user_id=? AND cs.channel_id=? AND cs.channel_type=1 WHERE m.app_id=? AND m.channel_type=1 AND ((m.sender_id=? AND m.channel_id=?) OR (m.sender_id=? AND m.channel_id=?)) AND m.id>COALESCE(cs.clear_before_seq,0) AND ums.hidden_at IS NULL AND ums.burned_at IS NULL AND (m.recalled_at IS NULL OR m.content_type=1006)`, userID, userID, userChannel, appID, userID, peerChannel, peerID, selfChannel).Scan(&lastID); err != nil {
				return err
			}
		} else {
			if err := tx.QueryRowContext(ctx, `SELECT COALESCE(MAX(m.id),0) FROM messages m JOIN chat_groups g ON g.app_id=m.app_id AND g.channel_id=m.channel_id JOIN group_members gm ON gm.group_id=g.id AND gm.user_id=? AND gm.status='active' LEFT JOIN user_message_states ums ON ums.app_id=m.app_id AND ums.user_id=? AND ums.message_id=m.id LEFT JOIN conversation_states cs ON cs.app_id=m.app_id AND cs.user_id=? AND cs.channel_id=m.channel_id AND cs.channel_type=2 WHERE m.app_id=? AND m.channel_id=? AND m.channel_type=2 AND m.created_at>=gm.joined_at AND m.id>COALESCE(cs.clear_before_seq,0) AND ums.hidden_at IS NULL AND ums.burned_at IS NULL AND (m.recalled_at IS NULL OR m.content_type=1006)`, userID, userID, userID, appID, channelID).Scan(&lastID); err != nil {
				return err
			}
		}
		if lastID == 0 {
			_, err := tx.ExecContext(ctx, `UPDATE user_conversations SET hidden_at=NOW(6),unread_count=0,updated_at=NOW(6) WHERE app_id=? AND user_id=? AND channel_id=? AND channel_type=?`, appID, userID, userChannel, channelType)
			return err
		}
		_, err := tx.ExecContext(ctx, `UPDATE user_conversations SET last_message_id=?,updated_at=NOW(6) WHERE app_id=? AND user_id=? AND channel_id=? AND channel_type=? AND last_message_id=?`, lastID, appID, userID, userChannel, channelType, messageID)
		return err
	})
}
func (r *SQLRepository) ClearConversation(ctx context.Context, appID, userID uint64, channelID string, channelType uint8) error {
	var maxSeq uint64
	var err error
	if channelType == ChannelPerson {
		peerID, parseErr := parsePersonChannel(appID, channelID)
		if parseErr != nil {
			return ErrForbidden
		}
		selfChannel := fmt.Sprintf("app%duser%d", appID, userID)
		peerChannel := fmt.Sprintf("app%duser%d", appID, peerID)
		err = r.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(id),0) FROM messages WHERE app_id=? AND channel_type=1 AND ((sender_id=? AND channel_id=?) OR (sender_id=? AND channel_id=?))`, appID, userID, peerChannel, peerID, selfChannel).Scan(&maxSeq)
	} else {
		err = r.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(id),0) FROM messages WHERE app_id=? AND channel_id=? AND channel_type=?`, appID, channelID, channelType).Scan(&maxSeq)
	}
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `INSERT INTO conversation_states(app_id,user_id,channel_id,channel_type,clear_before_seq,created_at,updated_at) VALUES(?,?,?,?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE clear_before_seq=GREATEST(clear_before_seq,VALUES(clear_before_seq)),updated_at=NOW(6)`, appID, userID, channelID, channelType, maxSeq)
	if err == nil {
		_, err = r.db.ExecContext(ctx, `UPDATE user_conversations SET hidden_at=NOW(6),unread_count=0,updated_at=NOW(6) WHERE app_id=? AND user_id=? AND channel_id=? AND channel_type=?`, appID, userID, channelID, channelType)
	}
	return err
}

func (r *SQLRepository) Recall(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error) {
	return r.queueMessageEvent(ctx, appID, userID, messageID, eventClientMsgNo, "recall", TypeRecall)
}

func (r *SQLRepository) BurnAfterRead(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo string) (QueuedMessage, error) {
	return r.queueMessageEvent(ctx, appID, userID, messageID, eventClientMsgNo, "burn_after_read", TypeCMD)
}

func (r *SQLRepository) queueMessageEvent(ctx context.Context, appID, userID, messageID uint64, eventClientMsgNo, eventType string, contentType uint32) (QueuedMessage, error) {
	if eventClientMsgNo == "" {
		return QueuedMessage{}, ErrClientMsgConflict
	}
	var queued QueuedMessage
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var target SendInput
		var targetClient string
		var targetPayload []byte
		var recalled sql.NullTime
		err := tx.QueryRowContext(ctx, `SELECT app_id,sender_id,channel_id,channel_type,client_msg_no,payload_json,recalled_at FROM messages WHERE app_id=? AND id=? FOR UPDATE`, appID, messageID).Scan(&target.AppID, &target.SenderID, &target.ChannelID, &target.ChannelType, &targetClient, &targetPayload, &recalled)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrForbidden
		}
		if err != nil {
			return err
		}
		if eventType == "recall" {
			if recalled.Valid {
				return ErrForbidden
			}
			if target.SenderID != userID && (target.ChannelType != ChannelGroup || !r.groupCanModerate(ctx, tx, appID, target.ChannelID, userID)) {
				return ErrForbidden
			}
		} else {
			var payload map[string]any
			if err := json.Unmarshal(targetPayload, &payload); err != nil {
				return err
			}
			burn, ok := payload["burn_after_read"].(map[string]any)
			if !ok || burn["enabled"] != true {
				return ErrForbidden
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO user_message_states(app_id,user_id,message_id,burned_at,read_at,created_at,updated_at) VALUES(?,?,?,NOW(6),NOW(6),NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE burned_at=NOW(6),read_at=NOW(6),updated_at=NOW(6)`, appID, userID, messageID); err != nil {
				return err
			}
		}
		payload := map[string]any{"protocol": "blin.chat.v1", "type": contentType, "content_type": eventType, "target_client_msg_no": targetClient, "actor_id": userID}
		if contentType == TypeCMD {
			payload["cmd"] = eventType
		} else {
			payload["system_message"] = true
		}
		canonical, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(canonical)
		eventInput := SendInput{AppID: appID, SenderID: userID, ChannelID: target.ChannelID, ChannelType: target.ChannelType, ClientMsgNo: eventClientMsgNo, ContentType: contentType, Payload: payload, System: contentType > 1000}
		queued, err = r.queueWithinTx(ctx, tx, eventInput, canonical, hex.EncodeToString(sum[:]), false)
		if err != nil {
			return err
		}
		if eventType == "recall" {
			if _, err := tx.ExecContext(ctx, `UPDATE messages SET recalled_at=NOW(6),updated_at=NOW(6) WHERE id=?`, messageID); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO message_events(app_id,event_id,event_type,message_id,actor_id,payload_json,created_at) VALUES(?,?,?,?,?,?,NOW(6))`, appID, "event-"+eventClientMsgNo, eventType, messageID, userID, json.RawMessage(canonical))
		return err
	})
	return queued, err
}

func (r *SQLRepository) groupCanModerate(ctx context.Context, tx *sql.Tx, appID uint64, channelID string, userID uint64) bool {
	var count int
	_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.user_id=? AND gm.status='active' AND gm.role IN ('owner','admin')`, appID, channelID, userID).Scan(&count)
	return count > 0
}
