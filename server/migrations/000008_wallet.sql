-- +goose Up
CREATE TABLE wallet_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  available_amount BIGINT NOT NULL DEFAULT 0,
  frozen_amount BIGINT NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  lock_reason VARCHAR(500) NOT NULL DEFAULT '',
  version BIGINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_wallet_user_currency (app_id,user_id,currency),
  CONSTRAINT fk_wallet_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT chk_wallet_available CHECK (available_amount >= 0),
  CONSTRAINT chk_wallet_frozen CHECK (frozen_amount >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_credentials (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
  locked_until DATETIME(6) NULL,
  updated_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_wallet_credential (app_id,user_id),
  CONSTRAINT fk_wallet_credential_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  transaction_no VARCHAR(64) NOT NULL,
  transaction_type VARCHAR(50) NOT NULL,
  reference_type VARCHAR(50) NOT NULL,
  reference_id VARCHAR(64) NOT NULL,
  status VARCHAR(20) NOT NULL,
  amount BIGINT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  metadata_json JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_wallet_transaction_no (app_id,transaction_no),
  KEY idx_wallet_reference (app_id,reference_type,reference_id),
  CONSTRAINT chk_wallet_transaction_amount CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_entries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  transaction_id BIGINT UNSIGNED NOT NULL,
  account_id BIGINT UNSIGNED NOT NULL,
  entry_type VARCHAR(20) NOT NULL,
  amount BIGINT NOT NULL,
  balance_after BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_wallet_entries_account (account_id,id),
  KEY idx_wallet_entries_transaction (transaction_id,id),
  CONSTRAINT fk_wallet_entry_transaction FOREIGN KEY (transaction_id) REFERENCES wallet_transactions(id),
  CONSTRAINT fk_wallet_entry_account FOREIGN KEY (account_id) REFERENCES wallet_accounts(id),
  CONSTRAINT chk_wallet_entry_amount CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_transfers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  order_no VARCHAR(64) NOT NULL,
  sender_id BIGINT UNSIGNED NOT NULL,
  recipient_id BIGINT UNSIGNED NOT NULL,
  group_id BIGINT UNSIGNED NULL,
  amount BIGINT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  expires_at DATETIME(6) NOT NULL,
  accepted_at DATETIME(6) NULL,
  refunded_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_wallet_transfer_order (app_id,order_no),
  KEY idx_wallet_transfer_recipient (app_id,recipient_id,status,created_at),
  CONSTRAINT fk_transfer_sender FOREIGN KEY (sender_id) REFERENCES users(id),
  CONSTRAINT fk_transfer_recipient FOREIGN KEY (recipient_id) REFERENCES users(id),
  CONSTRAINT chk_transfer_amount CHECK (amount > 0),
  CONSTRAINT chk_transfer_not_self CHECK (sender_id <> recipient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_red_packets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  order_no VARCHAR(64) NOT NULL,
  sender_id BIGINT UNSIGNED NOT NULL,
  channel_id VARCHAR(128) NOT NULL,
  channel_type TINYINT UNSIGNED NOT NULL,
  packet_type VARCHAR(20) NOT NULL,
  designated_user_id BIGINT UNSIGNED NULL,
  total_amount BIGINT NOT NULL,
  total_count INT UNSIGNED NOT NULL,
  remaining_amount BIGINT NOT NULL,
  remaining_count INT UNSIGNED NOT NULL,
  greeting VARCHAR(100) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  expires_at DATETIME(6) NOT NULL,
  refunded_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_red_packet_order (app_id,order_no),
  KEY idx_red_packet_expire (status,expires_at,id),
  CONSTRAINT fk_red_packet_sender FOREIGN KEY (sender_id) REFERENCES users(id),
  CONSTRAINT chk_red_packet_amount CHECK (total_amount > 0 AND remaining_amount >= 0),
  CONSTRAINT chk_red_packet_count CHECK (total_count > 0 AND remaining_count >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wallet_red_packet_claims (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  app_id BIGINT UNSIGNED NOT NULL,
  red_packet_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  amount BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_red_packet_claim (red_packet_id,user_id),
  CONSTRAINT fk_red_packet_claim_packet FOREIGN KEY (red_packet_id) REFERENCES wallet_red_packets(id),
  CONSTRAINT fk_red_packet_claim_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT chk_red_packet_claim_amount CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- +goose Down
DROP TABLE wallet_red_packet_claims;
DROP TABLE wallet_red_packets;
DROP TABLE wallet_transfers;
DROP TABLE wallet_entries;
DROP TABLE wallet_transactions;
DROP TABLE wallet_credentials;
DROP TABLE wallet_accounts;
