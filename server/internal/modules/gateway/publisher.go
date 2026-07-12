package gateway

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"bim/server/internal/platform/database"
	"bim/server/internal/platform/redisx"
	"github.com/redis/go-redis/v9"
)

type Publisher struct {
	redis  *redisx.Client
	db     *database.DB
	maxLen int64
}

func NewPublisher(redisClient *redisx.Client, db *database.DB, maxLen int64) *Publisher {
	return &Publisher{redis: redisClient, db: db, maxLen: maxLen}
}
func (p *Publisher) Publish(ctx context.Context, eventType string, message map[string]any) error {
	raw, _ := json.Marshal(message)
	recipients, err := p.recipientIDs(ctx, message)
	if err != nil {
		return err
	}
	for _, target := range recipients {
		stream := p.redis.Key("stream", "user", fmt.Sprint(target.appID), fmt.Sprint(target.userID))
		if err := p.redis.XAdd(ctx, &redis.XAddArgs{Stream: stream, MaxLen: p.maxLen, Approx: true, Values: map[string]any{"event_type": eventType, "data": string(raw)}}).Err(); err != nil {
			return err
		}
	}
	return nil
}

type recipient struct{ appID, userID uint64 }

func (p *Publisher) recipientIDs(ctx context.Context, message map[string]any) ([]recipient, error) {
	appID := number(message["app_id"])
	if appID == 0 {
		appID = number(message["appid"])
	}
	unique := map[uint64]struct{}{}
	if presenceUserID := number(message["presence_user_id"]); presenceUserID > 0 && p.db != nil {
		unique[presenceUserID] = struct{}{}
		rows, err := p.db.QueryContext(ctx, `SELECT user_id FROM friendships WHERE app_id=? AND friend_id=? AND status='active'`, appID, presenceUserID)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var id uint64
			if err := rows.Scan(&id); err != nil {
				return nil, err
			}
			unique[id] = struct{}{}
		}
	}
	for _, key := range []string{"sender_id", "receiver_id"} {
		if id := number(message[key]); id > 0 {
			unique[id] = struct{}{}
		}
	}
	if groupID := number(message["group_id"]); groupID > 0 && p.db != nil {
		rows, err := p.db.QueryContext(ctx, `SELECT user_id FROM group_members WHERE app_id=? AND group_id=? AND status='active'`, appID, groupID)
		if err != nil && err != sql.ErrNoRows {
			return nil, err
		}
		if rows != nil {
			defer rows.Close()
			for rows.Next() {
				var id uint64
				if err := rows.Scan(&id); err != nil {
					return nil, err
				}
				unique[id] = struct{}{}
			}
		}
	}
	channelID, _ := message["channel_id"].(string)
	channelType := number(message["channel_type"])
	if channelType == 2 && channelID != "" && p.db != nil {
		rows, err := p.db.QueryContext(ctx, `SELECT gm.user_id FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id AND g.app_id=gm.app_id WHERE gm.app_id=? AND g.channel_id=? AND gm.status='active'`, appID, channelID)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var id uint64
			if err := rows.Scan(&id); err != nil {
				return nil, err
			}
			unique[id] = struct{}{}
		}
	}
	if channelType == 1 && channelID != "" {
		prefix := fmt.Sprintf("app%duser", appID)
		if strings.HasPrefix(channelID, prefix) {
			if id, err := strconv.ParseUint(strings.TrimPrefix(channelID, prefix), 10, 64); err == nil {
				unique[id] = struct{}{}
			}
		}
	}
	result := make([]recipient, 0, len(unique))
	for id := range unique {
		result = append(result, recipient{appID, id})
	}
	return result, nil
}
func number(value any) uint64 {
	switch v := value.(type) {
	case float64:
		return uint64(v)
	case uint64:
		return v
	case int:
		return uint64(v)
	case json.Number:
		n, _ := strconv.ParseUint(v.String(), 10, 64)
		return n
	case string:
		n, _ := strconv.ParseUint(v, 10, 64)
		return n
	}
	return 0
}
