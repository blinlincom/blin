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
    defaultValue: '900000002',
  );
  static const appKey = String.fromEnvironment(
    'BIM_APP_KEY',
    defaultValue: 'vUBChM61mzSxIQuHsAoKDEd5PqZFTRW2',
  );

  static const imDeviceFlagApp = 0;
  static const imDeviceLevelMaster = 1;
}
