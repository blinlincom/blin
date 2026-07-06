import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../app/session_controller.dart';
import '../../calls/livekit_call_models.dart';
import '../../core/app_config.dart';
import '../../core/app_logger.dart';
import '../../core/models.dart';
import '../moments/moments_page.dart';
import '../../im/business_im_service.dart';
import '../../im/im_message_types.dart';

part 'tabs/messages_tab.dart';
part 'tabs/contacts_tab.dart';
part 'tabs/discover_tab.dart';
part 'tabs/mine_tab.dart';
part 'contacts/quick_actions_page.dart';
part 'contacts/search_page.dart';
part 'contacts/connection_pages.dart';
part 'contacts/add_friend_page.dart';
part 'contacts/friend_requests_page.dart';
part 'contacts/group_pages.dart';
part 'contacts/private_chat_actions_page.dart';
part 'chat/chat_page.dart';
part 'chat/action_input_pages.dart';
part 'chat/media_picker_pages.dart';
part 'common/list_tiles.dart';
part 'common/avatar.dart';
part 'chat/message_list.dart';
part 'chat/chat_header.dart';
part 'chat/message_bubble.dart';
part 'common/media_preview.dart';
part 'chat/media_viewer_pages.dart';
part 'chat/tool_panel.dart';
part 'chat/composer_bar.dart';
part 'calls/livekit_call_page.dart';
part 'common/section_header.dart';
part 'common/navigation_helpers.dart';
part 'chat/message_helpers.dart';
part 'common/display_helpers.dart';
part 'common/conversation_helpers.dart';
part 'contacts/contact_helpers.dart';
part 'common/map_helpers.dart';
part 'common/media_helpers.dart';

const _primaryColor = Color(0xff1677ff);
const _pageColor = Color(0xfff5f6f8);
const _surfaceColor = Color(0xffffffff);
const _borderColor = Color(0xffe7e8ec);
const _lightBorderColor = Color(0xfff0f1f4);
const _fillColor = Color(0xfff4f5f7);
const _mutedColor = Color(0xff9aa0aa);
const _secondaryTextColor = Color(0xff6f7785);
const _textColor = Color(0xff202124);
const _dangerColor = Color(0xffa40000);
const _chatPageColor = Color(0xfff7f8fa);
const _chatMineBubbleColor = Color(0xffdff6d8);
const _chatOnlineColor = Color(0xff55c875);
const _chatAckColor = Color(0xff42c977);
const _privateChannelType = 1;
const _groupChannelType = 2;

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _index = 0;
  int _totalUnread = 0;
  bool _initialSyncOverlayVisible = false;
  Timer? _initialSyncOverlayHideTimer;
  final Set<int> _activeIncomingCallIds = <int>{};
  StreamSubscription<BusinessImCallEvent>? _callSub;

  @override
  void initState() {
    super.initState();
    _totalUnread = _conversationUnreadTotal(
      widget.controller.cachedConversations(),
    );
    _initialSyncOverlayVisible =
        widget.controller.initialHistorySyncState.blocked;
    widget.controller.addListener(_onControllerChanged);
    _callSub = widget.controller.callEvents.listen(_onCallEvent);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _callSub?.cancel();
      widget.controller.addListener(_onControllerChanged);
      _callSub = widget.controller.callEvents.listen(_onCallEvent);
      _totalUnread = _conversationUnreadTotal(
        widget.controller.cachedConversations(),
      );
      _initialSyncOverlayHideTimer?.cancel();
      _initialSyncOverlayHideTimer = null;
      _initialSyncOverlayVisible =
          widget.controller.initialHistorySyncState.blocked;
    }
  }

  @override
  void dispose() {
    _initialSyncOverlayHideTimer?.cancel();
    _callSub?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onCallEvent(BusinessImCallEvent event) {
    final callEvent = event.event;
    final call = callEvent.call;
    if (!callEvent.isInvite ||
        call.callId <= 0 ||
        callEvent.operatorId == widget.controller.session?.userId ||
        _activeIncomingCallIds.contains(call.callId)) {
      return;
    }
    _activeIncomingCallIds.add(call.callId);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _activeIncomingCallIds.remove(call.callId);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LiveKitCallPage.incoming(
            controller: widget.controller,
            initialCall: call,
          ),
        ),
      );
      _activeIncomingCallIds.remove(call.callId);
    });
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final nextUnread = _conversationUnreadTotal(
      widget.controller.cachedConversations(),
    );
    var needsBuild = false;
    if (_index == 0 || nextUnread != _totalUnread) {
      _totalUnread = nextUnread;
      needsBuild = true;
    }
    if (_syncInitialHistoryOverlay()) {
      needsBuild = true;
    }
    if (needsBuild) {
      setState(() {});
    }
  }

  bool _syncInitialHistoryOverlay() {
    final state = widget.controller.initialHistorySyncState;
    if (state.blocked) {
      _initialSyncOverlayHideTimer?.cancel();
      _initialSyncOverlayHideTimer = null;
      if (_initialSyncOverlayVisible) {
        return false;
      }
      _initialSyncOverlayVisible = true;
      return true;
    }
    if (!_initialSyncOverlayVisible ||
        _initialSyncOverlayHideTimer != null ||
        state.progress < 1) {
      return false;
    }
    _initialSyncOverlayHideTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) {
        return;
      }
      _initialSyncOverlayHideTimer = null;
      setState(() => _initialSyncOverlayVisible = false);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final showInitialSyncOverlay = _showInitialSyncOverlay;
    final pages = [
      MessagesTab(controller: widget.controller),
      ContactsTab(controller: widget.controller),
      DiscoverTab(controller: widget.controller),
      MineTab(controller: widget.controller),
    ];
    return Scaffold(
      appBar: _index == 3
          ? null
          : AppBar(
              title: Text(_title),
              centerTitle: true,
              toolbarHeight: 50,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: _surfaceColor,
              foregroundColor: _textColor,
              titleTextStyle: const TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              actions: _actions(showInitialSyncOverlay),
            ),
      backgroundColor: _pageColor,
      body: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: showInitialSyncOverlay,
              child: pages[_index],
            ),
            if (showInitialSyncOverlay)
              Positioned.fill(
                child: _InitialHistorySyncOverlay(
                  state: widget.controller.initialHistorySyncState,
                  onRetry: _retryInitialSync,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _borderColor)),
          color: Colors.white,
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: showInitialSyncOverlay
              ? (_) => _showInitialSyncLockedTip()
              : (value) => setState(() => _index = value),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: _surfaceColor,
          selectedItemColor: _primaryColor,
          unselectedItemColor: const Color(0xff5f6772),
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          iconSize: 24,
          items: [
            BottomNavigationBarItem(
              icon: _BottomNavIcon(
                icon: Icons.sms_outlined,
                unread: _totalUnread,
              ),
              label: '消息',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              label: '通讯录',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              label: '发现',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: '我',
            ),
          ],
        ),
      ),
    );
  }

  bool get _showInitialSyncOverlay {
    return _initialSyncOverlayVisible ||
        widget.controller.initialHistorySyncBlocked;
  }

  List<Widget> _actions(bool showInitialSyncOverlay) {
    return [
      if (_index == 0 || _index == 1)
        IconButton(
          tooltip: '更多',
          onPressed: showInitialSyncOverlay
              ? _showInitialSyncLockedTip
              : () => _open(QuickActionsPage(controller: widget.controller)),
          icon: const Icon(Icons.add_circle_outline, size: 23),
        ),
    ];
  }

  Future<void> _retryInitialSync() async {
    try {
      await widget.controller.loadConversations();
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'retry initial history sync failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  void _showInitialSyncLockedTip() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('聊天数据同步完成后可操作'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) {
      setState(() {});
    }
  }

  String get _title {
    return switch (_index) {
      0 => _messagesTitle,
      1 => '通讯录',
      2 => '发现',
      _ => '我的',
    };
  }

  String get _messagesTitle {
    if (_showInitialSyncOverlay) {
      return '消息';
    }
    final status = widget.controller.imStatusText;
    if (status == '连接中') {
      return '连接中...';
    }
    if (status == '重连中') {
      return '重连中...';
    }
    if (status == '同步中') {
      return '同步中...';
    }
    if (status == '已连接' && widget.controller.imError == null) {
      return '消息';
    }
    if (widget.controller.imError != null) {
      return status.isEmpty ? '连接异常' : status;
    }
    return '消息';
  }
}

