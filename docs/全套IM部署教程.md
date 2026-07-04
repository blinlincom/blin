# BIM 全套 IM 部署教程

这份文档按“照着做就能跑”的方式写，覆盖四个部分：

- TP8 业务 API：登录、注册、好友、群聊、红包、转账、发送消息、历史消息。
- 悟空 IM：底层消息存储、频道、webhook、在线状态。
- BIM Gateway：客户端唯一实时长连接入口，负责消息实时推送和 ACK 游标。
- Flutter 客户端：只调用业务 API 和 Gateway，不直连悟空 WSS/WS/TCP。

## 1. 当前线上结论

当前线上服务器已具备运行条件：

```text
业务端目录：/www/wwwroot/blin
悟空 IM 目录：/www/wwwroot/wkim
Gateway 目录：/www/wwwroot/bim_gateway
Redis：127.0.0.1:6379
业务 API：https://blcold.cn/api/
Gateway health：https://blcold.cn/api/sync/health
Gateway open：https://blcold.cn/api/sync/open
悟空 API：https://blcold.cn/im-api
悟空 WS 代理：https://blcold.cn/im-ws
```

已确认：

```text
redis.service       active
wukongim.service   active
bim-gateway.service active
https://blcold.cn/api/sync/health 返回 code=1 且 redis=ok
```

客户端能正常运行的前置条件：

- 登录或 `im_connect` 必须返回 `route.https_stream_addr`、`stream.ticket`、`stream.expire_in`、`stream.last_cursor`。
- `GATEWAY_SECRET` 必须和 `BIM_GATEWAY_SECRET` 完全一致。
- 悟空 webhook 必须能回调业务端 `/callback/chat/webhook/{WEBHOOK_SECRET}`。
- 业务端 webhook 必须能把消息写进 Redis Stream。
- Nginx `/api/sync/` 必须关闭缓冲，否则长连接会卡住。

如果这些条件都满足，当前客户端会走 Gateway HTTPS Stream 实时收消息；不会再走旧 WSS/WS/TCP。

## 2. 架构图

```text
Flutter 客户端
  |-- HTTPS 表单/API 请求 --> TP8 业务端 /api/*
  |-- HTTPS Stream -------> BIM Gateway /api/sync/open

TP8 业务端
  |-- 发送消息/建群/好友/红包/转账 --> 悟空 IM HTTP API
  |-- webhook 接收悟空事件
  |-- 写 Redis Stream：im:deliver:{uid}

BIM Gateway
  |-- 读 Redis Stream：im:deliver:{uid}
  |-- 推送 frame 给客户端
  |-- 保存 ACK：im:ack:{uid}:{device}

悟空 IM
  |-- 存储消息
  |-- 推送 msg.notify/msg.offline/user.onlinestatus webhook
```

## 3. 客户端现在怎么跑

客户端启动后：

1. 调业务端登录接口，登录成功后再调用加密 `im_connect`。
2. 业务端调用悟空 `/user/token` 更新用户 token。
3. 业务端生成 Gateway 不透明 ticket，并把 claims/frame_key 写入 Redis。
4. 客户端拿到：

```json
{
  "chat": {
    "uid": "app900000002user1",
    "route": {
      "https_stream_addr": "https://blcold.cn/api/sync/open"
    },
    "stream": {
      "ticket": "bgt_开头的不透明短期票据",
      "frame_key": "Base64 32字节AES-GCM密钥",
      "frame_alg": "AES-256-GCM",
      "expire_in": 120,
      "last_cursor": "0-0"
    }
  }
}
```

5. 客户端打开：

```http
POST https://blcold.cn/api/sync/open
Content-Type: application/json

{
  "ticket": "im_connect返回的stream.ticket",
  "last_cursor": "本地ACK游标或stream.last_cursor"
}
```

6. Gateway 返回持续不断的二进制流：

```text
4字节大端长度 + JSON secure envelope
```

外层只能看到：

