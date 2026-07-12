# BIM 新接口契约

新客户端只允许调用 `/api/v2/` 与 `/api/sync/`。TP8 action 接口、旧轮询接口、旧 `/api/im_*` 接口均已下线，不提供兼容和转发。

- [API接口清单.md](./API接口清单.md)：用户端、后台、回调与实时连接入口。
- 服务响应统一采用 `code`、`message`、`data`、`request_id` 信封。
- 鉴权接口使用 Bearer Access Token；刷新令牌只提交到刷新入口。
- 实时连接先申请单次票据，再使用 WSS 连接 `/api/sync/connect`。
- 数字资产、TRON、GasFree、闪兑和 OTC 不属于新产品，接口与数据模型均不提供。
