package adminportal

import (
	"bim/server/internal/modules/adminauth"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
)

type Handler struct{ db *database.DB }

func NewHandler(db *database.DB) *Handler { return &Handler{db: db} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/content/posts", h.posts)
	r.Put("/content/posts/{id}/review", h.reviewPost)
	r.Get("/content/reports", h.reports)
	r.Put("/content/reports/{id}", h.resolveReport)
	r.Get("/products", h.products)
	r.Post("/products", h.saveProduct)
	r.Put("/products/{id}", h.saveProduct)
	r.Get("/sticker-packs", h.stickerPacks)
	r.Post("/sticker-packs", h.saveStickerPack)
	r.Put("/sticker-packs/{id}", h.saveStickerPack)
	r.Get("/market", h.market)
	r.Put("/market/{id}/review", h.reviewMarket)
	r.Get("/merchants", h.merchants)
	r.Put("/merchants/{id}/review", h.reviewMerchant)
	r.Get("/withdrawals", h.withdrawals)
	r.Put("/withdrawals/{id}/review", h.reviewWithdrawal)
	return r
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func id(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	v, e := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if e != nil || v == 0 {
		httpx.Error(w, r, 400, "INVALID_ID", "编号无效")
		return 0, false
	}
	return v, true
}
func (h *Handler) posts(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT p.id,p.title,u.nickname,s.name,p.status,p.review_reason,p.created_at FROM content_posts p JOIN users u ON u.id=p.user_id JOIN content_sections s ON s.id=p.section_id WHERE p.app_id=1 AND p.deleted_at IS NULL ORDER BY p.id DESC LIMIT 500`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var title, user, section, status, reason string
		var created any
		if rows.Scan(&id, &title, &user, &section, &status, &reason, &created) == nil {
			items = append(items, map[string]any{"id": id, "title": title, "author": user, "section": section, "status": status, "review_reason": reason, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) reviewPost(w http.ResponseWriter, r *http.Request) { h.review(w, r, "content_posts") }
func (h *Handler) market(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT id,name,version,status,created_at FROM app_market_items WHERE app_id=1 ORDER BY id DESC LIMIT 500`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var name, version, status string
		var created any
		if rows.Scan(&id, &name, &version, &status, &created) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "version": version, "status": status, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) reviewMarket(w http.ResponseWriter, r *http.Request) {
	h.review(w, r, "app_market_items")
}
func (h *Handler) review(w http.ResponseWriter, r *http.Request, table string) {
	resource, ok := id(w, r)
	if !ok {
		return
	}
	var q struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.Status != "published" && q.Status != "rejected" {
		httpx.Error(w, r, 400, "STATUS_INVALID", "审核状态无效")
		return
	}
	if q.Status == "rejected" && len([]rune(strings.TrimSpace(q.Reason))) < 2 {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "拒绝时必须填写原因")
		return
	}
	column := "review_reason"
	if table == "app_market_items" {
		column = "description"
	}
	res, e := h.db.ExecContext(r.Context(), `UPDATE `+table+` SET status=?,`+column+`=IF(?='rejected',?,`+column+`),updated_at=NOW(6) WHERE app_id=1 AND id=?`, q.Status, q.Status, strings.TrimSpace(q.Reason), resource)
	if e != nil {
		fail(w, r)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		httpx.Error(w, r, 404, "RESOURCE_NOT_FOUND", "记录不存在")
		return
	}
	h.audit(r, "review."+table, resource, q.Reason)
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) reports(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT cr.id,u.nickname,cr.target_type,cr.target_id,cr.reason,cr.status,cr.created_at FROM content_reports cr JOIN users u ON u.id=cr.user_id WHERE cr.app_id=1 ORDER BY cr.id DESC LIMIT 500`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, target uint64
		var user, typ, reason, status string
		var created any
		if rows.Scan(&id, &user, &typ, &target, &reason, &status, &created) == nil {
			items = append(items, map[string]any{"id": id, "reporter": user, "target_type": typ, "target_id": target, "reason": reason, "status": status, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) resolveReport(w http.ResponseWriter, r *http.Request) {
	resource, ok := id(w, r)
	if !ok {
		return
	}
	var q struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.Status != "resolved" && q.Status != "rejected" {
		httpx.Error(w, r, 400, "STATUS_INVALID", "处理状态无效")
		return
	}
	_, e := h.db.ExecContext(r.Context(), `UPDATE content_reports SET status=?,updated_at=NOW(6) WHERE app_id=1 AND id=?`, q.Status, resource)
	if e != nil {
		fail(w, r)
		return
	}
	h.audit(r, "report."+q.Status, resource, q.Reason)
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) products(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT id,name,description,COALESCE(cover_asset_id,0),price_cents,stock,status FROM products WHERE app_id=1 ORDER BY id DESC`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, asset, price uint64
		var stock uint32
		var name, desc, status string
		if rows.Scan(&id, &name, &desc, &asset, &price, &stock, &status) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "description": desc, "cover_asset_id": asset, "price_cents": price, "stock": stock, "status": status})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) saveProduct(w http.ResponseWriter, r *http.Request) {
	var q struct {
		Name         string `json:"name"`
		Description  string `json:"description"`
		CoverAssetID uint64 `json:"cover_asset_id"`
		PriceCents   uint64 `json:"price_cents"`
		Stock        uint32 `json:"stock"`
		Status       string `json:"status"`
	}
	if !decode(w, r, &q) {
		return
	}
	if strings.TrimSpace(q.Name) == "" || q.Status != "active" && q.Status != "disabled" {
		httpx.Error(w, r, 400, "PRODUCT_INVALID", "商品参数无效")
		return
	}
	resource, _ := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	var e error
	if resource == 0 {
		res, err := h.db.ExecContext(r.Context(), `INSERT INTO products(app_id,name,description,cover_asset_id,price_cents,stock,status,created_at,updated_at) VALUES(1,?,?,?,?,?,?,NOW(6),NOW(6))`, q.Name, q.Description, nullID(q.CoverAssetID), q.PriceCents, q.Stock, q.Status)
		e = err
		if err == nil {
			v, _ := res.LastInsertId()
			resource = uint64(v)
		}
	} else {
		_, e = h.db.ExecContext(r.Context(), `UPDATE products SET name=?,description=?,cover_asset_id=?,price_cents=?,stock=?,status=?,updated_at=NOW(6) WHERE app_id=1 AND id=?`, q.Name, q.Description, nullID(q.CoverAssetID), q.PriceCents, q.Stock, q.Status, resource)
	}
	if e != nil {
		fail(w, r)
		return
	}
	h.audit(r, "product.save", resource, "")
	httpx.OK(w, r, map[string]any{"id": resource})
}
func (h *Handler) stickerPacks(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT id,name,COALESCE(cover_asset_id,0),price_cents,status FROM sticker_packs WHERE app_id=1 ORDER BY id DESC`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, cover, price uint64
		var name, status string
		if rows.Scan(&id, &name, &cover, &price, &status) == nil {
			items = append(items, map[string]any{"id": id, "name": name, "cover_asset_id": cover, "price_cents": price, "status": status})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) saveStickerPack(w http.ResponseWriter, r *http.Request) {
	var q struct {
		Name         string   `json:"name"`
		CoverAssetID uint64   `json:"cover_asset_id"`
		PriceCents   uint64   `json:"price_cents"`
		Status       string   `json:"status"`
		AssetIDs     []uint64 `json:"asset_ids"`
	}
	if !decode(w, r, &q) {
		return
	}
	if strings.TrimSpace(q.Name) == "" || len(q.AssetIDs) > 200 {
		httpx.Error(w, r, 400, "PACK_INVALID", "表情包参数无效")
		return
	}
	resource, _ := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	e := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		if resource == 0 {
			res, err := tx.ExecContext(r.Context(), `INSERT INTO sticker_packs(app_id,name,cover_asset_id,price_cents,status,created_at,updated_at) VALUES(1,?,?,?, ?,NOW(6),NOW(6))`, q.Name, nullID(q.CoverAssetID), q.PriceCents, q.Status)
			if err != nil {
				return err
			}
			v, _ := res.LastInsertId()
			resource = uint64(v)
		} else {
			if _, err := tx.ExecContext(r.Context(), `UPDATE sticker_packs SET name=?,cover_asset_id=?,price_cents=?,status=?,updated_at=NOW(6) WHERE app_id=1 AND id=?`, q.Name, nullID(q.CoverAssetID), q.PriceCents, q.Status, resource); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `DELETE FROM stickers WHERE pack_id=?`, resource); err != nil {
				return err
			}
		}
		for i, asset := range q.AssetIDs {
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO stickers(pack_id,asset_id,sort_order,created_at) VALUES(?,?,?,NOW(6))`, resource, asset, i); err != nil {
				return err
			}
		}
		return nil
	})
	if e != nil {
		fail(w, r)
		return
	}
	h.audit(r, "sticker_pack.save", resource, "")
	httpx.OK(w, r, map[string]any{"id": resource})
}
func (h *Handler) merchants(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT mp.user_id,u.username,u.nickname,mp.status,mp.review_reason,mp.created_at FROM merchant_profiles mp JOIN users u ON u.id=mp.user_id WHERE mp.app_id=1 ORDER BY mp.updated_at DESC`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var uid uint64
		var username, nickname, status, reason string
		var created any
		if rows.Scan(&uid, &username, &nickname, &status, &reason, &created) == nil {
			items = append(items, map[string]any{"user_id": uid, "username": username, "nickname": nickname, "status": status, "review_reason": reason, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) reviewMerchant(w http.ResponseWriter, r *http.Request) {
	uid, ok := id(w, r)
	if !ok {
		return
	}
	var q struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.Status != "approved" && q.Status != "rejected" && q.Status != "disabled" {
		httpx.Error(w, r, 400, "STATUS_INVALID", "商户状态无效")
		return
	}
	_, e := h.db.ExecContext(r.Context(), `INSERT INTO merchant_profiles(app_id,user_id,status,review_reason,created_at,updated_at) VALUES(1,?,?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE status=VALUES(status),review_reason=VALUES(review_reason),updated_at=NOW(6)`, uid, q.Status, q.Reason)
	if e != nil {
		fail(w, r)
		return
	}
	h.audit(r, "merchant."+q.Status, uid, q.Reason)
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) withdrawals(w http.ResponseWriter, r *http.Request) {
	rows, e := h.db.QueryContext(r.Context(), `SELECT wd.id,wd.order_no,u.nickname,wd.amount,wd.method,wd.account_masked,wd.status,wd.review_reason,wd.created_at FROM wallet_withdrawals wd JOIN users u ON u.id=wd.user_id WHERE wd.app_id=1 ORDER BY wd.id DESC LIMIT 500`)
	if e != nil {
		fail(w, r)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var no, user, method, masked, status, reason string
		var amount int64
		var created any
		if rows.Scan(&id, &no, &user, &amount, &method, &masked, &status, &reason, &created) == nil {
			items = append(items, map[string]any{"id": id, "order_no": no, "user": user, "amount_cents": amount, "method": method, "account_masked": masked, "status": status, "review_reason": reason, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) reviewWithdrawal(w http.ResponseWriter, r *http.Request) {
	resource, ok := id(w, r)
	if !ok {
		return
	}
	var q struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.Status != "completed" && q.Status != "rejected" {
		httpx.Error(w, r, 400, "STATUS_INVALID", "提现状态无效")
		return
	}
	e := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var appID, userID, accountID uint64
		var amount, frozen, available int64
		var status string
		if err := tx.QueryRowContext(r.Context(), `SELECT wd.app_id,wd.user_id,wd.amount,wd.status,wa.id,wa.available_amount,wa.frozen_amount FROM wallet_withdrawals wd JOIN wallet_accounts wa ON wa.app_id=wd.app_id AND wa.user_id=wd.user_id AND wa.currency='CNY' WHERE wd.id=? FOR UPDATE`, resource).Scan(&appID, &userID, &amount, &status, &accountID, &available, &frozen); err != nil {
			return err
		}
		if status != "pending" || frozen < amount {
			return sql.ErrNoRows
		}
		frozen -= amount
		if q.Status == "rejected" {
			available += amount
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=NOW(6) WHERE id=?`, available, frozen, accountID); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE wallet_withdrawals SET status=?,review_reason=?,updated_at=NOW(6) WHERE id=?`, q.Status, q.Reason, resource)
		return err
	})
	if e != nil {
		httpx.Error(w, r, 409, "WITHDRAWAL_STATE_INVALID", "提现状态不允许此操作")
		return
	}
	h.audit(r, "withdrawal."+q.Status, resource, q.Reason)
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) audit(r *http.Request, action string, resource uint64, reason string) {
	p, _ := adminauth.PrincipalFromContext(r.Context())
	_, _ = h.db.ExecContext(r.Context(), `INSERT INTO admin_audit_logs(admin_id,action,resource_type,resource_id,reason,before_json,after_json,request_id,ip,user_agent,created_at) VALUES(?,?,'portal',?,?,'{}','{}',?,?,?,NOW(6))`, p.Admin.ID, action, strconv.FormatUint(resource, 10), reason, httpx.RequestID(r.Context()), r.RemoteAddr, r.UserAgent())
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
