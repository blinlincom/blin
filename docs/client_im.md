# BIM 客户端 IM 对接文档

企业级连接状态、心跳保活、断线重连、Gateway ACK、Sequence 增量同步和跨端漫游设计见 [企业级客户端IM方案书.md](企业级客户端IM方案书.md)。

## 运行配置

客户端配置通过 `--dart-define` 覆盖：

```bash
flutter run \
  --dart-define=BIM_API_BASE_URL=https://blcold.cn/api/ \
  --dart-define=BIM_APP_ID=900000002 \
  --dart-define=BIM_APP_KEY=替换为业务端应用密钥
```

默认值在 `lib/src/core/app_config.dart`。业务 API 可以是 `http` 或 `https`，当前线上默认 `https://blcold.cn/api/`。IM 实时连接地址不写死，登录后读取业务端 `im_connect.route.https_stream_addr` 和 `im_connect.stream`。客户端只走 Gateway HTTPS Stream，不再直连 WSS/WS/TCP。

多平台配置要点：

- Android：包名 `bimotc.com`，需要网络权限；缓存加密 key 通过 Android Keystore 保护。
- Android 媒体权限：聊天内图片/视频选择使用应用内相册网格，需要 `READ_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`；不申请 `MANAGE_EXTERNAL_STORAGE`。
- iOS/macOS：需要允许访问业务 API 和 Gateway HTTP/HTTPS Stream 地址；聊天内图片/视频选择需要相册权限说明 `NSPhotoLibraryUsageDescription`；缓存加密 key 通过 Keychain 插件通道获取。若业务端仍使用 HTTP，需要按平台网络安全策略放行对应域名。
- Windows/Linux：当前使用应用私有目录下的 `.bim_data` 初始化 MMKV，运行环境必须允许写入应用数据目录；缓存加密 key 保存到应用私有安全文件，发布时应配合系统账户权限保护目录。
- Web：当前实时层和 MMKV 缓存不是 Web 适配方案，不能直接按移动端配置运行；如要支持 Web，需要补 WebSocket-only 实时层和 Web 安全存储实现。
- 实时地址：业务端必须返回 `route.https_stream_addr` 和 `stream.ticket`。客户配置 HTTPS/TLS 时地址使用 `https://.../api/sync/open`，未配置时可使用 `http://.../api/sync/open`；客户端不接受 WSS/WS/TCP 降级。
- 屏幕方向：Android、iOS 入口固定竖屏，多端布局仍按不同屏幕宽度自适应。

## 当前实时架构

客户端不再接入 Flutter IM SDK，也不保留旧 WSS/TCP 直连协议代码。实时层由 `lib/src/im/gateway_stream_client.dart` 和 `lib/src/im/business_im_service.dart` 实现：

- 登录后调用业务端 `im_connect` 获取 `uid`、`token`、`device_flag`、`device_level`、`route.https_stream_addr`、`stream.ticket`、`stream.expire_in`、`stream.last_cursor`。
- 实时连接固定为 Gateway：`POST /api/sync/open`，请求体为 `ticket + last_cursor`。
- Gateway 下发 4 字节大端长度前缀 + JSON frame，客户端解析 `message/heartbeat/kick/error`。
- 实时消息 payload 归一化后写入 MMKV，并通知聊天页和会话列表增量刷新。
- 本地落库成功后调用 `POST /api/sync/ack` 推进 Gateway ACK cursor；ACK ticket 过期前自动重新 `im_connect` 刷新。
- 发送消息仍必须调用业务端 `im_person_send` / `im_group_send`，由业务端执行权限、好友、红包、转账、@、引用、阅后即焚等规则。

客户端没有消息轮询。实时活性只看成功解密后的 Gateway frame/heartbeat，收到 HTTP 200 响应头并不代表已经在线。超过 40 秒未收到有效帧视为连接可疑，前台恢复会立即换票重连；连续 60 秒无有效帧由看门狗关闭连接并按指数退避重连。新版 IM 文档已经废弃旧 `user_heartbeat`，客户端不再调用该接口。

