ALTER TABLE `mr_otc_ad`
  ADD COLUMN `asset_hold_id` bigint unsigned NOT NULL DEFAULT 0 AFTER `deposit_reserved`,
  ADD COLUMN `fiat_hold_id` bigint unsigned NOT NULL DEFAULT 0 AFTER `asset_hold_id`,
  ADD COLUMN `escrow_remaining` decimal(30,8) NOT NULL DEFAULT 0.00000000 AFTER `fiat_hold_id`,
  ADD KEY `idx_otc_ad_asset_hold` (`asset_hold_id`),
  ADD KEY `idx_otc_ad_fiat_hold` (`fiat_hold_id`);

CREATE TABLE IF NOT EXISTS `mr_otc_ad_fiat_hold` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `merchant_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `ad_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `remaining_amount` decimal(18,2) NOT NULL,
  `status` tinyint unsigned NOT NULL DEFAULT 1 COMMENT '1冻结 2释放 3消费完 4部分消费',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_otc_ad_fiat_ad` (`appid`,`ad_id`),
  KEY `idx_otc_ad_fiat_user` (`appid`,`user_id`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='OTC买币广告平台余额托管';
