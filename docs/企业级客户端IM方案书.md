# BIM 企业级客户端 IM 方案书

## 1. 目标

本方案用于 BIM Flutter 多端客户端，目标是把客户端实时通信能力升级为企业级 IM 客户端标准：

- 连接状态与生命周期可控。
- 心跳保活能识别“假在线”。
- 断线后使用指数退避和随机抖动重连，避免雪崩。
- 离线消息通过 Gateway 队列和 ACK 游标可靠补偿。
- 使用 `message_seq` 做频道级增量同步。
- 支持同账号多端状态漫游。
- 发送消息、红包、转账、好友、群聊权限全部走 TP8 业务端，不绕过业务规则。

## 2. 当前服务端架构

当前服务端由三层组成：

```text
Flutter 客户端
  -> TP8 业务 API：登录、好友、群聊、发送消息、红包、转账、权限判断
  -> BIM Gateway：HTTPS 长连接实时投递、ACK 游标、连接状态
  -> 悟空 IM：底层消息存储、频道、message_seq、webhook、离线事件
```

客户端不能直接调用悟空 IM 管理接口，也不能绕过 TP8 业务端发送消息。

客户端实时接收以 Gateway 为主：

```text
im_connect 返回 route.https_stream_addr + stream.ticket + stream.last_cursor
客户端 POST /api/sync/open 打开 HTTPS Stream
Gateway 推送悟空 webhook 归一化后的消息帧
客户端落库成功后 POST /api/sync/ack
```

悟空 IM 是服务端底层能力，不作为客户端 SDK 直连入口。

## 3. 客户端分层设计

建议把现有客户端拆成以下职责层：

```text
SessionController
  - 登录态、冷启动、热启动、生命周期分发

ApiClient
  - TP8 业务接口
  - 签名、timestamp、nonce、secure_payload、secure_response

GatewayStreamClient
  - /api/sync/open 长连接
  - 二进制帧解析
  - heartbeat、超时检测、重连
  - /api/sync/ack

BusinessImService
  - IM 状态机
  - 会话列表合并
  - 消息收发状态
  - Sequence 增量同步

ImCacheStore
  - MMKV 本地缓存
  - 会话、消息、ACK 游标、频道 seq、删除墓碑、清空边界

ChatFeatureService
  - 好友、群聊、禁言、转账、红包、撤回等业务动作
```

现有 `BusinessImService` 里直接连接悟空 WSS/TCP 的逻辑必须删除，正式用户端只保留：

```text
Gateway HTTPS Stream
```

生产客户端只认业务端 `im_connect` 返回的 Gateway stream 字段。

## 4. 连接状态机

客户端维护统一连接状态：

```text
idle           未启动
bootstrapping 读取本地缓存和登录态
connecting    请求 im_connect 或打开 Gateway stream
connected     长连接已建立，正在接收消息
syncing       正在做补偿同步
degraded      实时连接断开，但本地缓存可用，等待重连
reconnecting  退避重连中
offline       网络不可用或用户在后台，暂停连接
kicked        同设备被新连接顶下
unauthorized  token 失效，需要重新登录
stopped       用户主动退出
```

状态展示规则：

- 首页标题显示连接状态，例如“连接中”“同步中”“重连中”。
- 会话列表不要插入连接状态假会话。
- 聊天页发送按钮只受业务状态影响，不因短暂同步阻塞 UI。
- 用户主动退出后进入 `stopped`，不自动重连。

状态切换：

```text
coldStart -> bootstrapping -> connecting -> connected
connected -> syncing -> connected
connected -> degraded -> reconnecting -> connected
connected -> kicked -> connecting 或 stopped
connected -> unauthorized -> stopped
```

## 5. 生命周期管理

### 冷启动

冷启动流程：

```text
初始化日志
初始化加密 MMKV
读取 device
读取 session
读取本地会话缓存
显示本地会话列表
调用 im_connect 获取最新 chat/stream
打开 Gateway stream
成功后做会话补偿同步
```

