package wallet

import (
	"bim/server/internal/platform/database"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	service  *Service
	db       *database.DB
	fieldKey string
}

func NewHandler(service *Service, db *database.DB, fieldKey ...string) *Handler {
	h := &Handler{service: service, db: db}
	if len(fieldKey) > 0 {
		h.fieldKey = fieldKey[0]
	}
	return h
}

func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Get("/balance", h.balance)
	router.Put("/payment-password", h.setPassword)
	router.Post("/transfers", h.createTransfer)
	router.Post("/transfers/{orderNo}/accept", h.acceptTransfer)
	router.Post("/red-packets", h.createRedPacket)
	router.Post("/red-packets/{orderNo}/claim", h.claimRedPacket)
	router.Get("/bills", h.bills)
	router.Get("/bills/{id}", h.billDetail)
	router.Get("/transfers/{orderNo}", h.transferDetail)
	router.Get("/red-packets/{orderNo}", h.redPacketDetail)
	router.Get("/withdrawals", h.withdrawals)
	router.Post("/withdrawals", h.createWithdrawal)
	router.Get("/collect-code", h.collectCode)
	router.Post("/collect-code/rotate", h.rotateCollectCode)
	router.Post("/pay-code", h.payCode)
	router.Post("/qr/scan", h.scanQR)
	router.Post("/qr/pay", h.payQR)
	router.Post("/qr/orders/{orderNo}/confirm", h.confirmQROrder)
	return router
}

func (h *Handler) createRedPacket(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var request struct {
		ChannelID        string  `json:"channel_id"`
		ChannelType      uint8   `json:"channel_type"`
		PacketType       string  `json:"packet_type"`
		DesignatedUserID *uint64 `json:"designated_user_id"`
		Amount           string  `json:"amount"`
		Count            uint32  `json:"count"`
		Greeting         string  `json:"greeting"`
		PaymentPassword  string  `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &request) {
		return
	}
	packet, err := h.service.CreateRedPacket(r.Context(), p.User.AppID, p.User.ID, request.ChannelID, request.ChannelType, request.PacketType, request.DesignatedUserID, request.Amount, request.Count, request.Greeting, request.PaymentPassword)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, httpx.Envelope{Code: "OK", Message: "红包已创建", Data: redPacketResponse(packet), RequestID: httpx.RequestID(r.Context())})
}

func (h *Handler) claimRedPacket(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	claim, err := h.service.ClaimRedPacket(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "orderNo"))
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]any{"red_packet_id": claim.RedPacketID, "order_no": claim.OrderNo, "user_id": claim.UserID, "amount": FormatAmount(claim.Amount), "created_at": claim.CreatedAt})
}

func redPacketResponse(value RedPacket) map[string]any {
	return map[string]any{"id": value.ID, "order_no": value.OrderNo, "sender_id": value.SenderID, "channel_id": value.ChannelID, "channel_type": value.ChannelType, "packet_type": value.PacketType, "total_amount": FormatAmount(value.TotalAmount), "total_count": value.TotalCount, "remaining_count": value.RemainingCount, "greeting": value.Greeting, "status": value.Status, "expires_at": value.ExpiresAt, "created_at": value.CreatedAt}
}

func (h *Handler) balance(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	balance, err := h.service.Balance(r.Context(), p.User.AppID, p.User.ID)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	var configured, attempts int
	var lockedUntil sql.NullTime
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*),COALESCE(MAX(failed_attempts),0),MAX(locked_until) FROM wallet_credentials WHERE app_id=? AND user_id=?`, p.User.AppID, p.User.ID).Scan(&configured, &attempts, &lockedUntil)
	var securityMethods int
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM user_credentials WHERE user_id=? AND credential_type IN ('phone','email') AND verified_at IS NOT NULL`, p.User.ID).Scan(&securityMethods)
	response := map[string]any{"available": FormatAmount(balance.Available), "frozen": FormatAmount(balance.Frozen), "currency": balance.Currency, "status": balance.Status, "lock_reason": balance.LockReason, "pay_password_set": configured > 0, "pay_password_failed_count": attempts, "security_bound": securityMethods > 0}
	if lockedUntil.Valid {
		response["pay_password_locked_until"] = lockedUntil.Time
	}
	httpx.OK(w, r, response)
}

func (h *Handler) setPassword(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var request struct {
		Password         string `json:"password"`
		Method           string `json:"method"`
		VerificationID   uint64 `json:"verification_id"`
		VerificationCode string `json:"verification_code"`
	}
	if !decodeWalletBody(w, r, &request) {
		return
	}
	if err := h.service.SetPaymentPassword(r.Context(), p.User.AppID, p.User.ID, request.Password, request.Method, request.VerificationID, request.VerificationCode); err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"configured": true})
}

func (h *Handler) createTransfer(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	var request struct {
		RecipientID     uint64 `json:"recipient_id"`
		Amount          string `json:"amount"`
		PaymentPassword string `json:"payment_password"`
	}
	if !decodeWalletBody(w, r, &request) {
		return
	}
	transfer, err := h.service.CreateTransfer(r.Context(), p.User.AppID, p.User.ID, request.RecipientID, request.Amount, request.PaymentPassword)
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, httpx.Envelope{Code: "OK", Message: "转账已创建", Data: transferResponse(transfer), RequestID: httpx.RequestID(r.Context())})
}

func (h *Handler) acceptTransfer(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		walletUnauthorized(w, r)
		return
	}
	transfer, err := h.service.AcceptTransfer(r.Context(), p.User.AppID, p.User.ID, chi.URLParam(r, "orderNo"))
	if err != nil {
		writeWalletError(w, r, err)
		return
	}
	httpx.OK(w, r, transferResponse(transfer))
}

func transferResponse(value Transfer) map[string]any {
	return map[string]any{"id": value.ID, "order_no": value.OrderNo, "sender_id": value.SenderID, "recipient_id": value.RecipientID, "amount": FormatAmount(value.Amount), "status": value.Status, "expires_at": value.ExpiresAt, "created_at": value.CreatedAt}
}
func decodeWalletBody(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func walletUnauthorized(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
}
func writeWalletError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrInvalidAmount):
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_AMOUNT", "金额格式无效")
	case errors.Is(err, ErrInsufficientBalance):
		httpx.Error(w, r, http.StatusConflict, "INSUFFICIENT_BALANCE", "余额不足")
	case errors.Is(err, ErrWalletLocked):
		httpx.Error(w, r, http.StatusForbidden, "WALLET_LOCKED", "钱包当前不可用")
	case errors.Is(err, ErrPaymentPassword):
		httpx.Error(w, r, http.StatusUnauthorized, "PAYMENT_PASSWORD_INVALID", "支付密码错误")
	case errors.Is(err, ErrPaymentPasswordLock):
		httpx.Error(w, r, http.StatusLocked, "PAYMENT_PASSWORD_LOCKED", "支付密码已锁定")
	case errors.Is(err, ErrSecurityMethod):
		httpx.Error(w, r, http.StatusPreconditionRequired, "SECURITY_METHOD_REQUIRED", "请先绑定并验证手机号或邮箱")
	case errors.Is(err, ErrOrderNotFound):
		httpx.Error(w, r, http.StatusNotFound, "ORDER_NOT_FOUND", "交易不存在")
	case errors.Is(err, ErrOrderState):
		httpx.Error(w, r, http.StatusConflict, "ORDER_STATE_INVALID", "交易状态不允许此操作")
	default:
		httpx.Error(w, r, http.StatusBadRequest, "WALLET_REQUEST_REJECTED", strings.TrimSpace(err.Error()))
	}
}
