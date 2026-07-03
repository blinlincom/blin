# BIM 客户端 IM 对接文档

## 运行配置

客户端配置通过 `--dart-define` 覆盖：

```bash
flutter run \
  --dart-define=BIM_API_BASE_URL=https://blcold.cn/api/ \
  --dart-define=BIM_APP_ID=900000002 \
  --dart-define=BIM_APP_KEY=替换为业务端应用密钥
```

默认值在 `lib/src/core/app_config.dart`。`BIM_API_BASE_URL` 可以是 `http` 或 `https`，由客户部署情况决定；当前线上默认使用 HTTPS。IM SDK 连接地址不在客户端写死，登录后读取业务端 `im_connect.route.tcp_addr`。

## 启动流程

1. `main.dart` 初始化 MMKV。
2. `SessionStore.ensureDeviceId()` 生成并持久化设备号，格式为 `bimotc.com-<随机16字节hex>`。
3. 冷启动 `SessionController.coldStart()` 读取 MMKV 登录态。
4. 已登录时调用 `im_connect`，请求携带 `device`、`device_flag=0`、`device_level=1`、`timestamp`、`sign`。
5. `WukongImService.start()` 使用 `uid`、`token`、`tcp_addr` 初始化 `wukongimfluttersdk` 并 `connect()`。
6. SDK 负责长连接、断线重连、会话同步、频道消息同步、命令消息监听和本地消息库。

热启动恢复时会再次刷新 `im_connect`，重新确认 token 和路由。客户端同时会调用 `WukongImService.ensureConnected()` 检查 SDK 连接状态，避免前后台切换后停在“连接中”。

## 签名规则

客户端新版 `im_*` 请求统一使用 `ApiSigner`：

- 参数包含 `appid`、业务参数、`usertoken`、`device`、`device_flag`、`device_level`、`timestamp`。
- 排除 `sign`、`callback`、`action` 和空值。
- 参数按 key 排序后 JSON 编码，拼接 `secretKey={BIM_APP_KEY}`。
- MD5 小写输出。

旧登录注册接口不加新版 IM 签名，但会传 `device`，用于业务端返回 IM 登录材料。

## SDK 实时层

依赖：`wukongimfluttersdk: ^1.7.9`。

SDK 自带本地缓存，内部使用 `sqflite`，数据库路径来自 `getDatabasesPath()`，文件名为 `wk_{uid}.db`。SDK 本地表包含 `message`、`message_extra`、`message_reaction`、`conversation`、`conversation_extra`、`channel`、`channel_members`、`reminders` 等。客户端不重复用 MMKV 存消息正文，避免双缓存不一致。

MMKV 只存客户端轻量状态：

- 登录态和设备号。
- 冷启动、热启动时间。
- 聊天草稿。
- 最近频道轻量索引。

当前 SDK 已提供本地消息库，所以客户端没有用 MMKV 保存消息正文、会话正文或历史记录。以后如果 SDK 某类数据没有本地缓存，只能用 MMKV 做轻量补充缓存，仍以 SDK/业务端数据为准。

客户端接入点：

- `lib/src/im/wukong_im_service.dart`
- `lib/src/im/bim_message_content.dart`
- `lib/src/im/im_message_types.dart`

SDK 回调：

- `addOnConnectionStatus`：更新连接状态。
- `addOnRefreshMsgListListener`：刷新会话列表。
- `addOnNewMsgListener`：收到新消息后刷新本地会话。
- `addOnRefreshMsgListener`：回执、撤回等消息刷新。
- `addOnCmdListener`：处理已读、红包领取、转账收款、阅后即焚等命令后刷新。
- `addOnSyncConversationListener`：SDK 冷启动/重连时调用业务端 `im_conversations`，转换为 `WKSyncConversation` 入库；普通页面不能直接请求该接口刷新列表。
- `addOnSyncChannelMsgListener`：SDK 拉频道历史时调用 `im_person_messages` 或 `im_group_messages`，转换为 `WKSyncChannelMsg` 入库。
- `addOnGetChannelListener`：SDK 需要频道资料时从好友/群列表补全名称和头像。

### ConnectionManager 管理

客户端不修改 SDK 源码，而是在 `WukongImService` 封装连接守护层，所有连接动作最终都调用 `WKIM.shared.connectionManager.connect()`：