## 启动流程

1. `main.dart` 初始化 MMKV 和本地日志。
2. `SessionStore.ensureDeviceId()` 生成并持久化设备号，格式为 32 位随机 hex，不带包名前缀。开发期发现旧 `bimotc.com-` 前缀设备号会直接重置。
3. 冷启动 `SessionController.coldStart()` 读取 MMKV 登录态。
4. 已登录时调用 `im_connect`，请求携带 `device`、`device_flag=0`、`device_level=1`、`timestamp`、`nonce`、`sign`。
5. `BusinessImService.start()` 读取本地 MMKV 会话缓存，并调用 `im_connect` 获取新的 Gateway ticket。
6. 使用本地 ACK cursor 或 `stream.last_cursor` 打开 `/api/sync/open`。
7. Gateway stream 打开后保持“连接中”；收到首个成功解密的 heartbeat/message 才变为“已连接”，然后执行离线补偿同步。

网络和生命周期恢复规则：

- 监听 Wi-Fi、蜂窝网络、VPN、以太网等网络类型变化；切网时废弃旧 `HttpClient`、旧 stream 和旧 ticket，防止半开连接继续占位。
- 网络恢复后防抖 500ms 获取新 ticket 重连，不等待旧连接 60 秒超时。
- App 回到前台时检查最近有效帧时间；stream 对象存在但超过 40 秒无有效帧时仍会强制重连。
- 后台保活关闭时进入后台会主动关闭 stream，回前台后使用新 ticket 建立连接。
- Gateway open/ACK 返回 401/403 只视为实时传输票据失效，先刷新 ticket；只有业务端 `im_connect` 明确返回账号认证失效时才停止重连并进入未登录状态。
- 指数退避次数不会在 HTTP 200 时清零，连接连续稳定 30 秒且心跳健康后才清零，避免短连接循环造成重连风暴。
- Gateway 在流打开后立即发送一次加密 heartbeat，后续按 25 秒周期发送；因此客户端无需等待首个周期心跳即可确认连接。

线上 Nginx 的 `/api/sync/` 必须保留以下流式代理要求：关闭响应缓冲、请求缓冲、缓存和 gzip，清空上游 `Connection` 头，开启 `proxy_socket_keepalive`，并将读写超时设置为明显大于心跳周期的值。否则代理层可能聚合帧或提前关闭长响应。

用户端页面不展示全局用户 ID、IM UID、`app...user...` 等内部标识；列表、聊天页、群成员页只显示昵称或用户名。内部 ID 只作为接口参数留在代码层，后台管理可另行展示。

热启动恢复时如果长连接已断开，`resumeConnection()` 会重新连接实时通道；不会循环请求业务端消息列表。

## 签名规则

客户端新版 `im_*` 请求统一使用请求签章器：

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
- 群禁言状态：`im_group_mute_status`

通用外层参数：`appid`、`usertoken`、`device`、`device_flag`、`device_level`、`timestamp`、`nonce`、`sign`、`client_msg_no`、`content_type`。

私聊额外传 `receiver_id`，群聊额外传 `group_id`。

消息内容不再以明文表单字段提交。客户端把 `content`、`money`、`asset_type`、`remark`、`url`、`card_user_id`、`mention_user_ids`、`reply_client_msg_no`、`quote_client_msg_no`、`quote`、`quote_json`、`burn_after_read` 等业务字段归一化后放入 `secure_payload`，再按业务端文档使用 AES-128-CBC 加密。签名只覆盖外层字段和密文，不覆盖明文字段。

图片、语音、视频、文件等本地附件不会用明文 `file` 字段上传。客户端先把原文件字节加密到临时密文文件，通过 multipart 字段 `secure_file` 上传，并提交 `secure_file_name`、`secure_file_size`、`secure_file_sha256` 等外层字段。请求完成后会删除本地临时密文文件。

