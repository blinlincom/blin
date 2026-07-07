import 'dart:convert';

class ApiResult<T> {
  const ApiResult({
    required this.code,
    required this.message,
    required this.data,
    required this.timestamp,
    this.sign,
  });

  final int code;
  final String message;
  final T data;
  final int timestamp;
  final String? sign;

  bool get isSuccess => code == 1;
}

class ApiException implements Exception {
  ApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

class ImRoute {
  const ImRoute({this.apiUrl = '', this.httpsStreamAddr = ''});

  final String apiUrl;
  final String httpsStreamAddr;

  factory ImRoute.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return ImRoute(
      apiUrl: map['api_url']?.toString() ?? '',
      httpsStreamAddr: map['https_stream_addr']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'api_url': apiUrl,
    'https_stream_addr': httpsStreamAddr,
  };
}

class GatewayStreamSession {
  const GatewayStreamSession({
    this.ticket = '',
    this.frameKey = '',
    this.frameAlg = '',
    this.expireIn = 0,
    this.lastCursor = '',
    this.httpsStreamAddr = '',
  });

  final String ticket;
  final String frameKey;
  final String frameAlg;
  final int expireIn;
  final String lastCursor;
  final String httpsStreamAddr;

  bool get isAvailable =>
      ticket.isNotEmpty && frameKey.isNotEmpty && httpsStreamAddr.isNotEmpty;

  factory GatewayStreamSession.fromJson(
    Object? value, {
    String httpsStreamAddr = '',
  }) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return GatewayStreamSession(
      ticket: map['ticket']?.toString() ?? '',
      frameKey: map['frame_key']?.toString() ?? '',
      frameAlg: map['frame_alg']?.toString() ?? '',
      expireIn: int.tryParse(map['expire_in']?.toString() ?? '') ?? 0,
      lastCursor: map['last_cursor']?.toString() ?? '',
      httpsStreamAddr: map['https_stream_addr']?.toString() ?? httpsStreamAddr,
    );
  }

  Map<String, Object?> toJson() => {
    'ticket': ticket,
    'frame_key': frameKey,
    'frame_alg': frameAlg,
    'expire_in': expireIn,
    'last_cursor': lastCursor,
    'https_stream_addr': httpsStreamAddr,
  };
}

class ChatSession {
  const ChatSession({
    required this.uid,
    required this.token,
    required this.device,
    required this.deviceFlag,
    required this.deviceLevel,
    required this.channelTypePerson,
    required this.channelTypeGroup,
    required this.route,
    this.stream,
    this.privateHistorySyncEnabled = true,
    this.groupHistorySyncEnabled = true,
  });

  final String uid;
  final String token;
  final String device;
  final int deviceFlag;
  final int deviceLevel;
  final int channelTypePerson;
  final int channelTypeGroup;
  final ImRoute route;
  final GatewayStreamSession? stream;
  final bool privateHistorySyncEnabled;
  final bool groupHistorySyncEnabled;