- 冷启动/登录：`start()` 初始化 `Options(uid, token, tcp_addr)` 后调用连接管理器。
- 热启动/前台恢复：`SessionController.appLifecycleChanged(resumed)` 调用 `hotResume()` 和 `ensureConnected()`。
- 后台切走：记录状态并取消本次连接 watchdog，不清空 SDK 登录态。
- 连接中超时：如果 12 秒仍未进入 `success/syncMsg/syncCompleted`，watchdog 重新触发连接管理器。
- 失败/无网络：记录 `reason_code`，进入 watchdog 调度；最小重连间隔 3 秒，避免频繁断开重连。
- 成功/同步完成：取消 watchdog，刷新 SDK 本地会话。

日志字段包含 `source`、`attempt`、`status`、`reason_code`、`node_id`、`background_seconds`，用于排查真机卡在连接中的原因。

## 消息发送规则

聊天内容发送必须走 WuKongIM Flutter SDK：

- 文本：`WKIM.shared.messageManager.sendWithOption(WKTextContent, WKChannel, WKSendOptions)`
- 图片、语音、视频、文件、表情、GIF、贴纸、名片、转账、红包：`WKIM.shared.messageManager.sendWithOption(BimMessageContent, WKChannel, WKSendOptions)`
- 已读：`im_message_read_receipt`
- 回执查询：`im_message_receipt_status`
- 撤回：`im_message_recall`
- 阅后即焚：`im_burn_after_read`
- 私聊红包领取：`im_person_red_packet_receive`
- 群红包领取：`im_group_red_packet_receive`
- 转账收款：`im_person_transfer_receive`

SDK 负责生成 `client_msg_no`、本地入库、会话更新、长连接投递和 sendack 状态刷新。客户端不再调用 `im_person_send` / `im_group_send` 作为代发接口，也不保留 HTTP 发送兜底，避免发送方无法即时显示、接收方无法通过 SDK 实时刷新。

聊天页已经接入用户侧交互：文本、图片、语音、视频、文件、名片、表情、GIF、贴纸、红包、转账都从聊天工具面板进入；引用通过长按消息后点“引用”；群聊 @ 和阅后即焚通过“文本选项”设置；撤回、已读、领取红包、收转账通过长按消息进入。用户端不展示队列重试、在线连接、接口回执调试等运维入口。

实时收发链路：

- 收消息：SDK TCP 长连接收到消息后写入 SDK 本地库，`addOnNewMsgListener` / `addOnRefreshMsgListener` / `addOnCmdListener` 刷新会话和聊天页。
- 发消息：客户端调用 SDK `sendWithOption`。SDK 先写入本地库并触发 `addOnMsgInsertedListener`，聊天页立即更新；随后 SDK 通过长连接投递并通过 `addOnRefreshMsgListener` 更新发送状态。
- 聊天页刷新：聊天页监听当前 `channel_id + channel_type` 的 SDK 消息版本；当前频道收到新消息、发送后同步、回执/撤回等刷新消息时会重载当前频道消息，不再只依赖会话列表变化。
- 会话同步：`im_conversations` 只允许由 SDK `addOnSyncConversationListener` 触发；页面不直接请求该接口，避免反复轮询业务端。

## 客户端功能封装

`lib/src/im/wukong_im_service.dart` 封装 SDK 实时发送和监听；`lib/src/im/chat_feature_service.dart` 只保留业务动作接口，不再保留消息 HTTP 代发方法：

- 私聊发送：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包。
- 群聊发送：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、指定转账、普通红包、拼手气红包、指定红包。
- 群聊文本：支持 `mention_user_ids`、`mention_all`、`reply_client_msg_no`、`burn_after_read`。
- 私聊文本：支持 `reply_client_msg_no`、`burn_after_read`。
- 回执与动作：已读回执、回执状态、撤回、阅后即焚、红包领取、转账收款。
- 好友：搜索用户、申请、处理申请、状态查询、删除好友。
- 群管理：建群、更新群资料、成员列表、加人、踢人、退出、解散、设置管理员、转让群主、禁言、解除禁言。
- 用户侧会话：清空单聊会话、删除好友、群资料、群成员、退群、解散群。
- 运维/后台能力：在线用户、重试发送失败队列、后台删除会话仍保留在业务端和服务封装里，不在普通客户端页面暴露。

文件类消息支持两种 payload 方式：

- 已上传资源：传 `url`。
- 本地文件：传 `file_path`。当前客户端把文件路径作为 SDK 消息 payload 发送，不再走业务端 multipart 代发。

常用方法和接口对应关系：

