package moments

import (
	"bim/server/internal/platform/database"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Service struct{ db *database.DB }

func NewService(db *database.DB) *Service { return &Service{db: db} }
func (s *Service) Create(ctx context.Context, appID, userID uint64, content, visibility string, media []Media) (Moment, error) {
	content = strings.TrimSpace(content)
	if len([]rune(content)) > 2000 {
		return Moment{}, fmt.Errorf("内容超过限制")
	}
	if visibility == "" {
		visibility = "friends"
	}
	if visibility != "friends" && visibility != "private" {
		return Moment{}, fmt.Errorf("可见范围无效")
	}
	if len(media) > 9 {
		return Moment{}, fmt.Errorf("媒体最多 9 项")
	}
	videos := 0
	assetIDs := make([]uint64, 0, len(media)*2)
	for _, item := range media {
		if item.AssetID == 0 || (item.Type != "image" && item.Type != "video") {
			return Moment{}, fmt.Errorf("媒体参数无效")
		}
		assetIDs = append(assetIDs, item.AssetID)
		if item.ThumbnailAssetID > 0 {
			assetIDs = append(assetIDs, item.ThumbnailAssetID)
		}
		if item.Type == "video" {
			videos++
		}
	}
	if videos > 1 || (videos == 1 && len(media) > 1) {
		return Moment{}, fmt.Errorf("视频动态只能包含一个视频")
	}
	if content == "" && len(media) == 0 {
		return Moment{}, fmt.Errorf("动态内容不能为空")
	}
	for _, assetID := range assetIDs {
		var kind string
		if err := s.db.QueryRowContext(ctx, `SELECT media_kind FROM media_assets WHERE app_id=? AND id=? AND owner_id=? AND status='ready'`, appID, assetID, userID).Scan(&kind); err != nil {
			return Moment{}, fmt.Errorf("媒体资源不存在或不属于当前用户")
		}
	}
	raw, _ := json.Marshal(media)
	status := "pending"
	var mode string
	_ = s.db.QueryRowContext(ctx, `SELECT COALESCE(JSON_UNQUOTE(JSON_EXTRACT(config_json,'$.moments_review_mode')),'manual') FROM applications WHERE id=?`, appID).Scan(&mode)
	if mode == "disabled" {
		return Moment{}, fmt.Errorf("朋友圈发布已关闭")
	}
	if mode == "auto" {
		status = "published"
	}
	now := time.Now().UTC()
	result, err := s.db.ExecContext(ctx, `INSERT INTO moments(app_id,user_id,content,media_json,visibility,status,created_at,updated_at) SELECT ?,?,?,?,?,?,?,? FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1)`, appID, userID, content, raw, visibility, status, now, now, appID, userID)
	if err != nil {
		return Moment{}, err
	}
	id, _ := result.LastInsertId()
	return s.Get(ctx, appID, userID, uint64(id))
}
func (s *Service) Feed(ctx context.Context, appID, userID, beforeID uint64, limit int) ([]Moment, error) {
	if beforeID == 0 {
		beforeID = ^uint64(0)
	}
	if limit <= 0 {
		limit = 20
	}
	if limit > 50 {
		limit = 50
	}
	rows, err := s.db.QueryContext(ctx, `SELECT m.id,m.user_id,u.nickname,COALESCE(u.avatar_asset_id,0),m.content,m.media_json,m.visibility,m.status,m.review_reason,m.created_at,EXISTS(SELECT 1 FROM moment_likes ml WHERE ml.moment_id=m.id AND ml.user_id=?) FROM moments m JOIN users u ON u.id=m.user_id WHERE m.app_id=? AND m.id<? AND m.deleted_at IS NULL AND ((m.user_id=? AND m.status IN ('pending','published')) OR (m.status='published' AND m.visibility='friends' AND EXISTS(SELECT 1 FROM friendships f WHERE f.app_id=m.app_id AND f.user_id=? AND f.friend_id=m.user_id AND f.status='active'))) ORDER BY m.id DESC LIMIT ?`, userID, appID, beforeID, userID, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Moment, 0)
	for rows.Next() {
		var item Moment
		var raw []byte
		if err := rows.Scan(&item.ID, &item.Author.ID, &item.Author.Nickname, &item.Author.AvatarAssetID, &item.Content, &raw, &item.Visibility, &item.Status, &item.ReviewReason, &item.CreatedAt, &item.Liked); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(raw, &item.Media)
		if err := s.grantMediaAccess(ctx, appID, userID, item.Media); err != nil {
			return nil, err
		}
		item.Likes, _ = s.likes(ctx, item.ID)
		item.Comments, _ = s.comments(ctx, item.ID)
		items = append(items, item)
	}
	return items, rows.Err()
}
func (s *Service) Get(ctx context.Context, appID, userID, id uint64) (Moment, error) {
	items, err := s.Feed(ctx, appID, userID, id+1, 1)
	if err != nil {
		return Moment{}, err
	}
	if len(items) == 0 || items[0].ID != id {
		return Moment{}, sql.ErrNoRows
	}
	return items[0], nil
}
func (s *Service) Delete(ctx context.Context, appID, userID, id uint64) error {
	result, err := s.db.ExecContext(ctx, `UPDATE moments SET deleted_at=NOW(6),updated_at=NOW(6) WHERE app_id=? AND id=? AND user_id=? AND deleted_at IS NULL`, appID, id, userID)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}
func (s *Service) Like(ctx context.Context, appID, userID, id uint64, liked bool) error {
	if err := s.canInteract(ctx, appID, userID, id); err != nil {
		return err
	}
	if liked {
		_, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO moment_likes(moment_id,app_id,user_id,created_at) VALUES(?,?,?,NOW(6))`, id, appID, userID)
		return err
	}
	_, err := s.db.ExecContext(ctx, `DELETE FROM moment_likes WHERE moment_id=? AND app_id=? AND user_id=?`, id, appID, userID)
	return err
}
func (s *Service) Comment(ctx context.Context, appID, userID, id uint64, content string, reply *uint64) (Comment, error) {
	content = strings.TrimSpace(content)
	if content == "" || len([]rune(content)) > 500 {
		return Comment{}, fmt.Errorf("评论内容无效")
	}
	if err := s.canInteract(ctx, appID, userID, id); err != nil {
		return Comment{}, err
	}
	if reply != nil {
		var count int
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE app_id=? AND id=? AND status=1`, appID, *reply).Scan(&count); err != nil || count == 0 {
			return Comment{}, fmt.Errorf("回复用户不存在")
		}
	}
	result, err := s.db.ExecContext(ctx, `INSERT INTO moment_comments(moment_id,app_id,user_id,reply_to_user_id,content,created_at) VALUES(?,?,?,?,?,NOW(6))`, id, appID, userID, reply, content)
	if err != nil {
		return Comment{}, err
	}
	cid, _ := result.LastInsertId()
	var item Comment
	item.ID = uint64(cid)
	item.ReplyToUserID = reply
	item.Content = content
	err = s.db.QueryRowContext(ctx, `SELECT u.id,u.nickname,COALESCE(u.avatar_asset_id,0),mc.created_at FROM moment_comments mc JOIN users u ON u.id=mc.user_id WHERE mc.id=?`, cid).Scan(&item.Author.ID, &item.Author.Nickname, &item.Author.AvatarAssetID, &item.CreatedAt)
	return item, err
}
func (s *Service) DeleteComment(ctx context.Context, appID, userID, commentID uint64) error {
	result, err := s.db.ExecContext(ctx, `UPDATE moment_comments mc JOIN moments m ON m.id=mc.moment_id SET mc.deleted_at=NOW(6) WHERE mc.id=? AND mc.app_id=? AND (mc.user_id=? OR m.user_id=?) AND mc.deleted_at IS NULL`, commentID, appID, userID, userID)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}
