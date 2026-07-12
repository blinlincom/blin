# BIM API v2 接口清单

统一响应：`{"code":"OK","message":"...","data":...,"request_id":"..."}`。受保护接口使用 `Authorization: Bearer <access_token>`。

## 公共与账号

- `GET /api/v2/app/info`
- `POST /api/v2/verification/captcha`
- `POST /api/v2/verification/code`
- `POST /api/v2/auth/register`
- `POST /api/v2/auth/login/password`
- `POST /api/v2/auth/token/refresh`
- `GET /api/v2/auth/me`
- `POST /api/v2/auth/logout`

## 用户、好友与群聊

- `/api/v2/users`：资料、设置、设备。
- `/api/v2/social`：好友申请、好友列表、搜索、群聊、成员、管理员、禁言、退群与解散。
- `/api/v2/engagement`：签到、邀请码、关注、粉丝、排行榜和徽章。

## 即时通讯

- `/api/v2/im/messages`：发送消息；客户端必须生成全局唯一 `client_msg_no`。
- `/api/v2/im/history`、`/conversations`、`/read`、`/receipts/{messageID}`。
- 消息删除、会话清空、撤回、阅后即焚均为用户级状态，不会被历史同步重新拉回。
- `GET /api/sync/connect` 获取单次连接票据，`GET /api/sync/ws` 建立长连接；客户端处理 `message`、`read_receipt`、在线状态和 ACK。

## 媒体、朋友圈与音视频

- `/api/v2/assets`：鉴权上传与短时签名下载。
- `/api/v2/moments`：动态、点赞、评论、删除。
- `/api/v2/calls`：发起、接听、拒绝、结束和 LiveKit token。
- `POST /callbacks/v1/livekit`：LiveKit 官方签名回调。

## 钱包

- `/api/v2/wallet/balance`、`/bills`、`/bills/{id}`。
- 支付密码、转账、红包、交易详情、提现、收款码、一次性付款码、扫码解析、扫码支付和付款方确认。
- 所有金额请求使用两位小数字符串；响应金额同样使用两位小数字符串。

## 用户内容与商品

- `/api/v2/portal/sections`、`/posts`、评论、点赞、收藏、举报。
- `/api/v2/portal/notes`。
- `/api/v2/portal/products`、`/orders`。
- `/api/v2/portal/stickers/packs`。
- `/api/v2/portal/market`。

## 管理后台

- `/admin-api/v1/auth`
- `/admin-api/v1/ops`：用户、群聊、消息、服务号、通话、审计。
- `/admin-api/v1/wallet`：钱包锁定、冻结、解冻和支付密码解锁。
- `/admin-api/v1/moments`、`/config`。
- `/admin-api/v1/portal`：内容、举报、商品、贴纸、应用、商户和提现审核。