冷启动必须先展示本地缓存，避免白屏和会话列表闪烁。

### 热启动

热启动流程：

```text
App resumed
如果 stream 仍活跃：只刷新状态，不重新拉全量
如果 stream 已断：调用 im_connect 获取新 ticket
重新打开 Gateway stream
按 last_cursor 或本地 ACK cursor 补偿离线消息
```

Gateway ticket 是单次使用，热启动重连不能复用旧 ticket。

### 后台

移动端进入后台：

- Android/iOS 不保证长连接持续存活。
- 客户端可以主动关闭 stream，状态置为 `offline`。
- 返回前台后重新 `im_connect` 并使用 ACK cursor 补偿。

桌面端可保持连接，但仍必须执行心跳超时检测。

## 6. 心跳保活机制

Gateway 当前会周期性下发 heartbeat 帧：

```json
{
  "type": "heartbeat",
  "timestamp": 1783163091,
  "cursor": "1783163091375-0"
}
```

客户端规则：

- 记录 `lastFrameAt`：收到任何 Gateway 帧都刷新。
- 记录 `lastHeartbeatAt`：收到 heartbeat 刷新。
- 如果 `now - lastFrameAt > 75s`，判定连接失活。
- 如果连续两个心跳周期没有任何帧，主动关闭连接并进入重连。
- 不依赖旧 `user_heartbeat` 接口。

防止“假在线”的关键：

```text
Socket 未关闭 != 在线
只有持续收到 Gateway 帧或 heartbeat，才认为在线
```

客户端在线状态来源：

- 本端：Gateway stream 活跃。
- 其他用户：业务端悟空 `user.onlinestatus` webhook 结果或业务 API。
- 不使用客户端自报在线作为真实在线依据。

## 7. 断线重连策略

重连必须使用指数退避 + 随机抖动。

推荐公式：

```text
base = 1s
max = 60s
attempt 从 0 开始
delay = min(max, base * 2^attempt)
jitter = random(0, delay * 0.3)
nextDelay = delay + jitter
```

示例：

```text
1.0s - 1.3s
2.0s - 2.6s
4.0s - 5.2s
8.0s - 10.4s
16.0s - 20.8s
32.0s - 41.6s
60.0s - 78.0s
```

重连触发：

- 网络错误。
- Gateway stream EOF。
- heartbeat 超时。
- HTTP 5xx。
- Nginx 断开。
- App 从后台恢复。

不重连场景：

- 用户主动退出。
- token 失效，业务端返回 401。
- 账号封禁，业务端返回 403。
- ticket replayed：重新 `im_connect` 后再连，不直接复用旧 ticket。

重连流程：

```text
关闭旧 stream
清理当前 reader
等待 nextDelay
调用 im_connect 获取新 ticket 和 last_cursor
打开 /api/sync/open
连接成功后 attempt 清零
按 ACK cursor 补偿消息
```

## 8. Gateway 离线队列与 ACK

Gateway 使用 Redis Stream 做每个用户的投递队列：

```text
im:deliver:{uid}
im:ack:{uid}:{device}
```

客户端打开 stream：

```http
POST /api/sync/open
Content-Type: application/json

{
  "ticket": "im_connect返回的stream.ticket",
  "last_cursor": "本地保存的ack_cursor或im_connect返回值"
}
```

消息帧：

```json
{
  "frame_id": "1783163091375-0",
  "type": "message",
  "uid": "app900000002user900100001",
  "channel_id": "app900000002user900100002",
  "channel_type": 1,
  "client_msg_no": "client-001",
  "message_id": "message-id",
  "message_seq": 1024,
  "payload": {},
  "timestamp": 1783163091,
  "cursor": "1783163091375-0"
}
```

ACK 原则：

```text
先写本地缓存，再 ACK Gateway
```

ACK 请求：

```http
POST /api/sync/ack
Content-Type: application/json

{
  "ticket": "当前stream.ticket",
  "last_cursor": "1783163091375-0",
  "client_msg_nos": ["client-001"]
}
```

