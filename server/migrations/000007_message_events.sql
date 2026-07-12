-- +goose Up
CREATE TABLE message_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  event_id VARCHAR(128) NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  message_id BIGINT UNSIGNED NOT NULL,
  actor_id BIGINT UNSIGNED NOT NULL,
  payload_json JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_message_event (app_id,event_id),
  KEY idx_message_events_target (message_id,event_type,created_at),
  CONSTRAINT fk_message_event_message FOREIGN KEY (message_id) REFERENCES messages(id),
  CONSTRAINT fk_message_event_actor FOREIGN KEY (actor_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE messages ADD COLUMN recalled_at DATETIME(6) NULL AFTER sent_at;

-- +goose Down
ALTER TABLE messages DROP COLUMN recalled_at;
DROP TABLE message_events;
