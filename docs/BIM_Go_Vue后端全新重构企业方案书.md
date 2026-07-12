# BIM Go + Vue 后端全新重构企业方案书

## 1. 最终结论

BIM 后端采用**停机式全新开发与一次性切换**，不再继续扩展 ThinkPHP 8。新系统使用一套 Go 代码仓库、一份 YAML 配置和一个发行包，统一承载业务 API、管理 API、实时 Gateway、Webhook、计划任务和异步 Worker；后台管理界面使用 Vue 3。

悟空 IM 和 LiveKit 保持为外部基础设施，由 BIM Go 后端统一配置、鉴权和调用，但不把其源码编译进 BIM 主进程。这样既满足业务系统与 Gateway 一套部署，也保留悟空 IM、LiveKit 独立升级和未来集群能力。

本次明确删除且不迁移：数字资产账户与流水、TRC20 地址与充值归集提币、TRON 钱包服务、GasFree、数字资产闪兑、OTC 商家与广告订单申诉保证金评价。

平台钱包继续保留：平台余额、账单、冻结、支付密码、收付款码、红包、转账、退款和支付服务号通知。

## 2. 现有系统审查

当前生产由 TP8、Go Gateway、Go TRON Wallet、悟空 IM、LiveKit、Redis 和 MySQL 组成。TP8 客户端 API 控制器约 19,000 行，包含约 224 个客户端动作；后台约 229 个动作；回调约 18 个；数据库约 108 张表。

当前主要问题是业务高度集中在超大控制器，协议、权限、事务和数据库实现相互耦合。因此禁止把 `Api.php` 按函数逐个翻译成一个新的 Go 大文件，新代码必须按领域重建。

## 3. 功能范围

### 3.1 必须保留

- 应用配置、版本、登录注册配置、图片/短信/邮箱验证码
- 用户名、手机号、邮箱、第三方登录、账号绑定和找回
- 用户资料、头像、背景图、账号安全、设备会话和设备互踢
- 好友申请、好友关系、非好友三句话、搜索和二维码加好友
- 群创建、成员、管理员、群主、禁言、公告、头像和解散
- 私聊、群聊、历史同步、清除、删除、撤回、引用、转发、收藏
- 文本、Emoji、表情、GIF、贴纸、语音、图片、视频、文件和名片
- 已读回执、群已读人数、ACK、Sequence、离线同步和跨端漫游
- 阅后即焚、红包、转账、领取/收款/退款回执
- 平台钱包、支付密码、冻结、账单、收付款码和商户权限
- 服务号、支付服务号、菜单、关注和免打扰
- 朋友圈、点赞、评论、可见范围、审核和后台管理
- LiveKit 一对一、群组音视频、会议和通话记录
- 论坛、帖子、评论、商城、订单、笔记、举报和审核
- 后台 RBAC、管理员、角色、权限、操作日志和安全审计
- 悟空 IM、LiveKit、支付和敏感词 Webhook

### 3.2 强制删除

新代码、Vue 菜单、YAML、数据库和发布包中不得出现：

- `wallet_asset_*`、`wallet_chain_*`
- `wallet_gasfree_*`、`wallet_sweep_*`、`wallet_exchange_*`
- `otc_*`
- TRON 私钥、助记词、TronGrid、GasFree 凭据
- `bim-tron-wallet.service`
- 链上充值、归集、提币和扫描回调

旧数字资产和 OTC 文档归档，不得继续出现在新系统运营手册。

## 4. 目标架构

采用**模块化单体 + 多角色进程**，不采用第一阶段微服务拆分。

同一二进制支持：

```text
bim-server serve --roles=api,admin,gateway,worker,scheduler
bim-server migrate
bim-server doctor
bim-server seed
bim-server jobs run <job-name>
```

单机阶段一个进程启动全部角色；后期扩容时仍使用同一发行包，将 API、Gateway、Worker 按角色部署到不同节点。