```json
{"type":"secure","alg":"AES-256-GCM","nonce":"base64","ciphertext":"base64"}
```

7. 客户端用 `stream.frame_key` 解密 envelope，得到 message/heartbeat/kick/error frame；收到消息后先写 MMKV，本地落库成功才调用：

```http
POST https://blcold.cn/api/sync/ack
Content-Type: application/json

{
  "ticket": "有效ticket",
  "last_cursor": "最新frame.cursor",
  "client_msg_nos": ["消息client_msg_no"]
}
```

ACK 是串行队列，不并发推进 cursor。某条 ACK 失败后，客户端会断开并重连，用旧 cursor 补偿，避免漏消息。

## 4. 新服务器部署前准备

建议系统：

```text
CentOS / Rocky / AlmaLinux / Ubuntu 均可
CPU：2核起
内存：4GB起
磁盘：40GB起
开放端口：80、443
内部端口：5001、5100、5200、8787、6379 不要直接暴露公网
```

必备软件：

```bash
nginx
php 8.0+
mysql 5.7/8.0
redis
go 1.22+
composer
```

当前宝塔结构示例：

```text
/www/wwwroot/blin          TP8业务端
/www/wwwroot/wkim          悟空IM
/www/wwwroot/bim_gateway   Gateway
```

## 5. Redis 部署

安装并启动：

```bash
yum -y install redis || dnf -y install redis || apt -y install redis-server
systemctl enable --now redis
redis-cli ping
```

正常返回：

```text
PONG
```

生产建议：

```bash
systemctl status redis --no-pager
redis-cli info memory
```

如果 Redis 设置了密码，后面两个地方都要配置同一个密码：

- `/www/wwwroot/bim_gateway/.env`
- `/www/wwwroot/blin/.env`

业务端 Redis Stream 写入代码已支持 Redis AUTH：

- Redis 无密码：`GATEWAY_REDIS_USERNAME` 和 `GATEWAY_REDIS_PASSWORD` 留空。
- Redis 仅密码：`GATEWAY_REDIS_PASSWORD=你的密码`。
- Redis ACL：`GATEWAY_REDIS_USERNAME=用户名`，`GATEWAY_REDIS_PASSWORD=密码`。

Gateway `.env` 的 `BIM_REDIS_USERNAME/BIM_REDIS_PASSWORD` 必须和业务端一致。

## 6. 悟空 IM 部署

当前线上目录：

```bash
cd /www/wwwroot/wkim
```

服务文件：

```bash
systemctl cat wukongim.service
```

当前启动命令：

```text
/www/wwwroot/wkim/main --config /www/wwwroot/wkim/config/wk.yaml --noStdout
```

配置文件：

```bash
/www/wwwroot/wkim/config/wk.yaml
```

推荐配置模板：

```yaml
mode: "release"
rootDir: "/www/wwwroot/wkim/wukongimdata"

external:
  ip: "你的服务器公网IP"
  wsAddr: "ws://你的服务器公网IP:5200"
  wssAddr: "wss://你的域名/im-ws"
  apiUrl: "https://你的域名/im-api"

webhook:
  httpAddr: "https://你的域名/callback/chat/webhook/你的WEBHOOK_SECRET"
  msgNotifyEventPushInterval: "500ms"
  msgNotifyEventRetryMaxCount: 5
  msgNotifyEventCountPerPush: 100
  focusEvents:
    - "msg.offline"
    - "msg.notify"
    - "user.onlinestatus"

manager:
  on: true

demo:
  on: true
```

说明：

- `apiUrl` 给业务端和调试使用。
- 客户端不再直连 `wssAddr`，但悟空自身 route 和调试仍可能用到。
- `webhook.httpAddr` 必须是业务端回调地址，并带路径 secret。
- `focusEvents` 必须包含 `msg.offline` 和 `msg.notify`，否则 Gateway 收不到消息事件。

创建 systemd：

