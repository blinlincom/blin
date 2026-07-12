-- +goose Up
ALTER TABLE users ADD COLUMN avatar_asset_id BIGINT UNSIGNED NULL AFTER avatar_url, ADD COLUMN background_asset_id BIGINT UNSIGNED NULL AFTER profile_background_url, ADD CONSTRAINT fk_user_avatar_asset FOREIGN KEY (avatar_asset_id) REFERENCES media_assets(id), ADD CONSTRAINT fk_user_background_asset FOREIGN KEY (background_asset_id) REFERENCES media_assets(id);
ALTER TABLE chat_groups ADD COLUMN avatar_asset_id BIGINT UNSIGNED NULL AFTER avatar_url, ADD CONSTRAINT fk_group_avatar_asset FOREIGN KEY (avatar_asset_id) REFERENCES media_assets(id);
ALTER TABLE service_accounts ADD COLUMN avatar_asset_id BIGINT UNSIGNED NULL AFTER avatar_url, ADD CONSTRAINT fk_service_avatar_asset FOREIGN KEY (avatar_asset_id) REFERENCES media_assets(id);

-- +goose Down
ALTER TABLE service_accounts DROP FOREIGN KEY fk_service_avatar_asset, DROP COLUMN avatar_asset_id;
ALTER TABLE chat_groups DROP FOREIGN KEY fk_group_avatar_asset, DROP COLUMN avatar_asset_id;
ALTER TABLE users DROP FOREIGN KEY fk_user_background_asset, DROP FOREIGN KEY fk_user_avatar_asset, DROP COLUMN background_asset_id, DROP COLUMN avatar_asset_id;