客户端本地必须保存：

```text
gateway_ack_cursor:{uid}:{device}
```

ACK 成功后更新本地 cursor。ACK 失败时不丢消息，下次打开 stream 仍从旧 cursor 补偿。

ACK 安全修正：

- `stream.ticket` 是短 TTL 材料，打开 stream 不能复用已经 claim 的 ticket。
- 长连接运行超过 ticket TTL 后，客户端 ACK 前必须重新调用 `im_connect` 获取新的 ACK ticket。
- ACK ticket 只用于 `/api/sync/ack` 校验，不用于替换当前已打开 stream。
- 如果 ACK 返回 401，客户端刷新 ticket 后只重试一次；仍失败则不推进本地 cursor。

## 9. 消息去重

客户端去重顺序：

```text
优先 client_msg_no
其次 message_id
最后 channel_id + channel_type + message_seq
```

写入消息时使用 upsert：

```text
如果 client_msg_no 已存在：合并状态、message_id、message_seq、payload
如果 message_id 已存在：合并
如果 seq 已存在：合并
否则追加
```

这样可以处理：

- 本地发送中消息。
- 业务端发送确认。
- Gateway 实时回推。
- 历史同步补偿。
- 多端漫游同步。

## 10. Sequence ID 增量同步

悟空 IM 会产生 `message_seq`。客户端必须把它作为频道级增量同步依据。

本地缓存每个频道：

```text
channel_max_seq:{uid}:{channel_type}:{channel_id}
channel_min_seq:{uid}:{channel_type}:{channel_id}
```

进入聊天页：

```text
读取本地消息
找 maxSeq
调用历史接口拉 maxSeq 之后的新消息
合并并刷新 UI
```

接口参数：

```text
im_person_messages:
  receiver_id
  start_message_seq=maxSeq
  pull_mode=1
  limit=50

im_group_messages:
  group_id
  start_message_seq=maxSeq
  pull_mode=1
  limit=50
```

向上翻历史：

```text
找 minSeq
调用历史接口拉 minSeq 之前的消息
end_message_seq=minSeq
pull_mode=0
limit=50
```

合并规则：

- `message_seq` 越小越早。
- `message_seq=0` 的本地发送中消息按本地时间排序。
- 服务端确认后补齐 `message_seq`，重新排序。

群聊边界：

- 服务端已限制群成员只能拉入群后的消息。
- 客户端仍要遵守服务端返回，不自行构造更早 seq 拉取。

## 11. 跨端状态漫游

跨端状态分三类：

### 必须漫游

- 消息记录。
- 会话摘要。
- 已读位置。
- 删除/清空边界。
- 撤回。
- 红包领取、转账收款动作回执。
- 群禁言、群成员变动。

### 本地优先，不强制漫游

- 输入框草稿。
- 最近打开频道。
- 本地附件临时路径。
- 发送失败的本地重试任务。

### 不允许展示给用户

- 全局用户 ID。
- IM UID：`app...user...`
- Gateway ticket。
- 内部 cursor。
- message_id 原始值。

多端在线规则：

- `device` 是客户端生成的 32 位随机 hex。
- `device_flag` 区分 App/Web/PC。
- 同账号不同 device 可以同时在线。
- 同账号同 device 重连会顶掉旧连接。
- Gateway ticket 单次使用，跨端不能共享。

已读漫游：

```text
用户打开会话
本地更新 read_marker
调用业务端已读接口或事件接口
其他端通过 CMD/事件刷新已读状态
```

删除漫游：

```text
用户删除单条消息
业务端写删除墓碑
本地删除并保存墓碑
其他端同步历史时过滤该用户删除的消息
```

清空漫游：

```text
用户清空私聊/群聊/全部聊天
业务端写清空边界
本地清空对应缓存
后续历史同步按边界过滤
```

## 12. 发送消息生命周期

发送状态：