```bash
cat >/etc/systemd/system/wukongim.service <<'EOF'
[Unit]
Description=WuKongIM Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/www/wwwroot/wkim
Environment=HOME=/root
Environment=USER=root
ExecStart=/www/wwwroot/wkim/main --config /www/wwwroot/wkim/config/wk.yaml --noStdout
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wukongim
systemctl status wukongim --no-pager
```

验证悟空 API：

```bash
curl -sS http://127.0.0.1:5001/route?intranet=0
curl -sS https://你的域名/im-api/route?intranet=0
```

如果公网 `/im-api/route` 不通，先修 Nginx 反代。

## 7. Gateway 部署

目录：

```bash
cd /www/wwwroot/bim_gateway
```

构建：

```bash
go test ./...
go build -o bim-gateway ./cmd/gateway
```

配置文件：

```bash
/www/wwwroot/bim_gateway/.env
```

模板：

```ini
BIM_GATEWAY_ADDR=127.0.0.1:8787
BIM_GATEWAY_NODE_ID=gateway-1
BIM_GATEWAY_PUBLIC_BASE_URL=https://你的域名/api/sync
BIM_GATEWAY_SECRET=用 openssl rand -hex 32 生成
BIM_GATEWAY_METRICS_TOKEN=用 openssl rand -hex 16 生成
BIM_GATEWAY_HEARTBEAT_SECONDS=25
BIM_GATEWAY_MAX_QUEUE_SIZE=1000
BIM_GATEWAY_MAX_CATCHUP=500
BIM_GATEWAY_MAX_CONNECTIONS=20000
BIM_GATEWAY_MAX_CONNECTIONS_PER_IP=3000
BIM_GATEWAY_TICKET_SINGLE_USE=true
BIM_GATEWAY_CLOCK_SKEW_SECONDS=30

BIM_REDIS_ADDR=127.0.0.1:6379
BIM_REDIS_USERNAME=
BIM_REDIS_PASSWORD=
BIM_REDIS_DB=0
BIM_REDIS_MODE=single
BIM_REDIS_STREAM_PREFIX=im
BIM_REDIS_POOL_SIZE=200
BIM_REDIS_MIN_IDLE_CONNS=20
BIM_REDIS_STREAM_MAX_LEN=10000
```

生成密钥：

```bash
openssl rand -hex 32
```

注意：

- `BIM_GATEWAY_SECRET` 必须和业务端 `.env` 的 `GATEWAY_SECRET` 一致。
- `BIM_GATEWAY_ADDR` 建议只监听 `127.0.0.1:8787`，不要直接暴露公网。
- `BIM_REDIS_STREAM_PREFIX` 必须和业务端 `GATEWAY_REDIS_PREFIX` 一致，当前是 `im`。

创建 systemd：

```bash
cat >/etc/systemd/system/bim-gateway.service <<'EOF'
[Unit]
Description=BIM HTTPS Stream Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/www/wwwroot/bim_gateway
EnvironmentFile=/www/wwwroot/bim_gateway/.env
ExecStart=/www/wwwroot/bim_gateway/bim-gateway
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now bim-gateway
systemctl status bim-gateway --no-pager
```

验证：

```bash
curl -sS http://127.0.0.1:8787/api/sync/health
curl -sS https://你的域名/api/sync/health
```

正常返回：

```json
{"code":1,"redis":"ok","node_id":"gateway-1"}
```

## 8. TP8 业务端配置

目录：

```bash
cd /www/wwwroot/blin
```

关键文件：

```text
/www/wwwroot/blin/.env
/www/wwwroot/blin/config/wukongim.php
/www/wwwroot/blin/app/common/tool/WukongIM.php
/www/wwwroot/blin/app/common/support/GatewayStream.php
/www/wwwroot/blin/app/callback/controller/Wkim.php
```

`.env` 的 `[WUKONGIM]` 段模板：

