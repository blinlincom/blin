package social

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

func (r *SQLRepository) ListGroups(ctx context.Context, appID, userID uint64) ([]Group, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT g.id,g.channel_id,g.name,COALESCE(g.avatar_asset_id,0),g.announcement,g.all_muted,g.invite_confirmation,g.owner_id,g.member_count,g.join_history_policy,g.created_at FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id AND g.app_id=gm.app_id WHERE gm.app_id=? AND gm.user_id=? AND gm.status='active' AND g.status='active' ORDER BY g.updated_at DESC,g.id DESC`, appID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Group, 0)
	for rows.Next() {
		var item Group
		if err := rows.Scan(&item.ID, &item.ChannelID, &item.Name, &item.AvatarAssetID, &item.Announcement, &item.AllMuted, &item.InviteConfirmation, &item.OwnerID, &item.MemberCount, &item.JoinHistoryPolicy, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *SQLRepository) GetGroup(ctx context.Context, appID, groupID, userID uint64) (Group, error) {
	var item Group
	err := r.db.QueryRowContext(ctx, `SELECT g.id,g.channel_id,g.name,COALESCE(g.avatar_asset_id,0),g.announcement,g.all_muted,g.invite_confirmation,g.owner_id,g.member_count,g.join_history_policy,g.created_at FROM chat_groups g JOIN group_members gm ON gm.group_id=g.id AND gm.app_id=g.app_id WHERE g.app_id=? AND g.id=? AND g.status='active' AND gm.user_id=? AND gm.status='active'`, appID, groupID, userID).Scan(&item.ID, &item.ChannelID, &item.Name, &item.AvatarAssetID, &item.Announcement, &item.AllMuted, &item.InviteConfirmation, &item.OwnerID, &item.MemberCount, &item.JoinHistoryPolicy, &item.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	return item, err
}

func (r *SQLRepository) ListGroupMembers(ctx context.Context, appID, groupID, userID uint64) ([]GroupMember, error) {
	var allowed int
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members WHERE app_id=? AND group_id=? AND user_id=? AND status='active'`, appID, groupID, userID).Scan(&allowed); err != nil {
		return nil, err
	}
	if allowed == 0 {
		return nil, ErrNotFound
	}
	rows, err := r.db.QueryContext(ctx, `SELECT u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),gm.role,gm.group_nickname,gm.muted_until,gm.joined_at FROM group_members gm JOIN users u ON u.id=gm.user_id AND u.app_id=gm.app_id WHERE gm.app_id=? AND gm.group_id=? AND gm.status='active' ORDER BY FIELD(gm.role,'owner','admin','member'),gm.joined_at,gm.id`, appID, groupID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]GroupMember, 0)
	for rows.Next() {
		var item GroupMember
		var muted sql.NullTime
		if err := rows.Scan(&item.User.ID, &item.User.Username, &item.User.Nickname, &item.User.AvatarAssetID, &item.Role, &item.GroupNickname, &muted, &item.JoinedAt); err != nil {
			return nil, err
		}
		if muted.Valid {
			value := muted.Time
			item.MutedUntil = &value
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *SQLRepository) AddGroupMembers(ctx context.Context, appID, groupID, actorID uint64, memberIDs []uint64) error {
	return r.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		channelID, role, err := lockGroupActor(ctx, tx, appID, groupID, actorID)
		if err != nil {
			return err
		}
		if role != "owner" && role != "admin" {
			return ErrForbidden
		}
		now := time.Now().UTC()
		added := make([]uint64, 0, len(memberIDs))
		for _, memberID := range memberIDs {
			result, err := tx.ExecContext(ctx, `INSERT INTO group_members(app_id,group_id,user_id,role,joined_at,status,created_at,updated_at) SELECT ?,?,?,'member',?,'active',?,? FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1) ON DUPLICATE KEY UPDATE role=IF(status='active',role,'member'),joined_at=IF(status='active',joined_at,VALUES(joined_at)),left_at=NULL,status='active',updated_at=VALUES(updated_at)`, appID, groupID, memberID, now, now, now, appID, memberID)
			if err != nil {
				return err
			}
			rows, _ := result.RowsAffected()
			if rows > 0 {
				added = append(added, memberID)
			}
		}
		if len(added) == 0 {
			return nil
		}
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET member_count=(SELECT COUNT(*) FROM group_members WHERE group_id=? AND status='active'),updated_at=NOW(6) WHERE id=?`, groupID, groupID); err != nil {
			return err
		}
		if err := enqueueChannelOperation(ctx, tx, appID, "subscriber_add", channelID, added); err != nil {
			return err
		}
		return enqueueGroupEvent(ctx, tx, appID, actorID, channelID, "members_added", map[string]any{"group_id": groupID, "member_ids": added})
	})
}

func (r *SQLRepository) RemoveGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, actorRole, err := lockGroupActor(ctx, tx, appID, groupID, actorID)
		if err != nil {
			return err
		}
		if actorRole != "owner" && actorRole != "admin" {
			return ErrForbidden
		}
		var targetRole string
		if err := tx.QueryRowContext(ctx, `SELECT role FROM group_members WHERE app_id=? AND group_id=? AND user_id=? AND status='active' FOR UPDATE`, appID, groupID, memberID).Scan(&targetRole); errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		} else if err != nil {
			return err
		}
		if targetRole == "owner" || (actorRole == "admin" && targetRole == "admin") {
			return ErrForbidden
		}
		if _, err := tx.ExecContext(ctx, `UPDATE group_members SET status='removed',left_at=NOW(6),muted_until=NULL,updated_at=NOW(6) WHERE app_id=? AND group_id=? AND user_id=?`, appID, groupID, memberID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET member_count=member_count-1,updated_at=NOW(6) WHERE id=? AND member_count>0`, groupID); err != nil {
			return err
		}
		if err := enqueueChannelOperation(ctx, tx, appID, "subscriber_remove", channelID, []uint64{memberID}); err != nil {
			return err
		}
		return enqueueGroupEvent(ctx, tx, appID, actorID, channelID, "member_removed", map[string]any{"group_id": groupID, "member_id": memberID})
	})
}