```text
Flutter / Web / 管理员浏览器
              |
          Nginx / TLS
              |
    +---------+----------+
    | BIM Go Server      |
    | Public/Admin API   |
    | HTTPS Stream       |
    | Webhook/Jobs       |
    +----+----------+----+
         |          |
      MySQL       Redis
         |          |
    悟空 IM       事件流/锁/限流
         |
      LiveKit
```

悟空 IM 负责消息基础路由、频道和序列号；BIM Go 负责好友权限、非好友限制、群权限、禁言、红包转账、回执、业务系统消息和审计。

## 5. 技术选型

- Go：实施时验证并固定稳定版本
- HTTP：`net/http` + `chi`
- MySQL 8：`go-sql-driver/mysql` + `sqlc`
- 数据迁移：`goose`
- Redis：`go-redis/v9`
- YAML：严格解析，环境变量或文件引用敏感值
- 日志：`slog` JSON，字段自动脱敏
- 监控：Prometheus + OpenTelemetry
- 契约：OpenAPI 3.1
- Vue：Vue 3 + TypeScript + Vite + Pinia + Vue Router
- 管理组件：统一 Design Tokens；可使用 Element Plus 基础组件
- 测试：Go testing、Testcontainers、Vitest、Vue Test Utils、Playwright、k6

当前服务器为 2 核、约 1.8 GiB 内存，不适合一开始引入 Kubernetes、Kafka和大量微服务。模块化单体更符合当前资源和运维能力。

## 6. Go 目录规范

```text
server/
  cmd/bim-server/main.go
  configs/config.example.yaml
  internal/
    bootstrap/
    platform/
      config/ database/ redis/ httpx/
      authn/ authz/ crypto/ audit/
      jobs/ observability/ storage/
    modules/
      appconfig/ identity/ user/ device/
      contact/ group/ messaging/ gateway/ presence/
      media/ sticker/ wallet/ payment/
      serviceaccount/ moments/ calls/
      content/ moderation/ notification/ admin/
    integrations/
      wukongim/ livekit/ sms/ email/ payment/ objectstorage/
    transport/
      publicapi/ adminapi/ webhook/ stream/
  migrations/
  queries/
  openapi/
  tests/
admin-web/
deploy/
docs/
```

每个领域模块统一包含：`domain.go`、`service.go`、`repository.go`、`repository_sql.go`、`handler.go`、`policy.go`、`events.go` 和测试。

禁止模块直接访问其他模块的表；跨模块通过服务接口或领域事件协作。Handler 不写业务规则，Service 不拼 SQL，Repository 不决定权限。

## 7. YAML 配置规范

```yaml
server:
  env: production
  public_url: https://example.com
  listen: 127.0.0.1:8080
  roles: [api, admin, gateway, worker, scheduler]
  shutdown_timeout: 15s

database:
  dsn: env://BIM_DATABASE_DSN
  max_open_conns: 80
  max_idle_conns: 20
  conn_max_lifetime: 30m

redis:
  mode: single
  addresses: [127.0.0.1:6379]
  password: env://BIM_REDIS_PASSWORD
  db: 0
  key_prefix: bim

security:
  token_signing_key: file:///etc/bim/secrets/token.key
  request_signing_key: file:///etc/bim/secrets/request.key
  field_encryption_key: file:///etc/bim/secrets/field.key
  allowed_clock_skew: 30s
  replay_window: 5m
  trusted_proxies: [127.0.0.1/32]

gateway:
  enabled: true
  path_prefix: /api/sync
  heartbeat_interval: 25s
  max_connections: 20000
  max_connections_per_ip: 3000
  queue_size: 1000
  stream_max_len: 10000
  ticket_single_use: true

wukongim:
  base_url: http://127.0.0.1:5001
  manager_token: env://BIM_WUKONG_MANAGER_TOKEN
  webhook_secret: env://BIM_WUKONG_WEBHOOK_SECRET
  channel_type_person: 1
  channel_type_group: 2

livekit:
  url: ws://127.0.0.1:7880
  api_key: env://BIM_LIVEKIT_API_KEY
  api_secret: env://BIM_LIVEKIT_API_SECRET
  webhook_secret: env://BIM_LIVEKIT_WEBHOOK_SECRET

storage:
  driver: local
  local:
    root: /var/lib/bim/uploads
  # 对外 API 根地址，不要追加 /uploads 或 /api。
  public_base_url: https://example.com

wallet:
  currency: CNY
  scale: 2
  payment_password_max_attempts: 3
  payment_password_lock: 30m

features:
  moments: true
  service_accounts: true
  platform_wallet: true
  digital_assets: false
  otc: false
```

