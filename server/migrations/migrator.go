package migrations

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"embed"
	"encoding/hex"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"
)

//go:embed *.sql
var files embed.FS

type Migration struct {
	Version  uint64
	Name     string
	SQL      string
	Checksum string
}

type Status struct {
	Version uint64 `json:"version"`
	Name    string `json:"name"`
	Applied bool   `json:"applied"`
}

type Migrator struct{ db *sql.DB }

func New(db *sql.DB) *Migrator { return &Migrator{db: db} }

func (m *Migrator) Up(ctx context.Context) error {
	if err := m.ensureTable(ctx); err != nil {
		return err
	}
	migrations, err := load()
	if err != nil {
		return err
	}
	applied, err := m.applied(ctx)
	if err != nil {
		return err
	}
	for _, migration := range migrations {
		if checksum, ok := applied[migration.Version]; ok {
			if checksum != migration.Checksum {
				return fmt.Errorf("migration %d checksum changed after apply", migration.Version)
			}
			continue
		}
		if err := m.apply(ctx, migration); err != nil {
			return err
		}
	}
	return nil
}

func (m *Migrator) Status(ctx context.Context) ([]Status, error) {
	if err := m.ensureTable(ctx); err != nil {
		return nil, err
	}
	migrations, err := load()
	if err != nil {
		return nil, err
	}
	applied, err := m.applied(ctx)
	if err != nil {
		return nil, err
	}
	result := make([]Status, 0, len(migrations))
	for _, migration := range migrations {
		_, ok := applied[migration.Version]
		result = append(result, Status{Version: migration.Version, Name: migration.Name, Applied: ok})
	}
	return result, nil
}

func (m *Migrator) ensureTable(ctx context.Context) error {
	_, err := m.db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
version BIGINT UNSIGNED NOT NULL PRIMARY KEY,
name VARCHAR(255) NOT NULL,
checksum CHAR(64) NOT NULL,
applied_at DATETIME(6) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)
	return err
}

func (m *Migrator) applied(ctx context.Context) (map[uint64]string, error) {
	rows, err := m.db.QueryContext(ctx, `SELECT version,checksum FROM schema_migrations ORDER BY version`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := map[uint64]string{}
	for rows.Next() {
		var version uint64
		var checksum string
		if err := rows.Scan(&version, &checksum); err != nil {
			return nil, err
		}
		result[version] = checksum
	}
	return result, rows.Err()
}

func (m *Migrator) apply(ctx context.Context, migration Migration) error {
	for index, statement := range splitStatements(migration.SQL) {
		if _, err := m.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("apply migration %d %s statement %d: %w", migration.Version, migration.Name, index+1, err)
		}
	}
	if _, err := m.db.ExecContext(ctx, `INSERT INTO schema_migrations(version,name,checksum,applied_at) VALUES(?,?,?,?)`, migration.Version, migration.Name, migration.Checksum, time.Now().UTC()); err != nil {
		return fmt.Errorf("record migration %d: %w", migration.Version, err)
	}
	return nil
}

// Migration files intentionally use ordinary DDL/DML without stored programs;
// splitting on semicolons keeps MySQL multiStatements disabled in the runtime
// DSN, which removes an unnecessary SQL-injection capability.
func splitStatements(script string) []string {
	parts := strings.Split(script, ";")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if statement := strings.TrimSpace(part); statement != "" {
			result = append(result, statement)
		}
	}
	return result
}

func load() ([]Migration, error) {
	entries, err := fs.ReadDir(files, ".")
	if err != nil {
		return nil, err
	}
	result := make([]Migration, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}
		parts := strings.SplitN(entry.Name(), "_", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("invalid migration filename %s", entry.Name())
		}
		version, err := strconv.ParseUint(parts[0], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("invalid migration version %s: %w", entry.Name(), err)
		}
		content, err := files.ReadFile(entry.Name())
		if err != nil {
			return nil, err
		}
		up := strings.SplitN(string(content), "-- +goose Down", 2)[0]
		up = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(up), "-- +goose Up"))
		sum := sha256.Sum256([]byte(up))
		result = append(result, Migration{Version: version, Name: entry.Name(), SQL: up, Checksum: hex.EncodeToString(sum[:])})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Version < result[j].Version })
	return result, nil
}
