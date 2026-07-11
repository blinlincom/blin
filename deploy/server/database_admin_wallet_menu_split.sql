UPDATE `mr_admin_permission` SET `name`='平台钱包',`url`='wallet',`icon`='mdi mdi-wallet',`sort`=10 WHERE `id`=171;
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT 0,'数字钱包','digital_wallet','mdi mdi-currency-usd',11,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='digital_wallet');
SET @digital_pid=(SELECT id FROM `mr_admin_permission` WHERE url='digital_wallet' LIMIT 1);
UPDATE `mr_admin_permission` SET `pid`=@digital_pid WHERE `id` IN (194,195,196,197,198,199,200,201);
UPDATE `mr_admin_permission` SET `pid`=0,`name`='OTC管理',`icon`='mdi mdi-swap-horizontal-bold',`sort`=12 WHERE `id`=188;
UPDATE `mr_admin_permission` SET `pid`=188 WHERE `id` IN (189,190,191,192,193);
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @digital_pid,'数字资产冻结','wallet/asset_holds','mdi mdi-snowflake',5,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_holds');
INSERT INTO `mr_admin_permission` (`pid`,`name`,`url`,`icon`,`sort`,`is_out`,`is_menu`)
SELECT @digital_pid,'数字资产管控','wallet/asset_controls','mdi mdi-shield-lock-outline',6,2,1
WHERE NOT EXISTS (SELECT 1 FROM `mr_admin_permission` WHERE `url`='wallet/asset_controls');
UPDATE `mr_admin_permission` SET `sort`=1 WHERE `id`=194;
UPDATE `mr_admin_permission` SET `sort`=2 WHERE `id`=201;
UPDATE `mr_admin_permission` SET `sort`=3 WHERE `id`=195;
UPDATE `mr_admin_permission` SET `sort`=4 WHERE `id`=199;
UPDATE `mr_admin_permission` SET `sort`=7 WHERE `id`=196;
UPDATE `mr_admin_permission` SET `sort`=8 WHERE `id`=197;
UPDATE `mr_admin_permission` SET `sort`=9 WHERE `id`=200;
UPDATE `mr_admin_permission` SET `sort`=10 WHERE `id`=198;
