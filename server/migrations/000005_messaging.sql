-- +goose Up
CREATE TABLE messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  client_msg_no VARCHAR(64) NOT NULL,
  message_id VARCHAR(64) NULL,
  message_seq BIGINT UNSIGNED NOT NULL DEFAULT 0,
  channel_id VARCHAR(128) NOT NULL,
  channel_type TINYINT UNSIGNED NOT NULL,
  sender_id BIGINT UNSIGNED NOT NULL,
  content_type INT UNSIGNED NOT NULL,
  payload_json JSON NOT NULL,
  payload_hash CHAR(64) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'queued',
  sent_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_message_client_no (app_id,client_msg_no),
  UNIQUE KEY uniq_message_remote_id (app_id,message_id),
  KEY idx_message_channel_seq (app_id,channel_id,channel_type,message_seq),
  KEY idx_message_sender_time (app_id,sender_id,created_at),
  CONSTRAINT fk_message_sender FOREIGN KEY (sender_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE message_outbox (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  message_id BIGINT UNSIGNED NOT NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  next_attempt_at DATETIME(6) NOT NULL,
  locked_at DATETIME(6) NULL,
  lock_owner VARCHAR(100) NOT NULL DEFAULT '',
  last_error VARCHAR(1000) NOT NULL DEFAULT '',
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_outbox_message (message_id),
  KEY idx_outbox_dispatch (status,next_attempt_at,id),
  CONSTRAINT fk_outbox_message FOREIGN KEY (message_id) REFERENCES messages(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_message_states (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  message_id BIGINT UNSIGNED NOT NULL,
  hidden_at DATETIME(6) NULL,
  burned_at DATETIME(6) NULL,
  read_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_message_state (app_id,user_id,message_id),
  KEY idx_user_message_visibility (app_id,user_id,hidden_at,burned_at,message_id),
  CONSTRAINT fk_user_message_state_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_user_message_state_message FOREIGN KEY (message_id) REFERENCES messages(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE conversation_states (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  channel_id VARCHAR(128) NOT NULL,
  channel_type TINYINT UNSIGNED NOT NULL,
  clear_before_seq BIGINT UNSIGNED NOT NULL DEFAULT 0,
  last_read_seq BIGINT UNSIGNED NOT NULL DEFAULT 0,
  pinned_at DATETIME(6) NULL,
  muted TINYINT UNSIGNED NOT NULL DEFAULT 0,
  hidden_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_conversation_user_channel (app_id,user_id,channel_id,channel_type),
  KEY idx_conversation_user_updated (app_id,user_id,updated_at),
  CONSTRAINT fk_conversation_state_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE conversation_states;
DROP TABLE user_message_states;
DROP TABLE message_outbox;
DROP TABLE messages;