  factory ChatSession.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    final historySync = map['history_sync'] is Map
        ? (map['history_sync'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final route = ImRoute.fromJson(map['route']);
    final serverHistoryEnabled = _flagEnabled(
      map['server_history_sync_enabled'] ??
          historySync['server_history_sync_enabled'],
      defaultValue: true,
    );
    return ChatSession(
      uid: map['uid']?.toString() ?? '',
      token: map['token']?.toString() ?? '',
      device: map['device']?.toString() ?? '',
      deviceFlag: int.tryParse(map['device_flag']?.toString() ?? '') ?? 0,
      deviceLevel: int.tryParse(map['device_level']?.toString() ?? '') ?? 1,
      channelTypePerson:
          int.tryParse(map['channel_type_person']?.toString() ?? '') ?? 1,
      channelTypeGroup:
          int.tryParse(map['channel_type_group']?.toString() ?? '') ?? 2,
      route: route,
      stream: map['stream'] == null
          ? null
          : GatewayStreamSession.fromJson(
              map['stream'],
              httpsStreamAddr: route.httpsStreamAddr,
            ),
      privateHistorySyncEnabled:
          serverHistoryEnabled &&
          _flagEnabled(
            map['private_history_sync_enabled'] ??
                historySync['private_history_sync_enabled'],
          ),
      groupHistorySyncEnabled:
          serverHistoryEnabled &&
          _flagEnabled(
            map['group_history_sync_enabled'] ??
                historySync['group_history_sync_enabled'],
          ),
    );
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'token': token,
    'device': device,
    'device_flag': deviceFlag,
    'device_level': deviceLevel,
    'channel_type_person': channelTypePerson,
    'channel_type_group': channelTypeGroup,
    'route': route.toJson(),
    if (stream != null) 'stream': stream!.toJson(),
    'private_history_sync_enabled': privateHistorySyncEnabled ? 1 : 0,
    'group_history_sync_enabled': groupHistorySyncEnabled ? 1 : 0,
    'server_history_sync_enabled':
        privateHistorySyncEnabled || groupHistorySyncEnabled ? 1 : 0,
  };
}

bool _flagEnabled(Object? value, {bool defaultValue = true}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  final text = value.toString().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.username,
    required this.userToken,
    required this.chat,
    this.nickname = '',
    this.avatar = '',
    this.profileBackground = '',
  });

  final int userId;
  final String username;
  final String userToken;
  final ChatSession? chat;
  final String nickname;
  final String avatar;
  final String profileBackground;

  factory UserSession.fromJson(Map<String, Object?> map) {
    return UserSession(
      userId: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      username: map['username']?.toString() ?? '',
      userToken: map['usertoken']?.toString() ?? '',
      chat: map['chat'] == null ? null : ChatSession.fromJson(map['chat']),
      nickname: map['nickname']?.toString() ?? '',
      avatar: map['usertx']?.toString() ?? '',
      profileBackground:
          _stringFromKeys(map, const [
            'profile_background',
            'profile_background_url',
            'moments_background',
            'moments_cover',
            'cover_url',
            'background_url',
            'user_bg',
            'userbg',
          ]) ??
          '',
    );
  }

  Map<String, Object?> toJson() => {
    'id': userId,
    'username': username,
    'usertoken': userToken,
    'chat': chat?.toJson(),
    'nickname': nickname,
    'usertx': avatar,
    'profile_background': profileBackground,
  };

  UserSession copyWith({
    ChatSession? chat,
    String? nickname,
    String? avatar,
    String? profileBackground,
  }) {
    return UserSession(
      userId: userId,
      username: username,
      userToken: userToken,
      chat: chat ?? this.chat,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      profileBackground: profileBackground ?? this.profileBackground,
    );
  }
}

class ImageCaptcha {
  const ImageCaptcha({this.image = '', this.token = ''});

  final String image;
  final String token;

  bool get hasImage => image.trim().isNotEmpty;

  factory ImageCaptcha.fromJson(Object? value) {
    if (value is String) {
      return ImageCaptcha(image: value);
    }
    final map = _objectMap(value);
    final nested = _objectMap(map['data']);
    return ImageCaptcha(
      image:
          _stringFromKeys(map, const [
            'image',
            'img',
            'url',
            'captcha',
            'captcha_img',
            'captcha_image',
            'image_base64',
            'base64',
          ]) ??
          _stringFromKeys(nested, const [
            'image',
            'img',
            'url',
            'captcha',
            'captcha_img',
            'captcha_image',
            'image_base64',
            'base64',
          ]) ??
          '',
      token:
          _stringFromKeys(map, const [
            'token',
            'captcha_token',
            'key',
            'captcha_key',
            'captcha_id',
          ]) ??
          _stringFromKeys(nested, const [
            'token',
            'captcha_token',
            'key',
            'captcha_key',
            'captcha_id',
          ]) ??
          '',
    );
  }
}

