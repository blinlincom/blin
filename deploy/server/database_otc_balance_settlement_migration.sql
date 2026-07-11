SET @sql = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_otc_config' AND COLUMN_NAME='payment_balance_enabled')=0,'ALTER TABLE mr_otc_config ADD payment_balance_enabled tinyint unsigned NOT NULL DEFAULT 1 AFTER manual_escrow','SELECT 1'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_otc_config' AND COLUMN_NAME='payment_alipay_enabled')=0,'ALTER TABLE mr_otc_config ADD payment_alipay_enabled tinyint unsigned NOT NULL DEFAULT 0 AFTER payment_balance_enabled','SELECT 1'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_otc_config' AND COLUMN_NAME='payment_wechat_enabled')=0,'ALTER TABLE mr_otc_config ADD payment_wechat_enabled tinyint unsigned NOT NULL DEFAULT 0 AFTER payment_alipay_enabled','SELECT 1'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql = IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='mr_otc_config' AND COLUMN_NAME='payment_bank_enabled')=0,'ALTER TABLE mr_otc_config ADD payment_bank_enabled tinyint unsigned NOT NULL DEFAULT 0 AFTER payment_wechat_enabled','SELECT 1'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

CREATE TABLE IF NOT EXISTS `mr_otc_fiat_hold` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `hold_no` varchar(48) NOT NULL,
  `order_no` varchar(40) NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `status` tinyint unsigned NOT NULL DEFAULT 1 COMMENT '1冻结 2释放 3消费',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `uk_otc_fiat_hold_no` (`hold_no`),
  UNIQUE KEY `uk_otc_fiat_order` (`appid`,`order_no`), KEY `idx_otc_fiat_user` (`appid`,`user_id`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='OTC平台余额托管';

UPDATE `mr_otc_config` SET `payment_balance_enabled`=1,`payment_alipay_enabled`=0,`payment_wechat_enabled`=0,`payment_bank_enabled`=0;
UPDATE `mr_otc_ad` SET `payment_methods`='balance',`version`=`version`+1,`update_time`=NOW() WHERE `status` IN (0,1);
