CREATE TABLE IF NOT EXISTS `bl_chat_private_receipt_setting` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `appid` int unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `peer_user_id` bigint unsigned NOT NULL,
  `enabled` tinyint unsigned NOT NULL DEFAULT '0',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_app_user_peer` (`appid`,`user_id`,`peer_user_id`),
  KEY `idx_peer` (`appid`,`peer_user_id`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='私聊会话回执设置';