class AppAuthConfig {
  const AppAuthConfig({
    this.passwordLoginEnabled = true,
    this.mobileLoginEnabled = false,
    this.loginCaptchaEnabled = false,
    this.registerEnabled = true,
    this.usernameRegisterEnabled = true,
    this.mobileRegisterEnabled = false,
    this.emailRegisterEnabled = false,
    this.registerCaptchaEnabled = false,
    this.inviteCodeEnabled = false,
    this.inviteCodeRequired = false,
  });

  static const defaults = AppAuthConfig();

  final bool passwordLoginEnabled;
  final bool mobileLoginEnabled;
  final bool loginCaptchaEnabled;
  final bool registerEnabled;
  final bool usernameRegisterEnabled;
  final bool mobileRegisterEnabled;
  final bool emailRegisterEnabled;
  final bool registerCaptchaEnabled;
  final bool inviteCodeEnabled;
  final bool inviteCodeRequired;

  bool get hasAnyLoginMode => passwordLoginEnabled || mobileLoginEnabled;
  bool get hasAnyRegisterMode =>
      usernameRegisterEnabled || mobileRegisterEnabled || emailRegisterEnabled;

  Map<String, Object?> toJson() => {
    'password_login_enabled': passwordLoginEnabled,
    'mobile_login_enabled': mobileLoginEnabled,
    'login_captcha_enabled': loginCaptchaEnabled,
    'register_enabled': registerEnabled,
    'username_register_enabled': usernameRegisterEnabled,
    'mobile_register_enabled': mobileRegisterEnabled,
    'email_register_enabled': emailRegisterEnabled,
    'register_captcha_enabled': registerCaptchaEnabled,
    'invite_code_enabled': inviteCodeEnabled,
    'invite_code_required': inviteCodeRequired,
  };

  factory AppAuthConfig.fromAppInfoMap(Map<String, Object?> map) {
    final sources = <Map<String, Object?>>[];
    void collect(Object? value, [int depth = 0]) {
      if (depth > 4) {
        return;
      }
      final object = _objectMap(value);
      if (object.isEmpty) {
        return;
      }
      sources.add(object);
      for (final key in const [
        'auth',
        'auth_config',
        'login',
        'login_config',
        'register',
        'register_config',
        'account',
        'account_config',
        'user',
        'user_config',
        'app_exten_info',
        'extend',
        'extra',
      ]) {
        collect(object[key], depth + 1);
      }
    }

    collect(map);
    final registerEnabled = _boolFromSources(sources, const [
      'register_enabled',
      'enable_register',
      'user_register_enabled',
      'registration_enabled',
      'allow_register',
      'is_register',
    ], defaultValue: true);
    final inviteEnabled = _boolFromSources(sources, const [
      'invite_code_enabled',
      'invitecode_enabled',
      'enable_invite_code',
      'register_invite_enabled',
      'is_invite_code',
      'invite_code',
      'invitecode',
    ]);
    return AppAuthConfig(
      passwordLoginEnabled: _boolFromSources(sources, const [
        'password_login_enabled',
        'enable_password_login',
        'login_password_enabled',
        'account_login_enabled',
        'username_login_enabled',
        'password_login',
        'account_login',
        'username_login',
      ], defaultValue: true),
      mobileLoginEnabled: _boolFromSources(sources, const [
        'mobile_login_enabled',
        'phone_login_enabled',
        'sms_login_enabled',
        'enable_mobile_login',
        'enable_phone_login',
        'is_mobile_login',
        'is_phone_login',
        'mobile_login',
        'phone_login',
        'sms_login',
      ]),
      loginCaptchaEnabled: _boolFromSources(sources, const [
        'login_captcha_enabled',
        'login_image_captcha_enabled',
        'enable_login_captcha',
        'enable_login_image_captcha',
        'is_login_captcha',
        'login_captcha',
        'login_img_code',
        'login_image_code',
      ]),
      registerEnabled: registerEnabled,
      usernameRegisterEnabled:
          registerEnabled &&
          _boolFromSources(sources, const [
            'username_register_enabled',
            'account_register_enabled',
            'enable_username_register',
            'enable_account_register',
            'is_username_register',
            'username_register',
            'account_register',
          ], defaultValue: true),
      mobileRegisterEnabled:
          registerEnabled &&
          _boolFromSources(sources, const [
            'mobile_register_enabled',
            'phone_register_enabled',
            'sms_register_enabled',
            'enable_mobile_register',
            'enable_phone_register',
            'is_mobile_register',
            'is_phone_register',
            'mobile_register',
            'phone_register',
            'sms_register',
          ]),
      emailRegisterEnabled:
          registerEnabled &&
          _boolFromSources(sources, const [
            'email_register_enabled',
            'enable_email_register',
            'is_email_register',
            'email_register',
          ]),
      registerCaptchaEnabled:
          registerEnabled &&
          _boolFromSources(sources, const [
            'register_captcha_enabled',
            'register_image_captcha_enabled',
            'enable_register_captcha',
            'enable_register_image_captcha',
            'is_register_captcha',
            'register_captcha',
            'register_img_code',
            'register_image_code',
          ]),
      inviteCodeEnabled: registerEnabled && inviteEnabled,
      inviteCodeRequired:
          registerEnabled &&
          _boolFromSources(
            sources,
            const [
              'invite_code_required',
              'invitecode_required',
              'require_invite_code',
              'required_invite_code',
            ],
            defaultValue:
                inviteEnabled &&
                _boolFromSources(sources, const [
                  'invite_code_must',
                  'invitecode_must',
                ]),
          ),
    );
  }
}