```text
draft       草稿
sending     本地已入库，正在请求业务端
queued      业务端进入重试队列
sent        业务端发送成功或 Gateway 回推确认
failed      业务拒绝或重试失败
revoked     已撤回
deleted     当前用户本地删除
```

发送流程：

```text
生成 client_msg_no
写入本地 sending 消息
刷新聊天页和会话列表
调用 TP8 im_person_send / im_group_send
业务端校验权限并发送到悟空 IM
返回 send_ack
本地合并为 sent/queued
Gateway 回推同一 client_msg_no
再次合并，补齐 message_id/message_seq
```

重试规则：

- 网络错误、超时、HTTP 5xx、429 可重试。
- 权限拒绝、禁言、非好友限制、余额不足不重试。
- 重试复用同一个 `client_msg_no`。
- 每次重试重新生成 `timestamp/nonce/sign`。
- 重试按钮只对 `failed` 消息显示。

## 13. 离线发送队列

客户端本地维护发送队列：

```text
pending_send:{uid}
```

队列字段：

```json
{
  "client_msg_no": "bim_1_xxx",
  "channel_id": "...",
  "channel_type": 1,
  "content_type": "text",
  "payload": {},
  "file_path": "",
  "attempt": 0,
  "next_retry_at": 1783163091000,
  "created_at": 1783163091000
}
```

网络恢复后：

```text
按 next_retry_at 取任务
检查消息仍存在且未撤回/删除
调用业务发送接口
成功后删除任务
失败则指数退避
```

附件消息如果本地文件不存在，应直接失败并提示用户重新选择。

## 14. Gateway Stream 协议解析

Gateway 响应不是普通 JSON，而是连续二进制帧：

```text
4 字节大端长度 + JSON body
```

客户端解析器必须支持：

- 半包。
- 粘包。
- 单帧过大保护。
- JSON 解析失败跳过当前帧并记录日志。

最大帧建议：

```text
单帧最大 1MB
超过直接断开并重连
```

支持帧类型：

```text
message    普通消息或业务事件
heartbeat  心跳
kick       被踢下线或同设备替换
error      Gateway 错误
```

## 15. 安全策略

客户端必须执行：

- 所有业务请求带 `device/timestamp/nonce/sign`。
- 消息业务字段走 `secure_payload`。
- 附件走 `secure_file`。
- 历史响应要求 `secure_response=1`。
- 本地 MMKV 使用加密 key。
- 日志脱敏 token、sign、secret、secure_payload、消息正文、金额、附件名。
- HTTPS 可用时 Gateway Stream 必须使用 HTTPS；客户未配置证书时才允许 HTTP。

客户端禁止：

- 调用旧私信接口。
- 轮询消息列表代替实时连接。
- 复用 Gateway ticket。
- 展示 IM UID、Gateway cursor、message_id 给普通用户。
- 明文上传消息内容、金额、附件。

## 16. 对现有客户端的改造清单

### 16.1 模型层

`ChatSession` 增加：

```dart
GatewayStreamSession? stream;
```

字段：

```text
ticket
expire_in
last_cursor
https_stream_addr
```

`ImRoute` 增加：

```text
https_stream_addr
```

### 16.2 新增 GatewayStreamClient

职责：

- 打开 `/api/sync/open`。
- 解析 4 字节长度帧。
- 维护 `lastFrameAt`。
- 发送 `/api/sync/ack`。
- 断线通知 `BusinessImService`。

### 16.3 BusinessImService 改造

旧 `_connectTcp()`、WSS/WS/TCP 协议解析和 X25519/AES 握手代码必须删除，实时入口只保留：

```text
_connectRealtime()
  -> im_connect 获取 stream.ticket
  -> POST /api/sync/open
  -> frame 落库
  -> POST /api/sync/ack
```

生产默认和开发调试均为：

```text
Gateway only
```

### 16.4 缓存层

`ImCacheStore` 增加：

```text
readGatewayCursor(uid, device)
writeGatewayCursor(uid, device, cursor)
readChannelMaxSeq(uid, channelId, channelType)
writeChannelMaxSeq(...)
readPendingSendQueue(uid)
writePendingSendQueue(...)
```

