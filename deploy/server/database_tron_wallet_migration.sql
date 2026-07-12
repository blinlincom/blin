SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `mr_wallet_chain_config` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `contract_address` varchar(64) NOT NULL DEFAULT '',
  `decimals` tinyint unsigned NOT NULL DEFAULT 6,
  `deposit_enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `withdraw_enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `transfer_enabled` tinyint unsigned NOT NULL DEFAULT 1,
  `min_deposit` decimal(30,8) NOT NULL DEFAULT '1.00000000',
  `min_withdraw` decimal(30,8) NOT NULL DEFAULT '10.00000000',
  `withdraw_fee` decimal(30,8) NOT NULL DEFAULT '1.00000000',
  `daily_withdraw_limit` decimal(30,8) NOT NULL DEFAULT '10000.00000000',
  `wallet_service_url` varchar(255) NOT NULL DEFAULT '',
  `status` tinyint unsigned NOT NULL DEFAULT 0,
  `config_version` int unsigned NOT NULL DEFAULT 1,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_app_asset_network` (`appid`,`asset_id`,`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='TRON链钱包配置';

CREATE TABLE IF NOT EXISTS `mr_wallet_chain_address` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `address_base58` varchar(64) NOT NULL,
  `address_hex` varchar(64) NOT NULL DEFAULT '',
  `derivation_index` bigint unsigned NOT NULL,
  `derivation_path` varchar(120) NOT NULL DEFAULT '',
  `status` tinyint unsigned NOT NULL DEFAULT 1,
  `assigned_time` datetime NOT NULL,
  `last_deposit_time` datetime DEFAULT NULL,
  `last_sweep_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_asset_network` (`appid`,`user_id`,`asset_id`,`network_id`),
  UNIQUE KEY `uk_address` (`address_base58`),
  UNIQUE KEY `uk_derivation_index` (`appid`,`network_id`,`derivation_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户链上充值地址';

CREATE TABLE IF NOT EXISTS `mr_wallet_asset_journal` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `journal_no` varchar(48) NOT NULL,
  `request_id` varchar(80) NOT NULL,
  `business_type` varchar(32) NOT NULL,
  `business_no` varchar(48) NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `status` tinyint unsigned NOT NULL DEFAULT 1,
  `param_hash` char(64) NOT NULL,
  `create_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_journal_no` (`journal_no`),
  UNIQUE KEY `uk_request` (`appid`,`request_id`),
  UNIQUE KEY `uk_business` (`appid`,`business_type`,`business_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数字资产复式记账主表';

CREATE TABLE IF NOT EXISTS `mr_wallet_asset_entry` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `journal_id` bigint unsigned NOT NULL,
  `account_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `direction` varchar(8) NOT NULL,
  `available_delta` decimal(30,8) NOT NULL DEFAULT '0.00000000',
  `frozen_delta` decimal(30,8) NOT NULL DEFAULT '0.00000000',
  `available_after` decimal(30,8) NOT NULL,
  `frozen_after` decimal(30,8) NOT NULL,
  `remark` varchar(255) NOT NULL DEFAULT '',
  `create_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_journal` (`journal_id`),
  KEY `idx_user_account` (`user_id`,`account_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数字资产复式记账分录';

CREATE TABLE IF NOT EXISTS `mr_wallet_asset_transfer` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `transfer_no` varchar(48) NOT NULL,
  `request_id` varchar(80) NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `sender_id` bigint unsigned NOT NULL,
  `receiver_id` bigint unsigned NOT NULL,
  `amount` decimal(30,8) NOT NULL,
  `remark` varchar(120) NOT NULL DEFAULT '',
  `status` varchar(24) NOT NULL DEFAULT 'success',
  `create_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_transfer_no` (`transfer_no`),
  UNIQUE KEY `uk_request` (`appid`,`sender_id`,`request_id`),
  KEY `idx_receiver` (`appid`,`receiver_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='USDT站内转账';

CREATE TABLE IF NOT EXISTS `mr_wallet_withdraw_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `withdraw_no` varchar(48) NOT NULL,
  `request_id` varchar(80) NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `to_address` varchar(64) NOT NULL,
  `amount` decimal(30,8) NOT NULL,
  `fee` decimal(30,8) NOT NULL,
  `receive_amount` decimal(30,8) NOT NULL,
  `status` varchar(24) NOT NULL DEFAULT 'risk_review',
  `risk_level` tinyint unsigned NOT NULL DEFAULT 0,
  `risk_reason` varchar(255) NOT NULL DEFAULT '',
  `review_admin_id` bigint unsigned NOT NULL DEFAULT 0,
  `txid` varchar(128) NOT NULL DEFAULT '',
  `config_version` int unsigned NOT NULL DEFAULT 1,
  `version` int unsigned NOT NULL DEFAULT 1,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_withdraw_no` (`withdraw_no`),
  UNIQUE KEY `uk_request` (`appid`,`user_id`,`request_id`),
  KEY `idx_status` (`appid`,`status`,`id`),
  KEY `idx_user` (`appid`,`user_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='USDT链上提币订单';

CREATE TABLE IF NOT EXISTS `mr_wallet_chain_event` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `network_id` int unsigned NOT NULL,
  `contract_address` varchar(64) NOT NULL,
  `block_number` bigint unsigned NOT NULL,
  `block_hash` varchar(128) NOT NULL DEFAULT '',
  `txid` varchar(128) NOT NULL,
  `log_index` int unsigned NOT NULL,
  `from_address` varchar(64) NOT NULL,
  `to_address` varchar(64) NOT NULL,
  `amount` decimal(30,8) NOT NULL,
  `solidified` tinyint unsigned NOT NULL DEFAULT 0,
  `execute_success` tinyint unsigned NOT NULL DEFAULT 0,
  `process_status` varchar(24) NOT NULL DEFAULT 'detected',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_chain_event` (`network_id`,`contract_address`,`txid`,`log_index`),
  KEY `idx_to_status` (`to_address`,`process_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='TRC20链事件';

CREATE TABLE IF NOT EXISTS `mr_wallet_chain_cursor` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `network_id` int unsigned NOT NULL,
  `cursor_name` varchar(32) NOT NULL DEFAULT 'deposit',
  `last_scanned_block` bigint unsigned NOT NULL DEFAULT 0,
  `last_solid_block` bigint unsigned NOT NULL DEFAULT 0,
  `lease_owner` varchar(80) NOT NULL DEFAULT '',
  `lease_until` datetime DEFAULT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_network_cursor` (`network_id`,`cursor_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='TRON扫描游标';

SET @wallet_parent_id := (SELECT `id` FROM `mr_admin_permission` WHERE `url`='wallet' LIMIT 1);
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @wallet_parent_id,'数字资产账户','wallet/asset_accounts','',20,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_accounts');
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @wallet_parent_id,'链上充值地址','wallet/chain_addresses','',21,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/chain_addresses');
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @wallet_parent_id,'USDT提币订单','wallet/asset_withdrawals','',22,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_withdrawals');
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @wallet_parent_id,'链上钱包配置','wallet/asset_chain_config','',23,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_chain_config');
