import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../calls/livekit_call_models.dart';
import '../core/app_logger.dart';
import '../features/home/home_page.dart';
import '../im/business_im_service.dart';
import '../im/im_message_types.dart';
import '../notifications/realtime_notification_bridge.dart';
import 'session_controller.dart';

class RealtimeEventCoordinator {
  RealtimeEventCoordinator({
    required SessionController controller,
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<CallOverlayHostState> callOverlayKey,
  }) : _controller = controller,
       _navigatorKey = navigatorKey,
       _callOverlayKey = callOverlayKey;

  final SessionController _controller;
  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<CallOverlayHostState> _callOverlayKey;
  final Set<int> _activeIncomingCallIds = <int>{};
  final Map<int, LiveKitCallInfo> _pendingIncomingCalls =
      <int, LiveKitCallInfo>{};
  final Map<int, DateTime> _recentEndedCallIds = <int, DateTime>{};
  final Queue<RealtimeNotificationPayload> _pendingPayloads =
      Queue<RealtimeNotificationPayload>();
  final Set<String> _notifiedMessageKeys = <String>{};
  final Set<String> _notifiedFriendApplyIds = <String>{};
  StreamSubscription<BusinessImCallEvent>? _callSub;
  StreamSubscription<BusinessImMessageEvent>? _messageSub;
  StreamSubscription<BusinessImFriendEvent>? _friendSub;
  StreamSubscription<RealtimeNotificationPayload>? _tapSub;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _handlingPayload = false;
  bool _drainScheduled = false;
  bool _notificationPermissionRequested = false;
  bool _disposed = false;

  void start() {
    RealtimeNotificationBridge.configure();
    _callSub = _controller.callEvents.listen(_onCallEvent);
    _messageSub = _controller.messageEvents.listen(_onMessageEvent);
    _friendSub = _controller.friendEvents.listen(_onFriendEvent);
    _tapSub = RealtimeNotificationBridge.taps.listen(_enqueuePayload);
    unawaited(_readLaunchPayload());
  }

