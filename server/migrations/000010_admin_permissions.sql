-- +goose Up
INSERT INTO permissions(code,name,created_at) VALUES
('dashboard:read','查看工作台',NOW(6)),
('user:read','查看用户',NOW(6)),('user:write','管理用户',NOW(6)),
('group:read','查看好友与群聊',NOW(6)),('group:write','管理群聊',NOW(6)),
('message:audit','审计消息',NOW(6)),('message:delete','删除消息',NOW(6)),
('wallet:read','查看钱包',NOW(6)),('wallet:control','管控钱包',NOW(6)),
('service_account:read','查看服务号',NOW(6)),('service_account:write','管理服务号',NOW(6)),
('moment:read','查看朋友圈',NOW(6)),('moment:moderate','审核朋友圈',NOW(6)),
('call:read','查看通话记录',NOW(6)),('moderation:read','查看内容审核',NOW(6)),
('moderation:write','执行内容审核',NOW(6)),('config:read','查看系统配置',NOW(6)),
('config:write','修改系统配置',NOW(6)),('audit:read','查看审计日志',NOW(6));

INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r CROSS JOIN permissions p WHERE r.code='super_admin';

-- +goose Down
DELETE rp FROM role_permissions rp JOIN roles r ON r.id=rp.role_id WHERE r.code='super_admin';
DELETE FROM permissions;