图片和视频选择不调用系统文件管理器。聊天页点击图片/视频后进入客户端自己的相册网格，通过 `photo_manager` 读取用户授权的相册、展示缩略图，选中后立即把本地消息写成“发送中”，后台上传完成后再按同一个 `client_msg_no` 合并为“已发送”。文件发送也不打开系统文件夹，客户端展示应用内文件中心：Android 会扫描应用可访问目录和公开 `Download/Documents/Pictures/Movies`，iOS/macOS/桌面只展示应用沙盒、下载目录等当前平台允许读取的目录。所有本地 `file_path` 只保存在 MMKV 本地消息里用于预览和失败重发，不进入 `secure_payload` 上行参数。

会话摘要和历史消息也不允许明文返回。客户端请求 `im_conversations`、`im_person_messages`、`im_group_messages` 时固定带 `secure_response=1` 并参与签名；业务端不再接受未声明密文响应的历史读取请求。业务端返回 `data.secure_payload`，客户端使用同一次请求的 `appid/appkey/usertoken/device/timestamp/nonce` 解密。响应 IV 规则为 `md5(device|response|timestamp|nonce).substring(0, 16)`，抓包只能看到 Base64 密文。

支持的 `content_type`：

- `text`：`content`
- `image`：上传 `secure_file` 或在 `secure_payload` 里传 `url`
- `emoji`：`emoji_code`，或上传 `secure_file`，或传 `url`
- `gif`：上传 `secure_file` 或传 `url`
- `sticker`：`sticker_id`，或上传 `secure_file`，或传 `url`
- `voice`：上传 `secure_file` 或传 `url`，可选 `duration`
- `video`：上传 `secure_file` 或传 `url`，可选 `cover_url`、`duration`
- `file`：上传 `secure_file` 或传 `url`，可选 `name`、`mime`、`size`
- `contact_card`：`card_user_id`
- `transfer`：`money`、`asset_type=money|integral`，群聊还必须传 `receiver_id`
- `red_packet`：`money`、`asset_type=money|integral`，群聊可传 `packet_type=ordinary|luck|specified`、`quantity`、`receiver_id`

### 表情、GIF 和贴纸

聊天输入区内置三栏面板：`表情`、`贴纸`、`商店`。输入法自带 Unicode 表情按普通文本发送；支持富内容输入的系统键盘可插入 `image/gif`、`image/png`、`image/jpeg`、`image/webp`，客户端会写入临时文件后按 `gif` 或 `image` 发送，不再跳转单独页面。

内置默认表情来自 `assets/emoji/emoji.xml` 和 `assets/emoji/default/`，发送 `content_type=emoji`，`secure_payload` 至少包含：

```json
{
  "content": "[表情]",
  "pack_id": "default",
  "emoji_id": "0_0",
  "emoji_code": "0_0",
  "sticker_id": "0_0",
  "emoji_asset": "assets/emoji/default/0_0.png",
  "media": {
    "pack_id": "default",
    "format": "png",
    "emoji_code": "0_0",
    "sticker_id": "0_0",
    "emoji_asset": "assets/emoji/default/0_0.png"
  }
}
```

动态贴纸按 `content_type=gif` 发送，静态贴纸按 `content_type=sticker` 发送。贴纸消息必须包含稳定的 `pack_id`、`sticker_id`，并包含 `url` 或 `media.url`；本地内置资源只允许 `pack_id=default` 使用 `assets/...`。客户端接收端会优先使用 `emoji_asset/sticker_asset`，其次使用 `url/media.url`，不会把 `[表情]`、`[GIF]`、`[贴纸]` 当成最终展示内容。

表情商店接口必须走密文请求和密文响应：