YAML 中不得写生产密码、私钥和 Token。启动时严格校验必填项、URL、金额精度和密钥长度；未知字段直接报错，避免拼写错误静默失效。`doctor` 命令检查 MySQL、Redis、悟空 IM、LiveKit、存储和系统时钟。

## 8. 数据库重建

新系统建立独立数据库 `bim_v2`，不在旧表上继续开发。正式切换前执行一次性 ETL。

核心表按领域设计：

- 身份：users、user_credentials、user_profiles、device_sessions、verification_challenges
- 好友：friendships、friend_requests、user_blocks
- 群聊：groups、group_members、group_mutes、group_events
- 消息：message_outbox、message_receipts、message_visibility、conversation_settings
- 钱包：wallet_accounts、wallet_ledger、wallet_entries、wallet_holds、wallet_orders、wallet_risk_events
- 红包转账：red_packets、red_packet_receipts、transfers
- 服务号：service_accounts、service_account_users、service_account_menus、service_messages
- 朋友圈：moment_posts、moment_media、moment_likes、moment_comments、moment_visibility
- 通话：calls、call_participants、call_events
- 后台：admins、roles、permissions、admin_audit_logs
- 系统：app_configs、files、jobs、outbox_events、idempotency_keys、webhook_events

平台资金必须采用双重记账。任何余额变化都产生不可变 Ledger 和 Entry；禁止直接修改余额而没有流水。金额使用定点数或整数分，不使用浮点数。

数字资产、TRON、GasFree、闪兑和 OTC 表不进入 `bim_v2`。旧库只读归档，并从新应用数据库账号权限中移除。

### 8.1 数据迁移顺序

1. 配置、管理员、角色和权限。
2. 用户、资料、认证方式和设备状态。
3. 好友、群组、禁言和群配置。
4. 平台钱包余额、账单、冻结、红包和转账。
5. 服务号和通知。
6. 朋友圈、内容、商城和订单。
7. IM 业务索引、可见性、回执和会话设置。

消息正文仍以悟空 IM 和现有消息队列为事实来源，ETL 不伪造消息序列。迁移工具必须输出源数量、目标数量、校验和、差异明细，并支持重复执行。

## 9. API 与客户端兼容

虽然是全新开发，第一版仍保持 Flutter 当前 action 名、字段语义、device/timestamp/sign、加密请求和加密响应兼容，避免客户端与服务端同时大改。

- OpenAPI 定义规范资源接口。
- `publicapi/compat` 提供当前 `/api/:action` 适配层。
- 适配层只做字段映射，不承载业务逻辑。
- Vue 后台只调用 `/admin-api/v1/...`。
- Flutter 后续逐模块迁往 `/api/v2/...`，完成后删除兼容层。

建立黄金响应测试：从旧 TP8 生成脱敏请求/响应样本，新 Go 服务逐接口比较业务码、字段、金额、排序、权限和数据库副作用。

## 10. Gateway 合并

现有 Gateway 的以下能力迁入 `modules/gateway`：

- 单次 Ticket
- device、timestamp、nonce、sign 验证
- HTTPS Stream 长连接
- 心跳和假在线清理
- ACK、Sequence 和断线补拉
- Redis Stream 离线队列
- 跨节点通知和踢线
- 同账号同平台设备互踢
- 在线状态实时事件
- 总连接数、IP 连接数和发送队列限制