func (s *Service) canInteract(ctx context.Context, appID, userID, id uint64) error {
	var count int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM moments m WHERE m.app_id=? AND m.id=? AND m.status='published' AND m.deleted_at IS NULL AND (m.user_id=? OR (m.visibility='friends' AND EXISTS(SELECT 1 FROM friendships f WHERE f.app_id=m.app_id AND f.user_id=? AND f.friend_id=m.user_id AND f.status='active')))`, appID, id, userID, userID).Scan(&count)
	if err != nil {
		return err
	}
	if count == 0 {
		return errors.New("动态不可访问")
	}
	return nil
}
func (s *Service) likes(ctx context.Context, id uint64) ([]Author, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT u.id,u.nickname,COALESCE(u.avatar_asset_id,0) FROM moment_likes ml JOIN users u ON u.id=ml.user_id WHERE ml.moment_id=? ORDER BY ml.created_at`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Author{}
	for rows.Next() {
		var a Author
		if err := rows.Scan(&a.ID, &a.Nickname, &a.AvatarAssetID); err != nil {
			return nil, err
		}
		items = append(items, a)
	}
	return items, rows.Err()
}
func (s *Service) comments(ctx context.Context, id uint64) ([]Comment, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT mc.id,u.id,u.nickname,COALESCE(u.avatar_asset_id,0),mc.reply_to_user_id,mc.content,mc.created_at FROM moment_comments mc JOIN users u ON u.id=mc.user_id WHERE mc.moment_id=? AND mc.deleted_at IS NULL ORDER BY mc.id`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Comment{}
	for rows.Next() {
		var c Comment
		var reply sql.NullInt64
		if err := rows.Scan(&c.ID, &c.Author.ID, &c.Author.Nickname, &c.Author.AvatarAssetID, &reply, &c.Content, &c.CreatedAt); err != nil {
			return nil, err
		}
		if reply.Valid {
			v := uint64(reply.Int64)
			c.ReplyToUserID = &v
		}
		items = append(items, c)
	}
	return items, rows.Err()
}

func (s *Service) grantMediaAccess(ctx context.Context, appID, userID uint64, media []Media) error {
	for _, item := range media {
		for _, assetID := range []uint64{item.AssetID, item.ThumbnailAssetID} {
			if assetID == 0 {
				continue
			}
			if _, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO media_access(asset_id,app_id,user_id,granted_at) SELECT id,app_id,?,NOW(6) FROM media_assets WHERE app_id=? AND id=? AND status='ready'`, userID, appID, assetID); err != nil {
				return err
			}
		}
	}
	return nil
}
