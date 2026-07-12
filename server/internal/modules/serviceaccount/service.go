package serviceaccount

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"

	"bim/server/internal/platform/database"
)

type Service struct{ db *database.DB }

func NewService(db *database.DB) *Service { return &Service{db: db} }
func (s *Service) List(ctx context.Context, appID, userID uint64) ([]Account, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT sa.id,sa.code,sa.name,COALESCE(sa.avatar_asset_id,0),sa.description,sa.input_enabled,COALESCE(uss.muted,0),COALESCE(uss.subscribed,1),sa.menu_json FROM service_accounts sa LEFT JOIN user_service_settings uss ON uss.app_id=sa.app_id AND uss.service_account_id=sa.id AND uss.user_id=? WHERE sa.app_id=? AND sa.status='active' ORDER BY sa.id`, userID, appID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Account, 0)
	for rows.Next() {
		var item Account
		var raw []byte
		if err := rows.Scan(&item.ID, &item.Code, &item.Name, &item.AvatarAssetID, &item.Description, &item.InputEnabled, &item.Muted, &item.Subscribed, &raw); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(raw, &item.Menu)
		items = append(items, item)
	}
	return items, rows.Err()
}
func (s *Service) Get(ctx context.Context, appID, userID uint64, code string) (Account, error) {
	items, err := s.List(ctx, appID, userID)
	if err != nil {
		return Account{}, err
	}
	for _, item := range items {
		if item.Code == code {
			return item, nil
		}
	}
	return Account{}, sql.ErrNoRows
}
func (s *Service) UpdateSettings(ctx context.Context, appID, userID uint64, code string, muted, subscribed bool) error {
	result, err := s.db.ExecContext(ctx, `INSERT INTO user_service_settings(app_id,user_id,service_account_id,subscribed,muted,created_at,updated_at) SELECT ?,?,id,?,?,NOW(6),NOW(6) FROM service_accounts WHERE app_id=? AND code=? AND status='active' ON DUPLICATE KEY UPDATE subscribed=VALUES(subscribed),muted=VALUES(muted),updated_at=NOW(6)`, appID, userID, boolByte(subscribed), boolByte(muted), appID, code)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return errors.New("service account not found")
	}
	return nil
}
func boolByte(v bool) uint8 {
	if v {
		return 1
	}
	return 0
}
