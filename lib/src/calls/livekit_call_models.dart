class LiveKitCallInfo {
  const LiveKitCallInfo({
    required this.callId,
    required this.callNo,
    required this.roomName,
    required this.callType,
    required this.mediaType,
    required this.channelId,
    required this.channelType,
    required this.creatorId,
    required this.receiverId,
    required this.groupId,
    required this.title,
    required this.status,
    required this.statusText,
    required this.liveKitUrl,
    required this.liveKitToken,
    required this.participants,
    this.self,
  });

  final int callId;
  final String callNo;
  final String roomName;
  final String callType;
  final String mediaType;
  final String channelId;
  final int channelType;
  final int creatorId;
  final int receiverId;
  final int groupId;
  final String title;
  final int status;
  final String statusText;
  final String liveKitUrl;
  final String liveKitToken;
  final List<LiveKitCallParticipant> participants;
  final LiveKitCallParticipant? self;

  bool get isPrivate => callType == 'private';
  bool get isGroup => callType == 'group';
  bool get isMeeting => callType == 'meeting';
  bool get isVideo => mediaType == 'video';
  bool get isEnded => status == 2 || status == 3 || status == 4 || status == 5;

  factory LiveKitCallInfo.fromJson(Object? value) {
    final map = _objectMap(value);
    final livekit = _objectMap(map['livekit']);
    final participants = _objectList(
      map['participants'],
    ).map(LiveKitCallParticipant.fromJson).toList(growable: false);
    final selfMap = _objectMap(map['self']);
    return LiveKitCallInfo(
      callId: _int(map['call_id'] ?? map['id']),
      callNo: _string(map['call_no']),
      roomName: _string(map['room_name']),
      callType: _string(map['call_type'], fallback: 'private'),
      mediaType: _string(map['media_type'], fallback: 'audio'),
      channelId: _string(map['channel_id']),
      channelType: _int(map['channel_type']),
      creatorId: _int(map['creator_id']),
      receiverId: _int(map['receiver_id']),
      groupId: _int(map['group_id']),
      title: _string(map['title']),
      status: _int(map['status']),
      statusText: _string(map['status_text']),
      liveKitUrl: _string(livekit['url']),
      liveKitToken: _string(livekit['token']),
      participants: participants,
      self: selfMap.isEmpty ? null : LiveKitCallParticipant.fromJson(selfMap),
    );
  }

  LiveKitCallInfo copyWithToken(Map<String, Object?> map) {
    final next = LiveKitCallInfo.fromJson(map);
    return next.liveKitToken.isNotEmpty ? next : this;
  }

  LiveKitCallInfo withConnectionFrom(LiveKitCallInfo current) {
    return LiveKitCallInfo(
      callId: callId,
      callNo: callNo,
      roomName: roomName,
      callType: callType,
      mediaType: mediaType,
      channelId: channelId,
      channelType: channelType,
      creatorId: creatorId,
      receiverId: receiverId,
      groupId: groupId,
      title: title,
      status: status,
      statusText: statusText,
      liveKitUrl: liveKitUrl.isNotEmpty ? liveKitUrl : current.liveKitUrl,
      liveKitToken: liveKitToken.isNotEmpty
          ? liveKitToken
          : current.liveKitToken,
      participants: participants.isNotEmpty
          ? participants
          : current.participants,
      self: self ?? current.self,
    );
  }
}

class LiveKitCallParticipant {
  const LiveKitCallParticipant({
    required this.userId,
    required this.uid,
    required this.role,
    required this.status,
    required this.statusText,
    required this.name,
    required this.avatar,
    required this.mutedAudio,
    required this.mutedVideo,
  });

  final int userId;
  final String uid;
  final String role;
  final int status;
  final String statusText;
  final String name;
  final String avatar;
  final bool mutedAudio;
  final bool mutedVideo;

  bool get joined => status == 1;

  factory LiveKitCallParticipant.fromJson(Object? value) {
    final map = _objectMap(value);
    return LiveKitCallParticipant(
      userId: _int(map['user_id']),
      uid: _string(map['uid']),
      role: _string(map['role'], fallback: 'member'),
      status: _int(map['status']),
      statusText: _string(map['status_text']),
      name: _string(map['name']),
      avatar: _string(map['avatar']),
      mutedAudio: _bool(map['muted_audio']),
      mutedVideo: _bool(map['muted_video']),
    );
  }
}

class LiveKitCallEvent {
  const LiveKitCallEvent({
    required this.event,
    required this.call,
    required this.operatorId,
    required this.operatorUid,
  });

  final String event;
  final LiveKitCallInfo call;
  final int operatorId;
  final String operatorUid;

  bool get isInvite => event == 'call.invite';
  bool get isCancel => event == 'call.cancel';
  bool get isReject => event == 'call.reject';
  bool get isHangup => event == 'call.hangup' || event == 'call.left';

  factory LiveKitCallEvent.fromGatewayPayload(Map<String, Object?> payload) {
    return LiveKitCallEvent(
      event: _string(payload['event']),
      call: LiveKitCallInfo.fromJson(payload['call']),
      operatorId: _int(payload['operator_id']),
      operatorUid: _string(payload['operator_uid']),
    );
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
  return const [];
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}
