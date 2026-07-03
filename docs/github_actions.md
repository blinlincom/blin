# GitHub Actions 自动打包

仓库包含 `.github/workflows/flutter-release.yml`。

## 触发方式

- 推送到 `main`：执行 `flutter analyze`。
- 推送 `v*` 标签：执行分析，并打包 Android、Web、iOS unsigned。
- 手动运行 `Flutter Release`：可以选择是否打包 Android、Web、iOS。

## 构建参数

Repository Variables：

- `BIM_API_BASE_URL`：业务端 API 地址，默认 `https://blcold.cn/api/`。
- `BIM_APP_ID`：应用 ID，默认 `900000002`。

Repository Secrets：

- `BIM_APP_KEY`：业务端应用密钥。未配置时使用代码默认值。

## Android 正式签名

未配置签名时，CI 会产出 release 构建但使用 debug keystore，方便测试下载。

正式发布需要配置以下 Secrets：

- `ANDROID_KEYSTORE_BASE64`：`release.keystore` 的 base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

生成 base64 示例：

```bash
base64 -w 0 release.keystore
```

配置后 workflow 会生成 `android/key.properties`，Gradle 自动使用正式签名。

## 产物

- `bim-android`：APK 和 AAB。
- `bim-web`：Web release 目录。
- `bim-ios-unsigned`：未签名 iOS `Runner.app` 压缩包。

## 本地推送安全

GitHub token 只用于本次 `git push` 网络认证，不写入源码、workflow、README 或 git remote URL。
