import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../app/session_controller.dart';
import '../../calls/livekit_call_models.dart';
import '../../core/app_config.dart';
import '../../core/design_tokens.dart';
import '../../core/app_logger.dart';
import '../../core/models.dart';
import '../../design/breakpoints.dart';
import '../../design/motion.dart';
import '../moments/moments_page.dart';
import '../../im/business_im_service.dart';
import '../../im/im_message_types.dart';
import '../../ui/bim_ui.dart';

part 'tabs/messages_tab.dart';
part 'tabs/contacts_tab.dart';
part 'tabs/discover_tab.dart';
part 'tabs/mine_tab.dart';
part 'contacts/quick_actions_page.dart';
part 'contacts/search_page.dart';
part 'contacts/qr_friend_pages.dart';
part 'contacts/connection_pages.dart';
part 'contacts/add_friend_page.dart';
part 'contacts/friend_requests_page.dart';
part 'contacts/group_pages.dart';
part 'contacts/private_chat_actions_page.dart';
part 'wallet/wallet_page.dart';
part 'wallet/payment_code_widgets.dart';
part 'wallet/payment_service_page.dart';
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
part 'chat/payment_detail_pages.dart';
part 'chat/tool_panel.dart';
part 'chat/composer_bar.dart';
part 'chat/emoji_picker.dart';
part 'chat/contact_card_picker.dart';
part 'calls/livekit_call_page.dart';
part 'common/section_header.dart';
part 'common/navigation_helpers.dart';
part 'chat/message_helpers.dart';
part 'common/display_helpers.dart';
part 'common/conversation_helpers.dart';
part 'contacts/contact_helpers.dart';
part 'common/map_helpers.dart';
part 'common/media_helpers.dart';

const _primaryColor = BimColors.primary;
const _pageColor = BimColors.background;
const _surfaceColor = BimColors.surface;
const _borderColor = BimColors.border;
const _lightBorderColor = BimColors.borderLight;
const _fillColor = BimColors.fill;
const _mutedColor = BimColors.mutedText;
const _secondaryTextColor = BimColors.secondaryText;
const _textColor = BimColors.text;
const _dangerColor = BimColors.dangerDeep;
const _chatPageColor = BimColors.chatBackground;
const _chatMineBubbleColor = BimColors.mineBubble;
const _chatOnlineColor = BimColors.online;
const _chatAckColor = BimColors.ack;
const _privateChannelType = 1;
const _groupChannelType = 2;

class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  State<CallOverlayHost> createState() => CallOverlayHostState();
}

class CallOverlayHostState extends State<CallOverlayHost> {
  LiveKitCallPage? _activeCallPage;

  bool handleSystemBack() {
    final page = _activeCallPage;
    if (page == null) {
      return false;
    }
    return _callPageKey(page)?.currentState?.handleSystemBack() ?? false;
  }

  bool showCall(LiveKitCallPage page, {ValueChanged<int>? onClosed}) {
    if (_activeCallPage != null) {
      AppLogger.warn(
        'call',
        'call overlay ignored new call because one call is already active',
        data: {
          'incoming': page.incoming,
          'call_id': page.initialCall?.callId,
          'call_type': page.callType,
          'media_type': page.mediaType,
        },
      );
      return false;
    }
    final hostedPage = page.withHost(
      key: GlobalKey<LiveKitCallPageState>(),
      onClosed: (callId) {
        onClosed?.call(callId);
        if (!mounted) {
          return;
        }
        setState(() => _activeCallPage = null);
      },
    );
    setState(() => _activeCallPage = hostedPage);
    return true;
  }

  GlobalKey<LiveKitCallPageState>? _callPageKey(LiveKitCallPage page) {
    final key = page.key;
    if (key is GlobalKey<LiveKitCallPageState>) {
      return key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CallHostScope(
      showCall: showCall,
      child: Stack(
        children: [
          widget.child,
          if (_activeCallPage != null) Positioned.fill(child: _activeCallPage!),
        ],
      ),
    );
  }
}

class CallHostScope extends InheritedWidget {
  const CallHostScope({
    required this.showCall,
    required super.child,
    super.key,
  });

