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

热启动恢复时会再次刷新 `im_connect`，重新确认 token 和路由。

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
- `addOnSyncConversationListener`：SDK 冷启动/重连时调用业务端 `im_conversations`，转换为 `WKSyncConversation` 入库。
- `addOnSyncChannelMsgListener`：SDK 拉频道历史时调用 `im_person_messages` 或 `im_group_messages`，转换为 `WKSyncChannelMsg` 入库。
- `addOnGetChannelListener`：SDK 需要频道资料时从好友/群列表补全名称和头像。

## 消息发送规则

客户端不直接用 SDK 伪造业务消息。发送动作统一走业务端签名接口：

- 私聊：`im_person_send`
- 群聊：`im_group_send`
- 已读：`im_message_read_receipt`
- 回执查询：`im_message_receipt_status`
- 撤回：`im_message_recall`
- 阅后即焚：`im_burn_after_read`
- 私聊红包领取：`im_person_red_packet_receive`
- 群红包领取：`im_group_red_packet_receive`
- 转账收款：`im_person_transfer_receive`

原因：好友关系、非好友三句限制、禁言、红包扣款、转账入账、过期退回、队列重试和去重必须由服务端保证。客户端使用 SDK 生成唯一 `client_msg_no`，提交业务接口；服务端发送到 IM 后，客户端通过 SDK 长连接或同步回写本地库。

聊天页已经接入用户侧交互：文本、图片、语音、视频、文件、名片、表情、GIF、贴纸、红包、转账都从聊天工具面板进入；引用通过长按消息后点“引用”；群聊 @ 和阅后即焚通过“文本选项”设置；撤回、已读、领取红包、收转账通过长按消息进入。用户端不展示队列重试、在线连接、接口回执调试等运维入口。

## 客户端功能封装

`lib/src/im/chat_feature_service.dart` 已封装业务端当前 IM 功能，所有方法都会使用 SDK 生成或复用 `client_msg_no`：

- 私聊发送：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包。
- 群聊发送：文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、指定转账、普通红包、拼手气红包、指定红包。
- 群聊文本：支持 `mention_user_ids`、`mention_all`、`reply_client_msg_no`、`burn_after_read`。
- 私聊文本：支持 `reply_client_msg_no`、`burn_after_read`。
- 回执与动作：已读回执、回执状态、撤回、阅后即焚、红包领取、转账收款。
- 好友：申请、处理申请、状态查询、删除好友。
- 群管理：建群、更新群资料、成员列表、加人、踢人、退出、解散、设置管理员、转让群主、禁言、解除禁言。
- 用户侧会话：清空单聊会话、删除好友、群资料、群成员、退群、解散群。
- 运维/后台能力：在线用户、重试发送失败队列、后台删除会话仍保留在业务端和服务封装里，不在普通客户端页面暴露。

文件类消息支持两种方式：

- 已上传资源：传 `url`。
- 本地文件：传 `filePath`，客户端使用 `multipart/form-data` 上传 `file` 字段；签名只覆盖非文件字段。

常用方法和接口对应关系：

- `sendPrivateText` -> `im_person_send content_type=text`
- `sendGroupText` -> `im_group_send content_type=text`
- `sendPrivateMedia` -> `im_person_send content_type=image|emoji|gif|sticker|voice|video|file`
- `sendGroupMedia` -> `im_group_send content_type=image|emoji|gif|sticker|voice|video|file`
- `sendPrivateContactCard` / `sendGroupContactCard` -> `content_type=contact_card`
- `sendPrivateTransfer` / `sendGroupTransfer` -> `content_type=transfer`
- `sendPrivateRedPacket` / `sendGroupRedPacket` -> `content_type=red_packet`
- `friendApply` / `friendHandle` / `friendApplyList` / `friendStatus` / `friendDelete` -> 好友接口
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
- 消息：SDK 本地会话列表为主，业务端 `im_conversations` 为冷启动兜底。
- 聊天页：读取 SDK 本地消息库；所有发送动作先走业务端 `im_person_send` / `im_group_send`，再由 SDK 长连接实时刷新；支持文本、图片、表情、GIF、贴纸、语音、视频、文件、名片、转账、红包、引用、群 @、阅后即焚、撤回、已读、红包领取、转账收款。
- 联系人：好友列表、群聊列表、添加好友、好友申请、发起群聊。
- 发现：添加朋友、新的朋友、发起群聊、我的群聊，全部为用户侧入口。
- 群资料：查看群成员、添加成员、禁言/解除禁言、设管理员、转让群主、移出成员、退群、解散群。
- 私聊设置：查看好友状态、清空聊天、删除好友。
- 我的：展示设备号、IM UID、TCP 地址、冷启动/热启动时间和连接状态。

## 校验

已执行：

```bash
flutter analyze
```

说明：本地未执行打包。`flutter test` 在当前 Termux/Flutter 环境会被 `objective_c` native assets Android 支持限制拦截，不属于业务代码错误。
