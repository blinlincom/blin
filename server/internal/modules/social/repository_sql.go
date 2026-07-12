package social

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"bim/server/internal/platform/database"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }

func (r *SQLRepository) SearchUserByUsername(ctx context.Context, appID uint64, username string) (UserSummary, error) {
	var user UserSummary
	err := r.db.QueryRowContext(ctx, `SELECT id,username,nickname,COALESCE(avatar_asset_id,0) FROM users WHERE app_id=? AND username=? AND status=1 LIMIT 1`, appID, username).
		Scan(&user.ID, &user.Username, &user.Nickname, &user.AvatarAssetID)
	if errors.Is(err, sql.ErrNoRows) {
		return UserSummary{}, ErrNotFound
	}
	return user, err
}

func (r *SQLRepository) ListFriends(ctx context.Context, appID, userID uint64, query string) ([]UserSummary, error) {
	like := "%" + escapeLike(query) + "%"
	rows, err := r.db.QueryContext(ctx, `SELECT u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),f.remark FROM friendships f JOIN users u ON u.id=f.friend_id AND u.app_id=f.app_id WHERE f.app_id=? AND f.user_id=? AND f.status='active' AND (?='' OR u.nickname LIKE ? ESCAPE '\\' OR f.remark LIKE ? ESCAPE '\\') ORDER BY COALESCE(NULLIF(f.remark,''),u.nickname),u.id`, appID, userID, query, like, like)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]UserSummary, 0)
	for rows.Next() {
		var user UserSummary
		if err := rows.Scan(&user.ID, &user.Username, &user.Nickname, &user.AvatarAssetID, &user.Remark); err != nil {
			return nil, err
		}
		result = append(result, user)
	}
	return result, rows.Err()
}

func (r *SQLRepository) CreateFriendRequest(ctx context.Context, appID, requesterID, recipientID uint64, message string) (uint64, error) {
	if friends, err := r.areFriends(ctx, appID, requesterID, recipientID); err != nil {
		return 0, err
	} else if friends {
		return 0, ErrAlreadyFriends
	}
	var pendingID uint64
	err := r.db.QueryRowContext(ctx, `SELECT id FROM friend_requests WHERE app_id=? AND requester_id=? AND recipient_id=? AND status='pending' LIMIT 1`, appID, requesterID, recipientID).Scan(&pendingID)
	if err == nil {
		return 0, ErrRequestPending
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	now := time.Now().UTC()
	result, err := r.db.ExecContext(ctx, `INSERT INTO friend_requests(app_id,requester_id,recipient_id,message,status,created_at,updated_at) SELECT ?,?,?,?,?,?,? FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1) AND EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1)`, appID, requesterID, recipientID, message, "pending", now, now, appID, requesterID, appID, recipientID)
	if err != nil {
		return 0, err
	}
	rows, _ := result.RowsAffected()
	if rows != 1 {
		return 0, ErrNotFound
	}
	id, err := result.LastInsertId()
	return uint64(id), err
}

func (r *SQLRepository) ListFriendRequests(ctx context.Context, appID, recipientID uint64) ([]FriendRequest, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT fr.id,fr.recipient_id,u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),fr.message,fr.status,fr.created_at FROM friend_requests fr JOIN users u ON u.id=fr.requester_id WHERE fr.app_id=? AND fr.recipient_id=? ORDER BY fr.created_at DESC,fr.id DESC`, appID, recipientID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]FriendRequest, 0)
	for rows.Next() {
		var item FriendRequest
		if err := rows.Scan(&item.ID, &item.RecipientID, &item.Requester.ID, &item.Requester.Username, &item.Requester.Nickname, &item.Requester.AvatarAssetID, &item.Message, &item.Status, &item.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func (r *SQLRepository) HandleFriendRequest(ctx context.Context, appID, requestID, recipientID uint64, accept bool) error {
	return r.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		var requesterID uint64
		err := tx.QueryRowContext(ctx, `SELECT requester_id FROM friend_requests WHERE id=? AND app_id=? AND recipient_id=? AND status='pending' FOR UPDATE`, requestID, appID, recipientID).Scan(&requesterID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		status := "rejected"
		if accept {
			status = "accepted"
			now := time.Now().UTC()
			for _, pair := range [][2]uint64{{requesterID, recipientID}, {recipientID, requesterID}} {
				_, err = tx.ExecContext(ctx, `INSERT INTO friendships(app_id,user_id,friend_id,status,created_at,updated_at) VALUES(?,?,?,'active',?,?) ON DUPLICATE KEY UPDATE status='active',updated_at=VALUES(updated_at)`, appID, pair[0], pair[1], now, now)
				if err != nil {
					return err
				}
			}
		}
		_, err = tx.ExecContext(ctx, `UPDATE friend_requests SET status=?,handled_at=NOW(6),updated_at=NOW(6) WHERE id=?`, status, requestID)
		return err
	})
}

func (r *SQLRepository) DeleteFriendship(ctx context.Context, appID, userID, friendID uint64) error {
	result, err := r.db.ExecContext(ctx, `UPDATE friendships SET status='deleted',updated_at=NOW(6) WHERE app_id=? AND ((user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)) AND status='active'`, appID, userID, friendID, friendID, userID)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *SQLRepository) CreateGroup(ctx context.Context, appID, ownerID uint64, name string, memberIDs []uint64) (Group, error) {
	var group Group
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		temporaryChannel := fmt.Sprintf("pending-%d-%d", ownerID, now.UnixNano())
		result, err := tx.ExecContext(ctx, `INSERT INTO chat_groups(app_id,channel_id,name,announcement,owner_id,join_history_policy,status,member_count,created_at,updated_at) VALUES(?,?,?,'',?,?,'active',?,?,?)`, appID, temporaryChannel, name, ownerID, "after_join", len(memberIDs), now, now)
		if err != nil {
			return err
		}
		groupID, err := result.LastInsertId()
		if err != nil {
			return err
		}
		channelID := fmt.Sprintf("app%dgroup%d", appID, groupID)
		if _, err := tx.ExecContext(ctx, `UPDATE chat_groups SET channel_id=? WHERE id=?`, channelID, groupID); err != nil {
			return err
		}
		for _, memberID := range memberIDs {
			role := "member"
			if memberID == ownerID {
				role = "owner"
			}
			result, err := tx.ExecContext(ctx, `INSERT INTO group_members(app_id,group_id,user_id,role,joined_at,status,created_at,updated_at) SELECT ?,?,?,?,?, 'active',?,? FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1)`, appID, groupID, memberID, role, now, now, now, appID, memberID)
			if err != nil {
				return err
			}
			rows, _ := result.RowsAffected()
			if rows != 1 {
				return ErrNotFound
			}
		}
		if err := enqueueChannelOperation(ctx, tx, appID, "subscriber_add", channelID, memberIDs); err != nil {
			return err
		}
		if err := enqueueGroupEvent(ctx, tx, appID, ownerID, channelID, "group_created", map[string]any{"group_id": groupID, "member_ids": memberIDs}); err != nil {
			return err
		}
		group = Group{ID: uint64(groupID), ChannelID: channelID, Name: name, OwnerID: ownerID, MemberCount: uint32(len(memberIDs)), JoinHistoryPolicy: "after_join", CreatedAt: now}
		return nil
	})
	return group, err
}

func (r *SQLRepository) areFriends(ctx context.Context, appID, userID, friendID uint64) (bool, error) {
	var count int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM friendships WHERE app_id=? AND user_id=? AND friend_id=? AND status='active'`, appID, userID, friendID).Scan(&count)
	return count > 0, err
}
func escapeLike(value string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return replacer.Replace(value)
}
