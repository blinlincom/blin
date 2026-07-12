-- +goose Up
CREATE TABLE applications (
  id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(100) NOT NULL,
  status TINYINT UNSIGNED NOT NULL DEFAULT 1,
  config_json JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  username VARCHAR(64) NOT NULL,
  nickname VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(1000) NOT NULL DEFAULT '',
  profile_background_url VARCHAR(1000) NOT NULL DEFAULT '',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1,
  session_version BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_app_username (app_id, username),
  KEY idx_user_app_status (app_id, status, id),
  CONSTRAINT fk_users_application FOREIGN KEY (app_id) REFERENCES applications(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_credentials (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  credential_type VARCHAR(20) NOT NULL,
  identifier VARCHAR(191) NOT NULL,
  secret_hash VARCHAR(255) NOT NULL DEFAULT '',
  verified_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_credential_type_identifier (credential_type, identifier),
  KEY idx_credential_user (user_id),
  CONSTRAINT fk_credentials_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE device_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id VARCHAR(64) NOT NULL,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  platform VARCHAR(20) NOT NULL,
  device_id VARCHAR(128) NOT NULL,
  device_name VARCHAR(150) NOT NULL DEFAULT '',
  refresh_token_hash CHAR(64) NOT NULL,
  session_version BIGINT UNSIGNED NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  last_ip VARCHAR(45) NOT NULL DEFAULT '',
  last_seen_at DATETIME(6) NOT NULL,
  expire_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_device_session_id (session_id),
  KEY idx_device_platform (app_id, user_id, platform, device_id, status),
  KEY idx_device_user_status (app_id, user_id, status),
  CONSTRAINT fk_device_sessions_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE verification_challenges (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  scene VARCHAR(50) NOT NULL,
  target VARCHAR(191) NOT NULL,
  code_hash CHAR(64) NOT NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  max_attempts INT UNSIGNED NOT NULL DEFAULT 5,
  expire_at DATETIME(6) NOT NULL,
  consumed_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_verification_lookup (app_id, scene, target, expire_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE verification_challenges;
DROP TABLE device_sessions;
DROP TABLE user_credentials;
DROP TABLE users;
DROP TABLE applications;
