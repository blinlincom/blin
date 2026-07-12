-- +goose Up
ALTER TABLE chat_groups
  ADD COLUMN all_muted TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER announcement,
  ADD COLUMN invite_confirmation TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER all_muted;

CREATE TABLE wukong_channel_outbox (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  operation VARCHAR(32) NOT NULL,
  channel_id VARCHAR(128) NOT NULL,
  channel_type TINYINT UNSIGNED NOT NULL,
  payload_json JSON NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  next_attempt_at DATETIME(6) NOT NULL,
  locked_at DATETIME(6) NULL,
  lock_owner VARCHAR(100) NOT NULL DEFAULT '',
  last_error VARCHAR(1000) NOT NULL DEFAULT '',
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_wukong_channel_dispatch (status,next_attempt_at,id),
  KEY idx_wukong_channel (app_id,channel_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE wukong_channel_outbox;
ALTER TABLE chat_groups DROP COLUMN invite_confirmation, DROP COLUMN all_muted;
