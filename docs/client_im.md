# BIM 客户端 IM 对接文档

## 运行配置

客户端配置通过 `--dart-define` 覆盖：

```bash
flutter run \
  --dart-define=BIM_API_BASE_URL=https://blcold.cn/api/ \
  --dart-define=BIM_APP_ID=900000002 \
  --dart-define=BIM_APP_KEY=替换为业务端应用密钥
```

默认值在 `lib/src/core/app_config.dart`。业务 API 可以是 `http` 或 `https`，当前线上默认 `https://blcold.cn/api/`。IM 实时连接地址不写死，登录后读取业务端 `im_connect.route`。如果业务端配置了 `wss_addr` 或 `websocket_addr` 且启用了 TLS，客户端优先使用 WSS；没有 WSS/WS 时才使用 `tcp_addr`。

## 当前实时架构

客户端不再接入 Flutter IM SDK，不保留 SDK 封装代码。实时层由 `lib/src/im/business_im_service.dart` 直接实现：

- 登录后调用业务端 `im_connect` 获取 `uid`、`token`、`device_flag`、`device_level`、`route`。
- 实时连接优先级：`wss_addr` -> `websocket_addr` -> `ws_addr` -> `tcp_addr`。
- WSS/WS 使用 WebSocket 二进制帧承载同一套 IM 协议；TCP 使用 `Socket.connect(tcp_addr)`。
- 按业务端接入的悟空 IM 协议发送 connect 包，并完成 X25519/AES 握手。
- 实时协议收到消息后校验 `msg_key`、AES 解密、Base64 解码业务 payload，然后写入 MMKV 消息缓存并通知 UI。
- 收到可持久化消息后发送 `recvack`。
- 发送消息仍必须调用业务端 `im_person_send` / `im_group_send`，由业务端执行权限、好友、红包、转账、@、引用、阅后即焚等规则。

客户端没有消息轮询。周期任务只有实时连接 ping/pong 保活，不会定时请求会话列表或消息列表。新版 IM 文档已经废弃旧 `user_heartbeat`，客户端不再调用该接口。

## 启动流程

1. `main.dart` 初始化 MMKV 和本地日志。
2. `SessionStore.ensureDeviceId()` 生成并持久化设备号，格式为 `bimotc.com-<随机16字节hex>`。
3. 冷启动 `SessionController.coldStart()` 读取 MMKV 登录态。
4. 已登录时调用 `im_connect`，请求携带 `device`、`device_flag=0`、`device_level=1`、`timestamp`、`nonce`、`sign`。
5. `BusinessImService.start()` 读取本地 MMKV 会话缓存，并按 WSS/WS/TCP 优先级建立实时长连接。
6. 握手成功后状态变为“已连接”，聊天页依靠实时长连接收包刷新。

热启动恢复时如果长连接已断开，`resumeConnection()` 会重新连接实时通道；不会循环请求业务端消息列表。

## 签名规则

客户端新版 `im_*` 请求统一使用 `ApiSigner`：

- 参数包含 `appid`、业务参数、`usertoken`、`device`、`device_flag`、`device_level`、`timestamp`、`nonce`。
- 排除 `sign`、`callback`、`action` 和空值。
- 参数按 key 排序后 JSON 编码，拼接 `secretKey={BIM_APP_KEY}`。
- MD5 小写输出。
- `nonce` 每次请求重新生成并参与签名。服务端在签名校验通过后缓存 `appid + usertoken + device + timestamp + nonce`，同一请求窗口内重复提交返回 HTTP `409` 和 `code=0`，用于拦截抓包原包重放。

旧 `user_heartbeat` 属于历史接口，当前用户在线状态由 IM 实时连接和服务端 `user.onlinestatus` 事件维护，客户端不再请求该接口。

## 消息发送

所有用户消息发送走业务端：

- 私聊：`im_person_send`
- 群聊：`im_group_send`

通用参数：`appid`、`usertoken`、`device`、`device_flag`、`device_level`、`timestamp`、`nonce`、`sign`、`client_msg_no`、`content_type`。

私聊额外传 `receiver_id`，群聊额外传 `group_id`。

支持的 `content_type`：