### 16.5 API 层

`ApiClient` 增加：

```text
openGatewayStream 不放在 Dio 普通请求里，使用 HttpClient stream
ackGatewayCursor 使用 Dio POST
```

注意：`/api/sync/open` 是长响应流，不能按普通 JSON 请求处理。

## 17. UI 交互规则

首页标题：

```text
connected: 消息
connecting: 连接中
syncing: 同步中
reconnecting: 重连中
offline: 消息
```

聊天页：

- 发送中显示小圆圈。
- 发送成功显示勾。
- 失败显示感叹号，可点击重发。
- 收到实时消息立即插入当前聊天，不刷新整个页面。
- 打开聊天页默认定位到底部。
- 输入框弹起时列表同步上移，不二次跳动。

通讯录：

- 好友列表优先读 MMKV 缓存。
- 后台刷新时增量替换，不清空再加载。
- 群聊不混在好友列表，放到通讯录“群聊”入口。

## 18. 观测与诊断

客户端日志必须记录：

- lifecycle：冷启动、热启动、后台、前台。
- im_connect：成功、失败、耗时。
- gateway：open、frame、heartbeat、ack、close。
- reconnect：attempt、delay、jitter、reason。
- sync：channel、start_seq、end_seq、count。
- send：client_msg_no、status、attempt、result。

不记录：

- 消息正文。
- 金额。
- token/sign/secret。
- secure_payload。
- 附件真实路径。

诊断页展示：

```text
当前连接状态
当前 transport: Gateway HTTPS Stream
最近 heartbeat 时间
最近 ack cursor
重连次数
最近错误
日志文件路径
```

## 19. 验收标准

### 连接

- 冷启动 2 秒内显示本地会话缓存。
- Gateway 正常时 5 秒内进入 connected。
- 断网后 75 秒内识别失活。
- 恢复网络后按指数退避重连成功。

### 消息

- A/B 同时在聊天页，A 发消息，B 当前页实时出现。
- B 在后台，A 连发多条，B 回前台后全部按顺序出现。
- 发送方本地消息从 sending 变 sent，不整页刷新。
- 同一消息不会重复出现。

### ACK

- 客户端收到消息但未落库，不发送 ACK。
- ACK 失败后重连可再次收到未确认消息。
- ACK 成功后重连不重复拉已确认消息。

### Sequence

- 打开聊天页按 `message_seq` 补齐缺口。
- 连续两条离线消息不会丢第一条。
- 群聊入群前消息不会展示。

### 跨端

- 手机端发送，桌面端能实时看到。
- 手机端已读，其他端能同步已读状态。
- 单端删除不影响对方。
- 清空聊天只影响当前用户可见记录。

## 20. 分阶段落地

### 第一阶段：Gateway Stream 主链路

- 解析 `im_connect.stream`。
- 新增 `GatewayStreamClient`。
- 接入 heartbeat、ack、cursor。
- 生产禁用直连悟空 WSS/TCP。

### 第二阶段：可靠消息同步

- 增加频道 maxSeq/minSeq。
- 历史接口按 sequence 增量拉取。
- 完善 pending send queue。
- 完善重复消息合并。

### 第三阶段：跨端漫游

- 已读、删除、清空边界漫游。
- CMD 事件统一处理。
- 多端会话状态一致性。

### 第四阶段：诊断与压测

- 增加诊断页。
- 模拟断网、弱网、后台恢复。
- 进行 1k/5k/1w 长连接阶梯压测。

## 21. 最终客户端原则

客户端只做三件事：

```text
1. 调业务端完成业务动作
2. 通过 Gateway 收实时结果
3. 用本地缓存保证 UI 快速、可靠、一致
```

业务规则不在客户端硬绕，实时能力不靠轮询，消息可靠性靠 Gateway ACK + 悟空 message_seq + 本地 MMKV 三层共同保证。
