# BIM Go + Vue 可交付部署与切换手册

## 1. 交付范围

本版本由一个 Go 服务统一提供用户 API、管理 API、实时 Gateway、任务 Worker、定时任务和回调入口，Vue 3 管理后台作为静态文件部署。数字资产、TRON、GasFree、闪兑和 OTC 已从新后端能力清单删除且配置层禁止开启。

保留业务包括：账号与设备、验证码、好友、群聊、私聊、消息历史与回执、红包、转账、平台钱包、扫码收付款、提现、服务号、朋友圈、音视频、媒体、内容社区、商品订单、便签、贴纸商店、应用市场、用户成长、后台审核与审计。

## 2. 目录

- `server/`：Go 服务与全新数据库迁移；不包含旧库导入器。
- `admin-web/`：Vue 3 管理后台。
- `deploy/go-vue/`：Nginx 与 systemd 模板。
- `server/configs/config.example.yaml`：完整 YAML 示例。
- `server/openapi/API接口清单.md`：客户端和后台接口入口。

## 3. 首次部署

1. 安装 MySQL 5.7+/8.0、Redis 6+、WuKongIM、LiveKit、Nginx。
2. 创建 `/opt/bim-server`、`/etc/bim/secrets`、`/var/lib/bim/uploads`，运行用户设为 `www`。
3. 生成三个独立 32 字节以上密钥：`token.key`、`request.key`、`field.key`。权限必须为 `600`。
4. 复制并修改 `config.example.yaml`。所有生产密钥使用 `env://` 或 `file://`，不要写入 YAML。
5. 执行 `bim-server doctor --config /etc/bim/config.yaml`。
6. 执行 `bim-server migrate --config /etc/bim/config.yaml`。
7. 本项目按全新产品初始化，不读取 `mr_` 旧业务表。
8. 使用密码文件创建超级管理员：`bim-server admin-create --config /etc/bim/config.yaml --username admin --password-file /root/admin-password`。
9. 将 `admin-web/dist` 放入 `/opt/bim-server/admin-web`，安装 systemd 和 Nginx 配置。
10. LiveKit webhook 设置为 `https://域名/callbacks/v1/livekit`。
11. WuKongIM 原生 webhook 设置为 `https://域名/callbacks/v1/wukong/{高强度路径密钥}`，事件参数由 WuKongIM 自动追加为 `?event=msg.notify` 等。

## 4. 停机切换

1. 备份数据库和旧程序，确认新库迁移状态。
2. 进入维护窗口，停止旧 TP8 写请求和旧 Gateway，不停止 MySQL、Redis、WuKongIM、LiveKit。
3. 检查 `migrate --status` 全部为 `applied=true`。
4. 启动 `bim-server.service`，检查 `/health/live` 与 `/health/ready`。
5. 修改 Nginx，将 `/api/`、`/admin-api/`、`/api/sync/`、`/callbacks/` 指向 Go 服务。
6. 完成注册登录、好友、单聊、群聊、钱包、红包、音视频、管理后台抽样后解除维护。

## 5. 当前生产部署

- 域名：`https://blcold.cn`
- Go 服务：`bim-server.service`，监听 `127.0.0.1:8080`
- Vue 后台：`https://blcold.cn/admin/`
- 配置：`/etc/bim/config.yaml`
- 密钥：`/etc/bim/secrets/`
- 上传目录：`/var/lib/bim/uploads`
- 管理员初始密码文件：`/root/bim-admin-password`
- 切换备份位置：服务器 `/root/bim-last-hardcut-backup` 文件所指目录
- 旧 `bim-gateway.service`、`bim-tron-wallet.service` 已禁用并停止；Nginx 不再加载 PHP 或旧站点目录。

生产数据库仍位于原 `blin` schema，但新服务只使用无前缀新表；`mr_*` 旧表不被任何 Go 查询引用，仅作为停机备份保留。

## 6. 回滚

保留旧程序目录和切换前数据库物理备份。回滚只恢复 Nginx 上游和旧服务进程；新表不与 `mr_` 表冲突，不需要在紧急回滚时删除。切勿在无备份情况下执行迁移 Down 或手工删除新表。

## 7. 安全要求

- 外网只开放 443；MySQL、Redis、WuKongIM 管理 API、LiveKit 管理端口仅内网访问。
- Gateway 生产只允许明确 Origin，连接票据单次使用。
- 业务 webhook 使用签名、时间窗和防重放；WuKongIM 原生 webhook 使用 32 字节以上路径密钥、TLS、事件白名单和请求体上限；LiveKit 使用官方 JWT 校验。
- 支付密码三次错误锁定；付款码 60 秒且一次性；商户扫描后仍需付款方二次确认。
- 提现账户使用 AES-GCM 字段加密，后台列表只展示掩码。
- 所有后台管控必须填写原因并写入审计日志。

## 8. 验收命令

```bash
make check
bim-server doctor --config /etc/bim/config.yaml
bim-server migrate --status --config /etc/bim/config.yaml
curl -fsS https://域名/health/ready
```

上线前还需执行并保存：数据库备份恢复演练、500/1000/5000 长连接阶梯压测、消息发送与 ACK 压测、钱包并发扣款测试、Webhook 重放测试和权限越权测试。