int _conversationUnreadTotal(Iterable<Map<String, Object?>> conversations) {
  var total = 0;
  for (final item in conversations) {
    total += _intValue(item, ['unread_quantity', 'unread']);
  }
  return total;
}

class _InitialHistorySyncOverlay extends StatelessWidget {
  const _InitialHistorySyncOverlay({
    required this.state,
    required this.onRetry,
  });

  final BusinessImInitialSyncState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress.clamp(0, 1).toDouble();
    final failed = state.error != null;
    final completed = !failed && !state.syncing && progress >= 1;
    final title = failed
        ? '聊天数据同步失败'
        : completed
        ? '聊天数据同步完成'
        : '正在同步聊天数据';
    final subtitle = failed
        ? state.error!
        : completed
        ? '正在进入消息'
        : state.text;
    final width = min(MediaQuery.sizeOf(context).width - 64, 280).toDouble();
    return ColoredBox(
      color: _surfaceColor,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: title,
          value: '${(progress * 100).round()}%',
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: failed
                      ? const Icon(
                          Icons.error_outline,
                          color: _dangerColor,
                          size: 38,
                        )
                      : completed
                      ? const Icon(
                          Icons.check_circle_outline,
                          color: _primaryColor,
                          size: 38,
                        )
                      : CircularProgressIndicator(
                          value: progress <= 0 ? null : progress,
                          strokeWidth: 3,
                          color: _primaryColor,
                          backgroundColor: _lightBorderColor,
                        ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      minHeight: 3,
                      value: failed ? null : value,
                      color: failed ? _dangerColor : _primaryColor,
                      backgroundColor: _lightBorderColor,
                    );
                  },
                ),
                const SizedBox(height: 9),
                Text(
                  failed ? '请重新同步' : '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: _mutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 16),
                  TextButton(onPressed: onRetry, child: const Text('重新同步')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({required this.icon, required this.unread});

  final IconData icon;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon),
          if (unread > 0)
            Positioned(
              top: -2,
              right: 0,
              child: _UnreadBadge(count: unread, compact: true),
            ),
        ],
      ),
    );
  }
}
