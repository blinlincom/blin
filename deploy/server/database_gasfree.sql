CREATE TABLE IF NOT EXISTS `mr_wallet_gasfree_config` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `auto_enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `rollout_mode` varchar(16) NOT NULL DEFAULT 'off' COMMENT 'off whitelist all',
  `provider_address` varchar(64) NOT NULL DEFAULT '',
  `max_transfer_fee` decimal(30,8) NOT NULL DEFAULT 2.00000000,
  `max_first_fee` decimal(30,8) NOT NULL DEFAULT 4.00000000,
  `min_net_amount` decimal(30,8) NOT NULL DEFAULT 10.00000000,
  `max_fee_rate` decimal(8,4) NOT NULL DEFAULT 10.0000,
  `config_version` int unsigned NOT NULL DEFAULT 1,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_gasfree_config` (`appid`,`asset_id`,`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='GasFree运营配置';

CREATE TABLE IF NOT EXISTS `mr_wallet_gasfree_account` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `eoa_address` varchar(64) NOT NULL,
  `gasfree_address` varchar(64) NOT NULL,
  `provider_address` varchar(64) NOT NULL DEFAULT '',
  `token_address` varchar(64) NOT NULL DEFAULT '',
  `token_decimals` tinyint unsigned NOT NULL DEFAULT 6,
  `active` tinyint unsigned NOT NULL DEFAULT 0,
  `allow_submit` tinyint unsigned NOT NULL DEFAULT 0,
  `recommended_nonce` bigint unsigned NOT NULL DEFAULT 0,
  `onchain_balance` decimal(30,8) NOT NULL DEFAULT 0.00000000,
  `provider_frozen` decimal(30,8) NOT NULL DEFAULT 0.00000000,
  `status` tinyint unsigned NOT NULL DEFAULT 1,
  `last_sync_time` datetime DEFAULT NULL,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_gasfree_user` (`appid`,`user_id`,`asset_id`,`network_id`),
  UNIQUE KEY `uk_gasfree_address` (`gasfree_address`),
  KEY `idx_gasfree_eoa` (`eoa_address`,`provider_address`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户GasFree账户';

CREATE TABLE IF NOT EXISTS `mr_wallet_gasfree_transfer` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL, `request_id` varchar(80) NOT NULL, `sweep_no` varchar(48) NOT NULL,
  `account_id` bigint unsigned NOT NULL, `user_id` bigint unsigned NOT NULL, `asset_id` int unsigned NOT NULL, `network_id` int unsigned NOT NULL,
  `eoa_address` varchar(64) NOT NULL, `gasfree_address` varchar(64) NOT NULL, `provider_address` varchar(64) NOT NULL,
  `receiver_address` varchar(64) NOT NULL, `token_address` varchar(64) NOT NULL,
  `value` decimal(30,8) NOT NULL, `max_fee` decimal(30,8) NOT NULL,
  `estimated_activate_fee` decimal(30,8) NOT NULL DEFAULT 0.00000000, `estimated_transfer_fee` decimal(30,8) NOT NULL DEFAULT 0.00000000,
  `nonce` bigint unsigned NOT NULL, `deadline` bigint unsigned NOT NULL, `signature_hash` char(64) NOT NULL DEFAULT '',
  `trace_id` varchar(128) DEFAULT NULL, `state` varchar(24) NOT NULL DEFAULT 'queued', `txn_state` varchar(24) NOT NULL DEFAULT '', `txn_hash` varchar(128) NOT NULL DEFAULT '',
  `txn_amount` decimal(30,8) NOT NULL DEFAULT 0.00000000, `txn_total_fee` decimal(30,8) NOT NULL DEFAULT 0.00000000,
  `retry_count` int unsigned NOT NULL DEFAULT 0, `last_error` varchar(500) NOT NULL DEFAULT '', `lease_owner` varchar(80) NOT NULL DEFAULT '', `lease_until` datetime DEFAULT NULL,
  `submitted_time` datetime DEFAULT NULL, `confirmed_time` datetime DEFAULT NULL, `create_time` datetime NOT NULL, `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_gasfree_request` (`request_id`), UNIQUE KEY `uk_gasfree_sweep` (`sweep_no`), UNIQUE KEY `uk_gasfree_trace` (`trace_id`),
  KEY `idx_gasfree_task` (`state`,`lease_until`,`id`), KEY `idx_gasfree_account_task` (`account_id`,`state`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='GasFree归集任务';

ALTER TABLE `mr_wallet_gasfree_transfer` MODIFY `trace_id` varchar(128) DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `mr_wallet_gasfree_fee_snapshot` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT, `provider_address` varchar(64) NOT NULL, `token_address` varchar(64) NOT NULL,
  `symbol` varchar(20) NOT NULL DEFAULT 'USDT', `decimals` tinyint unsigned NOT NULL DEFAULT 6,
  `activate_fee` decimal(30,8) NOT NULL, `transfer_fee` decimal(30,8) NOT NULL, `supported` tinyint unsigned NOT NULL DEFAULT 1,
  `provider_config_json` json DEFAULT NULL, `fetched_time` datetime NOT NULL,
  PRIMARY KEY (`id`), KEY `idx_gasfree_fee` (`token_address`,`fetched_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='GasFree费率快照';

CREATE TABLE IF NOT EXISTS `mr_wallet_gasfree_whitelist` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT, `appid` int unsigned NOT NULL, `user_id` bigint unsigned NOT NULL,
  `status` tinyint unsigned NOT NULL DEFAULT 1, `operator_id` bigint unsigned NOT NULL DEFAULT 0, `create_time` datetime NOT NULL, `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_gasfree_whitelist` (`appid`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='GasFree灰度白名单';

SET @sql=IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_wallet_chain_address' AND COLUMN_NAME='address_type')=0,'ALTER TABLE mr_wallet_chain_address ADD address_type varchar(16) NOT NULL DEFAULT "eoa", ADD display_priority int NOT NULL DEFAULT 0, ADD accept_deposit tinyint unsigned NOT NULL DEFAULT 1, ADD gasfree_account_id bigint unsigned NOT NULL DEFAULT 0','SELECT 1'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

INSERT INTO mr_wallet_gasfree_config(appid,asset_id,network_id,create_time,update_time)
SELECT c.appid,c.asset_id,c.network_id,NOW(),NOW() FROM mr_wallet_chain_config c
WHERE NOT EXISTS(SELECT 1 FROM mr_wallet_gasfree_config g WHERE g.appid=c.appid AND g.asset_id=c.asset_id AND g.network_id=c.network_id);
SET @wallet_parent_id := (SELECT id FROM mr_admin_permission WHERE url='wallet' LIMIT 1);
INSERT INTO mr_admin_permission(pid,name,url,icon,sort,is_out,is_menu)
SELECT @wallet_parent_id,'GasFree管理','wallet/gasfree','mdi mdi-gas-station',4,2,1
WHERE NOT EXISTS(SELECT 1 FROM mr_admin_permission WHERE url='wallet/gasfree');
