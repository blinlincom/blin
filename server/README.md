# BIM Go Server

这是 BIM 正式 Go 后端工程。生产环境由该进程统一承载用户 API、管理 API、实时 Gateway、Worker、Scheduler 和回调入口；TP8 与独立 Gateway 已退出生产流量。

## 本地检查

```bash
cd server
GOPROXY=https://goproxy.cn,direct go mod download
go test ./...
go build ./cmd/bim-server
```

## 配置检查

复制 `configs/config.example.yaml`，将敏感值配置为环境变量或密钥文件后执行：

```bash
./bim-server doctor --config configs/config.yaml
```

数字资产和 OTC 已从新系统范围删除，配置校验会拒绝开启这两个功能。

## 生产入口

- 用户 API：`/api/v2/`
- 管理 API：`/admin-api/v1/`
- 实时连接：`/api/sync/connect`
- WuKongIM 回调：`/callbacks/v1/wukong/{secret}`
- LiveKit 回调：`/callbacks/v1/livekit`
- 健康检查：`/health/live`、`/health/ready`

生产配置位于 `/etc/bim/config.yaml`，密钥位于 `/etc/bim/secrets/`。超级管理员初始密码只保存在服务器 `/root/bim-admin-password`，文件权限为 `600`。
