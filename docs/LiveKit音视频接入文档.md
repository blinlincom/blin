# BIM LiveKit 音视频接入文档

## 功能范围

- 私聊支持一对一语音通话、视频通话。
- 群聊支持多人语音通话、多人视频通话，入口在聊天快捷功能面板。
- 快捷操作支持创建语音会议、视频会议。
- 来电、接听、拒绝、取消、挂断信令走业务端 Gateway 实时通道，媒体流走 LiveKit。
- 客户端使用 `livekit_client 2.8.1`，不再使用占位 UI。

## 服务端配置

业务端 `/www/wwwroot/blin/.env` 已追加：

```ini
[LIVEKIT]
; 已部署 LiveKit Server 后设为 true。
ENABLED = true
; 当前生产入口，Flutter SDK 会连接 wss://blcold.cn/livekit/rtc。
URL = wss://blcold.cn/livekit
; 只允许放在服务端 .env，不允许下发客户端。
API_KEY = <服务端已配置>
API_SECRET = <服务端已配置>
TOKEN_TTL = 3600
PRIVATE_TIMEOUT = 45
GROUP_TIMEOUT = 90
MEETING_TIMEOUT = 300
MAX_GROUP_PARTICIPANTS = 16
MAX_MEETING_PARTICIPANTS = 50
; 官方 webhook 已使用 Authorization JWT + body sha256 校验，此项默认留空。
WEBHOOK_SECRET =
```

当前服务器部署：

- LiveKit Server：`1.13.3`
- systemd 服务：`livekit.service`
- LiveKit 配置：`/etc/livekit/livekit.yaml`
- 信令入口：`https://blcold.cn/livekit/` 反向代理到本机 `127.0.0.1:7880`
- SDK 连接地址：业务端返回 `wss://blcold.cn/livekit`
- 媒体 TCP：`7881`
- 媒体 UDP：`50000-60000`
- Redis：`127.0.0.1:6379`
- Webhook：`https://blcold.cn/api/livekit_webhook`

阿里云安全组必须放行：

- `443/TCP`：HTTPS/WSS 信令入口。
- `7881/TCP`：ICE/TCP 备用媒体通道。
- `50000-60000/UDP`：WebRTC 主媒体通道。

## 新增接口

所有接口继续走业务端签名和 `secure_payload` 加密。

- `im_call_create`：发起通话或会议
  - `call_type`: `private` / `group` / `meeting`
  - `media_type`: `audio` / `video`
  - `receiver_id`: 私聊必填
  - `group_id`: 群聊必填
  - `title`: 可选
  - 返回 `livekit.url` 和 `livekit.token`

- `im_call_accept`：接听
  - `call_id`
  - 返回新的 LiveKit token

- `im_call_reject`：拒绝
  - `call_id`

- `im_call_cancel`：主叫取消未接通呼叫
  - `call_id`

- `im_call_hangup`：挂断
  - `call_id`
  - `end_call=1` 时结束群聊/会议房间

- `im_call_token`：重新获取通话 token
  - `call_id`

- `livekit_webhook`：LiveKit 回调
  - LiveKit 官方回调会在 `Authorization` 放置签名 JWT。
  - 业务端校验 JWT 的 `iss`、`exp/nbf`、HS256 签名和请求体 `sha256`。
  - 如果以后在前置安全网关增加静态密钥，也支持 `Authorization: Bearer {WEBHOOK_SECRET}` 或 `X-LiveKit-Secret`。

## 客户端 UI

- 通话页为深色全屏页面，适配状态栏、底部安全区和横向宽屏。
- 私聊视频：远端画面全屏，本地画面右上角小窗。
- 私聊语音：居中展示头像、昵称和状态。
- 群聊/会议：成员自适应宫格，显示昵称、麦克风状态和视频画面。
- 控制区固定底部：麦克风、摄像头、扬声器、翻转摄像头、挂断。
- 来电页底部展示拒绝/接听，接听后才连接 LiveKit。

## 平台权限

- Android：`CAMERA`、`RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、蓝牙音频权限。
- iOS：`NSCameraUsageDescription`、`NSMicrophoneUsageDescription`。
- macOS：开启 camera、microphone、network client entitlement。

## 数据库

已新增三张表：

- `mr_livekit_call`
- `mr_livekit_call_participant`
- `mr_livekit_event_log`

## 注意事项

- LiveKit `API_SECRET` 只允许放服务端，客户端只拿短期 token。
- LiveKit 未配置时，业务端会直接返回“音视频服务未配置”。
- Gateway 必须正常在线，否则来电信令不能实时送达。
- 当前服务器本机防火墙为放行状态；如果公网 `7881/TCP` 或 `50000-60000/UDP` 不通，需要在阿里云安全组放行。
