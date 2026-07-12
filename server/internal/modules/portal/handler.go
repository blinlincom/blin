package portal

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
)

type Handler struct{ db *database.DB }

func NewHandler(db *database.DB) *Handler { return &Handler{db: db} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/sections", h.sections)
	r.Get("/posts", h.posts)
	r.Post("/posts", h.createPost)
	r.Get("/posts/{id}", h.postDetail)
	r.Put("/posts/{id}", h.updatePost)
	r.Delete("/posts/{id}", h.deletePost)
	r.Post("/posts/{id}/comments", h.comment)
	r.Put("/posts/{id}/like", h.like)
	r.Delete("/posts/{id}/like", h.unlike)
	r.Put("/posts/{id}/collection", h.collect)
	r.Delete("/posts/{id}/collection", h.uncollect)
	r.Post("/reports", h.report)
	r.Get("/notes", h.notes)
	r.Post("/notes", h.createNote)
	r.Put("/notes/{id}", h.updateNote)
	r.Delete("/notes/{id}", h.deleteNote)
	r.Get("/products", h.products)
	r.Post("/products/{id}/orders", h.buyProduct)
	r.Get("/orders", h.orders)
	r.Get("/stickers/packs", h.stickerPacks)
	r.Post("/stickers/packs/{id}/acquire", h.acquireStickerPack)
	r.Get("/market", h.market)
	r.Post("/market", h.publishMarketItem)
	return r
}