- `im_sticker_packs`：分页返回可用表情包，支持字段 `list/items/rows/records/packs/packages`。每个包需要 `pack_id`、`title/name`、`cover/cover_url`、`price/price_text`、`items/stickers`；每个贴纸需要 `sticker_id`、`name/title`、`url/file_url/image_url/gif_url`、`format`、`animated`。
- `im_sticker_mine`：返回当前用户已拥有包，可返回包对象列表，也可返回 `pack_ids/ids/owned_pack_ids`。
- `im_sticker_pack_buy`：购买或添加表情包，参数 `pack_id`。免费包也必须走该接口写入用户拥有关系，客户端不本地伪造拥有状态。

客户端会把表情包列表和已拥有包 ID 缓存到加密 MMKV。商店接口不可用时，`商店` 页直接显示接口错误；`贴纸` 页只展示已缓存且已拥有的贴纸包，不生成假数据。会话列表摘要中 `[表情]`、`[GIF]`、`[贴纸]` 使用媒体前缀样式显示，聊天气泡内展示真实图片/GIF，并在发送中显示上传进度，失败时点击重发。

客户端生成唯一 `client_msg_no`，格式为 `bim_{userId}_{timestamp随机串}`。同一条消息只生成一次，避免重复文本触发 `client_msg_no已被其它消息内容占用`。

发送时客户端先写入 MMKV 本地“发送中”消息，业务端返回后按同一 `client_msg_no` 合并为“已发送”或“队列中”。网络或超时类错误最多重试 3 次，重试复用同一个 `client_msg_no` 但重新生成 `nonce/sign`；业务拒绝不重试。接收方和发送方的服务端推送都通过实时长连接进入本地缓存。

群禁言不再使用悟空频道黑名单。服务端只写 `chat_group_mute` 业务表，群发前用该表硬校验；客户端打开群聊时调用 `im_group_mute_status` 获取当前用户禁言状态。若被禁言，输入框和更多面板直接禁用，并显示“你已被管理员禁言，原因：...”这类用户提示。

## 消息接收

实时收包处理流程：

1. Gateway stream 按 4 字节大端长度前缀切包。
2. JSON 解码 frame，按 `type=message|heartbeat|kick|error` 分发。
3. `heartbeat` 只刷新连接活性；`kick/error` 关闭当前 stream 并按状态机处理。
4. `message` 读取 `cursor`、`channel_id`、`channel_type`、`client_msg_no`、`message_id`、`message_seq`、`payload`。
5. payload 如果是 JSON 对象直接使用；如果是字符串或 Base64 JSON，客户端会解成业务 payload。
6. 归一化为聊天页字段：`client_msg_no`、`message_id`、`message_seq`、`channel_id`、`channel_type`、`from_uid`、`is_me`、`content`、`content_type`、`payload`、`timestamp`、`status`。
7. 写入 MMKV，按 `client_msg_no` 优先、`message_seq` 次之去重合并。
8. 更新会话缓存和当前频道消息版本，UI 自动刷新。
9. 本地落库成功后调用 `/api/sync/ack`，ACK 成功才保存本地 Gateway cursor。

私聊收到的频道如果是当前用户 UID，会转换为对方 `from_uid`，与聊天页使用的私聊频道保持一致。

服务层同时暴露本地广播消息流。聊天页和首页会话列表订阅该事件流后直接增量合并消息和会话，实时收包、本地发送中、发送确认、发送失败都会立即推送到 UI；重新读取 MMKV 只作为冷启动和补偿同步使用。

命令消息不进入普通消息列表。群主或管理员禁言/解除禁言时，服务端发送 `content_type=cmd`、`cmd=group_member_mute_changed` 的 CMD 通知，客户端只用它刷新本地禁言状态和输入框，不把 CMD 当聊天气泡展示。会话列表同步时服务端会取多条 recent 并选择第一条可展示聊天消息，避免 CMD 把会话摘要冲空。

`im_group_mute_status` 请求示例：

