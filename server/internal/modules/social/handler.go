package social

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }

func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Get("/users/search", h.searchUser)
	router.Get("/friends", h.listFriends)
	router.Post("/friend-requests", h.applyFriend)
	router.Get("/friend-requests", h.listRequests)
	router.Post("/friend-requests/{requestID}/decision", h.handleRequest)
	router.Delete("/friends/{friendID}", h.deleteFriend)
	router.Post("/groups", h.createGroup)
	router.Get("/groups", h.listGroups)
	router.Get("/groups/{groupID}", h.getGroup)
	router.Patch("/groups/{groupID}", h.updateGroup)
	router.Delete("/groups/{groupID}", h.dissolveGroup)
	router.Get("/groups/{groupID}/members", h.listGroupMembers)
	router.Post("/groups/{groupID}/members", h.addGroupMembers)
	router.Delete("/groups/{groupID}/members/{memberID}", h.removeGroupMember)
	router.Put("/groups/{groupID}/members/{memberID}/role", h.setGroupMemberRole)
	router.Put("/groups/{groupID}/members/{memberID}/mute", h.muteGroupMember)
	router.Post("/groups/{groupID}/leave", h.leaveGroup)
	return router
}

func groupIDFromRequest(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	value, err := strconv.ParseUint(chi.URLParam(r, "groupID"), 10, 64)
	if err != nil || value == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_GROUP_ID", "群聊编号无效")
		return 0, false
	}
	return value, true
}

func (h *Handler) listGroups(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	items, err := h.service.ListGroups(r.Context(), p.User.AppID, p.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}

func (h *Handler) getGroup(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	item, err := h.service.GetGroup(r.Context(), p.User.AppID, groupID, p.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, item)
}

func (h *Handler) listGroupMembers(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	items, err := h.service.ListGroupMembers(r.Context(), p.User.AppID, groupID, p.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}

func (h *Handler) addGroupMembers(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	var request struct {
		MemberIDs []uint64 `json:"member_ids"`
	}
	if !decode(w, r, &request) {
		return
	}
	if err := h.service.AddGroupMembers(r.Context(), p.User.AppID, groupID, p.User.ID, request.MemberIDs); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"added": true})
}

func (h *Handler) removeGroupMember(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	memberID, err := strconv.ParseUint(chi.URLParam(r, "memberID"), 10, 64)
	if err != nil || memberID == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_MEMBER_ID", "成员编号无效")
		return
	}
	if err := h.service.RemoveGroupMember(r.Context(), p.User.AppID, groupID, p.User.ID, memberID); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"removed": true})
}

func (h *Handler) updateGroup(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	var request GroupUpdate
	if !decode(w, r, &request) {
		return
	}
	if err := h.service.UpdateGroup(r.Context(), p.User.AppID, groupID, p.User.ID, request); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}

func (h *Handler) setGroupMemberRole(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	memberID, err := strconv.ParseUint(chi.URLParam(r, "memberID"), 10, 64)
	if err != nil || memberID == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_MEMBER_ID", "成员编号无效")
		return
	}
	var request struct {
		Role string `json:"role"`
	}
	if !decode(w, r, &request) {
		return
	}
	if err := h.service.SetGroupMemberRole(r.Context(), p.User.AppID, groupID, p.User.ID, memberID, request.Role); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}

func (h *Handler) muteGroupMember(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	memberID, err := strconv.ParseUint(chi.URLParam(r, "memberID"), 10, 64)
	if err != nil || memberID == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_MEMBER_ID", "成员编号无效")
		return
	}
	var request struct {
		MutedUntil *time.Time `json:"muted_until"`
	}
	if !decode(w, r, &request) {
		return
	}
	if err := h.service.MuteGroupMember(r.Context(), p.User.AppID, groupID, p.User.ID, memberID, request.MutedUntil); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}

func (h *Handler) leaveGroup(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	if err := h.service.LeaveGroup(r.Context(), p.User.AppID, groupID, p.User.ID); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"left": true})
}

