package redisx

import (
	"context"
	"fmt"
	"strings"
	"time"

	"bim/server/internal/platform/config"
	"github.com/redis/go-redis/v9"
)

type Client struct {
	redis.UniversalClient
	prefix string
}

func Open(ctx context.Context, cfg config.RedisConfig) (*Client, error) {
	if len(cfg.Addresses) == 0 {
		return nil, fmt.Errorf("redis addresses are empty")
	}
	client := redis.NewUniversalClient(&redis.UniversalOptions{
		Addrs: cfg.Addresses, Password: cfg.Password, DB: cfg.DB,
		PoolSize: 50, MinIdleConns: 5,
	})
	checkCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := client.Ping(checkCtx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return &Client{UniversalClient: client, prefix: strings.Trim(cfg.KeyPrefix, ":")}, nil
}

func (c *Client) Key(parts ...string) string {
	values := make([]string, 0, len(parts)+1)
	if c.prefix != "" {
		values = append(values, c.prefix)
	}
	for _, part := range parts {
		if cleaned := strings.Trim(part, ": "); cleaned != "" {
			values = append(values, cleaned)
		}
	}
	return strings.Join(values, ":")
}
