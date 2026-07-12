package adminauth

import (
	"bim/server/internal/platform/database"
	"context"
	"database/sql"
	"time"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }
func (r *SQLRepository) FindByUsername(ctx context.Context, username string) (Admin, error) {
	return r.find(ctx, `a.username=?`, username)
}
func (r *SQLRepository) FindByID(ctx context.Context, id uint64) (Admin, error) {
	return r.find(ctx, `a.id=?`, id)
}
func (r *SQLRepository) find(ctx context.Context, where string, value any) (Admin, error) {
	var admin Admin
	err := r.db.QueryRowContext(ctx, `SELECT a.id,a.username,a.password_hash,a.status,a.session_version FROM admins a WHERE `+where+` LIMIT 1`, value).Scan(&admin.ID, &admin.Username, &admin.PasswordHash, &admin.Status, &admin.SessionVersion)
	if err != nil {
		return Admin{}, err
	}
	rows, err := r.db.QueryContext(ctx, `SELECT DISTINCT p.code FROM permissions p JOIN role_permissions rp ON rp.permission_id=p.id JOIN admin_roles ar ON ar.role_id=rp.role_id WHERE ar.admin_id=? ORDER BY p.code`, admin.ID)
	if err != nil {
		return Admin{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var permission string
		if err := rows.Scan(&permission); err != nil {
			return Admin{}, err
		}
		admin.Permissions = append(admin.Permissions, permission)
	}
	return admin, rows.Err()
}
func (r *SQLRepository) CreateSession(ctx context.Context, session Session) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		if _, err := tx.ExecContext(ctx, `UPDATE admin_sessions SET status='revoked',updated_at=? WHERE admin_id=? AND status='active'`, now, session.AdminID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO admin_sessions(session_id,admin_id,refresh_token_hash,session_version,status,expire_at,last_seen_at,created_at,updated_at) VALUES(?,?,?,?,'active',?,?,?,?)`, session.ID, session.AdminID, session.RefreshHash, session.SessionVersion, session.ExpiresAt, now, now, now)
		return err
	})
}
func (r *SQLRepository) FindSession(ctx context.Context, id string) (Session, error) {
	var session Session
	err := r.db.QueryRowContext(ctx, `SELECT session_id,admin_id,session_version,refresh_token_hash,expire_at FROM admin_sessions WHERE session_id=? AND status='active'`, id).Scan(&session.ID, &session.AdminID, &session.SessionVersion, &session.RefreshHash, &session.ExpiresAt)
	return session, err
}
func (r *SQLRepository) RotateSession(ctx context.Context, id, hash string, expires time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE admin_sessions SET refresh_token_hash=?,expire_at=?,last_seen_at=NOW(6),updated_at=NOW(6) WHERE session_id=? AND status='active'`, hash, expires, id)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows != 1 {
		return ErrUnauthorized
	}
	return nil
}
func (r *SQLRepository) RevokeSession(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE admin_sessions SET status='revoked',updated_at=NOW(6) WHERE session_id=?`, id)
	return err
}
func (r *SQLRepository) CreateSuperAdmin(ctx context.Context, username, hash string) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		result, err := tx.ExecContext(ctx, `INSERT INTO admins(username,password_hash,status,session_version,created_at,updated_at) VALUES(?,?,1,1,?,?)`, username, hash, now, now)
		if err != nil {
			return err
		}
		adminID, err := result.LastInsertId()
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO admin_roles(admin_id,role_id) SELECT ?,id FROM roles WHERE code='super_admin'`, adminID)
		return err
	})
}