class AppInfo {
  const AppInfo({
    required this.name,
    this.icon = '',
    this.introduction = '',
    this.auth = AppAuthConfig.defaults,
  });

  final String name;
  final String icon;
  final String introduction;
  final AppAuthConfig auth;

  factory AppInfo.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return AppInfo(
      name: map['appname']?.toString() ?? 'BIM',
      icon: map['appicon']?.toString() ?? '',
      introduction: map['application_introduction']?.toString() ?? '',
      auth: AppAuthConfig.fromAppInfoMap(map),
    );
  }

  Map<String, Object?> toJson() => {
    'appname': name,
    'appicon': icon,
    'application_introduction': introduction,
    'auth': auth.toJson(),
  };
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

String? _stringFromKeys(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = _valueForKey(map, key);
    if (value != null &&
        value is! Map &&
        value is! Iterable &&
        value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return null;
}

bool _boolFromSources(
  List<Map<String, Object?>> sources,
  List<String> keys, {
  bool defaultValue = false,
}) {
  for (final source in sources) {
    for (final key in keys) {
      final value = _valueForKey(source, key);
      if (value != null) {
        return _enabled(value, defaultValue: defaultValue);
      }
    }
  }
  return defaultValue;
}

Object? _valueForKey(Map<String, Object?> map, String key) {
  final wanted = key.toLowerCase();
  for (final entry in map.entries) {
    if (entry.key.toLowerCase() == wanted) {
      return entry.value;
    }
  }
  return null;
}

bool _enabled(Object? value, {bool defaultValue = false}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) {
    return defaultValue;
  }
  if (const {
    '1',
    'true',
    'yes',
    'on',
    'open',
    'enable',
    'enabled',
    '开启',
    '开',
    '启用',
  }.contains(text)) {
    return true;
  }
  if (const {
    '0',
    'false',
    'no',
    'off',
    'close',
    'closed',
    'disable',
    'disabled',
    '关闭',
    '关',
    '停用',
  }.contains(text)) {
    return false;
  }
  return int.tryParse(text) != null ? int.parse(text) != 0 : defaultValue;
}