```ini
[WUKONGIM]
PUBLIC_TLS = true
PUBLIC_HOST = 你的域名
PUBLIC_API_PATH = /im-api
PUBLIC_WS_PATH = /im-ws
PUBLIC_API_URL = https://你的域名/im-api
PUBLIC_WS_URL = wss://你的域名/im-ws
PUBLIC_TCP_ADDR =

WEBHOOK_SECRET = 用 openssl rand -hex 32 生成
WEBHOOK_REQUIRE_SECRET = true
WEBHOOK_ALLOWED_IPS = 127.0.0.1,::1,你的服务器公网IP
WEBHOOK_REQUIRE_HTTPS = true
WEBHOOK_REQUIRE_SIGNATURE = false
WEBHOOK_SIGNATURE_WINDOW = 300
WEBHOOK_MAX_BODY_BYTES = 2097152

GATEWAY_ENABLED = true
GATEWAY_PUBLIC_STREAM_ADDR = https://你的域名/api/sync/open
GATEWAY_SECRET = 必须和 BIM_GATEWAY_SECRET 一致
GATEWAY_TICKET_TTL = 120
GATEWAY_REDIS_HOST = 127.0.0.1
GATEWAY_REDIS_PORT = 6379
GATEWAY_REDIS_TIMEOUT = 0.5
GATEWAY_REDIS_PREFIX = im
GATEWAY_REDIS_STREAM_MAX_LEN = 10000
```

没有 HTTPS 的客户环境：

```ini
PUBLIC_TLS = false
PUBLIC_API_URL = http://你的域名/im-api
PUBLIC_WS_URL = ws://你的域名/im-ws
WEBHOOK_REQUIRE_HTTPS = false
GATEWAY_PUBLIC_STREAM_ADDR = http://你的域名/api/sync/open
```

客户端会自动使用业务端返回的 `http://.../api/sync/open`，但正式生产建议必须上 HTTPS。

修改业务端 `.env` 后清缓存：

```bash
cd /www/wwwroot/blin
rm -rf runtime/cache/* runtime/temp/*
```

## 9. Nginx 配置

主站点 root 指向：

```text
/www/wwwroot/blin/public
```

当前宝塔扩展配置目录：

```text
/www/server/panel/vhost/nginx/extension/你的域名/
```

### 9.1 Gateway 反向代理

文件：

```bash
/www/server/panel/vhost/nginx/extension/你的域名/gateway_proxy.conf
```

内容：

