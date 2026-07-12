class AppConfig {
  const AppConfig._();

  static const appName = 'BIM';
  static const packageName = 'bimotc.com';
  static const apiBaseUrl = String.fromEnvironment(
    'BIM_API_BASE_URL',
    defaultValue: 'https://blcold.cn/api/',
  );
  static const appId = String.fromEnvironment(
    'BIM_APP_ID',
    defaultValue: '1',
  );
  static const appKey = String.fromEnvironment(
    'BIM_APP_KEY',
    defaultValue: 'vUBChM61mzSxIQuHsAoKDEd5PqZFTRW2',
  );
  // 开发调试期默认打印完整请求参数；正式发布时用
  // --dart-define=BIM_DEBUG_FULL_API_LOG=false 关闭敏感明文日志。
  static const debugFullApiLog = bool.fromEnvironment(
    'BIM_DEBUG_FULL_API_LOG',
    defaultValue: true,
  );

  static const imDeviceFlagApp = 0;
  static const imDeviceLevelMaster = 1;
}
