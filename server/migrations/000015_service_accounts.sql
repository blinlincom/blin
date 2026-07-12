-- +goose Up
CREATE TABLE service_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  code VARCHAR(64) NOT NULL,
  name VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(1000) NOT NULL DEFAULT '',
  description VARCHAR(500) NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  input_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0,
  menu_json JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_service_code (app_id,code),
  UNIQUE KEY uniq_service_user (app_id,user_id),
  CONSTRAINT fk_service_account_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_service_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  service_account_id BIGINT UNSIGNED NOT NULL,
  subscribed TINYINT UNSIGNED NOT NULL DEFAULT 1,
  muted TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_service_setting (app_id,user_id,service_account_id),
  CONSTRAINT fk_user_service_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_user_service_account FOREIGN KEY (service_account_id) REFERENCES service_accounts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO users(app_id,username,nickname,status,session_version,created_at,updated_at)
VALUES(1,'payment_service','支付通知',1,1,NOW(6),NOW(6));
INSERT INTO service_accounts(app_id,user_id,code,name,description,status,input_enabled,menu_json,created_at,updated_at)
SELECT 1,id,'payment','支付通知','钱包、红包、转账和收付款通知','active',0,JSON_ARRAY(),NOW(6),NOW(6)
FROM users WHERE app_id=1 AND username='payment_service';

-- +goose Down
DELETE FROM service_accounts WHERE app_id=1 AND code='payment';
DELETE FROM users WHERE app_id=1 AND username='payment_service';
DROP TABLE user_service_settings;
DROP TABLE service_accounts;
