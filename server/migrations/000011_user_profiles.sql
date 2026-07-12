-- +goose Up
ALTER TABLE users
  ADD COLUMN bio VARCHAR(300) NOT NULL DEFAULT '' AFTER profile_background_url,
  ADD COLUMN gender TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER bio,
  ADD COLUMN region VARCHAR(100) NOT NULL DEFAULT '' AFTER gender;

CREATE TABLE user_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  read_receipts_enabled TINYINT UNSIGNED NOT NULL DEFAULT 1,
  history_sync_enabled TINYINT UNSIGNED NOT NULL DEFAULT 1,
  burn_after_read_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0,
  new_message_sound_enabled TINYINT UNSIGNED NOT NULL DEFAULT 1,
  moments_visible TINYINT UNSIGNED NOT NULL DEFAULT 1,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_settings (app_id,user_id),
  CONSTRAINT fk_user_settings_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE user_settings;
ALTER TABLE users DROP COLUMN region,DROP COLUMN gender,DROP COLUMN bio;
