package messaging

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

func (r *SQLRepository) Conversations(ctx context.Context, appID, userID uint64, limit int) ([]ConversationView, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT uc.channel_id,uc.channel_type,CASE WHEN uc.channel_type=1 THEN COALESCE(u.nickname,'') ELSE COALESCE(g.name,'') END,CASE WHEN uc.channel_type=1 THEN COALESCE(u.avatar_asset_id,0) ELSE COALESCE(g.avatar_asset_id,0) END,m.id,m.client_msg_no,COALESCE(m.message_id,''),m.message_seq,m.sender_id,m.content_type,m.payload_json,m.status,m.created_at,uc.unread_count,(cs.pinned_at IS NOT NULL),COALESCE(cs.muted,0),uc.updated_at FROM user_conversations uc JOIN messages m ON m.id=uc.last_message_id LEFT JOIN users u ON uc.channel_type=1 AND u.app_id=uc.app_id AND u.id=CAST(SUBSTRING(uc.channel_id,LENGTH(CONCAT('app',uc.app_id,'user'))+1) AS UNSIGNED) LEFT JOIN chat_groups g ON uc.channel_type=2 AND g.app_id=uc.app_id AND g.channel_id=uc.channel_id LEFT JOIN conversation_states cs ON cs.app_id=uc.app_id AND cs.user_id=uc.user_id AND cs.channel_id=uc.channel_id AND cs.channel_type=uc.channel_type WHERE uc.app_id=? AND uc.user_id=? AND uc.hidden_at IS NULL AND (uc.channel_type<>2 OR g.status='active') ORDER BY (cs.pinned_at IS NOT NULL) DESC,COALESCE(cs.pinned_at,uc.updated_at) DESC,uc.last_message_id DESC LIMIT ?`, appID, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]ConversationView, 0)
	for rows.Next() {
		var item ConversationView
		var payload []byte
		if err := rows.Scan(&item.ChannelID, &item.ChannelType, &item.Title, &item.AvatarAssetID, &item.LastMessage.ID, &item.LastMessage.ClientMsgNo, &item.LastMessage.MessageID, &item.LastMessage.MessageSeq, &item.LastMessage.SenderID, &item.LastMessage.ContentType, &payload, &item.LastMessage.Status, &item.LastMessage.CreatedAt, &item.UnreadCount, &item.Pinned, &item.Muted, &item.UpdatedAt); err != nil {
			return nil, err
		}
		item.LastMessage.SyncSeq = item.LastMessage.ID
		if err := json.Unmarshal(payload, &item.LastMessage.Payload); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *SQLRepository) ReadReceiptSummary(ctx context.Context, appID, userID, messageID uint64) (ReadReceiptSummary, error) {
	var senderID uint64
	var channelID string
	var channelType uint8
	if err := r.db.QueryRowContext(ctx, `SELECT sender_id,channel_id,channel_type FROM messages WHERE app_id=? AND id=?`, appID, messageID).Scan(&senderID, &channelID, &channelType); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ReadReceiptSummary{}, ErrForbidden
		}
		return ReadReceiptSummary{}, err
	}
	if senderID != userID {
		return ReadReceiptSummary{}, ErrForbidden
	}
	var summary ReadReceiptSummary
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM user_message_states WHERE app_id=? AND message_id=? AND user_id<>? AND read_at IS NOT NULL`, appID, messageID, senderID).Scan(&summary.ReadCount); err != nil {
		return ReadReceiptSummary{}, err
	}
	if channelType == ChannelPerson {
		summary.TotalRecipients = 1
		return summary, nil
	}
	if err := r.db.QueryRowContext(ctx, `SELECT GREATEST(COUNT(*)-1,0) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id AND g.app_id=gm.app_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active'`, appID, channelID).Scan(&summary.TotalRecipients); err != nil {
		return ReadReceiptSummary{}, err
	}
	return summary, nil
}