func principal(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return p, ok
}
func pathID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id == 0 {
		httpx.Error(w, r, 400, "INVALID_ID", "编号无效")
		return 0, false
	}
	return id, true
}
func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20))
	d.DisallowUnknownFields()
	if err := d.Decode(target); err != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func page(r *http.Request) (uint64, int) {
	before, _ := strconv.ParseUint(r.URL.Query().Get("before_id"), 10, 64)
	if before == 0 {
		before = ^uint64(0)
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return before, limit
}
func (h *Handler) sections(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT id,name,description FROM content_sections WHERE app_id=? AND status='active' ORDER BY sort_order,id`, p.User.AppID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var name, desc string
		if rows.Scan(&id, &name, &desc) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "description": desc})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) posts(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	before, limit := page(r)
	section, _ := strconv.ParseUint(r.URL.Query().Get("section_id"), 10, 64)
	rows, err := h.db.QueryContext(r.Context(), `SELECT p.id,p.section_id,p.user_id,u.nickname,COALESCE(u.avatar_asset_id,0),p.title,p.content,p.media_json,p.like_count,p.comment_count,p.view_count,p.created_at,EXISTS(SELECT 1 FROM content_likes l WHERE l.post_id=p.id AND l.user_id=?),EXISTS(SELECT 1 FROM content_collections c WHERE c.post_id=p.id AND c.user_id=?) FROM content_posts p JOIN users u ON u.id=p.user_id WHERE p.app_id=? AND p.status='published' AND p.deleted_at IS NULL AND p.id<? AND (?=0 OR p.section_id=?) ORDER BY p.id DESC LIMIT ?`, p.User.ID, p.User.ID, p.User.AppID, before, section, section, limit)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, sid, uid, avatar, views uint64
		var likes, comments uint32
		var nickname, title, content string
		var raw []byte
		var created any
		var liked, collected bool
		if rows.Scan(&id, &sid, &uid, &nickname, &avatar, &title, &content, &raw, &likes, &comments, &views, &created, &liked, &collected) == nil {
			var media any
			_ = json.Unmarshal(raw, &media)
			items = append(items, map[string]any{"id": id, "section_id": sid, "author": map[string]any{"id": uid, "nickname": nickname, "avatar_asset_id": avatar}, "title": title, "content": content, "media": media, "like_count": likes, "comment_count": comments, "view_count": views, "liked": liked, "collected": collected, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}

type postInput struct {
	SectionID uint64           `json:"section_id"`
	Title     string           `json:"title"`
	Content   string           `json:"content"`
	Media     []map[string]any `json:"media"`
}

func validPost(q postInput) bool {
	return q.SectionID > 0 && strings.TrimSpace(q.Title) != "" && len([]rune(q.Title)) <= 200 && len([]rune(q.Content)) <= 100000 && len(q.Media) <= 9
}
func (h *Handler) createPost(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q postInput
	if !decode(w, r, &q) || !validPost(q) {
		httpx.Error(w, r, 400, "POST_INVALID", "帖子内容无效")
		return
	}
	raw, _ := json.Marshal(q.Media)
	result, err := h.db.ExecContext(r.Context(), `INSERT INTO content_posts(app_id,section_id,user_id,title,content,media_json,status,created_at,updated_at) SELECT ?,?,?,?,?,?,'pending',NOW(6),NOW(6) FROM DUAL WHERE EXISTS(SELECT 1 FROM content_sections WHERE app_id=? AND id=? AND status='active')`, p.User.AppID, q.SectionID, p.User.ID, strings.TrimSpace(q.Title), q.Content, raw, p.User.AppID, q.SectionID)
	if err != nil {
		fail(w, r)
		return
	}
	id, _ := result.LastInsertId()
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "帖子已提交审核", Data: map[string]any{"id": id, "status": "pending"}, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) postDetail(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	_, _ = h.db.ExecContext(r.Context(), `UPDATE content_posts SET view_count=view_count+1 WHERE app_id=? AND id=? AND status='published' AND deleted_at IS NULL`, p.User.AppID, id)
	r.URL.RawQuery = "before_id=" + strconv.FormatUint(id+1, 10) + "&limit=1"
	h.posts(w, r)
}
func (h *Handler) updatePost(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var q postInput
	if !decode(w, r, &q) || !validPost(q) {
		httpx.Error(w, r, 400, "POST_INVALID", "帖子内容无效")
		return
	}
	raw, _ := json.Marshal(q.Media)
	res, err := h.db.ExecContext(r.Context(), `UPDATE content_posts SET section_id=?,title=?,content=?,media_json=?,status='pending',review_reason='',updated_at=NOW(6) WHERE app_id=? AND id=? AND user_id=? AND deleted_at IS NULL`, q.SectionID, strings.TrimSpace(q.Title), q.Content, raw, p.User.AppID, id, p.User.ID)
	if err != nil {
		fail(w, r)
		return
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		httpx.Error(w, r, 404, "POST_NOT_FOUND", "帖子不存在")
		return
	}
	httpx.OK(w, r, map[string]any{"updated": true, "status": "pending"})
}
func (h *Handler) deletePost(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.db.ExecContext(r.Context(), `UPDATE content_posts SET deleted_at=NOW(6),updated_at=NOW(6) WHERE app_id=? AND id=? AND user_id=? AND deleted_at IS NULL`, p.User.AppID, id, p.User.ID)
	if err != nil {
		fail(w, r)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		httpx.Error(w, r, 404, "POST_NOT_FOUND", "帖子不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
func (h *Handler) comment(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var q struct {
		Content       string  `json:"content"`
		ReplyToUserID *uint64 `json:"reply_to_user_id"`
	}
	if !decode(w, r, &q) {
		return
	}
	q.Content = strings.TrimSpace(q.Content)
	if q.Content == "" || len([]rune(q.Content)) > 2000 {
		httpx.Error(w, r, 400, "COMMENT_INVALID", "评论内容无效")
		return
	}
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		res, e := tx.ExecContext(r.Context(), `INSERT INTO content_comments(app_id,post_id,user_id,reply_to_user_id,content,status,created_at,updated_at) SELECT ?,?,?,?,?,'published',NOW(6),NOW(6) FROM content_posts WHERE app_id=? AND id=? AND status='published' AND deleted_at IS NULL`, p.User.AppID, id, p.User.ID, q.ReplyToUserID, q.Content, p.User.AppID, id)
		if e != nil {
			return e
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			return sql.ErrNoRows
		}
		_, e = tx.ExecContext(r.Context(), `UPDATE content_posts SET comment_count=comment_count+1 WHERE id=?`, id)
		return e
	})
	if err != nil {
		httpx.Error(w, r, 404, "POST_NOT_FOUND", "帖子不存在")
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "评论成功", RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) like(w http.ResponseWriter, r *http.Request) {
	h.relation(w, r, "content_likes", true)
}
func (h *Handler) unlike(w http.ResponseWriter, r *http.Request) {
	h.relation(w, r, "content_likes", false)
}
func (h *Handler) collect(w http.ResponseWriter, r *http.Request) {
	h.relation(w, r, "content_collections", true)
}
func (h *Handler) uncollect(w http.ResponseWriter, r *http.Request) {
	h.relation(w, r, "content_collections", false)
}
func (h *Handler) relation(w http.ResponseWriter, r *http.Request, table string, value bool) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		if value {
			res, e := tx.ExecContext(r.Context(), `INSERT IGNORE INTO `+table+`(app_id,post_id,user_id,created_at) SELECT ?,?,?,NOW(6) FROM content_posts WHERE app_id=? AND id=? AND status='published' AND deleted_at IS NULL`, p.User.AppID, id, p.User.ID, p.User.AppID, id)
			if e != nil {
				return e
			}
			n, _ := res.RowsAffected()
			if n == 0 {
				return nil
			}
			if table == "content_likes" {
				_, e = tx.ExecContext(r.Context(), `UPDATE content_posts SET like_count=like_count+1 WHERE id=?`, id)
			}
			return e
		}
		res, e := tx.ExecContext(r.Context(), `DELETE FROM `+table+` WHERE app_id=? AND post_id=? AND user_id=?`, p.User.AppID, id, p.User.ID)
		if e != nil {
			return e
		}
		n, _ := res.RowsAffected()
		if n > 0 && table == "content_likes" {
			_, e = tx.ExecContext(r.Context(), `UPDATE content_posts SET like_count=GREATEST(like_count-1,0) WHERE id=?`, id)
		}
		return e
	})
	if err != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, map[string]bool{"active": value})
}
func (h *Handler) report(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q struct {
		TargetType string `json:"target_type"`
		TargetID   uint64 `json:"target_id"`
		Reason     string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	q.Reason = strings.TrimSpace(q.Reason)
	if (q.TargetType != "post" && q.TargetType != "comment" && q.TargetType != "user") || q.TargetID == 0 || len([]rune(q.Reason)) < 2 || len([]rune(q.Reason)) > 500 {
		httpx.Error(w, r, 400, "REPORT_INVALID", "举报参数无效")
		return
	}
	_, err := h.db.ExecContext(r.Context(), `INSERT INTO content_reports(app_id,user_id,target_type,target_id,reason,status,created_at,updated_at) VALUES(?,?,?,?,?,'pending',NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE reason=VALUES(reason),status='pending',updated_at=NOW(6)`, p.User.AppID, p.User.ID, q.TargetType, q.TargetID, q.Reason)
	if err != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, map[string]bool{"submitted": true})
}

type noteInput struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

func (h *Handler) notes(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT id,title,content,created_at,updated_at FROM user_notes WHERE app_id=? AND user_id=? AND deleted_at IS NULL ORDER BY updated_at DESC,id DESC LIMIT 500`, p.User.AppID, p.User.ID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var title, content string
		var created, updated any
		if rows.Scan(&id, &title, &content, &created, &updated) == nil {
			items = append(items, map[string]any{"id": id, "title": title, "content": content, "created_at": created, "updated_at": updated})
		}
	}
	httpx.OK(w, r, items)
}
func validNote(q noteInput) bool {
	return strings.TrimSpace(q.Title) != "" && len([]rune(q.Title)) <= 200 && len([]rune(q.Content)) <= 100000
}
func (h *Handler) createNote(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q noteInput
	if !decode(w, r, &q) || !validNote(q) {
		httpx.Error(w, r, 400, "NOTE_INVALID", "便签内容无效")
		return
	}
	res, err := h.db.ExecContext(r.Context(), `INSERT INTO user_notes(app_id,user_id,title,content,created_at,updated_at) VALUES(?,?,?,?,NOW(6),NOW(6))`, p.User.AppID, p.User.ID, strings.TrimSpace(q.Title), q.Content)
	if err != nil {
		fail(w, r)
		return
	}
	id, _ := res.LastInsertId()
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "创建成功", Data: map[string]any{"id": id}, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) updateNote(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var q noteInput
	if !decode(w, r, &q) || !validNote(q) {
		httpx.Error(w, r, 400, "NOTE_INVALID", "便签内容无效")
		return
	}
	res, err := h.db.ExecContext(r.Context(), `UPDATE user_notes SET title=?,content=?,updated_at=NOW(6) WHERE app_id=? AND user_id=? AND id=? AND deleted_at IS NULL`, strings.TrimSpace(q.Title), q.Content, p.User.AppID, p.User.ID, id)
	if err != nil {
		fail(w, r)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		httpx.Error(w, r, 404, "NOTE_NOT_FOUND", "便签不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) deleteNote(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.db.ExecContext(r.Context(), `UPDATE user_notes SET deleted_at=NOW(6),updated_at=NOW(6) WHERE app_id=? AND user_id=? AND id=? AND deleted_at IS NULL`, p.User.AppID, p.User.ID, id)
	if err != nil {
		fail(w, r)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		httpx.Error(w, r, 404, "NOTE_NOT_FOUND", "便签不存在")
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
func (h *Handler) products(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT id,name,description,COALESCE(cover_asset_id,0),price_cents,stock FROM products WHERE app_id=? AND status='active' ORDER BY id DESC`, p.User.AppID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, asset, price uint64
		var stock uint32
		var name, desc string
		if rows.Scan(&id, &name, &desc, &asset, &price, &stock) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "description": desc, "cover_asset_id": asset, "price_cents": price, "stock": stock})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) buyProduct(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	productID, ok := pathID(w, r)
	if !ok {
		return
	}
	var q struct {
		Quantity uint32 `json:"quantity"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.Quantity < 1 || q.Quantity > 100 {
		httpx.Error(w, r, 400, "QUANTITY_INVALID", "购买数量无效")
		return
	}
	orderNo := "GOODS-" + randomHex(16)
	var total uint64
	err := h.db.WithinTx(r.Context(), &sql.TxOptions{Isolation: sql.LevelSerializable}, func(tx *sql.Tx) error {
		var price uint64
		var stock uint32
		if e := tx.QueryRowContext(r.Context(), `SELECT price_cents,stock FROM products WHERE app_id=? AND id=? AND status='active' FOR UPDATE`, p.User.AppID, productID).Scan(&price, &stock); e != nil {
			return e
		}
		if stock < q.Quantity {
			return errors.New("stock")
		}
		total = price * uint64(q.Quantity)
		var accountID, balance uint64
		var status string
		if e := tx.QueryRowContext(r.Context(), `SELECT id,available_amount,status FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, p.User.AppID, p.User.ID).Scan(&accountID, &balance, &status); e != nil || status != "active" || balance < total {
			return errors.New("balance")
		}
		if _, e := tx.ExecContext(r.Context(), `UPDATE wallet_accounts SET available_amount=available_amount-?,version=version+1,updated_at=NOW(6) WHERE id=?`, total, accountID); e != nil {
			return e
		}
		res, e := tx.ExecContext(r.Context(), `INSERT INTO product_orders(app_id,order_no,user_id,product_id,quantity,total_cents,status,created_at,updated_at) VALUES(?,?,?,?,?,?,'paid',NOW(6),NOW(6))`, p.User.AppID, orderNo, p.User.ID, productID, q.Quantity, total)
		if e != nil {
			return e
		}
		orderID, _ := res.LastInsertId()
		tr, e := tx.ExecContext(r.Context(), `INSERT INTO wallet_transactions(app_id,transaction_no,transaction_type,reference_type,reference_id,status,amount,currency,metadata_json,created_at,updated_at) VALUES(?,?,'product_purchase','product_order',?,'completed',?,'CNY',JSON_OBJECT('product_id',?),NOW(6),NOW(6))`, p.User.AppID, "TX-"+randomHex(16), strconv.FormatInt(orderID, 10), total, productID)
		if e != nil {
			return e
		}
		txID, _ := tr.LastInsertId()
		if _, e = tx.ExecContext(r.Context(), `INSERT INTO wallet_entries(app_id,transaction_id,account_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,'debit',?,?-?,NOW(6))`, p.User.AppID, txID, accountID, total, balance, total); e != nil {
			return e
		}
		_, e = tx.ExecContext(r.Context(), `UPDATE products SET stock=stock-?,updated_at=NOW(6) WHERE id=?`, q.Quantity, productID)
		return e
	})
	if err != nil {
		httpx.Error(w, r, 409, "ORDER_FAILED", "库存不足、余额不足或钱包不可用")
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "购买成功", Data: map[string]any{"order_no": orderNo, "total_cents": total}, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) orders(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT o.order_no,p.name,o.quantity,o.total_cents,o.status,o.created_at FROM product_orders o JOIN products p ON p.id=o.product_id WHERE o.app_id=? AND o.user_id=? ORDER BY o.id DESC LIMIT 500`, p.User.AppID, p.User.ID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var no, name, status string
		var qty uint32
		var total uint64
		var created any
		if rows.Scan(&no, &name, &qty, &total, &status, &created) == nil {
			items = append(items, map[string]any{"order_no": no, "product_name": name, "quantity": qty, "total_cents": total, "status": status, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) stickerPacks(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT sp.id,sp.name,COALESCE(sp.cover_asset_id,0),sp.price_cents,EXISTS(SELECT 1 FROM user_sticker_packs usp WHERE usp.user_id=? AND usp.pack_id=sp.id) FROM sticker_packs sp WHERE sp.app_id=? AND sp.status='active' ORDER BY sp.id DESC`, p.User.ID, p.User.AppID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, cover, price uint64
		var name string
		var owned bool
		if rows.Scan(&id, &name, &cover, &price, &owned) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "cover_asset_id": cover, "price_cents": price, "owned": owned})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) acquireStickerPack(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var price uint64
	if err := h.db.QueryRowContext(r.Context(), `SELECT price_cents FROM sticker_packs WHERE app_id=? AND id=? AND status='active'`, p.User.AppID, id).Scan(&price); err != nil {
		httpx.Error(w, r, 404, "PACK_NOT_FOUND", "表情包不存在")
		return
	}
	if price > 0 {
		httpx.Error(w, r, 409, "PAYMENT_REQUIRED", "付费表情包请通过钱包订单购买")
		return
	}
	_, err := h.db.ExecContext(r.Context(), `INSERT IGNORE INTO user_sticker_packs(app_id,user_id,pack_id,acquired_at) VALUES(?,?,?,NOW(6))`, p.User.AppID, p.User.ID, id)
	if err != nil {
		fail(w, r)
		return
	}
	httpx.OK(w, r, map[string]bool{"owned": true})
}
func (h *Handler) market(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT id,owner_id,name,description,COALESCE(icon_asset_id,0),version,price_cents,download_count FROM app_market_items WHERE app_id=? AND status='published' ORDER BY id DESC LIMIT 200`, p.User.AppID)
	if err != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, owner, icon, price, downloads uint64
		var name, desc, version string
		if rows.Scan(&id, &owner, &name, &desc, &icon, &version, &price, &downloads) == nil {
			items = append(items, map[string]any{"id": id, "owner_id": owner, "name": name, "description": desc, "icon_asset_id": icon, "version": version, "price_cents": price, "download_count": downloads})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) publishMarketItem(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(w, r)
	if !ok {
		return
	}
	var q struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		IconAssetID uint64 `json:"icon_asset_id"`
		Version     string `json:"version"`
		PackageURL  string `json:"package_url"`
		PriceCents  uint64 `json:"price_cents"`
	}
	if !decode(w, r, &q) {
		return
	}
	q.Name = strings.TrimSpace(q.Name)
	q.Version = strings.TrimSpace(q.Version)
	if q.Name == "" || q.Version == "" || len([]rune(q.Name)) > 150 || len(q.PackageURL) > 1000 {
		httpx.Error(w, r, 400, "MARKET_ITEM_INVALID", "应用信息无效")
		return
	}
	res, err := h.db.ExecContext(r.Context(), `INSERT INTO app_market_items(app_id,owner_id,name,description,icon_asset_id,version,package_url,price_cents,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'pending',NOW(6),NOW(6))`, p.User.AppID, p.User.ID, q.Name, q.Description, nullID(q.IconAssetID), q.Version, q.PackageURL, q.PriceCents)
	if err != nil {
		fail(w, r)
		return
	}
	id, _ := res.LastInsertId()
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "应用已提交审核", Data: map[string]any{"id": id, "status": "pending"}, RequestID: httpx.RequestID(r.Context())})
}
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(int64(n), 10)
	}
	return hex.EncodeToString(b)
}
func nullID(v uint64) any {
	if v == 0 {
		return nil
	}
	return v
}
func fail(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, 500, "INTERNAL_ERROR", "系统暂时不可用")
}
