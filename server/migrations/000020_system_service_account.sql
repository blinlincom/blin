-- +goose Up
INSERT INTO users(app_id,username,nickname,status,session_version,created_at,updated_at)
VALUES(1,'system_notice','系统通知',1,1,NOW(6),NOW(6));
INSERT INTO service_accounts(app_id,user_id,code,name,description,status,input_enabled,menu_json,created_at,updated_at)
SELECT 1,id,'system','系统通知','账号、群聊和安全通知','active',0,JSON_ARRAY(),NOW(6),NOW(6)
FROM users WHERE app_id=1 AND username='system_notice';

-- +goose Down
DELETE FROM service_accounts WHERE app_id=1 AND code='system';
DELETE FROM users WHERE app_id=1 AND username='system_notice';