API 与 Gateway 共用同一个身份模块、设备会话仓储、审计日志、Redis 和 YAML，不再维护两套共享密钥身份逻辑。

长连接使用独立 HTTP Server，不配置普通 API 的短读取超时。慢客户端超过队列阈值后断开，并要求按 Sequence 补拉，禁止无限堆积内存。

## 11. 悟空 IM 与 LiveKit

- 所有消息发送必须先经过 Go 业务权限检查，客户端不得调用悟空管理 API。
- `client_msg_no` 唯一；同号同内容幂等，同号不同内容拒绝。
- CMD 设置 `SyncOnce=1`；系统消息类型大于 1000。
- Webhook 校验签名、时间戳、Nonce、重放窗口和事件幂等键。
- Webhook 先落 `webhook_events`，再异步处理；重复事件返回成功。
- 撤回、已读、红包、转账、禁言和群事件统一使用事件模型。
- LiveKit Token 只能由 Go 服务按真实参与者和权限签发。
- 通话创建、邀请、接听、拒绝、取消和挂断使用状态机，Webhook 不能越级改变终态。

## 12. Vue 管理后台

管理后台包含：工作台、用户与设备、好友与群聊、消息审计、禁言举报风控、平台钱包、红包转账、商户、服务号、朋友圈、LiveKit 通话、文件、应用配置、管理员权限、系统健康、任务、Webhook 和告警。

不得出现数字资产、GasFree、TRON 或 OTC 菜单、路由和 API。

权限使用 `resource:action`：

```text
user:read
user:update
wallet:freeze
wallet:unlock
group:mute
group:dissolve
message:audit
config:update
```

前端隐藏按钮不是权限控制。每个 Admin API 必须在服务端检查权限、应用范围、二次验证和审计原因。

高风险操作必须二次确认并填写原因：钱包冻结/解冻、余额调整、支付密码重置、用户封禁、群解散、聊天记录删除和安全配置变更。

## 13. 企业安全基线

### 13.1 身份和设备

- Access Token 短期有效，Refresh Token 旋转并可撤销。
- Token 绑定 app、user、platform、device 和 session version。
- 同账号同平台只允许一个活跃设备；跨平台由后台策略控制。
- 登录、绑定、找回和支付密码操作必须经过图形验证码与对应安全验证。
- 登录密码使用 Argon2id；支付密码使用独立盐、独立密钥域和独立锁定策略。

### 13.2 请求安全

- 生产强制 TLS；开发 HTTP 只能监听本机或受信网段。
- 敏感接口要求 device、timestamp、nonce、sign 和 request_id。
- Redis 保存 Nonce，防止重放。
- 限制请求体、上传大小、Header 数量、读取和写入超时。
- JSON 严格解码，拒绝未知字段和重复关键字段。
- SQL 全部参数化；排序字段使用白名单。
- CORS 只允许配置的客户端和后台域名。

### 13.3 资金安全

- 幂等键覆盖红包、转账、收付款、退款和后台余额操作。
- 余额检查、冻结、扣款、入账和流水在同一事务内完成。
- 行锁或条件更新防止超卖、重复领取和重复收款。
- 后台不能直接改余额，只能创建带原因、审核人和流水的调整单。
- 定时退款使用数据库抢占锁和幂等状态机。

### 13.4 文件安全

- MIME、扩展名和文件头三重验证。
- 随机对象键，不信任原文件名。
- 图片重编码；视频异步探测并生成封面。
- 上传目录禁止脚本执行。
- 私有文件使用短期签名 URL。

### 13.5 管理后台

- 管理员启用 MFA。
- Cookie 设置 Secure、HttpOnly 和 SameSite。
- 使用 CSRF Token、CSP、点击劫持保护和严格 CORS。
- 管理接口独立限流和 IP 策略。
- 审计日志只能追加，记录操作者、对象、前后值、原因、IP、设备和 Trace ID。

## 14. 测试体系

### 14.1 单元与集成测试

每个领域覆盖正常、边界、权限、并发、幂等、超时和失败补偿。资金和消息状态机分支覆盖率目标不低于 90%，其他核心模块不低于 80%。

