package messaging

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }
func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Post("/messages", h.send)
	router.Get("/history", h.history)
	router.Get("/conversations", h.conversations)
	router.Get("/messages/{messageID}/read-summary", h.readSummary)
	router.Post("/read", h.markRead)
	router.Delete("/messages/{messageID}", h.hideMessage)
	router.Delete("/conversation", h.clearConversation)
	router.Post("/messages/{messageID}/recall", h.recall)
	router.Post("/messages/{messageID}/burn-read", h.burnRead)
	return router
}

func (h *Handler) conversations(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := h.service.Conversations(r.Context(), p.User.AppID, p.User.ID, limit)
	if err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}
func (h *Handler) readSummary(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
		return
	}
	id, err := strconv.ParseUint(chi.URLParam(r, "messageID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "消息编号无效")
		return
	}
	value, err := h.service.ReadReceiptSummary(r.Context(), p.User.AppID, p.User.ID, id)
	if err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, value)
}

func (h *Handler) recall(w http.ResponseWriter, r *http.Request)   { h.messageEvent(w, r, true) }
func (h *Handler) burnRead(w http.ResponseWriter, r *http.Request) { h.messageEvent(w, r, false) }
func (h *Handler) messageEvent(w http.ResponseWriter, r *http.Request, recall bool) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	messageID, err := strconv.ParseUint(chi.URLParam(r, "messageID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "消息编号无效")
		return
	}
	var request struct {
		ClientMsgNo string `json:"client_msg_no"`
	}
	if !decodeMessageBody(w, r, &request) {
		return
	}
	var result QueuedMessage
	if recall {
		result, err = h.service.Recall(r.Context(), principal.User.AppID, principal.User.ID, messageID, request.ClientMsgNo)
	} else {
		result, err = h.service.BurnAfterRead(r.Context(), principal.User.AppID, principal.User.ID, messageID, request.ClientMsgNo)
	}
	if err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, httpx.Envelope{Code: "OK", Message: "事件已进入发送队列", Data: result, RequestID: httpx.RequestID(r.Context())})
}

func (h *Handler) history(w http.ResponseWriter, r *http.Request) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	channelType, err := strconv.ParseUint(r.URL.Query().Get("channel_type"), 10, 8)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "频道类型无效")
		return
	}
	before, _ := strconv.ParseUint(r.URL.Query().Get("before_seq"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := h.service.History(r.Context(), HistoryInput{AppID: principal.User.AppID, UserID: principal.User.ID, ChannelID: r.URL.Query().Get("channel_id"), ChannelType: uint8(channelType), BeforeSeq: before, Limit: limit})
	if err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}
func (h *Handler) markRead(w http.ResponseWriter, r *http.Request) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	var request struct {
		ChannelID   string `json:"channel_id"`
		ChannelType uint8  `json:"channel_type"`
		ThroughSeq  uint64 `json:"through_seq"`
	}
	if !decodeMessageBody(w, r, &request) {
		return
	}
	if err := h.service.MarkRead(r.Context(), principal.User.AppID, principal.User.ID, request.ChannelID, request.ChannelType, request.ThroughSeq); err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"read": true})
}
func (h *Handler) hideMessage(w http.ResponseWriter, r *http.Request) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	messageID, err := strconv.ParseUint(chi.URLParam(r, "messageID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "消息编号无效")
		return
	}
	if err := h.service.HideMessage(r.Context(), principal.User.AppID, principal.User.ID, messageID); err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
func (h *Handler) clearConversation(w http.ResponseWriter, r *http.Request) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	var request struct {
		ChannelID   string `json:"channel_id"`
		ChannelType uint8  `json:"channel_type"`
	}
	if !decodeMessageBody(w, r, &request) {
		return
	}
	if err := h.service.ClearConversation(r.Context(), principal.User.AppID, principal.User.ID, request.ChannelID, request.ChannelType); err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"cleared": true})
}
func decodeMessageBody(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}

func (h *Handler) send(w http.ResponseWriter, r *http.Request) {
	principal, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	var request struct {
		ClientMsgNo string         `json:"client_msg_no"`
		ChannelID   string         `json:"channel_id"`
		ChannelType uint8          `json:"channel_type"`
		ContentType uint32         `json:"content_type"`
		Payload     map[string]any `json:"payload"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 2<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "消息参数格式错误")
		return
	}
	result, err := h.service.Send(r.Context(), SendInput{AppID: principal.User.AppID, SenderID: principal.User.ID, ClientMsgNo: request.ClientMsgNo, ChannelID: request.ChannelID, ChannelType: request.ChannelType, ContentType: request.ContentType, Payload: request.Payload})
	if err != nil {
		writeMessageError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, httpx.Envelope{Code: "OK", Message: "消息已进入发送队列", Data: result, RequestID: httpx.RequestID(r.Context())})
}
func writeMessageError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrMuted):
		httpx.Error(w, r, http.StatusForbidden, "CHAT_MUTED", "当前无法发送消息，请联系管理员")
	case errors.Is(err, ErrStrangerLimit):
		httpx.Error(w, r, http.StatusForbidden, "STRANGER_LIMIT", "非好友消息已达到上限")
	case errors.Is(err, ErrForbidden):
		httpx.Error(w, r, http.StatusForbidden, "MESSAGE_FORBIDDEN", "当前消息不允许发送")
	case errors.Is(err, ErrClientMsgConflict):
		httpx.Error(w, r, http.StatusConflict, "CLIENT_MSG_NO_CONFLICT", "消息编号已被其他内容占用")
	case errors.Is(err, ErrInvalidPayload):
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_MESSAGE_PAYLOAD", "消息内容格式无效")
	default:
		httpx.Error(w, r, http.StatusBadRequest, "MESSAGE_REJECTED", strings.TrimSpace(err.Error()))
	}
}
