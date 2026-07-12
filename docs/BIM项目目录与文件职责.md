# BIM 项目目录与文件职责

## 根目录

- `lib/`：Flutter 多端客户端业务代码。
- `server/`：正式 Go 后端，统一承载 API、Gateway、Worker、Scheduler 与 webhook。
- `admin-web/`：Vue 3 管理后台。
- `deploy/go-vue/`：Nginx 和 systemd 部署模板。
- `docs/`：产品、接口、部署、安全和客户端说明。
- `.github/workflows/`：持续集成与发布流程。
- `Makefile`：本地统一检查、构建入口。

## Go 后端

- `server/cmd/bim-server/main.go`：`serve`、`doctor`、`migrate`、`admin-create` 命令入口。
- `server/configs/config.example.yaml`：完整 YAML 配置示例。
- `server/internal/bootstrap/`：依赖装配、总路由、进程关闭与健康检查。
- `server/internal/platform/`：配置、数据库、Redis、鉴权、HTTP 信封、日志、幂等和 webhook 安全基础设施。
- `server/internal/integration/wukong/`：WuKongIM HTTP API 客户端与频道操作分发。
- `server/internal/modules/identity/`：注册、登录、设备会话、Token 与账号安全。
- `server/internal/modules/userprofile/`：用户资料、头像和资料背景。
- `server/internal/modules/social/`：搜索用户、好友申请、联系人、群聊、成员、角色和禁言。
- `server/internal/modules/messaging/`：消息协议、去重、发送队列、历史、会话、回执、撤回与阅后即焚。
- `server/internal/modules/messagingwebhook/`：业务 HMAC 回调与 WuKongIM 原生 webhook 适配。
- `server/internal/modules/gateway/`：WSS 票据、连接生命周期、心跳、ACK、Redis Stream 和实时事件分发。
- `server/internal/modules/media/`：受控上传、媒体授权和签名访问。
- `server/internal/modules/wallet/`：平台余额、支付密码、红包、转账、账单、收付款码和提现。
- `server/internal/modules/serviceaccount/`：支付通知、系统通知等服务号。
- `server/internal/modules/moments/`：朋友圈发布、可见性、评论、点赞和媒体访问授权。
- `server/internal/modules/calls/`：LiveKit 房间令牌、通话状态和回调。
- `server/internal/modules/admin*`：后台登录、配置、用户/群聊/消息/钱包/朋友圈/审计管理。
- `server/internal/transport/`：用户 API、后台 API、回调 API 和实时连接的顶层路由。
- `server/migrations/`：按版本顺序执行的全新数据库结构和初始化数据。
- `server/openapi/`：新接口清单与契约约束。

## Vue 后台

- `admin-web/src/api/client.ts`：管理 API、Token 刷新和统一错误处理。
- `admin-web/src/app/`：后台壳层与应用入口。
- `admin-web/src/router/`：路由与登录守卫。
- `admin-web/src/stores/auth.ts`：管理员会话状态。
- `admin-web/src/modules/navigation.ts`：侧边导航定义。
- `admin-web/src/design/`：后台 Design Tokens 与通用页面样式。
- `admin-web/src/views/`：仪表盘、用户、群聊、消息、钱包、朋友圈、服务号、通话、配置和审计页面。

## 生产服务器

- `/opt/bim-server/bim-server`：Go 可执行文件。
- `/opt/bim-server/admin-web/`：Vue 后台静态文件。
- `/etc/bim/config.yaml`：非敏感生产配置和密钥文件引用。
- `/etc/bim/secrets/`：数据库、Token、字段加密、WuKongIM、LiveKit 等密钥。
- `/var/lib/bim/uploads/`：上传对象。
- `/etc/systemd/system/bim-server.service`：进程守护配置。
- `/www/server/panel/vhost/nginx/blcold.cn.conf`：TLS、API 与后台入口。

数字资产、TRON、GasFree、闪兑和 OTC 已从交付范围删除；旧 TP8 文件不是新系统组成部分，新代码不得引用 `mr_*` 表或旧 action 路由。
