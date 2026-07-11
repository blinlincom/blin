CREATE TABLE IF NOT EXISTS `mr_wallet_sweep_config` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `target_address` varchar(64) NOT NULL DEFAULT '',
  `resource_address` varchar(64) NOT NULL DEFAULT '',
  `min_sweep_amount` decimal(30,8) NOT NULL DEFAULT 10.00000000,
  `auto_enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `signing_enabled` tinyint unsigned NOT NULL DEFAULT 0,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_sweep_config` (`appid`,`asset_id`,`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='TRON自动归集配置';

CREATE TABLE IF NOT EXISTS `mr_wallet_sweep_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `sweep_no` varchar(48) NOT NULL,
  `appid` int unsigned NOT NULL,
  `address_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `asset_id` int unsigned NOT NULL,
  `network_id` int unsigned NOT NULL,
  `from_address` varchar(64) NOT NULL,
  `to_address` varchar(64) NOT NULL,
  `amount` decimal(30,8) NOT NULL,
  `status` varchar(24) NOT NULL DEFAULT 'queued',
  `txid` varchar(128) NOT NULL DEFAULT '',
  `retry_count` int unsigned NOT NULL DEFAULT 0,
  `last_error` varchar(500) NOT NULL DEFAULT '',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_sweep_no` (`sweep_no`),
  KEY `idx_sweep_status` (`appid`,`status`,`id`),
  KEY `idx_sweep_address` (`address_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='TRON归集订单';

INSERT INTO `mr_wallet_sweep_config` (`appid`,`asset_id`,`network_id`,`create_time`,`update_time`)
SELECT c.appid,c.asset_id,c.network_id,NOW(),NOW()
FROM `mr_wallet_chain_config` c
WHERE NOT EXISTS (
  SELECT 1 FROM `mr_wallet_sweep_config` s
  WHERE s.appid=c.appid AND s.asset_id=c.asset_id AND s.network_id=c.network_id
);

SET @wallet_parent_id := (SELECT id FROM mr_admin_permission WHERE url='wallet' LIMIT 1);
INSERT INTO mr_admin_permission(pid,name,url,icon,sort,is_out,is_menu)
SELECT @wallet_parent_id,'链上充值流水','wallet/deposit_events','mdi mdi-format-list-bulleted',2,2,1
WHERE NOT EXISTS(SELECT 1 FROM mr_admin_permission WHERE url='wallet/deposit_events');
INSERT INTO mr_admin_permission(pid,name,url,icon,sort,is_out,is_menu)
SELECT @wallet_parent_id,'自动归集管理','wallet/sweep_management','mdi mdi-bank-transfer',3,2,1
WHERE NOT EXISTS(SELECT 1 FROM mr_admin_permission WHERE url='wallet/sweep_management');
