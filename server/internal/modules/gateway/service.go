package gateway

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/httpx"
	"bim/server/internal/platform/redisx"
	"github.com/redis/go-redis/v9"
	"golang.org/x/net/websocket"
)

type Ticket struct {
	UserID, AppID                 uint64
	SessionID, DeviceID, Platform string
}
type Service struct {
	redis       *redisx.Client
	cfg         config.GatewayConfig
	connections atomic.Int64
}

func NewService(redis *redisx.Client, cfg config.GatewayConfig) *Service {
	return &Service{redis: redis, cfg: cfg}
}

func (s *Service) Issue(ctx context.Context, p identity.Principal) (string, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	ticket := base64.RawURLEncoding.EncodeToString(raw[:])
	value, _ := json.Marshal(Ticket{UserID: p.User.ID, AppID: p.User.AppID, SessionID: p.SessionID, DeviceID: p.DeviceID, Platform: p.Platform})
	if err := s.redis.Set(ctx, s.redis.Key("gateway", "ticket", ticket), value, 2*time.Minute).Err(); err != nil {
		return "", err
	}
	return ticket, nil
}

func (s *Service) TicketHandler(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "请先登录")
		return
	}
	ticket, err := s.Issue(r.Context(), p)
	if err != nil {
		httpx.Error(w, r, http.StatusServiceUnavailable, "GATEWAY_UNAVAILABLE", "连接服务暂不可用")
		return
	}
	httpx.OK(w, r, map[string]any{"ticket": ticket, "expires_in": 120, "heartbeat_seconds": int(s.cfg.HeartbeatInterval.Value().Seconds())})
}

func (s *Service) WebSocketHandler() http.Handler {
	server := websocket.Server{Handler: websocket.Handler(s.handle), Handshake: func(cfg *websocket.Config, r *http.Request) error {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin == "" {
			return nil
		}
		parsed, err := url.Parse(origin)
		if err != nil {
			return errors.New("invalid origin")
		}
		for _, allowed := range s.cfg.AllowedOrigins {
			value, parseErr := url.Parse(allowed)
			if parseErr == nil && strings.EqualFold(value.Host, parsed.Host) {
				return nil
			}
		}
		return errors.New("origin is not allowed")
	}}
	return server
}
func (s *Service) handle(conn *websocket.Conn) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer conn.Close()
	if current := s.connections.Add(1); s.cfg.MaxConnections > 0 && current > int64(s.cfg.MaxConnections) {
		s.connections.Add(-1)
		return
	}
	defer s.connections.Add(-1)
	ip := connectionIP(conn.Request())
	ipKey := s.redis.Key("gateway", "ip", ip)
	count, err := s.redis.Incr(ctx, ipKey).Result()
	if err != nil {
		return
	}
	_ = s.redis.Expire(ctx, ipKey, 3*s.cfg.HeartbeatInterval.Value()).Err()
	defer s.redis.Decr(context.Background(), ipKey)
	if s.cfg.MaxConnectionsPerIP > 0 && count > int64(s.cfg.MaxConnectionsPerIP) {
		return
	}
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	var hello struct{ Type, Ticket, LastEventID string }
	if err := websocket.JSON.Receive(conn, &hello); err != nil || hello.Type != "connect" {
		return
	}
	ticket, err := s.consumeTicket(ctx, hello.Ticket)
	if err != nil {
		return
	}
	_ = conn.SetDeadline(time.Time{})
	presenceKey := s.redis.Key("presence", fmt.Sprint(ticket.AppID), fmt.Sprint(ticket.UserID), ticket.Platform, ticket.DeviceID)
	presenceSet := s.redis.Key("presence", "user", fmt.Sprint(ticket.AppID), fmt.Sprint(ticket.UserID))
	presenceMember := ticket.Platform + ":" + ticket.DeviceID
	_ = s.redis.Set(ctx, presenceKey, time.Now().Unix(), 3*s.cfg.HeartbeatInterval.Value()).Err()
	_ = s.redis.ZAdd(ctx, presenceSet, redis.Z{Score: float64(time.Now().Add(3 * s.cfg.HeartbeatInterval.Value()).Unix()), Member: presenceMember}).Err()
	defer func() {
		s.redis.Del(context.Background(), presenceKey)
		s.redis.ZRem(context.Background(), presenceSet, presenceMember)
	}()
	events := make(chan map[string]any, s.cfg.QueueSize)
	go s.readEvents(ctx, ticket, hello.LastEventID, events)
	heartbeat := time.NewTicker(s.cfg.HeartbeatInterval.Value())
	defer heartbeat.Stop()
	incoming := make(chan map[string]any, 1)
	lastHeartbeat := atomic.Int64{}
	lastHeartbeat.Store(time.Now().UnixNano())
	go func() {
		for {
			var frame map[string]any
			if err := websocket.JSON.Receive(conn, &frame); err != nil {
				cancel()
				return
			}
			select {
			case incoming <- frame:
			case <-ctx.Done():
				return
			}
		}
	}()
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-events:
			if err := websocket.JSON.Send(conn, event); err != nil {
				return
			}
		case frame := <-incoming:
			s.handleFrame(ctx, presenceKey, presenceSet, presenceMember, ipKey, frame, &lastHeartbeat)
		case <-heartbeat.C:
			if time.Since(time.Unix(0, lastHeartbeat.Load())) > 3*s.cfg.HeartbeatInterval.Value() {
				return
			}
			if err := websocket.JSON.Send(conn, map[string]any{"type": "ping", "server_time": time.Now().UnixMilli()}); err != nil {
				return
			}
		}
	}
}