- `sendTextMessage` -> SDK `WKTextContent` + `WKSendOptions`
- `sendPrivateMedia` / `sendGroupMedia` -> SDK `BimMessageContent`，`content_type=image|emoji|gif|sticker|voice|video|file`
- `sendPrivateContactCard` / `sendGroupContactCard` -> SDK `BimMessageContent`，`content_type=contact_card`
- `sendPrivateTransfer` / `sendGroupTransfer` -> SDK `BimMessageContent`，`content_type=transfer`
- `sendPrivateRedPacket` / `sendGroupRedPacket` -> SDK `BimMessageContent`，`content_type=red_packet`
- `friendSearch` / `friendApply` / `friendHandle` / `friendApplyList` / `friendStatus` / `friendDelete` -> 好友接口
- `groupCreate` / `groupUpdate` / `groupMembers` / `groupMembersAdd` / `groupMembersRemove` / `groupMemberMute` / `groupMemberUnmute` / `groupAdminSet` / `groupOwnerTransfer` / `groupLeave` / `groupDelete` -> 群管理接口
- `privateConversationDelete` -> 用户侧清空单聊会话
- `retryMessages` / `onlineUsers` -> 后台或内部维护能力，普通客户端不开放入口

## 消息类型

客户端注册并渲染以下类型：

- `1` 文本
- `2` 图片
- `3` 语音
- `4` 视频
- `5` 文件
- `99` 命令消息
- `1006` 撤回
- `5101` 转账
- `5102` 红包
- `5103` 红包领取通知
- `5104` 转账收款通知
- `5201` 表情
- `5202` GIF
- `5203` 贴纸
- `5207` 名片

## 用户端页面

- 登录/注册：业务端登录注册接口。
- 消息：只读取 SDK 本地会话列表。业务端 `im_conversations` 只能由悟空 SDK 会话同步回调触发，返回后由 SDK 入库并刷新 UI，页面层不做业务端兜底请求，避免重复轮询业务端。
- 聊天页：读取 SDK 本地消息库；所有聊天内容发送都走 SDK 长连接，不走业务端 HTTP 代发；支持文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包、引用、群 @、阅后即焚、撤回、已读、红包领取、转账收款。
- 联系人：好友列表、群聊列表、添加好友、好友申请、搜索用户、发起群聊。
- 发现：添加朋友、新的朋友、发起群聊、我的群聊，全部为用户侧入口。
- 群资料：查看群成员、添加成员、禁言/解除禁言、设管理员、转让群主、移出成员、退群、解散群。
- 私聊设置：查看好友状态、清空聊天、删除好友。
- 我的：展示设备号、IM UID、TCP 地址、冷启动/热启动时间和连接状态。

## 好友搜索

客户端搜索页会同时筛选 SDK/业务端已同步的本地好友、群聊，并调用业务端新 IM 接口 `im_friend_search` 搜索用户候选。

请求参数：`appid`、`usertoken`、`device`、`device_flag`、`device_level`、`timestamp`、`sign`，以及 `keyword` 或 `friend_id`，可选 `limit`。

返回字段：`list[].user`、`friend_id`、`uid`、`channel_id`、`channel_type`、`is_friend`、`non_friend_message_limit`、`non_friend_message_count`、`pending_out_apply`、`pending_in_apply`。

客户端规则：

- 已是好友：点击搜索结果进入私聊，私聊频道使用返回的 `channel_id`。
- 已发申请：显示已申请，不重复发起。
- 对方已申请：跳转好友申请页处理。
- 未建立关系：调用 `im_friend_apply` 发起好友申请。

好友列表展示规则：

- 标题优先显示好友备注，其次显示 `friend.nickname`，再显示用户名。
- 副标题显示用户名、用户 ID 和签名。
- 本地搜索会匹配好友昵称、用户名和用户 ID；远程搜索调用 `im_friend_search`，入口文案以用户名搜索为主。

## 本地日志

客户端启动时初始化本地日志文件：

- 文件路径在 App 内“我的 -> 消息连接 -> 诊断日志”页面展示。
- 页面支持一键复制完整日志，便于直接提供排查。
- 日志保留内存最近 300 条，同时写入 `bim.log`，超过 2MB 自动轮转为 `bim.log.1`。
- 敏感字段会脱敏：`token`、`password`、`sign`、`secret`、`key`。

重点日志范围：

- API 请求/响应、耗时和错误码。
- `client_msg_no`、频道、消息类型和发送结果。
- SDK ConnectionManager 状态、连接重试、连接中 watchdog。
- SDK 新消息、刷新消息、频道同步、会话同步。

## 校验

已执行：

```bash
flutter analyze
```

说明：本地未执行打包。`flutter test` 在当前 Termux/Flutter 环境会被 `objective_c` native assets Android 支持限制拦截，不属于业务代码错误。
