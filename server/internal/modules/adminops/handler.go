package adminops

import (
	"bim/server/internal/modules/adminauth"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/httpx"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
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
	r.With(adminauth.Require("dashboard:read")).Get("/dashboard", h.dashboard)
	r.With(adminauth.Require("user:read")).Get("/users", h.users)
	r.With(adminauth.Require("user:write")).Post("/users/{id}/control", h.userControl)
	r.With(adminauth.Require("group:read")).Get("/groups", h.groups)
	r.With(adminauth.Require("group:read")).Get("/groups/{id}/members", h.groupMembers)
	r.With(adminauth.Require("group:write")).Post("/groups/{id}/control", h.groupControl)
	r.With(adminauth.Require("message:audit")).Get("/messages", h.messages)
	r.With(adminauth.Require("message:delete")).Delete("/messages/{id}", h.deleteMessage)
	r.With(adminauth.Require("service_account:read")).Get("/service-accounts", h.serviceAccounts)
	r.With(adminauth.Require("service_account:write")).Post("/service-accounts", h.saveServiceAccount)
	r.With(adminauth.Require("call:read")).Get("/calls", h.calls)
	r.With(adminauth.Require("audit:read")).Get("/audit-logs", h.auditLogs)
	return r
}
func (h *Handler) dashboard(w http.ResponseWriter, r *http.Request) {
	var users, groups, messages, pendingMoments, calls int64
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM users WHERE app_id=1 AND status=1`).Scan(&users)
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM chat_groups WHERE app_id=1 AND status='active'`).Scan(&groups)
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM messages WHERE app_id=1 AND created_at>=CURRENT_DATE`).Scan(&messages)
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM moments WHERE app_id=1 AND status='pending' AND deleted_at IS NULL`).Scan(&pendingMoments)
	_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM call_sessions WHERE app_id=1 AND created_at>=CURRENT_DATE`).Scan(&calls)
	httpx.OK(w, r, map[string]int64{"active_users": users, "active_groups": groups, "messages_today": messages, "pending_moments": pendingMoments, "calls_today": calls})
}
func (h *Handler) users(w http.ResponseWriter, r *http.Request) {
	q := "%" + strings.TrimSpace(r.URL.Query().Get("q")) + "%"
	rows, err := h.db.QueryContext(r.Context(), `SELECT u.id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),u.status,u.created_at,COALESCE(wa.available_amount,0),COALESCE(wa.frozen_amount,0),COALESCE(wa.status,'active'),ucr.private_muted_until,ucr.group_muted_until,ucr.reason FROM users u LEFT JOIN wallet_accounts wa ON wa.app_id=u.app_id AND wa.user_id=u.id AND wa.currency='CNY' LEFT JOIN user_chat_restrictions ucr ON ucr.app_id=u.app_id AND ucr.user_id=u.id WHERE u.app_id=1 AND (u.username LIKE ? OR u.nickname LIKE ?) ORDER BY u.id DESC LIMIT 200`, q, q)
	if err != nil {
		fail(w, r, "USER_LIST_FAILED", "用户列表加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, avatar uint64
		var username, nickname, walletStatus, reason string
		var status uint8
		var created time.Time
		var available, frozen int64
		var privateMute, groupMute sql.NullTime
		if rows.Scan(&id, &username, &nickname, &avatar, &status, &created, &available, &frozen, &walletStatus, &privateMute, &groupMute, &reason) != nil {
			fail(w, r, "USER_LIST_FAILED", "用户列表加载失败")
			return
		}
		items = append(items, map[string]any{"id": id, "username": username, "nickname": nickname, "avatar_asset_id": avatar, "status": status, "created_at": created, "wallet_available": available, "wallet_frozen": frozen, "wallet_status": walletStatus, "private_muted_until": nullTime(privateMute), "group_muted_until": nullTime(groupMute), "mute_reason": reason})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) userControl(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var q struct {
		Action string     `json:"action"`
		Reason string     `json:"reason"`
		Until  *time.Time `json:"until"`
	}
	if !decode(w, r, &q) {
		return
	}
	if !reasonOK(q.Reason) {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "必须填写操作原因")
		return
	}
	p, _ := adminauth.PrincipalFromContext(r.Context())
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		switch q.Action {
		case "enable", "disable":
			status := 1
			if q.Action == "disable" {
				status = 0
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE users SET status=?,session_version=session_version+1,updated_at=NOW(6) WHERE app_id=1 AND id=?`, status, id); err != nil {
				return err
			}
			if status == 0 {
				_, _ = tx.ExecContext(r.Context(), `UPDATE device_sessions SET status='revoked',updated_at=NOW(6) WHERE app_id=1 AND user_id=? AND status='active'`, id)
			}
		case "mute_private", "mute_group", "unmute_private", "unmute_group":
			column := "private_muted_until"
			if strings.Contains(q.Action, "group") {
				column = "group_muted_until"
			}
			var until any = q.Until
			if strings.HasPrefix(q.Action, "unmute") {
				until = nil
			} else if q.Until == nil {
				until = time.Date(9999, 12, 31, 23, 59, 59, 0, time.UTC)
			}
			_, err := tx.ExecContext(r.Context(), `INSERT INTO user_chat_restrictions(app_id,user_id,`+column+`,reason,created_at,updated_at) VALUES(1,?,?,?,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE `+column+`=VALUES(`+column+`),reason=VALUES(reason),updated_at=NOW(6)`, id, until, q.Reason)
			if err != nil {
				return err
			}
		case "revoke_sessions":
			_, err := tx.ExecContext(r.Context(), `UPDATE device_sessions SET status='revoked',updated_at=NOW(6) WHERE app_id=1 AND user_id=? AND status='active'`, id)
			if err != nil {
				return err
			}
		default:
			return errors.New("unsupported action")
		}
		return audit(r, tx, p.Admin.ID, "user."+q.Action, "user", id, q.Reason, nil, map[string]any{"action": q.Action, "until": q.Until})
	})
	if err != nil {
		httpx.Error(w, r, 400, "USER_CONTROL_FAILED", "用户管控失败")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) groups(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.QueryContext(r.Context(), `SELECT g.id,g.channel_id,g.name,COALESCE(g.avatar_asset_id,0),g.owner_id,u.nickname,g.member_count,g.all_muted,g.status,g.created_at FROM chat_groups g JOIN users u ON u.id=g.owner_id WHERE g.app_id=1 ORDER BY g.id DESC LIMIT 200`)
	if err != nil {
		fail(w, r, "GROUP_LIST_FAILED", "群聊列表加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, avatar, owner uint64
		var channel, name, ownerName, status string
		var count uint32
		var allMuted bool
		var created time.Time
		if rows.Scan(&id, &channel, &name, &avatar, &owner, &ownerName, &count, &allMuted, &status, &created) != nil {
			fail(w, r, "GROUP_LIST_FAILED", "群聊列表加载失败")
			return
		}
		items = append(items, map[string]any{"id": id, "channel_id": channel, "name": name, "avatar_asset_id": avatar, "owner_id": owner, "owner_name": ownerName, "member_count": count, "all_muted": allMuted, "status": status, "created_at": created})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) groupMembers(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	rows, err := h.db.QueryContext(r.Context(), `SELECT gm.user_id,u.username,u.nickname,COALESCE(u.avatar_asset_id,0),gm.role,gm.muted_until,gm.joined_at FROM group_members gm JOIN users u ON u.id=gm.user_id WHERE gm.app_id=1 AND gm.group_id=? AND gm.status='active' ORDER BY FIELD(gm.role,'owner','admin','member'),gm.id`, id)
	if err != nil {
		fail(w, r, "GROUP_MEMBER_FAILED", "群成员加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var userID, avatar uint64
		var username, nickname, role string
		var muted sql.NullTime
		var joined time.Time
		if rows.Scan(&userID, &username, &nickname, &avatar, &role, &muted, &joined) != nil {
			fail(w, r, "GROUP_MEMBER_FAILED", "群成员加载失败")
			return
		}
		items = append(items, map[string]any{"user_id": userID, "username": username, "nickname": nickname, "avatar_asset_id": avatar, "role": role, "muted_until": nullTime(muted), "joined_at": joined})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) groupControl(w http.ResponseWriter, r *http.Request) {
	groupID, ok := pathID(w, r)
	if !ok {
		return
	}
	var q struct {
		Action string     `json:"action"`
		UserID uint64     `json:"user_id"`
		Reason string     `json:"reason"`
		Until  *time.Time `json:"until"`
	}
	if !decode(w, r, &q) {
		return
	}
	if !reasonOK(q.Reason) {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "必须填写操作原因")
		return
	}
	p, _ := adminauth.PrincipalFromContext(r.Context())
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var channelID string
		if err := tx.QueryRowContext(r.Context(), `SELECT channel_id FROM chat_groups WHERE app_id=1 AND id=? AND status='active' FOR UPDATE`, groupID).Scan(&channelID); err != nil {
			return err
		}
		var systemUser uint64
		if err := tx.QueryRowContext(r.Context(), `SELECT user_id FROM service_accounts WHERE app_id=1 AND code='system' AND status='active'`).Scan(&systemUser); err != nil {
			return err
		}
		switch q.Action {
		case "dissolve":
			if err := adminGroupEvent(r, tx, 1, systemUser, channelID, q.Action, map[string]any{"group_id": groupID, "user_id": q.UserID, "until": q.Until}); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE chat_groups SET status='dissolved',member_count=0,updated_at=NOW(6) WHERE app_id=1 AND id=? AND status='active'`, groupID); err != nil {
				return err
			}
			_, err := tx.ExecContext(r.Context(), `UPDATE group_members SET status='dissolved',left_at=NOW(6),updated_at=NOW(6) WHERE group_id=? AND status='active'`, groupID)
			if err != nil {
				return err
			}
			if err := adminChannelOperation(r, tx, 1, "channel_delete", channelID, nil); err != nil {
				return err
			}
		case "remove_member":
			result, err := tx.ExecContext(r.Context(), `UPDATE group_members SET status='removed',left_at=NOW(6),updated_at=NOW(6) WHERE group_id=? AND user_id=? AND status='active' AND role<>'owner'`, groupID, q.UserID)
			if err != nil {
				return err
			}
			if err := adminChannelOperation(r, tx, 1, "subscriber_remove", channelID, []uint64{q.UserID}); err != nil {
				return err
			}
			rows, _ := result.RowsAffected()
			if rows == 0 {
				return errors.New("member cannot be removed")
			}
			_, err = tx.ExecContext(r.Context(), `UPDATE chat_groups SET member_count=member_count-1,updated_at=NOW(6) WHERE id=?`, groupID)
			if err != nil {
				return err
			}
		case "mute_member", "unmute_member":
			var until any = q.Until
			if q.Action == "unmute_member" {
				until = nil
			} else if q.Until == nil {
				until = time.Date(9999, 12, 31, 23, 59, 59, 0, time.UTC)
			}
			result, err := tx.ExecContext(r.Context(), `UPDATE group_members SET muted_until=?,updated_at=NOW(6) WHERE group_id=? AND user_id=? AND status='active' AND role<>'owner'`, until, groupID, q.UserID)
			if err != nil {
				return err
			}
			rows, _ := result.RowsAffected()
			if rows == 0 {
				return errors.New("member cannot be muted")
			}
		default:
			return errors.New("unsupported action")
		}
		if q.Action != "dissolve" {
			if err := adminGroupEvent(r, tx, 1, systemUser, channelID, q.Action, map[string]any{"group_id": groupID, "user_id": q.UserID, "until": q.Until}); err != nil {
				return err
			}
		}
		return audit(r, tx, p.Admin.ID, "group."+q.Action, "group", groupID, q.Reason, nil, map[string]any{"user_id": q.UserID, "until": q.Until})
	})
	if err != nil {
		httpx.Error(w, r, 400, "GROUP_CONTROL_FAILED", "群聊管控失败")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}

func adminChannelOperation(r *http.Request, tx *sql.Tx, appID uint64, operation, channelID string, members []uint64) error {
	values := make([]string, 0, len(members))
	for _, id := range members {
		values = append(values, "app"+strconv.FormatUint(appID, 10)+"user"+strconv.FormatUint(id, 10))
	}
	payload, _ := json.Marshal(map[string]any{"members": values})
	nextAttempt := time.Now().UTC()
	if operation == "channel_delete" {
		nextAttempt = nextAttempt.Add(10 * time.Second)
	}
	_, err := tx.ExecContext(r.Context(), `INSERT INTO wukong_channel_outbox(app_id,operation,channel_id,channel_type,payload_json,status,next_attempt_at,created_at,updated_at) VALUES(?,?,?,2,?,'pending',?,NOW(6),NOW(6))`, appID, operation, channelID, payload, nextAttempt)
	return err
}

func adminGroupEvent(r *http.Request, tx *sql.Tx, appID, sender uint64, channel, event string, data map[string]any) error {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return err
	}
	client := "srv-admin-group-" + hex.EncodeToString(raw)
	payload, _ := json.Marshal(map[string]any{"protocol": "blin.chat.v1", "type": 5401, "system_message": true, "event": event, "actor": "system", "data": data})
	sum := sha256.Sum256(payload)
	result, err := tx.ExecContext(r.Context(), `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,2,?,5401,?,?,'queued',NOW(6),NOW(6))`, appID, client, channel, sender, payload, hex.EncodeToString(sum[:]))
	if err != nil {
		return err
	}
	messageID, _ := result.LastInsertId()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',NOW(6),NOW(6),NOW(6))`, messageID); err != nil {
		return err
	}
	_, err = tx.ExecContext(r.Context(), `INSERT INTO user_conversations(app_id,user_id,channel_id,channel_type,last_message_id,unread_count,created_at,updated_at) SELECT ?,gm.user_id,?,2,?,1,NOW(6),NOW(6) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active' ON DUPLICATE KEY UPDATE last_message_id=VALUES(last_message_id),unread_count=unread_count+1,hidden_at=NULL,updated_at=NOW(6)`, appID, channel, messageID, appID, channel)
	return err
}
func (h *Handler) messages(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.QueryContext(r.Context(), `SELECT m.id,m.client_msg_no,COALESCE(m.message_id,''),m.channel_id,m.channel_type,m.sender_id,u.nickname,m.content_type,m.payload_json,m.status,m.message_seq,m.created_at,m.recalled_at FROM messages m JOIN users u ON u.id=m.sender_id WHERE m.app_id=1 ORDER BY m.id DESC LIMIT 300`)
	if err != nil {
		fail(w, r, "MESSAGE_LIST_FAILED", "消息列表加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, sender, seq uint64
		var client, remote, channel, nickname, status string
		var channelType uint8
		var contentType uint32
		var payload []byte
		var created time.Time
		var recalled sql.NullTime
		if rows.Scan(&id, &client, &remote, &channel, &channelType, &sender, &nickname, &contentType, &payload, &status, &seq, &created, &recalled) != nil {
			fail(w, r, "MESSAGE_LIST_FAILED", "消息列表加载失败")
			return
		}
		var data any
		_ = json.Unmarshal(payload, &data)
		items = append(items, map[string]any{"id": id, "client_msg_no": client, "message_id": remote, "channel_id": channel, "channel_type": channelType, "sender_id": sender, "sender_name": nickname, "content_type": contentType, "payload": data, "status": status, "message_seq": seq, "created_at": created, "recalled_at": nullTime(recalled)})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) deleteMessage(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var q struct {
		Reason string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if !reasonOK(q.Reason) {
		httpx.Error(w, r, 400, "REASON_REQUIRED", "必须填写删除原因")
		return
	}
	p, _ := adminauth.PrincipalFromContext(r.Context())
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		var appID, sender uint64
		var channel, client string
		var channelType uint8
		if err := tx.QueryRowContext(r.Context(), `SELECT app_id,sender_id,channel_id,channel_type,client_msg_no FROM messages WHERE id=? AND recalled_at IS NULL FOR UPDATE`, id).Scan(&appID, &sender, &channel, &channelType, &client); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE messages SET recalled_at=NOW(6),updated_at=NOW(6) WHERE id=?`, id); err != nil {
			return err
		}
		var systemUser uint64
		if err := tx.QueryRowContext(r.Context(), `SELECT user_id FROM service_accounts WHERE app_id=? AND code='system'`, appID).Scan(&systemUser); err != nil {
			return err
		}
		if err := enqueueRecall(r, tx, appID, systemUser, channel, channelType, client, id); err != nil {
			return err
		}
		return audit(r, tx, p.Admin.ID, "message.delete", "message", id, q.Reason, nil, map[string]any{"recalled": true})
	})
	if err != nil {
		httpx.Error(w, r, 409, "MESSAGE_DELETE_FAILED", "消息不存在或已经删除")
		return
	}
	httpx.OK(w, r, map[string]bool{"deleted": true})
}
func (h *Handler) serviceAccounts(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.QueryContext(r.Context(), `SELECT sa.id,sa.code,sa.name,COALESCE(sa.avatar_asset_id,0),sa.description,sa.status,sa.input_enabled,sa.menu_json,sa.updated_at FROM service_accounts sa WHERE sa.app_id=1 ORDER BY sa.id`)
	if err != nil {
		fail(w, r, "SERVICE_LIST_FAILED", "服务号列表加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, avatar uint64
		var code, name, description, status string
		var input bool
		var menu []byte
		var updated time.Time
		if rows.Scan(&id, &code, &name, &avatar, &description, &status, &input, &menu, &updated) != nil {
			fail(w, r, "SERVICE_LIST_FAILED", "服务号列表加载失败")
			return
		}
		var menuValue any
		_ = json.Unmarshal(menu, &menuValue)
		items = append(items, map[string]any{"id": id, "code": code, "name": name, "avatar_asset_id": avatar, "description": description, "status": status, "input_enabled": input, "menu": menuValue, "updated_at": updated})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) saveServiceAccount(w http.ResponseWriter, r *http.Request) {
	var q struct {
		ID            uint64 `json:"id"`
		Name          string `json:"name"`
		Description   string `json:"description"`
		AvatarAssetID uint64 `json:"avatar_asset_id"`
		InputEnabled  bool   `json:"input_enabled"`
		Menu          any    `json:"menu"`
		Reason        string `json:"reason"`
	}
	if !decode(w, r, &q) {
		return
	}
	if q.ID == 0 || strings.TrimSpace(q.Name) == "" || !reasonOK(q.Reason) {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "服务号参数或原因无效")
		return
	}
	menu, _ := json.Marshal(q.Menu)
	p, _ := adminauth.PrincipalFromContext(r.Context())
	err := h.db.WithinTx(r.Context(), nil, func(tx *sql.Tx) error {
		result, err := tx.ExecContext(r.Context(), `UPDATE service_accounts SET name=?,description=?,avatar_asset_id=NULLIF(?,0),input_enabled=?,menu_json=?,updated_at=NOW(6) WHERE app_id=1 AND id=?`, q.Name, q.Description, q.AvatarAssetID, q.InputEnabled, menu, q.ID)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows == 0 {
			return sql.ErrNoRows
		}
		return audit(r, tx, p.Admin.ID, "service_account.update", "service_account", q.ID, q.Reason, nil, q)
	})
	if err != nil {
		httpx.Error(w, r, 400, "SERVICE_UPDATE_FAILED", "服务号保存失败")
		return
	}
	httpx.OK(w, r, map[string]bool{"updated": true})
}
func (h *Handler) calls(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.QueryContext(r.Context(), `SELECT cs.id,cs.call_no,cs.initiator_id,u.nickname,cs.conversation_channel_id,cs.conversation_channel_type,cs.call_type,cs.status,cs.started_at,cs.ended_at,cs.end_reason,cs.created_at,(SELECT COUNT(*) FROM call_participants cp WHERE cp.call_id=cs.id) FROM call_sessions cs JOIN users u ON u.id=cs.initiator_id WHERE cs.app_id=1 ORDER BY cs.id DESC LIMIT 300`)
	if err != nil {
		fail(w, r, "CALL_LIST_FAILED", "通话记录加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, initiator uint64
		var callNo, name, channel, callType, status, reason string
		var channelType uint8
		var started, ended sql.NullTime
		var created time.Time
		var count int
		if rows.Scan(&id, &callNo, &initiator, &name, &channel, &channelType, &callType, &status, &started, &ended, &reason, &created, &count) != nil {
			fail(w, r, "CALL_LIST_FAILED", "通话记录加载失败")
			return
		}
		items = append(items, map[string]any{"id": id, "call_no": callNo, "initiator_id": initiator, "initiator_name": name, "channel_id": channel, "channel_type": channelType, "call_type": callType, "status": status, "started_at": nullTime(started), "ended_at": nullTime(ended), "end_reason": reason, "created_at": created, "participant_count": count})
	}
	httpx.OK(w, r, items)
}
func (h *Handler) auditLogs(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.QueryContext(r.Context(), `SELECT al.id,a.username,al.action,al.resource_type,al.resource_id,al.reason,al.request_id,al.ip,al.created_at FROM admin_audit_logs al JOIN admins a ON a.id=al.admin_id ORDER BY al.id DESC LIMIT 500`)
	if err != nil {
		fail(w, r, "AUDIT_LIST_FAILED", "审计日志加载失败")
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id uint64
		var admin, action, resource, resourceID, reason, requestID, ip string
		var created time.Time
		if rows.Scan(&id, &admin, &action, &resource, &resourceID, &reason, &requestID, &ip, &created) != nil {
			fail(w, r, "AUDIT_LIST_FAILED", "审计日志加载失败")
			return
		}
		items = append(items, map[string]any{"id": id, "admin": admin, "action": action, "resource_type": resource, "resource_id": resourceID, "reason": reason, "request_id": requestID, "ip": ip, "created_at": created})
	}
	httpx.OK(w, r, items)
}
func enqueueRecall(r *http.Request, tx *sql.Tx, appID, sender uint64, channel string, channelType uint8, target string, targetID uint64) error {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return err
	}
	client := "srv-admin-" + hex.EncodeToString(raw)
	payload, _ := json.Marshal(map[string]any{"protocol": "blin.chat.v1", "type": 1006, "system_message": true, "content_type": "recall", "target_client_msg_no": target, "actor": "system"})
	sum := sha256.Sum256(payload)
	result, err := tx.ExecContext(r.Context(), `INSERT INTO messages(app_id,client_msg_no,channel_id,channel_type,sender_id,content_type,payload_json,payload_hash,status,created_at,updated_at) VALUES(?,?,?,?,?,1006,?,?,'queued',NOW(6),NOW(6))`, appID, client, channel, channelType, sender, payload, hex.EncodeToString(sum[:]))
	if err != nil {
		return err
	}
	messageID, _ := result.LastInsertId()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO message_outbox(message_id,status,next_attempt_at,created_at,updated_at) VALUES(?,'pending',NOW(6),NOW(6),NOW(6))`, messageID); err != nil {
		return err
	}
	event, _ := json.Marshal(map[string]any{"target_message_id": targetID})
	_, err = tx.ExecContext(r.Context(), `INSERT INTO message_events(app_id,event_id,event_type,message_id,actor_id,payload_json,created_at) VALUES(?,?,'admin_recall',?,?,?,NOW(6))`, appID, "event-"+client, targetID, sender, event)
	return err
}
func audit(r *http.Request, tx *sql.Tx, adminID uint64, action, resource string, id uint64, reason string, before, after any) error {
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(after)
	_, err := tx.ExecContext(r.Context(), `INSERT INTO admin_audit_logs(admin_id,action,resource_type,resource_id,reason,before_json,after_json,request_id,ip,user_agent,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,NOW(6))`, adminID, action, resource, strconv.FormatUint(id, 10), reason, nullJSON(beforeJSON), nullJSON(afterJSON), httpx.RequestID(r.Context()), r.RemoteAddr, r.UserAgent())
	return err
}
func nullJSON(v []byte) any {
	if string(v) == "null" {
		return nil
	}
	return v
}
func pathID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id == 0 {
		httpx.Error(w, r, 400, "INVALID_ID", "编号无效")
		return 0, false
	}
	return id, true
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2<<20))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "请求参数格式错误")
		return false
	}
	return true
}
func reasonOK(v string) bool { n := len([]rune(strings.TrimSpace(v))); return n >= 2 && n <= 500 }
func nullTime(v sql.NullTime) any {
	if v.Valid {
		return v.Time
	}
	return nil
}
func fail(w http.ResponseWriter, r *http.Request, code, message string) {
	httpx.Error(w, r, 500, code, message)
}
