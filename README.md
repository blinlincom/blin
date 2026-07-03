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

客户端使用 `wukongimfluttersdk` 作为实时层。登录后先调用业务端 `im_connect` 获取 `uid`、`token` 和 `tcp_addr`，再由 SDK 建立长连接、同步会话、同步频道消息并写入 SDK 本地库。

发送、红包、转账、撤回、回执、好友三句限制、禁言等业务规则不在客户端绕过，统一调用业务端签名 `im_*` 接口，由服务端发送到 IM，客户端通过 SDK 实时收到结果。

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
