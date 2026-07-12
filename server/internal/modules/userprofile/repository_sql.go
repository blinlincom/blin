package userprofile

import (
	"bim/server/internal/platform/database"
	"context"
	"database/sql"
	"errors"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }
func (r *SQLRepository) Profile(ctx context.Context, appID, userID uint64) (Profile, error) {
	var p Profile
	err := r.db.QueryRowContext(ctx, `SELECT id,username,nickname,COALESCE(avatar_asset_id,0),COALESCE(background_asset_id,0),bio,gender,region,status FROM users WHERE app_id=? AND id=?`, appID, userID).Scan(&p.ID, &p.Username, &p.Nickname, &p.AvatarAssetID, &p.BackgroundAssetID, &p.Bio, &p.Gender, &p.Region, &p.Status)
	if errors.Is(err, sql.ErrNoRows) {
		return Profile{}, ErrNotFound
	}
	return p, err
}
func (r *SQLRepository) UpdateProfile(ctx context.Context, appID, userID uint64, input Profile) (Profile, error) {
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		for _, id := range []uint64{input.AvatarAssetID, input.BackgroundAssetID} {
			if id == 0 {
				continue
			}
			var count int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_assets ma JOIN media_access ac ON ac.asset_id=ma.id AND ac.app_id=ma.app_id WHERE ma.app_id=? AND ma.id=? AND ac.user_id=? AND ma.media_kind='image' AND ma.status='ready'`, appID, id, userID).Scan(&count); err != nil || count != 1 {
				return ErrForbidden
			}
		}
		result, err := tx.ExecContext(ctx, `UPDATE users SET nickname=?,avatar_asset_id=NULLIF(?,0),background_asset_id=NULLIF(?,0),bio=?,gender=?,region=?,updated_at=NOW(6) WHERE app_id=? AND id=? AND status=1`, input.Nickname, input.AvatarAssetID, input.BackgroundAssetID, input.Bio, input.Gender, input.Region, appID, userID)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return Profile{}, err
	}
	return r.Profile(ctx, appID, userID)
}
func (r *SQLRepository) Settings(ctx context.Context, appID, userID uint64) (Settings, error) {
	_, err := r.db.ExecContext(ctx, `INSERT INTO user_settings(app_id,user_id,created_at,updated_at) VALUES(?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE updated_at=updated_at`, appID, userID)
	if err != nil {
		return Settings{}, err
	}
	var v [5]uint8
	err = r.db.QueryRowContext(ctx, `SELECT read_receipts_enabled,history_sync_enabled,burn_after_read_enabled,new_message_sound_enabled,moments_visible FROM user_settings WHERE app_id=? AND user_id=?`, appID, userID).Scan(&v[0], &v[1], &v[2], &v[3], &v[4])
	return Settings{v[0] == 1, v[1] == 1, v[2] == 1, v[3] == 1, v[4] == 1}, err
}
func (r *SQLRepository) UpdateSettings(ctx context.Context, appID, userID uint64, input Settings) (Settings, error) {
	_, err := r.db.ExecContext(ctx, `INSERT INTO user_settings(app_id,user_id,read_receipts_enabled,history_sync_enabled,burn_after_read_enabled,new_message_sound_enabled,moments_visible,created_at,updated_at) VALUES(?,?,?,?,?,?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE read_receipts_enabled=VALUES(read_receipts_enabled),history_sync_enabled=VALUES(history_sync_enabled),burn_after_read_enabled=VALUES(burn_after_read_enabled),new_message_sound_enabled=VALUES(new_message_sound_enabled),moments_visible=VALUES(moments_visible),updated_at=NOW(6)`, appID, userID, input.ReadReceiptsEnabled, input.HistorySyncEnabled, input.BurnAfterReadEnabled, input.NewMessageSoundEnabled, input.MomentsVisible)
	if err != nil {
		return Settings{}, err
	}
	return r.Settings(ctx, appID, userID)
}
func (r *SQLRepository) Devices(ctx context.Context, appID, userID uint64, current string) ([]DeviceSession, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT session_id,platform,device_id,device_name,last_seen_at,expire_at FROM device_sessions WHERE app_id=? AND user_id=? AND status='active' ORDER BY last_seen_at DESC`, appID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []DeviceSession{}
	for rows.Next() {
		var item DeviceSession
		if err := rows.Scan(&item.SessionID, &item.Platform, &item.DeviceID, &item.DeviceName, &item.LastSeenAt, &item.ExpiresAt); err != nil {
			return nil, err
		}
		item.Current = item.SessionID == current
		items = append(items, item)
	}
	return items, rows.Err()
}
func (r *SQLRepository) RevokeDevice(ctx context.Context, appID, userID uint64, sessionID, current string) error {
	result, err := r.db.ExecContext(ctx, `UPDATE device_sessions SET status='revoked',updated_at=NOW(6) WHERE app_id=? AND user_id=? AND session_id=? AND session_id<>? AND status='active'`, appID, userID, sessionID, current)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return ErrNotFound
	}
	return nil
}