func (s *Service) consumeTicket(ctx context.Context, value string) (Ticket, error) {
	if strings.TrimSpace(value) == "" {
		return Ticket{}, errors.New("empty ticket")
	}
	key := s.redis.Key("gateway", "ticket", value)
	script := redis.NewScript(`local v=redis.call('GET',KEYS[1]); if v then redis.call('DEL',KEYS[1]) end; return v`)
	raw, err := script.Run(ctx, s.redis, []string{key}).Text()
	if err != nil {
		return Ticket{}, err
	}
	var ticket Ticket
	if err := json.Unmarshal([]byte(raw), &ticket); err != nil {
		return Ticket{}, err
	}
	return ticket, nil
}
func (s *Service) handleFrame(ctx context.Context, presenceKey, presenceSet, presenceMember, ipKey string, frame map[string]any, lastHeartbeat *atomic.Int64) {
	switch frame["type"] {
	case "pong", "heartbeat":
		lastHeartbeat.Store(time.Now().UnixNano())
		_ = s.redis.Set(ctx, presenceKey, time.Now().Unix(), 3*s.cfg.HeartbeatInterval.Value()).Err()
		_ = s.redis.ZAdd(ctx, presenceSet, redis.Z{Score: float64(time.Now().Add(3 * s.cfg.HeartbeatInterval.Value()).Unix()), Member: presenceMember}).Err()
		_ = s.redis.Expire(ctx, ipKey, 3*s.cfg.HeartbeatInterval.Value()).Err()
	case "ack":
		if id, ok := frame["event_id"].(string); ok && id != "" {
			_ = s.redis.Set(ctx, presenceKey+":ack", id, 24*time.Hour).Err()
		}
	}
}

func (s *Service) PresenceHandler(w http.ResponseWriter, r *http.Request) {
	p, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
		return
	}
	var request struct {
		UserIDs []uint64 `json:"user_ids"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil || len(request.UserIDs) > 500 {
		httpx.Error(w, r, 400, "INVALID_REQUEST", "用户列表无效")
		return
	}
	result := make(map[string]bool, len(request.UserIDs))
	now := time.Now().Unix()
	for _, id := range request.UserIDs {
		if id == 0 {
			continue
		}
		key := s.redis.Key("presence", "user", fmt.Sprint(p.User.AppID), fmt.Sprint(id))
		_ = s.redis.ZRemRangeByScore(r.Context(), key, "-inf", fmt.Sprint(now)).Err()
		count, err := s.redis.ZCard(r.Context(), key).Result()
		if err != nil {
			httpx.Error(w, r, 503, "PRESENCE_UNAVAILABLE", "在线状态暂不可用")
			return
		}
		result[strconv.FormatUint(id, 10)] = count > 0
	}
	httpx.OK(w, r, result)
}
func connectionIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
func (s *Service) readEvents(ctx context.Context, ticket Ticket, lastID string, output chan<- map[string]any) {
	if lastID == "" {
		lastID = "0-0"
	}
	stream := s.redis.Key("stream", "user", fmt.Sprint(ticket.AppID), fmt.Sprint(ticket.UserID))
	for {
		result, err := s.redis.XRead(ctx, &redis.XReadArgs{Streams: []string{stream, lastID}, Count: 100, Block: 5 * time.Second}).Result()
		if errors.Is(err, redis.Nil) {
			continue
		}
		if err != nil {
			return
		}
		for _, batch := range result {
			for _, message := range batch.Messages {
				event := map[string]any{"type": "event", "event_id": message.ID, "payload": message.Values}
				select {
				case output <- event:
					lastID = message.ID
				case <-ctx.Done():
					return
				}
			}
		}
	}
}
