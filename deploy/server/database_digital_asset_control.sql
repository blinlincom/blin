CREATE TABLE IF NOT EXISTS `mr_wallet_asset_control` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `block_transfer` tinyint unsigned NOT NULL DEFAULT 0,
  `block_otc` tinyint unsigned NOT NULL DEFAULT 0,
  `block_withdraw` tinyint unsigned NOT NULL DEFAULT 0,
  `block_exchange` tinyint unsigned NOT NULL DEFAULT 0,
  `reason` varchar(255) NOT NULL DEFAULT '',
  `operator_id` int unsigned NOT NULL DEFAULT 0,
  `status` tinyint unsigned NOT NULL DEFAULT 1,
  `start_time` datetime DEFAULT NULL,
  `end_time` datetime DEFAULT NULL,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_asset` (`appid`,`user_id`,`asset_id`),
  KEY `idx_status_end` (`status`,`end_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mr_wallet_asset_hold_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `hold_id` bigint unsigned NOT NULL,
  `hold_no` varchar(40) NOT NULL,
  `action` varchar(24) NOT NULL,
  `amount` decimal(30,8) NOT NULL DEFAULT 0,
  `remaining_before` decimal(30,8) NOT NULL DEFAULT 0,
  `remaining_after` decimal(30,8) NOT NULL DEFAULT 0,
  `operator_type` varchar(16) NOT NULL DEFAULT 'system',
  `operator_id` bigint unsigned NOT NULL DEFAULT 0,
  `reason` varchar(255) NOT NULL DEFAULT '',
  `request_id` varchar(80) NOT NULL,
  `create_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_request` (`appid`,`request_id`),
  KEY `idx_hold` (`hold_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `mr_wallet_asset_hold`
  ADD COLUMN `original_amount` decimal(30,8) NOT NULL DEFAULT 0 AFTER `amount`,
  ADD COLUMN `remaining_amount` decimal(30,8) NOT NULL DEFAULT 0 AFTER `original_amount`,
  ADD COLUMN `reason` varchar(255) NOT NULL DEFAULT '' AFTER `status`,
  ADD COLUMN `operator_type` varchar(16) NOT NULL DEFAULT 'system' AFTER `reason`,
  ADD COLUMN `operator_id` bigint unsigned NOT NULL DEFAULT 0 AFTER `operator_type`,
  ADD COLUMN `request_id` varchar(80) NOT NULL DEFAULT '' AFTER `operator_id`,
  ADD COLUMN `expire_time` datetime DEFAULT NULL AFTER `request_id`,
  ADD COLUMN `released_time` datetime DEFAULT NULL AFTER `expire_time`,
  ADD COLUMN `consumed_time` datetime DEFAULT NULL AFTER `released_time`,
  ADD UNIQUE KEY `uk_hold_request` (`appid`,`request_id`);

UPDATE `mr_wallet_asset_hold`
SET `original_amount`=`amount`, `remaining_amount`=`amount`
WHERE `original_amount`=0 AND `amount`>0;
