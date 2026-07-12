package calls

import (
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
)

var ErrCallState = errors.New("invalid call state")

type Session struct {
	CallNo       string        `json:"call_no"`
	RoomName     string        `json:"room_name"`
	InitiatorID  uint64        `json:"initiator_id"`
	ChannelID    string        `json:"channel_id"`
	ChannelType  uint8         `json:"channel_type"`
	CallType     string        `json:"call_type"`
	Status       string        `json:"status"`
	StartedAt    *time.Time    `json:"started_at,omitempty"`
	EndedAt      *time.Time    `json:"ended_at,omitempty"`
	Participants []Participant `json:"participants"`
}
type Participant struct {
	UserID        uint64 `json:"user_id"`
	Nickname      string `json:"nickname"`
	AvatarAssetID uint64 `json:"avatar_asset_id"`
	Role          string `json:"role"`
	Status        string `json:"status"`
}
type Service struct {
	db     *database.DB
	config config.LiveKitConfig
}

func NewService(db *database.DB, cfg config.LiveKitConfig) *Service {
	return &Service{db: db, config: cfg}
}
func (s *Service) Initiate(ctx context.Context, appID, initiatorID uint64, channelID string, channelType uint8, callType string, invitees []uint64) (Session, error) {
	channelID = strings.TrimSpace(channelID)
	if callType != "audio" && callType != "video" {
		return Session{}, ErrCallState
	}
	ids := unique(invitees, initiatorID)
	if len(ids) == 0 || len(ids) > 50 {
		return Session{}, ErrCallState
	}
	if err := s.authorize(ctx, appID, initiatorID, channelID, channelType, ids); err != nil {
		return Session{}, err
	}
	callNo, err := randomID("CALL")
	if err != nil {
		return Session{}, err
	}
	room := "bim-" + strings.ToLower(callNo)
	now := time.Now().UTC()
	err = s.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		result, err := tx.ExecContext(ctx, `INSERT INTO call_sessions(app_id,call_no,room_name,initiator_id,conversation_channel_id,conversation_channel_type,call_type,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'ringing',?,?)`, appID, callNo, room, initiatorID, channelID, channelType, callType, now, now)
		if err != nil {
			return err
		}
		callID, _ := result.LastInsertId()
		if _, err := tx.ExecContext(ctx, `INSERT INTO call_participants(app_id,call_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,?,'initiator','accepted',?,?,?)`, appID, callID, initiatorID, now, now, now); err != nil {
			return err
		}
		for _, id := range ids {
			if _, err := tx.ExecContext(ctx, `INSERT INTO call_participants(app_id,call_id,user_id,role,status,created_at,updated_at) VALUES(?,?,?,'invitee','invited',?,?)`, appID, callID, id, now, now); err != nil {
				return err
			}
			direct := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(id, 10)
			if err := enqueueMessage(ctx, tx, appID, initiatorID, direct, 1, 99, map[string]any{"cmd": "call_invite", "call_no": callNo, "room_name": room, "call_type": callType, "initiator_id": initiatorID, "origin_channel_id": channelID, "origin_channel_type": channelType}, now); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return Session{}, err
	}
	return s.Get(ctx, appID, initiatorID, callNo)
}
func (s *Service) Accept(ctx context.Context, appID, userID uint64, callNo string) (Session, error) {
	err := s.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var id uint64
		var status string
		if err := tx.QueryRowContext(ctx, `SELECT id,status FROM call_sessions WHERE app_id=? AND call_no=? FOR UPDATE`, appID, callNo).Scan(&id, &status); err != nil {
			return ErrCallState
		}
		if status != "ringing" && status != "active" {
			return ErrCallState
		}
		result, err := tx.ExecContext(ctx, `UPDATE call_participants SET status='accepted',joined_at=COALESCE(joined_at,NOW(6)),updated_at=NOW(6) WHERE call_id=? AND user_id=? AND status='invited'`, id, userID)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows != 1 {
			return ErrCallState
		}
		_, err = tx.ExecContext(ctx, `UPDATE call_sessions SET status='active',started_at=COALESCE(started_at,NOW(6)),updated_at=NOW(6) WHERE id=?`, id)
		return err
	})
	if err != nil {
		return Session{}, err
	}
	return s.Get(ctx, appID, userID, callNo)
}
func (s *Service) Reject(ctx context.Context, appID, userID uint64, callNo string) error {
	return s.participantDecision(ctx, appID, userID, callNo, "rejected")
}
func (s *Service) End(ctx context.Context, appID, userID uint64, callNo, reason string) (Session, error) {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		reason = "hangup"
	}
	var final Session
	err := s.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var id uint64
		var initiator uint64
		var channel string
		var channelType uint8
		var callType, status string
		var started sql.NullTime
		if err := tx.QueryRowContext(ctx, `SELECT id,initiator_id,conversation_channel_id,conversation_channel_type,call_type,status,started_at FROM call_sessions WHERE app_id=? AND call_no=? FOR UPDATE`, appID, callNo).Scan(&id, &initiator, &channel, &channelType, &callType, &status, &started); err != nil {
			return ErrCallState
		}
		var member int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM call_participants WHERE call_id=? AND user_id=? AND (status='accepted' OR role='initiator')`, id, userID).Scan(&member); err != nil || member == 0 {
			return ErrCallState
		}
		if status == "ended" || status == "cancelled" {
			return ErrCallState
		}
		end := time.Now().UTC()
		finalStatus := "ended"
		if !started.Valid {
			finalStatus = "cancelled"
		}
		if _, err := tx.ExecContext(ctx, `UPDATE call_sessions SET status=?,ended_at=?,end_reason=?,updated_at=? WHERE id=?`, finalStatus, end, reason, end, id); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE call_participants SET status=IF(status='invited','missed',status),left_at=IF(status='accepted',?,left_at),updated_at=? WHERE call_id=?`, end, end, id); err != nil {
			return err
		}
		duration := int64(0)
		if started.Valid {
			duration = int64(end.Sub(started.Time).Seconds())
			if duration < 0 {
				duration = 0
			}
		}
		summary := "通话已结束"
		if finalStatus == "cancelled" {
			summary = "已取消"
		}
		rows, err := tx.QueryContext(ctx, `SELECT user_id FROM call_participants WHERE call_id=? AND user_id<>?`, id, userID)
		if err != nil {
			return err
		}
		participantIDs := make([]uint64, 0)
		for rows.Next() {
			var participantID uint64
			if err := rows.Scan(&participantID); err != nil {
				rows.Close()
				return err
			}
			participantIDs = append(participantIDs, participantID)
		}
		rows.Close()
		for _, participantID := range participantIDs {
			direct := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(participantID, 10)
			if err := enqueueMessage(ctx, tx, appID, userID, direct, 1, 99, map[string]any{"cmd": "call_ended", "call_no": callNo, "status": finalStatus, "end_reason": reason}, end); err != nil {
				return err
			}
		}
		messageChannel := channel
		if channelType == 1 && userID != initiator {
			messageChannel = "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(initiator, 10)
		}
		if err := enqueueMessage(ctx, tx, appID, userID, messageChannel, channelType, 5301, map[string]any{"call_no": callNo, "call_type": callType, "status": finalStatus, "duration_seconds": duration, "end_reason": reason, "summary": summary}, end); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return Session{}, err
	}
	final, err = s.Get(ctx, appID, userID, callNo)
	return final, err
}
func (s *Service) Get(ctx context.Context, appID, userID uint64, callNo string) (Session, error) {
	var item Session
	var started, ended sql.NullTime
	err := s.db.QueryRowContext(ctx, `SELECT cs.call_no,cs.room_name,cs.initiator_id,cs.conversation_channel_id,cs.conversation_channel_type,cs.call_type,cs.status,cs.started_at,cs.ended_at FROM call_sessions cs JOIN call_participants cp ON cp.call_id=cs.id WHERE cs.app_id=? AND cs.call_no=? AND cp.user_id=?`, appID, callNo, userID).Scan(&item.CallNo, &item.RoomName, &item.InitiatorID, &item.ChannelID, &item.ChannelType, &item.CallType, &item.Status, &started, &ended)
	if err != nil {
		return Session{}, ErrCallState
	}
	if started.Valid {
		v := started.Time
		item.StartedAt = &v
	}
	if ended.Valid {
		v := ended.Time
		item.EndedAt = &v
	}
	rows, err := s.db.QueryContext(ctx, `SELECT cp.user_id,u.nickname,COALESCE(u.avatar_asset_id,0),cp.role,cp.status FROM call_participants cp JOIN call_sessions cs ON cs.id=cp.call_id JOIN users u ON u.id=cp.user_id WHERE cs.app_id=? AND cs.call_no=? ORDER BY cp.id`, appID, callNo)
	if err != nil {
		return Session{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var p Participant
		if err := rows.Scan(&p.UserID, &p.Nickname, &p.AvatarAssetID, &p.Role, &p.Status); err != nil {
			return Session{}, err
		}
		item.Participants = append(item.Participants, p)
	}
	return item, rows.Err()
}
func (s *Service) Token(ctx context.Context, appID, userID uint64, callNo string) (map[string]any, error) {
	session, err := s.Get(ctx, appID, userID, callNo)
	if err != nil {
		return nil, err
	}
	allowed := false
	for _, p := range session.Participants {
		if p.UserID == userID && (p.Status == "accepted" || p.Role == "initiator") {
			allowed = true
		}
	}
	if !allowed || session.Status == "ended" || session.Status == "cancelled" {
		return nil, ErrCallState
	}
	token, expires, err := liveKitToken(s.config.APIKey, s.config.APISecret, session.RoomName, strconv.FormatUint(userID, 10))
	if err != nil {
		return nil, err
	}
	return map[string]any{"url": s.config.URL, "token": token, "room_name": session.RoomName, "expires_at": expires}, nil
}
func (s *Service) participantDecision(ctx context.Context, appID, userID uint64, callNo, status string) error {
	return s.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var id uint64
		if err := tx.QueryRowContext(ctx, `SELECT id FROM call_sessions WHERE app_id=? AND call_no=? AND status='ringing' FOR UPDATE`, appID, callNo).Scan(&id); err != nil {
			return ErrCallState
		}
		result, err := tx.ExecContext(ctx, `UPDATE call_participants SET status=?,left_at=NOW(6),updated_at=NOW(6) WHERE call_id=? AND user_id=? AND status='invited'`, status, id, userID)
		if err != nil {
			return err
		}
		rows, _ := result.RowsAffected()
		if rows != 1 {
			return ErrCallState
		}
		var pending int
		_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM call_participants WHERE call_id=? AND status='invited'`, id).Scan(&pending)
		if pending == 0 {
			_, err = tx.ExecContext(ctx, `UPDATE call_sessions SET status='cancelled',ended_at=NOW(6),end_reason='declined',updated_at=NOW(6) WHERE id=?`, id)
		}
		return err
	})
}
func (s *Service) authorize(ctx context.Context, appID, initiator uint64, channel string, channelType uint8, ids []uint64) error {
	if channelType == 1 {
		if len(ids) != 1 {
			return ErrCallState
		}
		expected := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(ids[0], 10)
		if channel != expected {
			return ErrCallState
		}
		var count int
		_ = s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM friendships WHERE app_id=? AND user_id=? AND friend_id=? AND status='active'`, appID, initiator, ids[0]).Scan(&count)
		if count != 1 {
			return ErrCallState
		}
		return nil
	}
	if channelType != 2 {
		return ErrCallState
	}
	var groupID uint64
	if err := s.db.QueryRowContext(ctx, `SELECT g.id FROM chat_groups g JOIN group_members gm ON gm.group_id=g.id WHERE g.app_id=? AND g.channel_id=? AND g.status='active' AND gm.user_id=? AND gm.status='active'`, appID, channel, initiator).Scan(&groupID); err != nil {
		return ErrCallState
	}
	for _, id := range ids {
		var count int
		_ = s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members WHERE group_id=? AND user_id=? AND status='active'`, groupID, id).Scan(&count)
		if count != 1 {
			return ErrCallState
		}
	}
	return nil
}
func unique(values []uint64, exclude uint64) []uint64 {
	set := map[uint64]struct{}{}
	for _, v := range values {
		if v != 0 && v != exclude {
			set[v] = struct{}{}
		}
	}
	out := make([]uint64, 0, len(set))
	for v := range set {
		out = append(out, v)
	}
	return out
}
func randomID(prefix string) (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return prefix + strings.ToUpper(hex.EncodeToString(raw)), nil
}
func liveKitToken(key, secret, room, identity string) (string, time.Time, error) {
	if key == "" || secret == "" {
		return "", time.Time{}, errors.New("livekit not configured")
	}
	now := time.Now().UTC()
	expires := now.Add(2 * time.Hour)
	header, _ := json.Marshal(map[string]any{"alg": "HS256", "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{"iss": key, "sub": identity, "nbf": now.Unix() - 5, "exp": expires.Unix(), "video": map[string]any{"roomJoin": true, "room": room, "canPublish": true, "canSubscribe": true, "canPublishData": true}})
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(unsigned))
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), expires, nil
}