func (r *SQLRepository) UpdateGroup(ctx context.Context, appID, groupID, actorID uint64, update GroupUpdate) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, role, err := lockGroupActor(ctx, tx, appID, groupID, actorID)
		if err != nil {
			return err
		}
		if role != "owner" && role != "admin" {
			return ErrForbidden
		}
		sets := make([]string, 0, 6)
		args := make([]any, 0, 8)
		changed := make(map[string]any)
		add := func(column string, value any) {
			sets = append(sets, column+"=?")
			args = append(args, value)
			changed[column] = value
		}
		if update.Name != nil {
			add("name", *update.Name)
		}
		if update.AvatarAssetID != nil {
			if *update.AvatarAssetID != 0 {
				var count int
				if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_assets ma JOIN media_access ac ON ac.asset_id=ma.id AND ac.app_id=ma.app_id WHERE ma.app_id=? AND ma.id=? AND ac.user_id=? AND ma.media_kind='image' AND ma.status='ready'`, appID, *update.AvatarAssetID, actorID).Scan(&count); err != nil || count != 1 {
					return ErrForbidden
				}
			}
			add("avatar_asset_id", nullAssetID(*update.AvatarAssetID))
		}
		if update.Announcement != nil {
			add("announcement", *update.Announcement)
		}
		if update.AllMuted != nil {
			add("all_muted", boolByte(*update.AllMuted))
		}
		if update.InviteConfirmation != nil {
			add("invite_confirmation", boolByte(*update.InviteConfirmation))
		}
		if len(sets) == 0 {
			return nil
		}
		sets = append(sets, "updated_at=NOW(6)")
		args = append(args, appID, groupID)
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET `+strings.Join(sets, ",")+` WHERE app_id=? AND id=? AND status='active'`, args...); err != nil {
			return err
		}
		return enqueueGroupEvent(ctx, tx, appID, actorID, channelID, "group_updated", map[string]any{"group_id": groupID, "changes": changed})
	})
}

func (r *SQLRepository) SetGroupMemberRole(ctx context.Context, appID, groupID, actorID, memberID uint64, role string) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, actorRole, err := lockGroupActor(ctx, tx, appID, groupID, actorID)
		if err != nil {
			return err
		}
		if actorRole != "owner" || actorID == memberID {
			return ErrForbidden
		}
		result, err := tx.ExecContext(ctx, `UPDATE group_members SET role=?,updated_at=NOW(6) WHERE app_id=? AND group_id=? AND user_id=? AND status='active' AND role<>'owner'`, role, appID, groupID, memberID)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows == 0 {
			return ErrNotFound
		}
		return enqueueGroupEvent(ctx, tx, appID, actorID, channelID, "member_role_changed", map[string]any{"group_id": groupID, "member_id": memberID, "role": role})
	})
}

func (r *SQLRepository) MuteGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64, until *time.Time) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, actorRole, err := lockGroupActor(ctx, tx, appID, groupID, actorID)
		if err != nil {
			return err
		}
		if actorRole != "owner" && actorRole != "admin" {
			return ErrForbidden
		}
		var targetRole string
		if err := tx.QueryRowContext(ctx, `SELECT role FROM group_members WHERE app_id=? AND group_id=? AND user_id=? AND status='active' FOR UPDATE`, appID, groupID, memberID).Scan(&targetRole); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		if targetRole == "owner" || (actorRole == "admin" && targetRole == "admin") {
			return ErrForbidden
		}
		if _, err := tx.ExecContext(ctx, `UPDATE group_members SET muted_until=?,updated_at=NOW(6) WHERE app_id=? AND group_id=? AND user_id=?`, until, appID, groupID, memberID); err != nil {
			return err
		}
		return enqueueGroupEvent(ctx, tx, appID, actorID, channelID, "member_mute_changed", map[string]any{"group_id": groupID, "member_id": memberID, "muted_until": until})
	})
}

