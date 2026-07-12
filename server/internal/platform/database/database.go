package database

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"bim/server/internal/platform/config"
	_ "github.com/go-sql-driver/mysql"
)

type DB struct{ *sql.DB }

func Open(ctx context.Context, cfg config.DatabaseConfig) (*DB, error) {
	if cfg.DSN == "" {
		return nil, fmt.Errorf("database DSN is empty")
	}
	db, err := sql.Open("mysql", cfg.DSN)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetMaxIdleConns(cfg.MaxIdleConns)
	db.SetConnMaxLifetime(cfg.ConnMaxLifetime.Value())
	checkCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := db.PingContext(checkCtx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return &DB{DB: db}, nil
}

func (db *DB) WithinTx(ctx context.Context, options *sql.TxOptions, fn func(*sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, options)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}
