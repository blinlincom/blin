package identity

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"bim/server/internal/platform/database"
	"github.com/go-sql-driver/mysql"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }

func (r *SQLRepository) CreateUser(ctx context.Context, user User, session Session) (User, error) {
	var created User
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		result, err := tx.ExecContext(ctx, `INSERT INTO users(app_id,username,invitation_code,nickname,status,session_version,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)`, user.AppID, user.Username, user.InvitationCode, user.Nickname, 1, 1, now, now)
		if err != nil {
			return mapMySQLError(err)
		}
		id, err := result.LastInsertId()
		if err != nil {
			return err
		}
		user.ID = uint64(id)
		_, err = tx.ExecContext(ctx, `INSERT INTO user_credentials(user_id,credential_type,identifier,secret_hash,verified_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)`, user.ID, "password", user.Username, user.PasswordHash, now, now, now)
		if err != nil {
			return mapMySQLError(err)
		}
		if user.ContactType != "" && user.ContactIdentifier != "" {
			_, err = tx.ExecContext(ctx, `INSERT INTO user_credentials(user_id,credential_type,identifier,verified_at,created_at,updated_at) VALUES(?,?,?,?,?,?)`, user.ID, user.ContactType, user.ContactIdentifier, now, now, now)
			if err != nil {
				return mapMySQLError(err)
			}
		}
		session.UserID, session.AppID = user.ID, user.AppID
		if err := insertSession(ctx, tx, session, now); err != nil {
			return err
		}
		created = user
		return nil
	})
	return created, err
}

func (r *SQLRepository) FindPasswordUser(ctx context.Context, appID uint64, username string) (User, error) {
	var user User
	err := r.db.QueryRowContext(ctx, `SELECT u.id,u.app_id,u.username,u.nickname,p.secret_hash,u.session_version,u.status FROM users u JOIN user_credentials p ON p.user_id=u.id AND p.credential_type='password' LEFT JOIN user_credentials i ON i.user_id=u.id AND i.credential_type IN ('phone','email') WHERE u.app_id=? AND (p.identifier=? OR i.identifier=?) LIMIT 1`, appID, username, username).
		Scan(&user.ID, &user.AppID, &user.Username, &user.Nickname, &user.PasswordHash, &user.SessionVersion, &user.Status)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (r *SQLRepository) FindUserByID(ctx context.Context, appID, userID uint64) (User, error) {
	var user User
	err := r.db.QueryRowContext(ctx, `SELECT id,app_id,username,nickname,session_version,status FROM users WHERE app_id=? AND id=? LIMIT 1`, appID, userID).
		Scan(&user.ID, &user.AppID, &user.Username, &user.Nickname, &user.SessionVersion, &user.Status)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (r *SQLRepository) ReplacePlatformSession(ctx context.Context, user User, session Session) error {
	return r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		now := time.Now().UTC()
		_, err := tx.ExecContext(ctx, `UPDATE device_sessions SET status='revoked',updated_at=? WHERE app_id=? AND user_id=? AND platform=? AND status='active'`, now, user.AppID, user.ID, session.Platform)
		if err != nil {
			return err
		}
		return insertSession(ctx, tx, session, now)
	})
}

func (r *SQLRepository) FindSession(ctx context.Context, sessionID string) (Session, error) {
	var session Session
	err := r.db.QueryRowContext(ctx, `SELECT session_id,app_id,user_id,platform,device_id,device_name,refresh_token_hash,session_version,expire_at FROM device_sessions WHERE session_id=? AND status='active' LIMIT 1`, sessionID).
		Scan(&session.ID, &session.AppID, &session.UserID, &session.Platform, &session.DeviceID, &session.DeviceName, &session.RefreshTokenHash, &session.SessionVersion, &session.ExpiresAt)
	return session, err
}

func (r *SQLRepository) RotateSession(ctx context.Context, sessionID, refreshHash string, expiresAt time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE device_sessions SET refresh_token_hash=?,expire_at=?,last_seen_at=NOW(6),updated_at=NOW(6) WHERE session_id=? AND status='active'`, refreshHash, expiresAt, sessionID)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows != 1 {
		return ErrSessionRevoked
	}
	return nil
}

func (r *SQLRepository) RevokeSession(ctx context.Context, sessionID string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE device_sessions SET status='revoked',updated_at=NOW(6) WHERE session_id=?`, sessionID)
	return err
}

func (r *SQLRepository) SecurityMethods(ctx context.Context, appID, userID uint64) ([]SecurityMethod, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT c.credential_type,c.identifier,c.verified_at FROM user_credentials c JOIN users u ON u.id=c.user_id WHERE u.app_id=? AND u.id=? AND c.credential_type IN ('phone','email') AND c.verified_at IS NOT NULL ORDER BY c.credential_type`, appID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]SecurityMethod, 0, 2)
	for rows.Next() {
		var item SecurityMethod
		if err := rows.Scan(&item.Type, &item.Identifier, &item.VerifiedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *SQLRepository) BindSecurityMethod(ctx context.Context, appID, userID uint64, method, identifier string) error {
	result, err := r.db.ExecContext(ctx, `INSERT INTO user_credentials(user_id,credential_type,identifier,verified_at,created_at,updated_at) SELECT id,?,?,NOW(6),NOW(6),NOW(6) FROM users WHERE app_id=? AND id=? AND status=1 ON DUPLICATE KEY UPDATE identifier=VALUES(identifier),verified_at=NOW(6),updated_at=NOW(6)`, method, identifier, appID, userID)
	if err != nil {
		return mapMySQLError(err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return ErrInvalidCredentials
	}
	return nil
}

func insertSession(ctx context.Context, tx *sql.Tx, session Session, now time.Time) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO device_sessions(session_id,app_id,user_id,platform,device_id,device_name,refresh_token_hash,session_version,status,last_ip,last_seen_at,expire_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, session.ID, session.AppID, session.UserID, session.Platform, session.DeviceID, session.DeviceName, session.RefreshTokenHash, session.SessionVersion, "active", "", now, session.ExpiresAt, now, now)
	return mapMySQLError(err)
}

func mapMySQLError(err error) error {
	if err == nil {
		return nil
	}
	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) && mysqlErr.Number == 1062 {
		if strings.Contains(mysqlErr.Message, "username") || strings.Contains(mysqlErr.Message, "credential") {
			return ErrUsernameTaken
		}
	}
	return fmt.Errorf("identity repository: %w", err)
}
