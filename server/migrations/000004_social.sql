-- +goose Up
CREATE TABLE friend_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  requester_id BIGINT UNSIGNED NOT NULL,
  recipient_id BIGINT UNSIGNED NOT NULL,
  message VARCHAR(200) NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  handled_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_friend_request_recipient (app_id,recipient_id,status,created_at),
  KEY idx_friend_request_pair (app_id,requester_id,recipient_id,status),
  CONSTRAINT fk_friend_request_requester FOREIGN KEY (requester_id) REFERENCES users(id),
  CONSTRAINT fk_friend_request_recipient FOREIGN KEY (recipient_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE friendships (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  friend_id BIGINT UNSIGNED NOT NULL,
  remark VARCHAR(100) NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_friend_direction (app_id,user_id,friend_id),
  KEY idx_friend_list (app_id,user_id,status,friend_id),
  CONSTRAINT fk_friendship_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_friendship_friend FOREIGN KEY (friend_id) REFERENCES users(id),
  CONSTRAINT chk_friendship_not_self CHECK (user_id <> friend_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE chat_groups (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  channel_id VARCHAR(64) NOT NULL,
  name VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(1000) NOT NULL DEFAULT '',
  announcement TEXT NOT NULL,
  owner_id BIGINT UNSIGNED NOT NULL,
  join_history_policy VARCHAR(20) NOT NULL DEFAULT 'after_join',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  member_count INT UNSIGNED NOT NULL DEFAULT 1,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_group_channel (app_id,channel_id),
  KEY idx_group_owner (app_id,owner_id,status),
  CONSTRAINT fk_group_owner FOREIGN KEY (owner_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE group_members (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  group_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'member',
  group_nickname VARCHAR(100) NOT NULL DEFAULT '',
  muted_until DATETIME(6) NULL,
  joined_at DATETIME(6) NOT NULL,
  left_at DATETIME(6) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_group_member (group_id,user_id),
  KEY idx_member_groups (app_id,user_id,status,group_id),
  KEY idx_group_members (group_id,status,role,user_id),
  CONSTRAINT fk_group_member_group FOREIGN KEY (group_id) REFERENCES chat_groups(id),
  CONSTRAINT fk_group_member_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE group_members;
DROP TABLE chat_groups;
DROP TABLE friendships;
DROP TABLE friend_requests;
