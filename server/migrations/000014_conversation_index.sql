-- +goose Up
CREATE TABLE user_conversations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  channel_id VARCHAR(128) NOT NULL,
  channel_type TINYINT UNSIGNED NOT NULL,
  last_message_id BIGINT UNSIGNED NOT NULL,
  unread_count INT UNSIGNED NOT NULL DEFAULT 0,
  hidden_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_conversation (app_id,user_id,channel_id,channel_type),
  KEY idx_user_conversation_activity (app_id,user_id,hidden_at,updated_at,last_message_id),
  CONSTRAINT fk_user_conversation_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_user_conversation_message FOREIGN KEY (last_message_id) REFERENCES messages(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE user_conversations;
