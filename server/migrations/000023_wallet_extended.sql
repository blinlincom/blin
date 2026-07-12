-- +goose Up
CREATE TABLE wallet_collect_codes (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,app_id BIGINT UNSIGNED NOT NULL,user_id BIGINT UNSIGNED NOT NULL,public_token CHAR(64) NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'active',created_at DATETIME(6) NOT NULL,updated_at DATETIME(6) NOT NULL,
 PRIMARY KEY(id),UNIQUE KEY uniq_collect_user(app_id,user_id),UNIQUE KEY uniq_collect_token(public_token),CONSTRAINT fk_collect_user FOREIGN KEY(user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE wallet_pay_codes (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,app_id BIGINT UNSIGNED NOT NULL,user_id BIGINT UNSIGNED NOT NULL,token_hash CHAR(64) NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'active',expires_at DATETIME(6) NOT NULL,used_at DATETIME(6) NULL,created_at DATETIME(6) NOT NULL,
 PRIMARY KEY(id),UNIQUE KEY uniq_pay_hash(token_hash),KEY idx_pay_user(app_id,user_id,status,expires_at),CONSTRAINT fk_pay_code_user FOREIGN KEY(user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE wallet_withdrawals (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,app_id BIGINT UNSIGNED NOT NULL,order_no VARCHAR(64) NOT NULL,user_id BIGINT UNSIGNED NOT NULL,amount BIGINT NOT NULL,method VARCHAR(30) NOT NULL,account_masked VARCHAR(100) NOT NULL,account_encrypted TEXT NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'pending',review_reason VARCHAR(500) NOT NULL DEFAULT '',created_at DATETIME(6) NOT NULL,updated_at DATETIME(6) NOT NULL,
 PRIMARY KEY(id),UNIQUE KEY uniq_withdrawal_no(order_no),KEY idx_withdrawal_user(app_id,user_id,id),KEY idx_withdrawal_review(app_id,status,id),CONSTRAINT fk_withdrawal_user FOREIGN KEY(user_id) REFERENCES users(id),CONSTRAINT chk_withdrawal_amount CHECK(amount>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE merchant_profiles (app_id BIGINT UNSIGNED NOT NULL,user_id BIGINT UNSIGNED NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'pending',review_reason VARCHAR(500) NOT NULL DEFAULT '',created_at DATETIME(6) NOT NULL,updated_at DATETIME(6) NOT NULL,PRIMARY KEY(app_id,user_id),CONSTRAINT fk_merchant_user FOREIGN KEY(user_id) REFERENCES users(id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE wallet_qr_orders (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,app_id BIGINT UNSIGNED NOT NULL,order_no VARCHAR(64) NOT NULL,payer_id BIGINT UNSIGNED NOT NULL,payee_id BIGINT UNSIGNED NOT NULL,merchant_id BIGINT UNSIGNED NULL,amount BIGINT NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'pending',expires_at DATETIME(6) NOT NULL,created_at DATETIME(6) NOT NULL,updated_at DATETIME(6) NOT NULL,PRIMARY KEY(id),UNIQUE KEY uniq_qr_order(order_no),KEY idx_qr_payer(app_id,payer_id,status,id),CONSTRAINT fk_qr_payer FOREIGN KEY(payer_id) REFERENCES users(id),CONSTRAINT fk_qr_payee FOREIGN KEY(payee_id) REFERENCES users(id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- +goose Down
DROP TABLE wallet_qr_orders; DROP TABLE merchant_profiles; DROP TABLE wallet_withdrawals; DROP TABLE wallet_pay_codes; DROP TABLE wallet_collect_codes;