  final bool Function(LiveKitCallPage page, {ValueChanged<int>? onClosed})
  showCall;

  static CallHostScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CallHostScope>();
  }

  @override
  bool updateShouldNotify(CallHostScope oldWidget) {
    return showCall != oldWidget.showCall;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey _quickActionButtonKey = GlobalKey();
  var _index = 0;
  int _totalUnread = 0;
  bool _initialSyncOverlayVisible = false;
  Timer? _initialSyncOverlayHideTimer;

  @override
  void initState() {
    super.initState();
    _totalUnread = _conversationUnreadTotal(
      widget.controller.cachedConversations(),
    );
    _initialSyncOverlayVisible =
        widget.controller.initialHistorySyncState.blocked;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
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
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
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
          : BimTopBar(title: _title, actions: _actions(showInitialSyncOverlay)),
      backgroundColor: _pageColor,
      body: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: showInitialSyncOverlay,
              child: _HomeTabStack(index: _index, children: pages),
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
              : (value) {
                  if (value == _index) {
                    return;
                  }
                  setState(() => _index = value);
                },
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
              label: '联系人',
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
          key: _quickActionButtonKey,
          tooltip: '更多',
          onPressed: showInitialSyncOverlay
              ? _showInitialSyncLockedTip
              : _openQuickActionsMenu,
          icon: const Icon(Icons.add_circle_outline, size: 23),
        ),
    ];
  }

  Future<void> _openQuickActionsMenu() async {
    final buttonContext = _quickActionButtonKey.currentContext;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    final button = buttonContext?.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) {
      return;
    }
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final left = max(8.0, bottomRight.dx - 184);
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xff2f3338),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      position: RelativeRect.fromLTRB(
        left,
        bottomRight.dy + 6,
        max(8.0, overlay.size.width - bottomRight.dx),
        0,
      ),
      items: const [
        PopupMenuItem(
          value: 'group',
          height: 48,
          child: _HomeQuickMenuRow(icon: Icons.groups_outlined, label: '发起群聊'),
        ),
        PopupMenuItem(
          value: 'friend',
          height: 48,
          child: _HomeQuickMenuRow(icon: Icons.person_add_alt_1, label: '添加好友'),
        ),
        PopupMenuItem(
          value: 'pay',
          height: 48,
          child: _HomeQuickMenuRow(icon: Icons.qr_code_2, label: '收付款'),
        ),
        PopupMenuItem(
          value: 'scan',
          height: 48,
          child: _HomeQuickMenuRow(icon: Icons.qr_code_scanner, label: '扫一扫'),
        ),
      ],
    );
    if (!mounted || selected == null) {
      return;
    }
    switch (selected) {
      case 'group':
        await _open(CreateGroupPage(controller: widget.controller));
        break;
      case 'friend':
        await _open(SearchPage(controller: widget.controller));
        break;
      case 'pay':
        await _open(WalletPayReceivePage(controller: widget.controller));
        break;
      case 'scan':
        await _open(WalletScanPage(controller: widget.controller));
        break;
    }
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
    showBimSnackBar(context, '聊天数据同步完成后可操作');
  }

  Future<void> _open(Widget page) async {
    await _push(context, page);
    if (mounted) {
      setState(() {});
    }
  }

  String get _title {
    return switch (_index) {
      0 => _messagesTitle,
      1 => '联系人',
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

class _HomeTabStack extends StatefulWidget {
  const _HomeTabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_HomeTabStack> createState() => _HomeTabStackState();
}

class _HomeTabStackState extends State<_HomeTabStack> {
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(_HomeTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
    if (oldWidget.children.length != widget.children.length) {
      _visited.removeWhere((index) => index >= widget.children.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          if (_visited.contains(index))
            widget.children[index]
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

class _HomeQuickMenuRow extends StatelessWidget {
  const _HomeQuickMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
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
                  height: BimDimensions.composerControl,
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
                    fontSize: BimTypography.title,
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
