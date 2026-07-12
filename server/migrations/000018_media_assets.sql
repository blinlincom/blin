-- +goose Up
CREATE TABLE media_assets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  owner_id BIGINT UNSIGNED NOT NULL,
  object_key VARCHAR(191) NOT NULL,
  original_name VARCHAR(255) NOT NULL DEFAULT '',
  media_kind VARCHAR(20) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  size_bytes BIGINT UNSIGNED NOT NULL,
  sha256 CHAR(64) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ready',
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_media_object_key (object_key),
  KEY idx_media_owner (app_id,owner_id,id),
  CONSTRAINT fk_media_owner FOREIGN KEY (owner_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE media_access (
  asset_id BIGINT UNSIGNED NOT NULL,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  granted_at DATETIME(6) NOT NULL,
  PRIMARY KEY (asset_id,user_id),
  KEY idx_media_access_user (app_id,user_id,asset_id),
  CONSTRAINT fk_media_access_asset FOREIGN KEY (asset_id) REFERENCES media_assets(id),
  CONSTRAINT fk_media_access_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE media_access;
DROP TABLE media_assets;
