package idempotency

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"
)

var ErrConflict = errors.New("idempotency key was used with a different request")

type Record struct {
	Key          string
	RequestHash  string
	ResponseCode int
	ResponseBody []byte
}

type Service struct{ db *sql.DB }

func New(db *sql.DB) *Service { return &Service{db: db} }

func Hash(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
}

func (s *Service) Load(ctx context.Context, scope, key, requestHash string) (Record, bool, error) {
	var record Record
	err := s.db.QueryRowContext(ctx, `SELECT idempotency_key,request_hash,response_code,response_body FROM idempotency_keys WHERE scope=? AND idempotency_key=? AND expire_time>NOW()`, scope, key).
		Scan(&record.Key, &record.RequestHash, &record.ResponseCode, &record.ResponseBody)
	if errors.Is(err, sql.ErrNoRows) {
		return Record{}, false, nil
	}
	if err != nil {
		return Record{}, false, fmt.Errorf("load idempotency key: %w", err)
	}
	if record.RequestHash != requestHash {
		return Record{}, false, ErrConflict
	}
	return record, true, nil
}

func (s *Service) Store(ctx context.Context, scope, key, requestHash string, code int, body []byte, ttl time.Duration) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO idempotency_keys(scope,idempotency_key,request_hash,response_code,response_body,expire_time,create_time) VALUES(?,?,?,?,?,DATE_ADD(NOW(), INTERVAL ? SECOND),NOW()) ON DUPLICATE KEY UPDATE response_code=VALUES(response_code),response_body=VALUES(response_body)`, scope, key, requestHash, code, body, int64(ttl.Seconds()))
	if err != nil {
		return fmt.Errorf("store idempotency key: %w", err)
	}
	return nil
}
