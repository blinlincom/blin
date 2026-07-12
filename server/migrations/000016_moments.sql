-- +goose Up
CREATE TABLE moments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  content VARCHAR(2000) NOT NULL DEFAULT '',
  media_json JSON NOT NULL,
  visibility VARCHAR(20) NOT NULL DEFAULT 'friends',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  review_reason VARCHAR(500) NOT NULL DEFAULT '',
  reviewed_by BIGINT UNSIGNED NULL,
  reviewed_at DATETIME(6) NULL,
  deleted_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_moment_feed (app_id,status,deleted_at,id),
  KEY idx_moment_user (app_id,user_id,deleted_at,id),
  CONSTRAINT fk_moment_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE moment_likes (
  moment_id BIGINT UNSIGNED NOT NULL,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (moment_id,user_id),
  KEY idx_moment_like_user (app_id,user_id,created_at),
  CONSTRAINT fk_moment_like_moment FOREIGN KEY (moment_id) REFERENCES moments(id),
  CONSTRAINT fk_moment_like_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE moment_comments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  moment_id BIGINT UNSIGNED NOT NULL,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  reply_to_user_id BIGINT UNSIGNED NULL,
  content VARCHAR(500) NOT NULL,
  deleted_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_moment_comment (moment_id,deleted_at,id),
  CONSTRAINT fk_moment_comment_moment FOREIGN KEY (moment_id) REFERENCES moments(id),
  CONSTRAINT fk_moment_comment_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE applications SET config_json=JSON_MERGE_PATCH(config_json,JSON_OBJECT('moments_review_mode','manual')),updated_at=NOW(6) WHERE id=1;

-- +goose Down
DROP TABLE moment_comments;
DROP TABLE moment_likes;
DROP TABLE moments;
