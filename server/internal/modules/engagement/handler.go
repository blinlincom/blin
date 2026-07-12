package engagement

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"database/sql"
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type Handler struct{ db *database.DB }

func NewHandler(db *database.DB) *Handler { return &Handler{db: db} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Post("/signin", h.signin)
	r.Post("/invitation", h.bindInvitation)
	r.Put("/follows/{userID}", h.follow)
	r.Delete("/follows/{userID}", h.unfollow)
	r.Get("/follows/{userID}/status", h.followStatus)
	r.Get("/follows", h.followList)
	r.Get("/fans", h.fans)
	r.Get("/rankings", h.rankings)
	r.Get("/badges", h.badges)
	r.Put("/badges/{id}/wear", h.wearBadge)
	return r
}
func p(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	v, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return v, ok
}
func pathID(w http.ResponseWriter, r *http.Request, key string) (uint64, bool) {
	v, e := strconv.ParseUint(chi.URLParam(r, key), 10, 64)
	if e != nil || v == 0 {
		httpx.Error(w, r, 400, "INVALID_ID", "用户编号无效")
		return 0, false
	}
	return v, true
}
func (h *Handler) signin(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	today := time.Now().In(time.Local).Format("2006-01-02")
	yesterday := time.Now().In(time.Local).AddDate(0, 0, -1).Format("2006-01-02")
	streak := 1
	_ = h.db.QueryRowContext(r.Context(), `SELECT streak_days+1 FROM user_signins WHERE app_id=? AND user_id=? AND signin_date=?`, u.User.AppID, u.User.ID, yesterday).Scan(&streak)
	result, err := h.db.ExecContext(r.Context(), `INSERT IGNORE INTO user_signins(app_id,user_id,signin_date,streak_days,created_at) VALUES(?,?,?,?,NOW(6))`, u.User.AppID, u.User.ID, today, streak)
	if err != nil {
		httpx.Error(w, r, 500, "SIGNIN_FAILED", "签到失败")
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		_ = h.db.QueryRowContext(r.Context(), `SELECT streak_days FROM user_signins WHERE app_id=? AND user_id=? AND signin_date=?`, u.User.AppID, u.User.ID, today).Scan(&streak)
	}
	httpx.OK(w, r, map[string]any{"signed": rows == 1, "streak_days": streak})
}
func (h *Handler) bindInvitation(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	var q struct {
		Code string `json:"code"`
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	if d.Decode(&q) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "邀请码无效")
		return
	}
	q.Code = strings.ToUpper(strings.TrimSpace(q.Code))
	result, err := h.db.ExecContext(r.Context(), `UPDATE users target JOIN users inviter ON inviter.app_id=target.app_id AND inviter.invitation_code=? SET target.invited_by=inviter.id,target.updated_at=NOW(6) WHERE target.app_id=? AND target.id=? AND target.invited_by IS NULL AND inviter.id<>target.id`, q.Code, u.User.AppID, u.User.ID)
	if err != nil {
		httpx.Error(w, r, 400, "INVITATION_FAILED", "邀请码绑定失败")
		return
	}
	rows, _ := result.RowsAffected()
	if rows != 1 {
		httpx.Error(w, r, 409, "INVITATION_ALREADY_SET", "邀请码无效或已绑定")
		return
	}
	httpx.OK(w, r, map[string]bool{"bound": true})
}
func (h *Handler) follow(w http.ResponseWriter, r *http.Request)   { h.setFollow(w, r, true) }
func (h *Handler) unfollow(w http.ResponseWriter, r *http.Request) { h.setFollow(w, r, false) }
func (h *Handler) setFollow(w http.ResponseWriter, r *http.Request, value bool) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	target, ok := pathID(w, r, "userID")
	if !ok {
		return
	}
	if target == u.User.ID {
		httpx.Error(w, r, 400, "SELF_OPERATION", "不能关注自己")
		return
	}
	if value {
		result, err := h.db.ExecContext(r.Context(), `INSERT IGNORE INTO user_follows(app_id,user_id,follow_user_id,created_at) SELECT ?,?,?,NOW(6) FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1)`, u.User.AppID, u.User.ID, target, u.User.AppID, target)
		if err != nil {
			httpx.Error(w, r, 500, "FOLLOW_FAILED", "关注失败")
			return
		}
		rows, _ := result.RowsAffected()
		if rows == 0 {
			var exists int
			_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM users WHERE app_id=? AND id=? AND status=1`, u.User.AppID, target).Scan(&exists)
			if exists == 0 {
				httpx.Error(w, r, 404, "USER_NOT_FOUND", "用户不存在")
				return
			}
		}
	} else {
		_, _ = h.db.ExecContext(r.Context(), `DELETE FROM user_follows WHERE app_id=? AND user_id=? AND follow_user_id=?`, u.User.AppID, u.User.ID, target)
	}
	httpx.OK(w, r, map[string]bool{"following": value})
}
func (h *Handler) followStatus(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	target, ok := pathID(w, r, "userID")
	if !ok {
		return
	}
	var count int
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM user_follows WHERE app_id=? AND user_id=? AND follow_user_id=?`, u.User.AppID, u.User.ID, target).Scan(&count)
	httpx.OK(w, r, map[string]bool{"following": count == 1})
}
func (h *Handler) followList(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	h.userList(w, r, `SELECT x.id,x.username,x.nickname,COALESCE(x.avatar_asset_id,0) FROM user_follows f JOIN users x ON x.id=f.follow_user_id WHERE f.app_id=? AND f.user_id=? ORDER BY f.created_at DESC`, u.User.AppID, u.User.ID)
}
func (h *Handler) fans(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	h.userList(w, r, `SELECT x.id,x.username,x.nickname,COALESCE(x.avatar_asset_id,0) FROM user_follows f JOIN users x ON x.id=f.user_id WHERE f.app_id=? AND f.follow_user_id=? ORDER BY f.created_at DESC`, u.User.AppID, u.User.ID)
}
func (h *Handler) userList(w http.ResponseWriter, r *http.Request, query string, args ...any) {
	rows, err := h.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		httpx.Error(w, r, 500, "USER_LIST_FAILED", "用户列表加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, avatar uint64
		var username, nickname string
		if rows.Scan(&id, &username, &nickname, &avatar) != nil {
			return
		}
		items = append(items, map[string]any{"id": id, "username": username, "nickname": nickname, "avatar_asset_id": avatar})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) rankings(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	kind := r.URL.Query().Get("kind")
	query := `SELECT u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),COUNT(f.user_id) score FROM users u LEFT JOIN user_follows f ON f.app_id=u.app_id AND f.follow_user_id=u.id WHERE u.app_id=? AND u.status=1 GROUP BY u.id ORDER BY score DESC,u.id LIMIT 100`
	if kind == "invitation" {
		query = `SELECT u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),COUNT(i.id) score FROM users u LEFT JOIN users i ON i.invited_by=u.id WHERE u.app_id=? AND u.status=1 GROUP BY u.id ORDER BY score DESC,u.id LIMIT 100`
	}
	rows, err := h.db.QueryContext(r.Context(), query, u.User.AppID)
	if err != nil {
		httpx.Error(w, r, 500, "RANKING_FAILED", "排行榜加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	rank := 0
	for rows.Next() {
		rank++
		var id, avatar, score uint64
		var username, nickname string
		if rows.Scan(&id, &username, &nickname, &avatar, &score) != nil {
			return
		}
		items = append(items, map[string]any{"rank": rank, "id": id, "username": username, "nickname": nickname, "avatar_asset_id": avatar, "score": score})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) badges(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT id,code,name,COALESCE(icon_asset_id,0),awarded_at,worn FROM user_badges WHERE app_id=? AND user_id=? ORDER BY awarded_at DESC`, u.User.AppID, u.User.ID)
	if err != nil {
		httpx.Error(w, r, 500, "BADGE_FAILED", "徽章加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, asset uint64
		var code, name string
		var awarded time.Time
		var worn bool
		if rows.Scan(&id, &code, &name, &asset, &awarded, &worn) != nil {
			return
		}
		items = append(items, map[string]any{"id": id, "code": code, "name": name, "icon_asset_id": asset, "awarded_at": awarded, "worn": worn})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) wearBadge(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(r.Context(), `UPDATE user_badges SET worn=0 WHERE app_id=? AND user_id=?`, u.User.AppID, u.User.ID); err != nil {
			return err
		}
		result, err := tx.ExecContext(r.Context(), `UPDATE user_badges SET worn=1 WHERE app_id=? AND user_id=? AND id=?`, u.User.AppID, u.User.ID, id)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows != 1 {
			return sql.ErrNoRows
		}
		return nil
	})
	if err != nil {
		httpx.Error(w, r, 404, "BADGE_NOT_FOUND", "徽章不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"worn": true})
}