- `text`：`content`
- `image`：上传 `file` 或传 `url`
- `emoji`：`emoji_code`，或上传 `file`，或传 `url`
- `gif`：上传 `file` 或传 `url`
- `sticker`：`sticker_id`，或上传 `file`，或传 `url`
- `voice`：上传 `file` 或传 `url`，可选 `duration`
- `video`：上传 `file` 或传 `url`，可选 `cover_url`、`duration`
- `file`：上传 `file` 或传 `url`，可选 `name`、`mime`、`size`
- `contact_card`：`card_user_id`
- `transfer`：`money`、`asset_type=money|integral`，群聊还必须传 `receiver_id`
- `red_packet`：`money`、`asset_type=money|integral`，群聊可传 `packet_type=ordinary|luck|specified`、`quantity`、`receiver_id`

客户端生成唯一 `client_msg_no`，格式为 `bim_{userId}_{timestamp随机串}`。同一条消息只生成一次，避免重复文本触发 `client_msg_no已被其它消息内容占用`。

发送时客户端先写入 MMKV 本地“发送中”消息，业务端返回后按同一 `client_msg_no` 合并为“已发送”或“队列中”。网络或超时类错误最多重试 3 次，重试复用同一个 `client_msg_no` 但重新生成 `nonce/sign`；业务拒绝不重试。接收方和发送方的服务端推送都通过实时长连接进入本地缓存。

## 消息接收

实时收包处理流程：

1. 按协议帧长度切包。
2. 解码 packet header 和 recv body。
3. 使用握手后的 AES key 校验 `msg_key`。
4. AES 解密 payload。
5. Base64 解码业务 payload JSON。
6. 归一化为聊天页字段：`client_msg_no`、`message_id`、`message_seq`、`channel_id`、`channel_type`、`from_uid`、`is_me`、`content`、`content_type`、`payload`、`timestamp`、`status`。
7. 写入 MMKV，按 `client_msg_no` 去重合并。
8. 更新会话缓存和当前频道消息版本，UI 自动刷新。
9. 非 `no_persist` 消息发送 `recvack`。

私聊收到的频道如果是当前用户 UID，会转换为对方 `from_uid`，与聊天页使用的私聊频道保持一致。

服务层同时暴露本地广播消息流。聊天页和首页会话列表订阅该事件流后直接增量合并消息和会话，实时收包、本地发送中、发送确认、发送失败都会立即推送到 UI；重新读取 MMKV 只作为冷启动和补偿同步使用。

## 本地缓存

MMKV 存储：

- 登录态和设备号。
- 冷启动、热启动时间。
- 会话列表轻量缓存。
- 频道消息轻量缓存。
- 聊天草稿。
- 最近访问频道索引。

历史消息接口只在本次启动首次打开某个聊天且本地没有消息时补偿同步一次：

- 私聊：`im_person_messages`
- 群聊：`im_group_messages`

这些同步由用户打开会话触发，不会使用定时器反复请求历史消息，也不会用业务接口代替实时收消息。若历史接口返回错误，本次启动会标记为已尝试，避免继续重复请求；实时收发仍以 WSS/WS/TCP 长连接为准。

## 连接保活

实时连接使用 30 秒 ping/pong 保活。如果连续未收到 pong，会关闭当前连接并按退避策略重连。客户端不再调用旧 `user_heartbeat`。

## 用户端功能

- 登录/注册：业务端登录注册接口。
- 消息：首页显示 MMKV 会话缓存，启动时同步一次 `im_conversations`，之后由 TCP 新消息推动更新。
- 聊天：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包。
- 私聊规则：非好友只能发送文字，且单向最多三条；图片、语音、视频、文件、转账、红包等由业务端拦截。
- 群聊：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、红包、指定转账。
- 群聊文本支持 `mention_user_ids`、`mention_all`、`reply_client_msg_no`、`burn_after_read`。
- 私聊文本支持 `reply_client_msg_no`、`burn_after_read`。
- 回执和动作：已读回执、回执状态、撤回、阅后即焚、红包领取、转账收款。
- 好友：搜索用户、申请、处理申请、状态查询、删除好友。
- 群管理：建群、更新群资料、成员列表、加人、踢人、退出、解散、设置管理员、转让群主、禁言、解除禁言。

## 本地日志

日志路径在应用“我的 -> 消息连接 -> 诊断日志”页面展示。重点日志：

- API 请求/响应、耗时和错误码。
- WSS/WS/TCP 连接、握手、断线、重连、ping/pong。
- `client_msg_no`、频道、消息类型和发送结果。
- 实时收消息、解密、缓存写入和 UI 版本刷新。
- 实时原始数据、帧类型、握手、断线、重连、ping/pong。

敏感字段会脱敏：`token`、`password`、`sign`、`secret`、`key`。

## 校验

代码变更后执行：

```bash
flutter pub get
dart format lib test
flutter analyze
```