func (h *Handler) dissolveGroup(w http.ResponseWriter, r *http.Request) {
	p, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	groupID, ok := groupIDFromRequest(w, r)
	if !ok {
		return
	}
	if err := h.service.DissolveGroup(r.Context(), p.User.AppID, groupID, p.User.ID); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"dissolved": true})
}

func (h *Handler) searchUser(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	user, err := h.service.SearchForAdd(r.Context(), principal.User.AppID, r.URL.Query().Get("username"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	if user.ID == principal.User.ID {
		httpx.Error(w, r, http.StatusBadRequest, "SELF_OPERATION", "不能添加自己")
		return
	}
	httpx.OK(w, r, user)
}

func (h *Handler) listFriends(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	items, err := h.service.ListFriends(r.Context(), principal.User.AppID, principal.User.ID, r.URL.Query().Get("q"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}

func (h *Handler) applyFriend(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	var request struct {
		RecipientID uint64 `json:"recipient_id"`
		Message     string `json:"message"`
	}
	if !decode(w, r, &request) {
		return
	}
	id, err := h.service.ApplyFriend(r.Context(), principal.User.AppID, principal.User.ID, request.RecipientID, request.Message)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, httpx.Envelope{Code: "OK", Message: "好友申请已发送", Data: map[string]uint64{"request_id": id}, RequestID: httpx.RequestID(r.Context())})
}

func (h *Handler) listRequests(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	items, err := h.service.ListFriendRequests(r.Context(), principal.User.AppID, principal.User.ID)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, items)
}

func (h *Handler) handleRequest(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	requestID, err := strconv.ParseUint(chi.URLParam(r, "requestID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "请求编号无效")
		return
	}
	var request struct {
		Accept bool `json:"accept"`
	}
	if !decode(w, r, &request) {
		return
	}
	if err := h.service.HandleFriendRequest(r.Context(), principal.User.AppID, requestID, principal.User.ID, request.Accept); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"accepted": request.Accept})
}

func (h *Handler) deleteFriend(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	friendID, err := strconv.ParseUint(chi.URLParam(r, "friendID"), 10, 64)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "INVALID_REQUEST", "好友编号无效")
		return
	}
	if err := h.service.DeleteFriendship(r.Context(), principal.User.AppID, principal.User.ID, friendID); err != nil {
		writeError(w, r, err)
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}

func (h *Handler) createGroup(w http.ResponseWriter, r *http.Request) {
	principal, ok := principal(r)
	if !ok {
		unauthorized(w, r)
		return
	}
	var request struct {
		Name      string   `json:"name"`
		MemberIDs []uint64 `json:"member_ids"`
	}
	if !decode(w, r, &request) {
		return
	}
	group, err := h.service.CreateGroup(r.Context(), principal.User.AppID, principal.User.ID, request.Name, request.MemberIDs)
	if err != nil {
		writeError(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, httpx.Envelope{Code: "OK", Message: "群聊已创建", Data: group, RequestID: httpx.RequestID(r.Context())})
}

func principal(r *http.Request) (identity.Principal, bool) {
	return identity.PrincipalFromContext(r.Context())
}
func unauthorized(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
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
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		httpx.Error(w, r, http.StatusNotFound, "NOT_FOUND", "数据不存在")
	case errors.Is(err, ErrAlreadyFriends):
		httpx.Error(w, r, http.StatusConflict, "ALREADY_FRIENDS", "已经是好友")
	case errors.Is(err, ErrRequestPending):
		httpx.Error(w, r, http.StatusConflict, "REQUEST_PENDING", "好友申请处理中")
	case errors.Is(err, ErrForbidden):
		httpx.Error(w, r, http.StatusForbidden, "FORBIDDEN", "操作不允许")
	default:
		httpx.Error(w, r, http.StatusBadRequest, "SOCIAL_REQUEST_REJECTED", strings.TrimSpace(err.Error()))
	}
}