使用 Testcontainers 启动 MySQL、Redis 和模拟第三方服务，验证真实事务、唯一键、锁、迁移和 Redis Stream。

### 14.2 契约测试

- Flutter 当前接口请求回放
- TP8 黄金响应与 Go 响应比较
- 悟空 IM API 与 Webhook 合约
- LiveKit Token 与 Webhook 合约
- 支付回调签名和重复通知

### 14.3 IM 双端真人测试

使用 A/B 两个真实账号验证：

- 前台、后台、离线、换设备和清除数据
- 文本连续发送、同内容、图片、视频、文件、语音、表情和贴纸
- 私聊、群聊、@、引用、撤回、删除、已读、未读和历史同步
- 非好友三句话、好友删除再添加
- 群加入时间边界、禁言、踢出、解散和群主转让
- 红包、转账、领取、过期退款和服务号通知
- Gateway 重连、ACK 丢失、重复帧、Sequence 断层和跨端漫游

### 14.4 压测

使用 k6 和 Go 长连接压测工具验证 API 热点、Gateway 连接数与心跳、Webhook 积压恢复、资金订单并发和慢消费者。发布报告必须包含 P50/P95/P99、错误率、内存、GC、连接数和数据库等待。

## 15. 停机式切换

允许停机不代表直接覆盖。正式切换按以下顺序：

1. 冻结 TP8 功能开发。
2. 完成 Go、Vue、迁移工具和全部测试。
3. 在独立测试域名完成真人验收。
4. 备份旧代码、数据库、上传文件、Redis 关键数据、悟空 IM 和 LiveKit 配置。
5. 开启维护模式，阻止登录、发消息、钱包操作和后台写入。
6. 等待钱包订单、红包、转账和回调完成或安全挂起。
7. 停止 TP8、旧 Gateway、旧定时任务和 TRON Wallet。
8. 执行最终数据库快照。
9. ETL 到 `bim_v2` 并输出校验报告。
10. 运行 `bim-server migrate`、`doctor` 和只读验收。
11. 启动 BIM Go Server 和 Vue 静态后台。
12. 修改 Nginx 上游，悟空 IM 和 LiveKit 指向新 Webhook。
13. 在维护模式内用 A/B 账号完成登录、私聊、群聊、钱包、朋友圈和通话冒烟测试。
14. 关闭维护模式并持续观察。

切换后若出现阻断级问题，重新进入维护模式，恢复旧数据库快照和 Nginx 上游。新系统开放写入后无法天然无损回滚，因此开放前冒烟测试必须全部通过。

## 16. 开发阶段

### 阶段 0：冻结契约和数据字典

- 导出全部 API、后台动作、表结构和配置。
- 标记保留、重写和删除。
- 建立 OpenAPI、错误码、事件类型和权限表。
- 建立 TP8 黄金测试数据。

### 阶段 1：基础平台

- Go 工程、YAML、日志、数据库、Redis、迁移、鉴权、RBAC 和审计。
- Vue 工程、Design Tokens、登录、路由和权限。
- CI、静态检查、单测和发行包。

### 阶段 2：账号、用户、配置和文件

- 登录注册、安全验证、设备会话、用户资料和上传。
- 应用配置和后台管理。

### 阶段 3：IM 核心与 Gateway

- 好友、群、消息权限、悟空 IM、历史、回执、Gateway 和在线状态。
- 完成双端实时测试和长连接压测。

### 阶段 4：平台钱包和支付业务

- 账本、支付密码、冻结、红包、转账、二维码和服务号通知。
- 完成并发、幂等和安全审计。

### 阶段 5：朋友圈、服务号、音视频和内容

- 朋友圈、服务号、LiveKit、论坛、商城、笔记、举报和审核。

### 阶段 6：后台完整化和数据迁移

- 所有可视化管理、审计、任务和系统健康。
- ETL、数量核对、抽样核对和性能优化。

### 阶段 7：停机切换

