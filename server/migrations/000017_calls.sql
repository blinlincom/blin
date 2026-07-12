-- +goose Up
CREATE TABLE call_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  call_no VARCHAR(64) NOT NULL,
  room_name VARCHAR(128) NOT NULL,
  initiator_id BIGINT UNSIGNED NOT NULL,
  conversation_channel_id VARCHAR(128) NOT NULL,
  conversation_channel_type TINYINT UNSIGNED NOT NULL,
  call_type VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ringing',
  started_at DATETIME(6) NULL,
  ended_at DATETIME(6) NULL,
  end_reason VARCHAR(50) NOT NULL DEFAULT '',
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_call_no (app_id,call_no),
  UNIQUE KEY uniq_call_room (room_name),
  KEY idx_call_status (app_id,status,created_at),
  KEY idx_call_initiator (app_id,initiator_id,created_at),
  CONSTRAINT fk_call_initiator FOREIGN KEY (initiator_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE call_participants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  call_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'invitee',
  status VARCHAR(20) NOT NULL DEFAULT 'invited',
  joined_at DATETIME(6) NULL,
  left_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_call_participant (call_id,user_id),
  KEY idx_call_user_status (app_id,user_id,status,updated_at),
  CONSTRAINT fk_call_participant_call FOREIGN KEY (call_id) REFERENCES call_sessions(id),
  CONSTRAINT fk_call_participant_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE call_participants;
DROP TABLE call_sessions;
