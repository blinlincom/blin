package wallet

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

func (h *Handler) bills(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT wt.id,wt.transaction_no,wt.transaction_type,wt.reference_type,wt.reference_id,wt.status,we.entry_type,we.amount,we.balance_after,wt.currency,wt.created_at FROM wallet_entries we JOIN wallet_transactions wt ON wt.id=we.transaction_id JOIN wallet_accounts wa ON wa.id=we.account_id WHERE wa.app_id=? AND wa.user_id=? ORDER BY we.id DESC LIMIT ?`, p.User.AppID, p.User.ID, limit)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var no, typ, refType, refID, status, entry, currency string
		var amount, balance int64
		var created time.Time
		if rows.Scan(&id, &no, &typ, &refType, &refID, &status, &entry, &amount, &balance, &currency, &created) == nil {
			items = append(items, map[string]any{"id": id, "transaction_no": no, "type": typ, "reference_type": refType, "reference_id": refID, "status": status, "entry_type": entry, "amount": FormatAmount(amount), "balance_after": FormatAmount(balance), "currency": currency, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) billDetail(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, r, 400, "INVALID_ID", "账单编号无效")
		return
	}
	var no, typ, refType, refID, status, currency string
	var amount int64
	var metadata []byte
	var created time.Time
	err = h.db.QueryRowContext(r.Context(), `SELECT DISTINCT wt.transaction_no,wt.transaction_type,wt.reference_type,wt.reference_id,wt.status,wt.amount,wt.currency,wt.metadata_json,wt.created_at FROM wallet_transactions wt JOIN wallet_entries we ON we.transaction_id=wt.id JOIN wallet_accounts wa ON wa.id=we.account_id WHERE wt.id=? AND wa.app_id=? AND wa.user_id=?`, id, p.User.AppID, p.User.ID).Scan(&no, &typ, &refType, &refID, &status, &amount, &currency, &metadata, &created)
	if err != nil {
		httpx.Error(w, r, 404, "BILL_NOT_FOUND", "账单不存在")
		return
	}
	httpx.OK(w, r, map[string]any{"id": id, "transaction_no": no, "type": typ, "reference_type": refType, "reference_id": refID, "status": status, "amount": FormatAmount(amount), "currency": currency, "metadata": string(metadata), "created_at": created})
}
func (h *Handler) transferDetail(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var v Transfer
	err := h.db.QueryRowContext(r.Context(), `SELECT id,order_no,sender_id,recipient_id,amount,status,expires_at,created_at FROM wallet_transfers WHERE app_id=? AND order_no=? AND (sender_id=? OR recipient_id=?)`, p.User.AppID, chi.URLParam(r, "orderNo"), p.User.ID, p.User.ID).Scan(&v.ID, &v.OrderNo, &v.SenderID, &v.RecipientID, &v.Amount, &v.Status, &v.ExpiresAt, &v.CreatedAt)
	if err != nil {
		writeWalletError(w, r, ErrOrderNotFound)
		return
	}
	httpx.OK(w, r, transferResponse(v))
}
func (h *Handler) redPacketDetail(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var v RedPacket
	err := h.db.QueryRowContext(r.Context(), `SELECT rp.id,rp.order_no,rp.sender_id,rp.channel_id,rp.channel_type,rp.packet_type,rp.total_amount,rp.total_count,rp.remaining_amount,rp.remaining_count,rp.greeting,rp.status,rp.expires_at,rp.created_at FROM wallet_red_packets rp WHERE rp.app_id=? AND rp.order_no=? AND (rp.sender_id=? OR EXISTS(SELECT 1 FROM wallet_red_packet_claims c WHERE c.red_packet_id=rp.id AND c.user_id=?))`, p.User.AppID, chi.URLParam(r, "orderNo"), p.User.ID, p.User.ID).Scan(&v.ID, &v.OrderNo, &v.SenderID, &v.ChannelID, &v.ChannelType, &v.PacketType, &v.TotalAmount, &v.TotalCount, &v.RemainingAmount, &v.RemainingCount, &v.Greeting, &v.Status, &v.ExpiresAt, &v.CreatedAt)
	if err != nil {
		writeWalletError(w, r, ErrOrderNotFound)
		return
	}
	rows, _ := h.db.QueryContext(r.Context(), `SELECT c.user_id,u.nickname,c.amount,c.created_at FROM wallet_red_packet_claims c JOIN users u ON u.id=c.user_id WHERE c.red_packet_id=? ORDER BY c.id`, v.ID)
	claims := []map[string]any{}
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var uid uint64
			var name string
			var amount int64
			var created time.Time
			if rows.Scan(&uid, &name, &amount, &created) == nil {
				claims = append(claims, map[string]any{"user_id": uid, "nickname": name, "amount": FormatAmount(amount), "created_at": created})
			}
		}
	}
	result := redPacketResponse(v)
	result["claims"] = claims
	httpx.OK(w, r, result)
}
func (h *Handler) withdrawals(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT order_no,amount,method,account_masked,status,review_reason,created_at FROM wallet_withdrawals WHERE app_id=? AND user_id=? ORDER BY id DESC LIMIT 200`, p.User.AppID, p.User.ID)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var no, method, masked, status, reason string
		var amount int64
		var created time.Time
		if rows.Scan(&no, &amount, &method, &masked, &status, &reason, &created) == nil {
			items = append(items, map[string]any{"order_no": no, "amount": FormatAmount(amount), "method": method, "account_masked": masked, "status": status, "review_reason": reason, "created_at": created})
		}
	}
	httpx.OK(w, r, items)
}
func (h *Handler) createWithdrawal(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var q struct {
		Amount          string `json:"amount"`
		Method          string `json:"method"`
		Account         string `json:"account"`
		PaymentPassword string `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &q) {
		return
	}
	amount, err := ParseAmount(q.Amount)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	q.Method = strings.TrimSpace(q.Method)
	q.Account = strings.TrimSpace(q.Account)
	if (q.Method != "bank" && q.Method != "alipay" && q.Method != "wechat") || len(q.Account) < 4 || len(q.Account) > 200 {
		httpx.Error(w, r, 400, "WITHDRAWAL_INVALID", "提现账户无效")
		return
	}
	if err = h.service.VerifyPaymentPassword(r.Context(), p.User.AppID, p.User.ID, q.PaymentPassword); err != nil {
		writeWalletError(w, r, err)
		return
	}
	encrypted, err := encryptField(h.fieldKey, q.Account)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	orderNo := "WD-" + randomToken()
	err = h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var accountID uint64
		var available, frozen int64
		var status string
		if e := tx.QueryRowContext(r.Context(), `SELECT id,available_amount,frozen_amount,status FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, p.User.AppID, p.User.ID).Scan(&accountID, &available, &frozen, &status); e != nil {
			return e
		}
		if status != "active" {
			return ErrWalletLocked
		}
		if available < amount {
			return ErrInsufficientBalance
		}
		available -= amount
		frozen += amount
		if _, e := tx.ExecContext(r.Context(), `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=NOW(6) WHERE id=?`, available, frozen, accountID); e != nil {
			return e
		}
		res, e := tx.ExecContext(r.Context(), `INSERT INTO wallet_withdrawals(app_id,order_no,user_id,amount,method,account_masked,account_encrypted,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'pending',NOW(6),NOW(6))`, p.User.AppID, orderNo, p.User.ID, amount, q.Method, mask(q.Account), encrypted)
		if e != nil {
			return e
		}
		wid, _ := res.LastInsertId()
		tr, e := tx.ExecContext(r.Context(), `INSERT INTO wallet_transactions(app_id,transaction_no,transaction_type,reference_type,reference_id,status,amount,currency,metadata_json,created_at,updated_at) VALUES(?,?,'withdrawal_freeze','withdrawal',?,'pending',?,'CNY',JSON_OBJECT('method',?),NOW(6),NOW(6))`, p.User.AppID, "TX-"+randomToken(), strconv.FormatInt(wid, 10), amount, q.Method)
		if e != nil {
			return e
		}
		tid, _ := tr.LastInsertId()
		_, e = tx.ExecContext(r.Context(), `INSERT INTO wallet_entries(app_id,transaction_id,account_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,'available_debit',?,?,NOW(6)),(?,?,?,'frozen_credit',?,?,NOW(6))`, p.User.AppID, tid, accountID, amount, available, p.User.AppID, tid, accountID, amount, frozen)
		return e
	})
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "提现申请已提交", Data: map[string]any{"order_no": orderNo, "status": "pending"}, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) collectCode(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	token, err := h.ensureCollectCode(r.Context(), p.User.AppID, p.User.ID, false)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"type": "collect", "payload": "bim://wallet/collect/" + token})
}
func (h *Handler) rotateCollectCode(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	token, err := h.ensureCollectCode(r.Context(), p.User.AppID, p.User.ID, true)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"type": "collect", "payload": "bim://wallet/collect/" + token})
}
func (h *Handler) ensureCollectCode(ctx context.Context, appID, userID uint64, rotate bool) (string, error) {
	var token string
	if !rotate {
		err := h.db.QueryRowContext(ctx, `SELECT public_token FROM wallet_collect_codes WHERE app_id=? AND user_id=? AND status='active'`, appID, userID).Scan(&token)
		if err == nil {
			return token, nil
		}
	}
	token = randomToken()
	_, err := h.db.ExecContext(ctx, `INSERT INTO wallet_collect_codes(app_id,user_id,public_token,status,created_at,updated_at) VALUES(?,?,?,'active',NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE public_token=VALUES(public_token),status='active',updated_at=NOW(6)`, appID, userID, token)
	return token, err
}
func (h *Handler) payCode(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var q struct {
		PaymentPassword string `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &q) {
		return
	}
	if err := h.service.VerifyPaymentPassword(r.Context(), p.User.AppID, p.User.ID, q.PaymentPassword); err != nil {
		writeWalletError(w, r, err)
		return
	}
	raw := randomToken() + randomToken()
	hash := sha256.Sum256([]byte(raw))
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(r.Context(), `UPDATE wallet_pay_codes SET status='expired' WHERE app_id=? AND user_id=? AND status='active'`, p.User.AppID, p.User.ID); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO wallet_pay_codes(app_id,user_id,token_hash,status,expires_at,created_at) VALUES(?,?,?,'active',DATE_ADD(NOW(6),INTERVAL 60 SECOND),NOW(6))`, p.User.AppID, p.User.ID, hex.EncodeToString(hash[:]))
		return err
	})
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"type": "pay", "payload": "bim://wallet/pay/" + raw, "expires_in": 60})
}
func (h *Handler) scanQR(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var q struct {
		Payload string `json:"payload"`
		Amount  string `json:"amount"`
	}
	if !decodeWalletBody(w, r, &q) {
		return
	}
	kind, token := parsePayload(q.Payload)
	if kind == "collect" {
		var uid uint64
		var name string
		if err := h.db.QueryRowContext(r.Context(), `SELECT c.user_id,u.nickname FROM wallet_collect_codes c JOIN users u ON u.id=c.user_id WHERE c.app_id=? AND c.public_token=? AND c.status='active'`, p.User.AppID, token).Scan(&uid, &name); err != nil || uid == p.User.ID {
			httpx.Error(w, r, 404, "QR_INVALID", "二维码无效")
			return
		}
		httpx.OK(w, r, map[string]any{"type": "collect", "payee_id": uid, "payee_nickname": name})
		return
	}
	if kind == "pay" {
		var merchant int
		_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM merchant_profiles WHERE app_id=? AND user_id=? AND status='approved'`, p.User.AppID, p.User.ID).Scan(&merchant)
		if merchant == 0 {
			httpx.Error(w, r, 403, "MERCHANT_REQUIRED", "仅认证商户可扫描付款码")
			return
		}
		hash := sha256.Sum256([]byte(token))
		var payer uint64
		var codeID uint64
		if err := h.db.QueryRowContext(r.Context(), `SELECT id,user_id FROM wallet_pay_codes WHERE app_id=? AND token_hash=? AND status='active' AND expires_at>NOW(6)`, p.User.AppID, hex.EncodeToString(hash[:])).Scan(&codeID, &payer); err != nil {
			httpx.Error(w, r, 404, "QR_INVALID", "付款码已失效")
			return
		}
		amount, err := ParseAmount(q.Amount)
		if err != nil {
			writeWalletError(w, r, err)
			return
		}
		orderNo := "QR-" + randomToken()
		err = h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
			result, err := tx.ExecContext(r.Context(), `UPDATE wallet_pay_codes SET status='used',used_at=NOW(6) WHERE id=? AND status='active' AND expires_at>NOW(6)`, codeID)
			if err != nil {
				return err
			}
			rows, _ := result.RowsAffected()
			if rows != 1 {
				return ErrOrderState
			}
			_, err = tx.ExecContext(r.Context(), `INSERT INTO wallet_qr_orders(app_id,order_no,payer_id,payee_id,merchant_id,amount,status,expires_at,created_at,updated_at) VALUES(?,?,?,?,?,?,'pending',DATE_ADD(NOW(6),INTERVAL 5 MINUTE),NOW(6),NOW(6))`, p.User.AppID, orderNo, payer, p.User.ID, p.User.ID, amount)
			return err
		})
		if err != nil {
			writeWalletError(w, r, err)
			return
		}
		httpx.OK(w, r, map[string]any{"type": "pay", "order_no": orderNo, "status": "pending_owner_confirmation"})
		return
	}
	httpx.Error(w, r, 400, "QR_INVALID", "二维码无法识别")
}
func (h *Handler) payQR(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var q struct {
		Payload         string `json:"payload"`
		Amount          string `json:"amount"`
		PaymentPassword string `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &q) {
		return
	}
	kind, token := parsePayload(q.Payload)
	if kind != "collect" {
		httpx.Error(w, r, 400, "QR_INVALID", "请扫描收款码")
		return
	}
	var payee uint64
	if err := h.db.QueryRowContext(r.Context(), `SELECT user_id FROM wallet_collect_codes WHERE app_id=? AND public_token=? AND status='active'`, p.User.AppID, token).Scan(&payee); err != nil || payee == p.User.ID {
		httpx.Error(w, r, 404, "QR_INVALID", "收款码无效")
		return
	}
	amount, err := ParseAmount(q.Amount)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	if err = h.service.VerifyPaymentPassword(r.Context(), p.User.AppID, p.User.ID, q.PaymentPassword); err != nil {
		writeWalletError(w, r, err)
		return
	}
	orderNo := "QR-" + randomToken()
	if err = h.settleQR(r.Context(), p.User.AppID, orderNo, p.User.ID, payee, amount); err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"order_no": orderNo, "status": "completed"})
}
func (h *Handler) confirmQROrder(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var q struct {
		PaymentPassword string `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &q) {
		return
	}
	if err := h.service.VerifyPaymentPassword(r.Context(), p.User.AppID, p.User.ID, q.PaymentPassword); err != nil {
		writeWalletError(w, r, err)
		return
	}
	var payee uint64
	var amount int64
	orderNo := chi.URLParam(r, "orderNo")
	if err := h.db.QueryRowContext(r.Context(), `SELECT payee_id,amount FROM wallet_qr_orders WHERE app_id=? AND order_no=? AND payer_id=? AND status='pending' AND expires_at>NOW(6)`, p.User.AppID, orderNo, p.User.ID).Scan(&payee, &amount); err != nil {
		writeWalletError(w, r, ErrOrderState)
		return
	}
	if err := h.settleQR(r.Context(), p.User.AppID, orderNo, p.User.ID, payee, amount); err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"order_no": orderNo, "status": "completed"})
}
func (h *Handler) settleQR(ctx context.Context, appID uint64, orderNo string, payerID, payeeID uint64, amount int64) error {
	return h.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable}, func(tx *sql.Tx) error {
		ids := []uint64{payerID, payeeID}
		if ids[0] > ids[1] {
			ids[0], ids[1] = ids[1], ids[0]
		}
		type acc struct {
			id        uint64
			available int64
			status    string
		}
		values := map[uint64]acc{}
		for _, uid := range ids {
			var a acc
			if e := tx.QueryRowContext(ctx, `SELECT id,available_amount,status FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, appID, uid).Scan(&a.id, &a.available, &a.status); e != nil {
				return e
			}
			values[uid] = a
		}
		payer, payee := values[payerID], values[payeeID]
		if payer.status != "active" || payee.status != "active" {
			return ErrWalletLocked
		}
		if payer.available < amount {
			return ErrInsufficientBalance
		}
		payer.available -= amount
		payee.available += amount
		if _, e := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,version=version+1,updated_at=NOW(6) WHERE id=?`, payer.available, payer.id); e != nil {
			return e
		}
		if _, e := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,version=version+1,updated_at=NOW(6) WHERE id=?`, payee.available, payee.id); e != nil {
			return e
		}
		res, e := tx.ExecContext(ctx, `INSERT INTO wallet_transactions(app_id,transaction_no,transaction_type,reference_type,reference_id,status,amount,currency,metadata_json,created_at,updated_at) VALUES(?,?,'qr_payment','qr_order',?,'completed',?,'CNY',JSON_OBJECT('payer_id',?,'payee_id',?),NOW(6),NOW(6))`, appID, "TX-"+randomToken(), orderNo, amount, payerID, payeeID)
		if e != nil {
			return e
		}
		tid, _ := res.LastInsertId()
		if _, e = tx.ExecContext(ctx, `INSERT INTO wallet_entries(app_id,transaction_id,account_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,'debit',?,?,NOW(6)),(?,?,?,'credit',?,?,NOW(6))`, appID, tid, payer.id, amount, payer.available, appID, tid, payee.id, amount, payee.available); e != nil {
			return e
		}
		_, _ = tx.ExecContext(ctx, `UPDATE wallet_qr_orders SET status='completed',updated_at=NOW(6) WHERE app_id=? AND order_no=? AND status='pending'`, appID, orderNo)
		return nil
	})
}
func parsePayload(value string) (string, string) {
	value = strings.TrimSpace(value)
	for _, kind := range []string{"collect", "pay"} {
		prefix := "bim://wallet/" + kind + "/"
		if strings.HasPrefix(value, prefix) {
			return kind, strings.TrimPrefix(value, prefix)
		}
	}
	return "", ""
}
func randomToken() string {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	return hex.EncodeToString(b)
}
func mask(value string) string {
	r := []rune(value)
	if len(r) <= 4 {
		return "****"
	}
	return string(r[:2]) + strings.Repeat("*", len(r)-4) + string(r[len(r)-2:])
}
func encryptField(secret, value string) (string, error) {
	if strings.TrimSpace(secret) == "" {
		return "", errors.New("field encryption key missing")
	}
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	sealed := gcm.Seal(nonce, nonce, []byte(value), nil)
	return base64.RawURLEncoding.EncodeToString(sealed), nil
}