  void dispose() {
    _disposed = true;
    _callSub?.cancel();
    _messageSub?.cancel();
    _friendSub?.cancel();
    _tapSub?.cancel();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _drainPayloads();
      _showPendingIncomingCallsOnResume();
    }
  }

  void onSessionAvailable() {
    if (_disposed || !_controller.isLoggedIn) {
      return;
    }
    _requestNotificationPermissionOnce();
    _drainPayloads();
  }

  Future<void> _readLaunchPayload() async {
    final payload = await RealtimeNotificationBridge.getLaunchPayload();
    if (payload != null) {
      _enqueuePayload(payload);
    }
  }

  void _enqueuePayload(RealtimeNotificationPayload payload) {
    if (_disposed || payload.type.isEmpty) {
      return;
    }
    _pendingPayloads.add(payload);
    _drainPayloads();
  }

  void _drainPayloads() {
    if (_handlingPayload || _disposed || !_controller.isLoggedIn) {
      return;
    }
    _handlingPayload = true;
    unawaited(() async {
      try {
        while (!_disposed && _pendingPayloads.isNotEmpty) {
          final payload = _pendingPayloads.removeFirst();
          var consumed = true;
          if (payload.isCall) {
            consumed = await _openCallFromNotification(payload.callId);
          } else if (payload.isMessage) {
            consumed = await _openMessageFromNotification(payload);
          } else if (payload.isFriendRequest) {
            consumed = await _openFriendRequestsFromNotification();
          }
          if (!consumed) {
            _pendingPayloads.addFirst(payload);
            _scheduleDrain();
            break;
          }
        }
      } finally {
        _handlingPayload = false;
      }
    }());
  }

  void _scheduleDrain() {
    if (_drainScheduled || _disposed) {
      return;
    }
    _drainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      _drainPayloads();
    });
  }

  void _requestNotificationPermissionOnce() {
    if (_notificationPermissionRequested) {
      return;
    }
    _notificationPermissionRequested = true;
    unawaited(RealtimeNotificationBridge.ensureNotificationPermission());
  }

  void _onCallEvent(BusinessImCallEvent event) {
    final callEvent = event.event;
    final call = callEvent.call;
    final currentUserId = _controller.session?.userId ?? 0;
    if (_isTerminalCallEvent(callEvent)) {
      _rememberEndedCall(call.callId);
      unawaited(RealtimeNotificationBridge.cancelIncomingCall(call.callId));
      _activeIncomingCallIds.remove(call.callId);
      _pendingIncomingCalls.remove(call.callId);
    }
    if (!callEvent.isInvite ||
        call.callId <= 0 ||
        call.isEnded ||
        call.creatorId == currentUserId ||
        callEvent.operatorId == currentUserId ||
        _recentEndedCallIds.containsKey(call.callId) ||
        _activeIncomingCallIds.contains(call.callId)) {
      return;
    }
    _activeIncomingCallIds.add(call.callId);
    _pendingIncomingCalls[call.callId] = call;
    if (_isForeground) {
      unawaited(_showIncomingCallPage(call));
    } else {
      unawaited(_showIncomingCallNotification(call));
    }
  }

  bool _isTerminalCallEvent(LiveKitCallEvent event) {
    return event.call.isEnded ||
        event.isCancel ||
        event.isReject ||
        event.isHangup;
  }

  Future<void> _showIncomingCallPage(LiveKitCallInfo call) async {
    if (_callOverlayKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !_activeIncomingCallIds.contains(call.callId)) {
          return;
        }
        unawaited(_showIncomingCallPage(call));
      });
      return;
    }
    final latestCall = await _confirmIncomingCall(call);
    if (_disposed || latestCall == null) {
      _activeIncomingCallIds.remove(call.callId);
      _pendingIncomingCalls.remove(call.callId);
      return;
    }
    final shown = _callOverlayKey.currentState?.showCall(
      LiveKitCallPage.incoming(
        controller: _controller,
        initialCall: latestCall,
      ),
      onClosed: (closedCallId) {
        if (closedCallId > 0) {
          _rememberEndedCall(closedCallId);
          unawaited(
            RealtimeNotificationBridge.cancelIncomingCall(closedCallId),
          );
        }
        _activeIncomingCallIds.remove(call.callId);
        _pendingIncomingCalls.remove(call.callId);
      },
    );
    if (shown != true) {
      _activeIncomingCallIds.remove(call.callId);
      _pendingIncomingCalls.remove(call.callId);
      AppLogger.warn(
        'call',
        'incoming call overlay unavailable or occupied',
        data: {'call_id': call.callId},
      );
      return;
    }
    _pendingIncomingCalls.remove(call.callId);
    unawaited(RealtimeNotificationBridge.cancelIncomingCall(call.callId));
  }

  Future<void> _showIncomingCallNotification(LiveKitCallInfo call) async {
    final title = _callTitle(call);
    await RealtimeNotificationBridge.showIncomingCall(
      callId: call.callId,
      title: title,
      text: call.isVideo ? '邀请你进行视频通话' : '邀请你进行语音通话',
      video: call.isVideo,
    );
    AppLogger.info(
      'notification',
      'incoming call notification shown',
      data: {'call_id': call.callId, 'title': title},
    );
  }

  Future<bool> _openCallFromNotification(int callId) async {
    if (callId <= 0 || _recentEndedCallIds.containsKey(callId)) {
      return true;
    }
    if (_callOverlayKey.currentState == null) {
      return false;
    }
    try {
      final call = await _controller.liveKitCallToken(callId);
      final latest = await _confirmIncomingCall(call);
      if (latest == null || _disposed) {
        await RealtimeNotificationBridge.cancelIncomingCall(callId);
        return true;
      }
      _activeIncomingCallIds.add(callId);
      final shown = _callOverlayKey.currentState?.showCall(
        LiveKitCallPage.incoming(controller: _controller, initialCall: latest),
        onClosed: (closedCallId) {
          if (closedCallId > 0) {
            _rememberEndedCall(closedCallId);
            unawaited(
              RealtimeNotificationBridge.cancelIncomingCall(closedCallId),
            );
          }
          _activeIncomingCallIds.remove(callId);
          _pendingIncomingCalls.remove(callId);
        },
      );
      if (shown == true) {
        _pendingIncomingCalls.remove(callId);
        await RealtimeNotificationBridge.cancelIncomingCall(callId);
      }
      return true;
    } catch (error, stackTrace) {
      _rememberEndedCall(callId);
      await RealtimeNotificationBridge.cancelIncomingCall(callId);
      AppLogger.warn(
        'call',
        'open incoming call from notification failed',
        data: {'call_id': callId, 'error': '$error', 'stack': '$stackTrace'},
      );
      return true;
    }
  }

  Future<LiveKitCallInfo?> _confirmIncomingCall(LiveKitCallInfo call) async {
    if (_recentEndedCallIds.containsKey(call.callId)) {
      return null;
    }
    try {
      final latest = await _controller
          .liveKitCallToken(call.callId)
          .timeout(const Duration(seconds: 6));
      final resolved = latest.withConnectionFrom(call);
      if (_recentEndedCallIds.containsKey(call.callId)) {
        return null;
      }
      if (_isUnavailableIncomingCall(resolved)) {
        _rememberEndedCall(call.callId);
        return null;
      }
      return resolved;
    } catch (error, stackTrace) {
      _rememberEndedCall(call.callId);
      AppLogger.warn(
        'call',
        'incoming call ignored because server confirmation failed',
        data: {
          'call_id': call.callId,
          'error': '$error',
          'stack': stackTrace.toString().split('\n').take(3).join('\n'),
        },
      );
      return null;
    }
  }

  bool _isUnavailableIncomingCall(LiveKitCallInfo call) {
    final statusText = call.statusText.toLowerCase();
    return call.callId <= 0 ||
        call.isEnded ||
        statusText.contains('取消') ||
        statusText.contains('拒') ||
        statusText.contains('挂断') ||
        statusText.contains('结束') ||
        statusText.contains('超时') ||
        statusText.contains('cancel') ||
        statusText.contains('reject') ||
        statusText.contains('hangup') ||
        statusText.contains('end') ||
        statusText.contains('timeout');
  }

  void _rememberEndedCall(int callId) {
    if (callId <= 0) {
      return;
    }
    final now = DateTime.now();
    _recentEndedCallIds.removeWhere(
      (_, value) => now.difference(value).inMinutes >= 10,
    );
    _recentEndedCallIds[callId] = now;
  }

  void _showPendingIncomingCallsOnResume() {
    if (_pendingIncomingCalls.isEmpty || _disposed) {
      return;
    }
    final calls = List<LiveKitCallInfo>.from(_pendingIncomingCalls.values);
    for (final call in calls) {
      if (_activeIncomingCallIds.contains(call.callId)) {
        unawaited(_showIncomingCallPage(call));
      }
    }
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!_shouldNotifyMessage(event)) {
      return;
    }
    final clientMsgNo = _stringValue(
      event.message,
      ['client_msg_no'],
      fallback: _stringValue(event.message['payload'], ['client_msg_no']),
    );
    if (clientMsgNo.isEmpty) {
      return;
    }
    final key = '${event.channelType}:${event.channelId}:$clientMsgNo';
    if (_notifiedMessageKeys.contains(key)) {
      return;
    }
    _notifiedMessageKeys.add(key);
    final title = _conversationTitle(event);
    final text = _messageNotificationText(event.message);
    unawaited(
      RealtimeNotificationBridge.showMessageNotification(
        channelId: event.channelId,
        channelType: event.channelType,
        clientMsgNo: clientMsgNo,
        title: title,
        text: text,
      ),
    );
    AppLogger.info(
      'notification',
      'message notification shown',
      data: {
        'channel_id': event.channelId,
        'channel_type': event.channelType,
        'client_msg_no': clientMsgNo,
        'title': title,
        'text': text,
      },
    );
  }

  void _onFriendEvent(BusinessImFriendEvent event) {
    if (event.event != 'friend_apply_created' || _isForeground) {
      return;
    }
    final detail = _asObjectMap(event.payload['friend']);
    final applyId = _stringValue(detail, ['apply_id', 'id']);
    if (applyId.isEmpty || !_notifiedFriendApplyIds.add(applyId)) {
      return;
    }
    final title = _friendRequestTitle(event.payload, detail);
    unawaited(
      RealtimeNotificationBridge.showFriendRequestNotification(
        applyId: applyId,
        title: title,
        text: '请求添加你为联系人',
      ),
    );
    AppLogger.info(
      'notification',
      'friend request notification shown',
      data: {'apply_id': applyId, 'title': title},
    );
  }

  bool _shouldNotifyMessage(BusinessImMessageEvent event) {
    if (_isForeground) {
      return false;
    }
    if (event.source != 'gateway_recv') {
      return false;
    }
    if (_boolValue(event.message['is_me'])) {
      return false;
    }
    final payload = _asObjectMap(event.message['payload']);
    if (_boolValue(payload['silent']) ||
        _boolValue(payload['no_sound']) ||
        _boolValue(payload['mute_notification']) ||
        _boolValue(payload['notification_silent'])) {
      return false;
    }
    return true;
  }

  Future<bool> _openMessageFromNotification(
    RealtimeNotificationPayload payload,
  ) async {
    if (payload.channelId.isEmpty || payload.channelType <= 0) {
      return true;
    }
    await RealtimeNotificationBridge.cancelMessageNotification(
      channelId: payload.channelId,
      channelType: payload.channelType,
    );
    final title = _titleForChannel(payload.channelId, payload.channelType);
    final groupId = _groupIdForChannel(payload.channelId, payload.channelType);
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return false;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          controller: _controller,
          title: title,
          channelId: payload.channelId,
          groupId: groupId,
          channelType: payload.channelType,
          initialClientMsgNo: payload.clientMsgNo,
        ),
      ),
    );
    unawaited(
      _controller.markConversationRead(
        channelId: payload.channelId,
        channelType: payload.channelType,
      ),
    );
    return true;
  }

  Future<bool> _openFriendRequestsFromNotification() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return false;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => FriendRequestsPage(controller: _controller),
      ),
    );
    _controller.markFriendApplicationsRead();
    return true;
  }

  String _conversationTitle(BusinessImMessageEvent event) {
    final conversationTitle = _titleFromMap(event.conversation);
    if (conversationTitle.isNotEmpty) {
      return conversationTitle;
    }
    final fromUser = _asObjectMap(event.message['from_user']);
    final fromUserTitle = _titleFromMap(fromUser);
    if (fromUserTitle.isNotEmpty) {
      return fromUserTitle;
    }
    return event.channelType == _groupChannelType ? '群聊' : '新消息';
  }

  String _friendRequestTitle(
    Map<String, Object?> payload,
    Map<String, Object?> detail,
  ) {
    final fromUser = _asObjectMap(detail['from_user']);
    final name = _titleFromMap(fromUser);
    if (name.isNotEmpty) {
      return name;
    }
    final senderName = _stringValue(payload, [
      'sender_nickname',
      'sender_name',
      'sender_username',
    ]);
    if (senderName.isNotEmpty) {
      return senderName;
    }
    return '新的朋友';
  }

  String _titleForChannel(String channelId, int channelType) {
    for (final item in _controller.cachedConversations()) {
      if (_stringValue(item, ['channel_id', 'uid']) == channelId &&
          _intValue(item, ['channel_type']) == channelType) {
        final title = _titleFromMap(item);
        if (title.isNotEmpty) {
          return title;
        }
      }
    }
    return channelType == _groupChannelType ? '群聊' : '聊天';
  }

  String _groupIdForChannel(String channelId, int channelType) {
    if (channelType != _groupChannelType) {
      return '';
    }
    for (final item in _controller.cachedConversations()) {
      if (_stringValue(item, ['channel_id', 'uid']) == channelId &&
          _intValue(item, ['channel_type']) == channelType) {
        return _stringValue(item, ['group_id', 'id'], fallback: channelId);
      }
    }
    return channelId;
  }

  String _titleFromMap(Map<String, Object?> map) {
    return _stringValue(map, [
      'remark',
      'display_name',
      'nickname',
      'name',
      'group_name',
      'title',
    ]);
  }

  String _callTitle(LiveKitCallInfo call) {
    if (call.title.isNotEmpty) {
      return call.title;
    }
    final currentUserId = _controller.session?.userId ?? 0;
    for (final participant in call.participants) {
      if (participant.userId > 0 &&
          participant.userId != currentUserId &&
          participant.name.isNotEmpty) {
        return participant.name;
      }
    }
    return call.isVideo ? '视频通话' : '语音通话';
  }

  String _messageNotificationText(Map<String, Object?> message) {
    final payload = _asObjectMap(message['payload']);
    final contentType = _messageContentType(message, payload);
    final content = _stringValue(message, [
      'content',
    ], fallback: _stringValue(payload, ['content', 'text']));
    return switch (contentType) {
      ChatContentTypes.image => '[图片]',
      ChatContentTypes.emoji => '[表情]',
      ChatContentTypes.gif => '[GIF]',
      ChatContentTypes.sticker => '[贴纸]',
      ChatContentTypes.voice => '[语音]',
      ChatContentTypes.video => '[视频]',
      ChatContentTypes.file => '[文件]',
      ChatContentTypes.contactCard => '[名片]',
      ChatContentTypes.redPacket =>
        '[红包]${content.isEmpty ? '恭喜发财，大吉大利' : content}',
      ChatContentTypes.transfer => '[转账]请收款',
      ChatContentTypes.call => '[通话]',
      ChatContentTypes.walletNotice => content.isEmpty ? '[钱包通知]' : content,
      _ => content.isEmpty ? '[消息]' : content,
    };
  }

  String _messageContentType(
    Map<String, Object?> message,
    Map<String, Object?> payload,
  ) {
    final direct = _stringValue(message, ['content_type']);
    if (direct.isNotEmpty) {
      return direct;
    }
    final payloadType = _stringValue(payload, ['content_type', 'type']);
    if (payloadType.isNotEmpty && int.tryParse(payloadType) == null) {
      return payloadType;
    }
    final code = _intValue(message, [
      'type',
    ], fallback: _intValue(payload, ['type']));
    return switch (code) {
      ImMessageTypes.image => ChatContentTypes.image,
      ImMessageTypes.voice => ChatContentTypes.voice,
      ImMessageTypes.video => ChatContentTypes.video,
      ImMessageTypes.file => ChatContentTypes.file,
      ImMessageTypes.transfer => ChatContentTypes.transfer,
      ImMessageTypes.redPacket => ChatContentTypes.redPacket,
      ImMessageTypes.redPacketReceived => ChatContentTypes.redPacketReceived,
      ImMessageTypes.transferReceived => ChatContentTypes.transferReceived,
      ImMessageTypes.emoji => ChatContentTypes.emoji,
      ImMessageTypes.gif => ChatContentTypes.gif,
      ImMessageTypes.sticker => ChatContentTypes.sticker,
      ImMessageTypes.contactCard => ChatContentTypes.contactCard,
      ImMessageTypes.call => ChatContentTypes.call,
      ImMessageTypes.walletNotice => ChatContentTypes.walletNotice,
      _ => ChatContentTypes.text,
    };
  }

  bool get _isForeground => _lifecycleState == AppLifecycleState.resumed;
}

const _groupChannelType = 2;

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

String _stringValue(Object? value, List<String> keys, {String fallback = ''}) {
  final map = _asObjectMap(value);
  for (final key in keys) {
    final item = map[key];
    if (item != null && item.toString().trim().isNotEmpty) {
      return item.toString().trim();
    }
  }
  return fallback;
}

int _intValue(Map<String, Object?> map, List<String> keys, {int fallback = 0}) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback;
}

bool _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}
