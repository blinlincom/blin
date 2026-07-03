# BIM

BIM Flutter client.

## 配置

默认接口配置在 `lib/src/core/app_config.dart`：

- `BIM_API_BASE_URL` 默认 `https://blcold.cn/api/`
- `BIM_APP_ID` 默认 `900000002`
- `BIM_APP_KEY` 默认当前应用 key，用于新版 `im_*` 请求签名

构建时可以通过 `--dart-define` 覆盖：

```bash
flutter run --dart-define=BIM_API_BASE_URL=https://your-domain/api/ --dart-define=BIM_APP_ID=900000002 --dart-define=BIM_APP_KEY=your_app_key
```

## IM 对接

客户端不再接入 Flutter IM SDK。登录后先调用业务端 `im_connect` 获取 `uid`、`token` 和 `route`，再按 `wss_addr`、`websocket_addr`、`ws_addr`、`tcp_addr` 的顺序建立实时长连接，实现握手、ping/pong、收包、ACK 和 MMKV 缓存刷新。

发送、红包、转账、撤回、回执、好友三句限制、禁言等业务规则不在客户端绕过，统一调用业务端签名 `im_*` 接口，由服务端发送到 IM，客户端通过实时长连接收到结果。IM 签名请求携带 `timestamp`、`nonce`、`sign`，服务端会拒绝同一 nonce 的抓包重放。客户端不会轮询消息列表。

详细接口和客户端规则见 [docs/client_im.md](docs/client_im.md)。

## GitHub 自动打包

已配置 GitHub Actions：推送到 `main` 会执行静态检查，推送 `v*` 标签或手动运行 workflow 会生成 Android、Web、iOS unsigned 产物。

配置方式见 [docs/github_actions.md](docs/github_actions.md)。

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test
```