```text
action=im_group_mute_status
usertoken=用户登录 token
device=32位随机hex设备号
device_flag=0
device_level=1
timestamp=当前秒级时间戳
nonce=随机串
sign=按签名规则生成
group_id=群聊业务ID
```

返回字段：`muted`、`reason`、`expire_time`、`permanent`、`notice`、`group_id`、`channel_id`、`channel_type`。`muted=1` 时客户端禁用输入框；`muted=0` 时恢复输入。

## 本地缓存

MMKV 存储：

- 登录态和设备号。
- 冷启动、热启动时间。
- 会话列表轻量缓存。
- 频道消息轻量缓存。
- 聊天草稿。
- 最近访问频道索引。

客户端不会使用默认 `mmkv` 目录和 `mmkv.default` 文件名。启动时在应用私有目录下初始化 `.bim_data` 缓存目录，实际存储实例名为 `bim_store_v1`，并通过 Android Keystore 保护随机加密 key 后以 MMKV `cryptKey` 打开。Android 侧关闭应用数据备份，避免缓存文件被系统备份导出。当前仍处于开发调试阶段，新版本不会读取旧 `app_flutter/mmkv` 调试缓存，也不会主动迁移或删除旧缓存文件。

业务端 `im_connect` 会返回 `private_history_sync_enabled`、`group_history_sync_enabled`、`server_history_sync_enabled`。这些字段只控制用户端是否拉取服务端历史，不代表服务端是否保存消息；后台仍可基于发送记录审计消息。

首次安装、清除应用数据或本地没有会话缓存时，客户端会先读取上述开关：

- 任一历史同步开启：消息首页标题显示“同步中”，调用 `im_conversations` 拉取允许同步类型的会话，完成后标题恢复“消息”。
- 历史同步全部关闭：不恢复已读历史，只加载当前账号、好友、群聊等基础资料；如果服务端会话存在未读数，仍会拉取未读补偿窗口，保证离线或换设备后能看到尚未读过的新消息。

未读补偿规则：

- `im_conversations` 在某类历史同步关闭时，只返回该类仍有未读数的会话；没有未读的会话不返回。
- 客户端发现某个同步关闭的会话 `unread_count > 0` 时，调用对应历史接口并带 `unread_only=1`、`unread_limit=未读数`。
- 私聊补偿接口：`im_person_messages`。
- 群聊补偿接口：`im_group_messages`。
- 未读补偿只合并新消息，不把服务端窗口当成完整历史，也不会删除本地已有消息。
- 用户打开会话并完成未读补偿后，服务端按原有已读逻辑清除该用户未读数。

聊天页历史消息接口只在本次启动首次打开某个聊天时同步一次，避免服务端历史开启后聊天页缺少前序消息：

- 私聊：`im_person_messages`
- 群聊：`im_group_messages`

这些同步由用户打开会话触发，不会使用定时器反复请求历史消息，也不会用业务接口代替实时收消息。若历史接口返回错误，本次启动不会标记为已完成，后续再次打开仍可补偿；实时收发只以 Gateway HTTPS Stream 为准。

同一个会话页生命周期内只允许一个历史同步任务在跑。成功返回空列表也会标记本次已同步，避免反复请求 `im_person_messages` 或 `im_group_messages`；接口异常会短暂退避后再允许重新打开会话同步。

客户端不会把 `im_conversations` 的会话摘要尾消息写入聊天记录缓存。聊天记录只来自 Gateway 实时帧、发送成功回执、本地发送中消息和对应历史消息接口。某类同步关闭且没有未读时，客户端不请求该类历史接口；用户端只显示本地缓存，卸载或清除应用数据后历史为空。某类同步关闭但存在未读时，只同步未读补偿窗口。某类同步开启时，客户端会从服务端恢复该类会话和历史，卸载重装后仍可拉取。

