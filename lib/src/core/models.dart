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

class WalletBalance {
  const WalletBalance({
    this.balance = '0.00',
    this.balanceLabel = '0.00',
    this.payPasswordSet = false,
    this.payPasswordLocked = false,
    this.payPasswordLockedUntil = '',
    this.payPasswordFailedCount = 0,
    this.securityBound = false,
    this.securityMethods = const [],
    this.serverTime = 0,
  });

  final String balance;
  final String balanceLabel;
  final bool payPasswordSet;
  final bool payPasswordLocked;
  final String payPasswordLockedUntil;
  final int payPasswordFailedCount;
  final bool securityBound;
  final List<WalletSecurityMethod> securityMethods;
  final int serverTime;

  factory WalletBalance.fromJson(Object? value) {
    final map = _objectMap(value);
    final balance = _decimalLabel(map['balance']);
    final methods = <WalletSecurityMethod>[];
    final rawMethods = map['security_methods'];
    if (rawMethods is Iterable) {
      for (final item in rawMethods) {
        final method = WalletSecurityMethod.fromJson(item);
        if (method.method.isNotEmpty) {
          methods.add(method);
        }
      }
    }
    return WalletBalance(
      balance: balance,
      balanceLabel:
          _stringFromKeys(map, const ['balance_label', 'balance_text']) ??
          balance,
      payPasswordSet: _enabled(map['pay_password_set']),
      payPasswordLocked: _enabled(map['pay_password_locked']),
      payPasswordLockedUntil:
          _stringFromKeys(map, const ['pay_password_locked_until']) ?? '',
      payPasswordFailedCount:
          int.tryParse(map['pay_password_failed_count']?.toString() ?? '') ?? 0,
      securityBound: _enabled(map['security_bound']),
      securityMethods: methods,
      serverTime: int.tryParse(map['server_time']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'balance': balance,
    'balance_label': balanceLabel,
    'pay_password_set': payPasswordSet ? 1 : 0,
    'pay_password_locked': payPasswordLocked ? 1 : 0,
    'pay_password_locked_until': payPasswordLockedUntil,
    'pay_password_failed_count': payPasswordFailedCount,
    'security_bound': securityBound ? 1 : 0,
    'security_methods': securityMethods.map((item) => item.toJson()).toList(),
    'server_time': serverTime,
  };
}

class WalletSecurityMethod {
  const WalletSecurityMethod({
    required this.method,
    required this.label,
    required this.target,
  });

  final String method;
  final String label;
  final String target;

  factory WalletSecurityMethod.fromJson(Object? value) {
    final map = _objectMap(value);
    return WalletSecurityMethod(
      method: map['method']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      target: map['target']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'method': method,
    'label': label,
    'target': target,
  };
}

class UserSecurityInfo {
  const UserSecurityInfo({
    this.mobileBound = false,
    this.emailBound = false,
    this.mobile = '',
    this.email = '',
    this.securityBound = false,
    this.securityMethods = const [],
  });

  final bool mobileBound;
  final bool emailBound;
  final String mobile;
  final String email;
  final bool securityBound;
  final List<WalletSecurityMethod> securityMethods;

  factory UserSecurityInfo.fromJson(Object? value) {
    final map = _objectMap(value);
    final methods = <WalletSecurityMethod>[];
    final rawMethods = map['security_methods'];
    if (rawMethods is Iterable) {
      for (final item in rawMethods) {
        final method = WalletSecurityMethod.fromJson(item);
        if (method.method.isNotEmpty) {
          methods.add(method);
        }
      }
    }
    return UserSecurityInfo(
      mobileBound: _enabled(map['mobile_bound']),
      emailBound: _enabled(map['email_bound']),
      mobile: map['mobile']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      securityBound: _enabled(map['security_bound']),
      securityMethods: methods,
    );
  }
}

class WalletOrder {
  const WalletOrder({
    this.id = 0,
    this.orderNo = '',
    this.orderType = '',
    this.amount = '0.00',
    this.amountLabel = '0.00',
    this.amountRequired = false,
    this.remark = '',
    this.status = 0,
    this.statusName = '',
    this.payerId = 0,
    this.payerName = '',
    this.payerAvatar = '',
    this.payeeId = 0,
    this.payeeName = '',
    this.payeeAvatar = '',
    this.qrToken = '',
    this.qrPayload = '',
    this.barPayload = '',
    this.expireTime = '',
    this.expireSeconds = 0,
    this.refreshIn = 0,
    this.paidTime = '',
    this.createTime = '',
    this.currentUserRole = '',
  });

  final int id;
  final String orderNo;
  final String orderType;
  final String amount;
  final String amountLabel;
  final bool amountRequired;
  final String remark;
  final int status;
  final String statusName;
  final int payerId;
  final String payerName;
  final String payerAvatar;
  final int payeeId;
  final String payeeName;
  final String payeeAvatar;
  final String qrToken;
  final String qrPayload;
  final String barPayload;
  final String expireTime;
  final int expireSeconds;
  final int refreshIn;
  final String paidTime;
  final String createTime;
  final String currentUserRole;

  bool get isPaid => status == 1;
  bool get isPending => status == 0;
  bool get isPayCode => orderType == 'pay';
  bool get isCollectCode => orderType == 'collect';
  bool get needsAmountInput => !amountRequired || amount == '0.00';

  factory WalletOrder.fromJson(Object? value) {
    final map = _objectMap(value);
    final amount = _decimalLabel(map['amount']);
    return WalletOrder(
      id: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      orderNo: map['order_no']?.toString() ?? '',
      orderType: map['order_type']?.toString() ?? '',
      amount: amount,
      amountLabel:
          _stringFromKeys(map, const ['amount_label', 'amount_text']) ?? amount,
      amountRequired: _enabled(map['amount_required']),
      remark: map['remark']?.toString() ?? '',
      status: int.tryParse(map['status']?.toString() ?? '') ?? 0,
      statusName: map['status_name']?.toString() ?? '',
      payerId: int.tryParse(map['payer_id']?.toString() ?? '') ?? 0,
      payerName: map['payer_name']?.toString() ?? '',
      payerAvatar: map['payer_avatar']?.toString() ?? '',
      payeeId: int.tryParse(map['payee_id']?.toString() ?? '') ?? 0,
      payeeName: map['payee_name']?.toString() ?? '',
      payeeAvatar: map['payee_avatar']?.toString() ?? '',
      qrToken: map['qr_token']?.toString() ?? '',
      qrPayload: map['qr_payload']?.toString() ?? '',
      barPayload: map['bar_payload']?.toString() ?? '',
      expireTime: map['expire_time']?.toString() ?? '',
      expireSeconds: int.tryParse(map['expire_seconds']?.toString() ?? '') ?? 0,
      refreshIn: int.tryParse(map['refresh_in']?.toString() ?? '') ?? 0,
      paidTime: map['paid_time']?.toString() ?? '',
      createTime: map['create_time']?.toString() ?? '',
      currentUserRole: map['current_user_role']?.toString() ?? '',
    );
  }
}

class WalletBill {
  const WalletBill({
    this.id = 0,
    this.billNo = '',
    this.orderNo = '',
    this.scene = '',
    this.sceneName = '',
    this.amount = '',
    this.amountLabel = '',
    this.direction = '',
    this.directionName = '',
    this.targetName = '',
    this.targetAvatar = '',
    this.status = 0,
    this.statusName = '',
    this.balanceAfter = '',
    this.remark = '',
    this.time = '',
    this.order,
  });

  final int id;
  final String billNo;
  final String orderNo;
  final String scene;
  final String sceneName;
  final String amount;
  final String amountLabel;
  final String direction;
  final String directionName;
  final String targetName;
  final String targetAvatar;
  final int status;
  final String statusName;
  final String balanceAfter;
  final String remark;
  final String time;
  final WalletOrder? order;

  factory WalletBill.fromJson(Object? value) {
    final map = _objectMap(value);
    return WalletBill(
      id: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      billNo: map['bill_no']?.toString() ?? '',
      orderNo: map['order_no']?.toString() ?? '',
      scene:
          _stringFromKeys(map, const [
            'scene',
            'transaction_type',
          ])?.toString() ??
          '',
      sceneName: map['scene_name']?.toString() ?? '',
      amount: map['amount']?.toString() ?? '',
      amountLabel: map['amount_label']?.toString() ?? '',
      direction: map['direction']?.toString() ?? '',
      directionName: map['direction_name']?.toString() ?? '',
      targetName: map['target_name']?.toString() ?? '',
      targetAvatar: map['target_avatar']?.toString() ?? '',
      status: int.tryParse(map['status']?.toString() ?? '') ?? 0,
      statusName: map['status_name']?.toString() ?? '',
      balanceAfter: map['balance_after']?.toString() ?? '',
      remark: map['remark']?.toString() ?? '',
      time:
          _stringFromKeys(map, const ['created_at', 'transaction_date']) ?? '',
      order: map['order'] is Map ? WalletOrder.fromJson(map['order']) : null,
    );
  }
}

class WalletWithdrawRecord {
  const WalletWithdrawRecord({
    this.id = 0,
    this.orderNo = '',
    this.amount = '',
    this.status = 0,
    this.statusName = '',
    this.account = '',
    this.name = '',
    this.createTime = '',
  });

  final int id;
  final String orderNo;
  final String amount;
  final int status;
  final String statusName;
  final String account;
  final String name;
  final String createTime;

  factory WalletWithdrawRecord.fromJson(Object? value) {
    final map = _objectMap(value);
    final status = int.tryParse(map['withdraw_status']?.toString() ?? '') ?? 0;
    return WalletWithdrawRecord(
      id: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      orderNo: map['withdrawal_note_number']?.toString() ?? '',
      amount: _decimalLabel(map['withdraw_fee']),
      status: status,
      statusName: switch (status) {
        1 => '已通过',
        2 => '未通过',
        _ => '审核中',
      },
      account: map['receivable_account']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      createTime: map['create_time']?.toString() ?? '',
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

String _decimalLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return '0.00';
  }
  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(unsigned)) {
    return '0.00';
  }
  final parts = unsigned.split('.');
  final yuan = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final cent = parts.length > 1 ? parts[1] : '';
  return '${negative ? '-' : ''}${yuan.isEmpty ? '0' : yuan}.${cent.padRight(2, '0').substring(0, 2)}';
}