func (r *SQLRepository) LeaveGroup(ctx context.Context, appID, groupID, userID uint64) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, role, err := lockGroupActor(ctx, tx, appID, groupID, userID)
		if err != nil {
			return err
		}
		if role == "owner" {
			return ErrForbidden
		}
		if _, err := tx.ExecContext(ctx, `UPDATE group_members SET status='left',left_at=NOW(6),muted_until=NULL,updated_at=NOW(6) WHERE app_id=? AND group_id=? AND user_id=?`, appID, groupID, userID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET member_count=member_count-1,updated_at=NOW(6) WHERE id=? AND member_count>0`, groupID); err != nil {
			return err
		}
		if err := enqueueChannelOperation(ctx, tx, appID, "subscriber_remove", channelID, []uint64{userID}); err != nil {
			return err
		}
		return enqueueGroupEvent(ctx, tx, appID, userID, channelID, "member_left", map[string]any{"group_id": groupID, "member_id": userID})
	})
}

func (r *SQLRepository) DissolveGroup(ctx context.Context, appID, groupID, ownerID uint64) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		channelID, role, err := lockGroupActor(ctx, tx, appID, groupID, ownerID)
		if err != nil {
			return err
		}
		if role != "owner" {
			return ErrForbidden
		}
		if err := enqueueGroupEvent(ctx, tx, appID, ownerID, channelID, "group_dissolved", map[string]any{"group_id": groupID}); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE group_members SET status='dissolved',left_at=NOW(6),updated_at=NOW(6) WHERE app_id=? AND group_id=? AND status='active'`, appID, groupID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET status='dissolved',member_count=0,updated_at=NOW(6) WHERE app_id=? AND id=?`, appID, groupID); err != nil {
			return err
		}
		return enqueueChannelOperation(ctx, tx, appID, "channel_delete", channelID, nil)
	})
}

func lockGroupActor(ctx context.Context, tx *sql.Tx, appID, groupID, actorID uint64) (string, string, error) {
	var channelID, role string
	err := tx.QueryRowContext(ctx, `SELECT g.channel_id,gm.role FROM chat_groups g JOIN group_members gm ON gm.group_id=g.id AND gm.app_id=g.app_id WHERE g.app_id=? AND g.id=? AND g.status='active' AND gm.user_id=? AND gm.status='active' FOR UPDATE`, appID, groupID, actorID).Scan(&channelID, &role)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", ErrNotFound
	}
	return channelID, role, err
}

func enqueueChannelOperation(ctx context.Context, tx *sql.Tx, appID uint64, operation, channelID string, memberIDs []uint64) error {
	members := make([]string, 0, len(memberIDs))
	for _, id := range memberIDs {
		members = append(members, "app"+strconv.FormatUint(appID, 10)+"user"+strconv.FormatUint(id, 10))
	}
	payload, err := json.Marshal(map[string]any{"members": members})
	if err != nil {
		return err
	}
	nextAttempt := time.Now().UTC()
	if operation == "channel_delete" {
		// Give the durable system-message outbox time to publish the dissolve event
		// before the remote channel is removed.
		nextAttempt = nextAttempt.Add(10 * time.Second)
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO wukong_channel_outbox(app_id,operation,channel_id,channel_type,payload_json,status,next_attempt_at,created_at,updated_at) VALUES(?,?,?,?,?,'pending',?,NOW(6),NOW(6))`, appID, operation, channelID, 2, payload, nextAttempt)
	return err
}

func enqueueGroupEvent(ctx context.Context, tx *sql.Tx, appID, actorID uint64, channelID, event string, data map[string]any) error {
	clientMsgNo, err := randomClientMsgNo()
	if err != nil {
		return err
	}
	payload := map[string]any{"protocol": "blin.chat.v1", "type": 5401, "system_message": true, "event": event, "actor_id": actorID, "data": data}
	canonical, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	hash := sha256.Sum256(canonical)
	result, err := tx.ExecContext(ctx, `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?, 'queued',NOW(6),NOW(6))`, appID, clientMsgNo, channelID, 2, actorID, 5401, canonical, hex.EncodeToString(hash[:]))
	if err != nil {
		return err
	}
	messageID, err := result.LastInsertId()
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',NOW(6),NOW(6),NOW(6))`, messageID)
	return err
}

func randomClientMsgNo() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate group event id: %w", err)
	}
	return "srv-group-" + hex.EncodeToString(value), nil
}

func boolByte(value bool) uint8 {
	if value {
		return 1
	}
	return 0
}
func nullAssetID(value uint64) any {
	if value == 0 {
		return nil
	}
	return value
}
