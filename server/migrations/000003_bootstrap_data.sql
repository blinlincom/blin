-- +goose Up
INSERT INTO applications(id,name,status,config_json,created_at,updated_at)
VALUES(1,'BIM',1,JSON_OBJECT(),NOW(6),NOW(6));

INSERT INTO roles(code,name,created_at) VALUES
('super_admin','超级管理员',NOW(6)),
('operations','运营管理员',NOW(6)),
('support','客服管理员',NOW(6)),
('finance','财务管理员',NOW(6)),
('auditor','审计员',NOW(6));

-- +goose Down
DELETE FROM roles WHERE code IN ('super_admin','operations','support','finance','auditor');
DELETE FROM applications WHERE id=1;