钱包收款、付款成功通知不进入好友私聊。服务端通过独立“支付通知”服务号发送 `wallet_notice` 消息，客户端将该服务号会话标记为只读，只允许查看通知卡片和进入账单详情。

## 聊天记录清理

用户端清理只影响当前登录用户自己的可见记录，不影响对方、其他群成员、好友关系、群资料、红包/转账订单和后台审计队列。

- 设置 -> 消息连接 -> 清空聊天记录：调用 `im_chat_records_clear_all`，服务端写入当前用户全局清空边界；客户端清空 MMKV 会话、单聊消息、群聊消息、已读标记、草稿和本地删除墓碑。
- 私聊详情 -> 清空聊天：调用 `im_person_conversation_delete`，服务端只隐藏当前用户与该对方的历史；客户端清空该私聊频道缓存。
- 群设置 -> 清空聊天：调用 `im_group_conversation_delete`，服务端只隐藏当前用户在该群的历史；客户端清空该群频道缓存。
- 长按消息 -> 删除：调用 `im_message_delete`，服务端按当前用户写入单条消息墓碑；客户端删除对应 `client_msg_no` 并记录本地墓碑。

客户端本地也会保存清空边界和单条删除墓碑。后续 `im_conversations`、`im_person_messages`、`im_group_messages` 同步回来的旧数据，会先按本地边界和墓碑过滤再写入 MMKV，避免刚清空或删除的消息被历史接口拉回来。

## 连接保活

实时连接由 Gateway 周期性下发 heartbeat 帧。客户端收到任何 Gateway 帧都会刷新 `lastFrameAt`；超过 75 秒没有任何帧即判定假在线，关闭当前 stream 并按指数退避 + 随机抖动重连。客户端不再调用旧 `user_heartbeat`。

## 用户端功能

- 登录/注册：业务端登录注册接口。
- 消息：首页显示 MMKV 会话缓存，启动时同步一次 `im_conversations`，之后由 Gateway 新消息推动更新。
- 聊天：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包。
- 私聊规则：非好友只能发送文字，且单向最多三条；图片、语音、视频、文件、转账、红包等由业务端拦截。
- 群聊：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、红包、指定转账。
- 群聊文本支持 `mention_user_ids`、`mention_all`、`reply_client_msg_no`、`quote`、`burn_after_read`。
- 私聊文本支持 `reply_client_msg_no`、`quote`、`burn_after_read`。
- 引用消息：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片可被引用；红包、转账、领取/收款回执、系统通知、撤回消息、阅后即焚消息不可引用。客户端发送时同时带 `reply_client_msg_no`、`quote_client_msg_no`、`quote` 和 `quote_json` 快照，`quote` 包含原消息发送人昵称、类型和摘要，用于实时消息、历史同步和换设备后的稳定展示。
- 回执和动作：已读回执、回执状态、撤回、阅后即焚、红包领取、转账收款。
- 好友：本地已添加好友可按昵称/用户名过滤；添加朋友只能按用户名搜索；支持申请、处理申请、状态查询、删除好友。
- 群管理：建群、更新群资料、成员列表、加人、踢人、退出、解散、设置管理员、转让群主、禁言、解除禁言。

## 本地日志

日志路径在应用“我的 -> 消息连接 -> 诊断日志”页面展示。重点日志：

- API 请求/响应、耗时和错误码。
- Gateway Stream 打开、heartbeat、断线、重连、ACK。
- `client_msg_no`、频道、消息类型和发送结果。
- 实时收消息、解密、缓存写入和 UI 版本刷新。
- 实时原始数据、帧类型、断线、重连、ACK。

敏感字段会脱敏：`token`、`password`、`sign`、`secret`、`key`、`secure_payload`、消息正文、金额、备注、附件名、附件大小、附件密文 hash、Gateway cursor。普通用户日志不输出原始 `message_id` 和 Gateway cursor。

## 校验

代码变更后执行：

```bash
flutter pub get
dart format lib test
flutter analyze
```
