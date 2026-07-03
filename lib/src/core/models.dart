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
  const ImRoute({
    this.apiUrl = '',
    this.tcpAddr = '',
    this.websocketAddr = '',
    this.wsAddr = '',
    this.wssAddr = '',
    this.tls = false,
  });

  final String apiUrl;
  final String tcpAddr;
  final String websocketAddr;
  final String wsAddr;
  final String wssAddr;
  final bool tls;

  factory ImRoute.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return ImRoute(
      apiUrl: map['api_url']?.toString() ?? '',
      tcpAddr: map['tcp_addr']?.toString() ?? '',
      websocketAddr: map['websocket_addr']?.toString() ?? '',
      wsAddr: map['ws_addr']?.toString() ?? '',
      wssAddr: map['wss_addr']?.toString() ?? '',
      tls: map['tls'] == true || map['tls']?.toString() == '1',
    );
  }

  Map<String, Object?> toJson() => {
    'api_url': apiUrl,
    'tcp_addr': tcpAddr,
    'websocket_addr': websocketAddr,
    'ws_addr': wsAddr,
    'wss_addr': wssAddr,
    'tls': tls,
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
  });

  final String uid;
  final String token;
  final String device;
  final int deviceFlag;
  final int deviceLevel;
  final int channelTypePerson;
  final int channelTypeGroup;
  final ImRoute route;

  factory ChatSession.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
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
      route: ImRoute.fromJson(map['route']),
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
  };
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.username,
    required this.userToken,
    required this.chat,
    this.nickname = '',
    this.avatar = '',
  });

  final int userId;
  final String username;
  final String userToken;
  final ChatSession? chat;
  final String nickname;
  final String avatar;

  factory UserSession.fromJson(Map<String, Object?> map) {
    return UserSession(
      userId: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      username: map['username']?.toString() ?? '',
      userToken: map['usertoken']?.toString() ?? '',
      chat: map['chat'] == null ? null : ChatSession.fromJson(map['chat']),
      nickname: map['nickname']?.toString() ?? '',
      avatar: map['usertx']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'id': userId,
    'username': username,
    'usertoken': userToken,
    'chat': chat?.toJson(),
    'nickname': nickname,
    'usertx': avatar,
  };

  UserSession copyWith({ChatSession? chat, String? nickname, String? avatar}) {
    return UserSession(
      userId: userId,
      username: username,
      userToken: userToken,
      chat: chat ?? this.chat,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
    );
  }
}

class AppInfo {
  const AppInfo({required this.name, this.icon = '', this.introduction = ''});

  final String name;
  final String icon;
  final String introduction;

  factory AppInfo.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return AppInfo(
      name: map['appname']?.toString() ?? 'BIM',
      icon: map['appicon']?.toString() ?? '',
      introduction: map['application_introduction']?.toString() ?? '',
    );
  }
}
