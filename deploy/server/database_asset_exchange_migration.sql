CREATE TABLE IF NOT EXISTS `mr_wallet_exchange_config` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `source_asset_id` int unsigned NOT NULL,
  `target_type` varchar(24) NOT NULL DEFAULT 'platform_balance',
  `rate` decimal(30,8) NOT NULL DEFAULT 1.00000000,
  `fee_rate` decimal(10,6) NOT NULL DEFAULT 0.000000,
  `min_amount` decimal(30,8) NOT NULL DEFAULT 1.00000000,
  `max_amount` decimal(30,8) NOT NULL DEFAULT 10000.00000000,
  `daily_limit` decimal(30,8) NOT NULL DEFAULT 50000.00000000,
  `quote_ttl` int unsigned NOT NULL DEFAULT 60,
  `status` tinyint unsigned NOT NULL DEFAULT 0,
  `config_version` int unsigned NOT NULL DEFAULT 1,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_exchange_config` (`appid`,`source_asset_id`,`target_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数字资产闪兑配置';

CREATE TABLE IF NOT EXISTS `mr_wallet_exchange_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `order_no` varchar(48) NOT NULL,
  `request_id` varchar(80) NOT NULL,
  `quote_token` char(64) NOT NULL,
  `source_asset_id` int unsigned NOT NULL,
  `source_symbol` varchar(16) NOT NULL,
  `source_amount` decimal(30,8) NOT NULL,
  `rate` decimal(30,8) NOT NULL,
  `fee_rate` decimal(10,6) NOT NULL,
  `fee_amount` decimal(30,8) NOT NULL,
  `target_amount` decimal(18,2) NOT NULL,
  `config_version` int unsigned NOT NULL,
  `quote_expire_time` datetime NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'quoted',
  `param_hash` char(64) NOT NULL,
  `completed_time` datetime DEFAULT NULL,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_exchange_order_no` (`order_no`),
  UNIQUE KEY `uk_exchange_request` (`appid`,`user_id`,`request_id`),
  UNIQUE KEY `uk_exchange_quote` (`quote_token`), KEY `idx_exchange_user` (`appid`,`user_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='USDD闪兑平台余额订单';

INSERT INTO `mr_otc_asset` (`appid`,`symbol`,`name`,`precision_scale`,`status`,`sort`,`create_time`,`update_time`)
SELECT 900000002,'USDD','Decentralized USD',6,1,90,NOW(),NOW()
WHERE NOT EXISTS (SELECT 1 FROM `mr_otc_asset` WHERE `appid`=900000002 AND `symbol`='USDD');

INSERT INTO `mr_wallet_exchange_config` (`appid`,`source_asset_id`,`rate`,`fee_rate`,`min_amount`,`max_amount`,`daily_limit`,`quote_ttl`,`status`,`create_time`,`update_time`)
SELECT a.appid,a.id,7.00000000,0.000000,1.00000000,10000.00000000,50000.00000000,60,0,NOW(),NOW()
FROM `mr_otc_asset` a WHERE a.appid=900000002 AND a.symbol='USDD'
AND NOT EXISTS (SELECT 1 FROM `mr_wallet_exchange_config` c WHERE c.appid=a.appid AND c.source_asset_id=a.id);

SET @wallet_parent_id := (SELECT `id` FROM `mr_admin_permission` WHERE `url`='wallet' LIMIT 1);
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @wallet_parent_id,'闪兑管理','wallet/asset_exchange','',24,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_exchange');