```nginx
location = /api/sync/metrics {
    allow 127.0.0.1;
    deny all;
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location /api/sync/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_connect_timeout 10s;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

必须保留：

```nginx
proxy_buffering off;
proxy_cache off;
proxy_read_timeout 3600s;
```

否则客户端可能一直连接中、收不到实时消息。

### 9.2 悟空 API 和 WS 反代

文件：

```bash
/www/server/panel/vhost/nginx/extension/你的域名/im_proxy.conf
```

内容：

```nginx
location ^~ /im-api/ {
    proxy_pass http://127.0.0.1:5001/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}

location = /im-api {
    return 301 /im-api/;
}

location ^~ /im-ws/ {
    proxy_pass http://127.0.0.1:5200/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
}

location = /im-ws {
    proxy_pass http://127.0.0.1:5200/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
}
```

客户端不再直连 `/im-ws`，但悟空 route、后台调试、服务端能力仍可能需要保留。

### 9.3 检查并重载 Nginx

```bash
/www/server/nginx/sbin/nginx -t
/www/server/nginx/sbin/nginx -s reload
```

## 10. 客户端配置

客户端只需要配置业务 API：

```bash
flutter run \
  --dart-define=BIM_API_BASE_URL=https://你的域名/api/ \
  --dart-define=BIM_APP_ID=900000002 \
  --dart-define=BIM_APP_KEY=业务端应用密钥
```

客户端不需要配置 Gateway 地址。Gateway 地址由业务端 `im_connect` 返回：

```text
route.https_stream_addr
stream.ticket
stream.last_cursor
```

当前客户端逻辑：

- 不使用悟空 Flutter SDK。
- 不使用 WSS/WS/TCP 直连。
- 不轮询消息。
- App 进入后台会关闭 stream。
- App 回前台重新 `im_connect` 获取新 ticket，再用 ACK cursor 补偿离线消息。
- 75 秒没有任何 Gateway frame/heartbeat，判定假在线并重连。

## 11. 验证步骤

### 11.1 验证服务状态

```bash
systemctl is-active redis
systemctl is-active wukongim
systemctl is-active bim-gateway
```

都应该返回：

```text
active
```

### 11.2 验证 Gateway

```bash
curl -sS http://127.0.0.1:8787/api/sync/health
curl -sS https://你的域名/api/sync/health
```

正常：

```json
{"code":1,"redis":"ok"}
```

### 11.3 验证悟空 API

```bash
curl -sS http://127.0.0.1:5001/route?intranet=0
curl -sS https://你的域名/im-api/route?intranet=0
```

能看到 route JSON 即正常。

### 11.4 验证业务端 im_connect

用真实登录 token 请求：

```bash
curl -sS https://你的域名/api/im_connect \
  -F appid=900000002 \
  -F usertoken=你的用户token \
  -F device=32位随机hex设备号 \
  -F device_flag=0 \
  -F device_level=1 \
  -F timestamp=当前秒级时间戳 \
  -F nonce=随机串 \
  -F sign=按业务端规则生成
```

必须返回：

```text
chat.route.https_stream_addr
chat.stream.ticket
chat.stream.expire_in
chat.stream.last_cursor
```

如果没有这些字段，客户端会连接失败。

### 11.5 验证 webhook 到 Redis

两个账号互发一条消息后检查 Redis：

```bash
redis-cli KEYS 'im:deliver:*'
redis-cli XLEN im:deliver:某个uid
redis-cli GET im:ack:某个uid:某个device
```

说明：

- `im:deliver:{uid}` 有数据，说明业务端 webhook 已经把消息投递给 Gateway。
- `im:ack:{uid}:{device}` 有值，说明客户端收到并 ACK 过。

### 11.6 客户端真实测试

用两个账号 A/B：

1. A 和 B 都登录。
2. A 给 B 发文字。
3. B 在会话列表应立即看到摘要。
4. B 进入聊天页应看到消息。
5. B 停留聊天页，A 再发第二条，B 页面应即时追加。
6. B 退到后台 1 分钟，A 发消息。
7. B 回前台，应重新连接 Gateway 并补偿消息。

如果会话列表有摘要但聊天页空白，重点检查：

- `im_person_messages` 是否返回密文响应且客户端能解密。
- Gateway frame 的 `channel_id/channel_type/client_msg_no/payload` 是否完整。
- 客户端诊断日志里是否有 `gateway message missing channel` 或 `gateway ack failed`。

## 12. 常见故障

### 12.1 客户端一直显示连接中

检查：

```bash
curl -sS https://你的域名/api/sync/health
systemctl status bim-gateway --no-pager
journalctl -u bim-gateway -n 100 --no-pager
```

常见原因：

- `im_connect` 没返回 `stream.ticket`。
- `GATEWAY_SECRET` 和 `BIM_GATEWAY_SECRET` 不一致。
- Nginx `/api/sync/` 没配或被 PHP 路由吃掉。
- Nginx 开了 `proxy_buffering`。

### 12.2 能发送，但对方不实时收到

检查：

```bash
journalctl -u wukongim -n 100 --no-pager
tail -n 200 /www/wwwroot/blin/runtime/log/gateway_stream.log
redis-cli KEYS 'im:deliver:*'
```

常见原因：

- 悟空 webhook 地址错。
- `WEBHOOK_SECRET` 和 `wk.yaml` 的路径 secret 不一致。
- `WEBHOOK_ALLOWED_IPS` 没包含悟空发起请求的 IP。
- 业务端写 Redis 失败。

### 12.3 客户端收到重复消息

当前去重规则：

- Gateway 投递前按 `uid + message_id/client_msg_no` 做 24 小时 Redis 去重。
- 客户端本地按 `client_msg_no` 优先、`message_seq` 次之合并。

如果仍重复，检查 webhook 是否给同一消息生成了不同 `client_msg_no` 或不同 `message_id`。

### 12.4 进入聊天页只有最新一条

检查：

- 会话摘要是否来自 Gateway。
- `im_person_messages` 或 `im_group_messages` 是否正常返回历史。
- 服务端是否开启对应历史同步字段。
- 客户端是否有本地清空边界或单条删除墓碑。

### 12.5 ACK 失败

客户端会串行 ACK。ACK 失败后不推进本地 cursor，会断开重连补偿。

检查：

```bash
journalctl -u bim-gateway -n 100 --no-pager
```

常见原因：

- ACK ticket 过期且 `im_connect` 刷新失败。
- Gateway secret 不一致。
- Redis 写入失败。

## 13. 日志位置

客户端：

```text
我的 -> 消息连接 -> 诊断日志
```

业务端：

```bash
/www/wwwroot/blin/runtime/log/
/www/wwwroot/blin/runtime/log/gateway_stream.log
```

Gateway：

```bash
journalctl -u bim-gateway -f
```

悟空：

```bash
journalctl -u wukongim -f
```

Nginx：

```bash
/www/wwwlogs/你的域名.log
/www/wwwlogs/你的域名.error.log
```

## 14. 安全规则

必须做到：

- 生产环境使用 HTTPS。
- Gateway 只监听 `127.0.0.1:8787`。
- Redis 不直接暴露公网。
- `BIM_GATEWAY_SECRET`、`GATEWAY_SECRET`、`WEBHOOK_SECRET` 使用 32 字节以上随机值。
- `/api/sync/metrics` 只允许本机访问。
- 客户端不展示 IM UID、Gateway cursor、message_id。
- 客户端日志不输出 token、sign、secret、secure_payload、消息正文、金额、附件 hash、Gateway cursor。

当前客户端已处理：

- 不直连悟空 WSS/WS/TCP。
- 不轮询消息。
- ACK 串行推进，失败不跳过消息。
- ACK ticket 过期自动刷新。
- 诊断日志不明文输出 Gateway cursor。

## 15. 高并发建议

当前单 Gateway 可先跑：

```text
BIM_GATEWAY_MAX_CONNECTIONS=20000
BIM_GATEWAY_MAX_CONNECTIONS_PER_IP=3000
BIM_REDIS_POOL_SIZE=200
BIM_REDIS_STREAM_MAX_LEN=10000
```

后期扩展集群时：

- Gateway 多实例都连接同一个 Redis。
- Nginx upstream 转发 `/api/sync/` 到多台 Gateway。
- ticket secret 所有 Gateway 保持一致。
- `im:gw:conn:{uid}:{device}` 用于后续连接路由。
- Redis 从单机升级为主从或集群前，要先评估 Stream key 分布和持久化策略。

## 16. 最小上线检查清单

上线前逐条确认：

- `redis-cli ping` 返回 `PONG`。
- `systemctl is-active wukongim` 返回 `active`。
- `systemctl is-active bim-gateway` 返回 `active`。
- `https://域名/api/sync/health` 返回 `code=1`。
- `https://域名/im-api/route?intranet=0` 可访问。
- `wk.yaml webhook.httpAddr` 是业务端回调地址。
- 业务端 `.env` 的 `WEBHOOK_SECRET` 和 `wk.yaml` 路径 secret 一致。
- 业务端 `.env` 的 `GATEWAY_SECRET` 和 Gateway `.env` 的 `BIM_GATEWAY_SECRET` 一致。
- `im_connect` 返回 `route.https_stream_addr` 和 `stream.ticket`。
- 客户端两个账号互发，前台和后台恢复都能收到消息。
