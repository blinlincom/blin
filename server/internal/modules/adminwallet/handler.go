package adminwallet

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/modules/adminauth"
	"bim/server/internal/modules/wallet"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct{ db *database.DB }

func NewHandler(db *database.DB) *Handler { return &Handler{db: db} }
func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.With(adminauth.Require("wallet:read")).Get("/accounts", h.accounts)
	router.With(adminauth.Require("wallet:control")).Post("/accounts/{userID}/control", h.control)
	return router
}

func (h *Handler) accounts(w http.ResponseWriter, r *http.Request) {
	appID, _ := strconv.ParseUint(r.URL.Query().Get("app_id"), 10, 64)
	if appID == 0 {
		appID = 1
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT wa.user_id,u.username,u.nickname,wa.available_amount,wa.frozen_amount,wa.currency,wa.status,wa.lock_reason,wa.updated_at FROM wallet_accounts wa JOIN users u ON u.id=wa.user_id WHERE wa.app_id=? ORDER BY wa.updated_at DESC,wa.user_id DESC LIMIT ?`, appID, limit)
	if err != nil {
		httpx.Error(w, r, http.StatusInternalServerError, "ADMIN_WALLET_QUERY_FAILED", "钱包查询失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var userID uint64
		var username, nickname, currency, status, reason string
		var available, frozen int64
		var updated time.Time
		if err := rows.Scan(&userID, &username, &nickname, &available, &frozen, &currency, &status, &reason, &updated); err != nil {
			httpx.Error(w, r, http.StatusInternalServerError, "ADMIN_WALLET_QUERY_FAILED", "钱包查询失败")
			return
		}
		items = append(items, map[string]any{"user_id": userID, "username": username, "nickname": nickname, "available": wallet.FormatAmount(available), "frozen": wallet.FormatAmount(frozen), "currency": currency, "status": status, "lock_reason": reason, "updated_at": updated})
	}
	httpx.OK(w, r, items)
}

func (h *Handler) control(w http.ResponseWriter, r *http.Request) {
	principal, ok := adminauth.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "ADMIN_UNAUTHORIZED", "请先登录")
		return
	}
	userID, err := strconv.ParseUint(chi.URLParam(r, "userID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "用户编号无效")
		return
	}
	var request struct {
		AppID  uint64 `json:"app_id"`
		Action string `json:"action"`
		Amount string `json:"amount"`
		Reason string `json:"reason"`
	}
	if !decode(w, r, &request) {
		return
	}
	if request.AppID == 0 {
		request.AppID = 1
	}
	request.Action, request.Reason = strings.TrimSpace(request.Action), strings.TrimSpace(request.Reason)
	if len([]rune(request.Reason)) < 2 || len([]rune(request.Reason)) > 500 {
		httpx.Error(w, r, http.StatusBadRequest, "REASON_REQUIRED", "必须填写操作原因")
		return
	}
	amount := int64(0)
	if request.Action == "freeze" || request.Action == "unfreeze" {
		amount, err = wallet.ParseAmount(request.Amount)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest, "INVALID_AMOUNT", "金额格式无效")
			return
		}
	}
	if err := h.apply(r, principal.Admin.ID, request.AppID, userID, request.Action, amount, request.Reason); err != nil {
		switch {
		case errors.Is(err, wallet.ErrInsufficientBalance):
			httpx.Error(w, r, http.StatusConflict, "INSUFFICIENT_BALANCE", "可用余额不足")
		case errors.Is(err, wallet.ErrOrderState):
			httpx.Error(w, r, http.StatusConflict, "BALANCE_STATE_INVALID", "冻结余额不足")
		default:
			httpx.Error(w, r, http.StatusBadRequest, "ADMIN_WALLET_CONTROL_FAILED", err.Error())
		}
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}

func (h *Handler) apply(r *http.Request, adminID, appID, userID uint64, action string, amount int64, reason string) error {
	return h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var accountID uint64
		var available, frozen int64
		var status, oldReason string
		err := tx.QueryRowContext(r.Context(), `SELECT id,available_amount,frozen_amount,status,lock_reason FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, appID, userID).Scan(&accountID, &available, &frozen, &status, &oldReason)
		if errors.Is(err, sql.ErrNoRows) {
			return errors.New("钱包不存在")
		}
		if err != nil {
			return err
		}
		before := map[string]any{"available": available, "frozen": frozen, "status": status, "reason": oldReason}
		switch action {
		case "lock":
			status = "locked"
			oldReason = reason
		case "unlock":
			status = "active"
			oldReason = ""
		case "freeze":
			if available < amount {
				return wallet.ErrInsufficientBalance
			}
			available -= amount
			frozen += amount
		case "unfreeze":
			if frozen < amount {
				return wallet.ErrOrderState
			}
			frozen -= amount
			available += amount
		case "unlock_payment_password":
			if _, err := tx.ExecContext(r.Context(), `UPDATE wallet_credentials SET failed_attempts=0,locked_until=NULL,updated_at=NOW(6) WHERE app_id=? AND user_id=?`, appID, userID); err != nil {
				return err
			}
		default:
			return errors.New("不支持的操作")
		}
		if action == "freeze" || action == "unfreeze" {
			transactionNo := "ADMIN-" + httpx.RequestID(r.Context()) + "-" + action
			result, err := tx.ExecContext(r.Context(), `INSERT INTO wallet_transactions(app_id,transaction_no,transaction_type,reference_type,reference_id,status,amount,currency,metadata_json,created_at,updated_at) VALUES(?,?,?,'admin_control',?,'completed',?,'CNY',JSON_OBJECT('admin_id',?,'reason',?),NOW(6),NOW(6))`, appID, transactionNo, "admin_"+action, strconv.FormatUint(userID, 10), amount, adminID, reason)
			if err != nil {
				return err
			}
			transactionID, err := result.LastInsertId()
			if err != nil {
				return err
			}
			firstType, secondType := "available_debit", "frozen_credit"
			firstBalance, secondBalance := available, frozen
			if action == "unfreeze" {
				firstType, secondType = "frozen_debit", "available_credit"
				firstBalance, secondBalance = frozen, available
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO wallet_entries(app_id,transaction_id,account_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,?,?,?,NOW(6)),(?,?,?,?,?,?,NOW(6))`, appID, transactionID, accountID, firstType, amount, firstBalance, appID, transactionID, accountID, secondType, amount, secondBalance); err != nil {
				return err
			}
		}
		if action != "unlock_payment_password" {
			if _, err := tx.ExecContext(r.Context(), `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,status=?,lock_reason=?,version=version+1,updated_at=NOW(6) WHERE id=?`, available, frozen, status, oldReason, accountID); err != nil {
				return err
			}
		}
		after := map[string]any{"available": available, "frozen": frozen, "status": status, "reason": oldReason}
		beforeJSON, _ := json.Marshal(before)
		afterJSON, _ := json.Marshal(after)
		_, err = tx.ExecContext(r.Context(), `INSERT INTO admin_audit_logs(admin_id,action,resource_type,resource_id,reason,before_json,after_json,request_id,ip,user_agent,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,NOW(6))`, adminID, "wallet."+action, "wallet_account", strconv.FormatUint(userID, 10), reason, json.RawMessage(beforeJSON), json.RawMessage(afterJSON), httpx.RequestID(r.Context()), r.RemoteAddr, r.UserAgent())
		return err
	})
}
func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