- 完整预演至少两次。
- 最终备份、ETL、冒烟测试、切流和观察。

## 17. 代码规范

- `gofmt`、`go vet`、`staticcheck` 和 `golangci-lint` 必须通过。
- 禁止使用 `panic` 处理普通业务错误。
- 错误使用领域错误码，并保留 `errors.Is/As` 链。
- 所有外部调用必须使用 Context、超时、重试边界和熔断策略。
- 只有幂等操作允许自动重试。
- 导出类型和复杂规则写中文注释；普通自解释代码不写废话注释。
- 日志不记录密码、Token、支付密码、验证码、完整手机号、完整邮箱和密钥。
- Vue 开启 TypeScript strict、ESLint 和 Prettier；禁止核心模型使用 `any`。
- API 模型由 OpenAPI 生成，不允许页面重复手写协议类型。
- 所有模块必须提供 README，说明职责、依赖、表、事件、错误码和测试方式。

## 18. 运维交付物

最终必须提供：

- 带中文注释的 `config.example.yaml`
- 单机部署傻瓜式中文教程
- Nginx、systemd、日志轮转配置
- MySQL、Redis、悟空 IM、LiveKit 配置教程
- 数据迁移与校验文档
- 备份、恢复、升级和回滚手册
- Vue 管理后台使用手册
- OpenAPI 文档和客户端调用示例
- Webhook 签名文档
- 告警与故障排查手册
- 安全基线和密钥轮换手册
- 压测报告和发布验收报告

## 19. 验收门槛

满足以下条件才允许切换：

- 保留功能全部有自动测试和真人测试记录。
- 删除功能在代码、路由、菜单、数据库和配置中均不可访问。
- 平台钱包总额、冻结额和流水借贷平衡完全一致。
- 好友、群成员、管理员、禁言和历史边界数量一致。
- A/B 实时消息、离线消息、换设备同步和回执全部通过。
- Gateway 压测无未受控内存增长、无 ACK 丢失、无重复业务入账。
- Webhook 重放、重复、乱序和签名失败测试通过。
- 管理后台越权、CSRF、XSS、SQL 注入和上传测试通过。
- 生产 YAML 不含明文密钥。
- `doctor`、迁移、备份恢复和停机预演全部通过。

## 20. 主要风险与控制

### 风险一：遗漏旧功能

控制：建立 224 个客户端动作、229 个后台动作和 18 个回调的功能矩阵，每一项必须标记为保留、替换或删除，并关联新接口和测试用例。

### 风险二：钱包账务不一致

控制：双重记账、迁移前后借贷平衡、用户余额总额核对、冻结总额核对、订单抽样和并发测试。任何差异都禁止开放服务。

### 风险三：即时消息在线正常、离线异常

控制：实时帧与服务端历史使用同一消息身份和 Sequence；缓存只负责显示，不是事实来源；测试前台、后台、断网、换设备和清除数据。

### 风险四：一体化进程相互影响

控制：API、Gateway、Worker 使用独立 Server、连接池、并发限制和健康状态；同一二进制可按角色拆进程，不形成代码耦合。

### 风险五：停机时间失控

控制：迁移脚本可重复执行，正式前至少两次全量预演；静态数据提前转换，停机窗口只处理最终增量和校验。

## 21. 最终决策

采用：

**Go 模块化单体 + Vue 3 管理后台 + 内置 Gateway + MySQL + Redis + 外部悟空 IM + 外部 LiveKit。**

不采用：

- 把旧 19,000 行控制器逐函数翻译成 Go。
- 第一阶段拆成大量微服务。
- 把悟空 IM 和 LiveKit 源码嵌入业务主进程。
- 保留数字资产、TRON、GasFree、闪兑和 OTC 的隐藏接口、表或菜单。
- 未完成数据校验和真实双端测试就直接切换生产。

该方案满足一套代码、一份 YAML、一套部署和未来横向扩展，同时把业务完整性、安全、平台资金一致性和即时通讯实时性作为重写的最高验收标准。
