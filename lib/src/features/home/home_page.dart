import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../app/session_controller.dart';
import '../../core/app_config.dart';
import '../../core/app_logger.dart';
import '../../core/models.dart';
import '../../im/business_im_service.dart';
import '../../im/im_message_types.dart';

const _primaryColor = Color(0xff1677ff);
const _pageColor = Color(0xfff5f6f8);
const _borderColor = Color(0xffe7e8ec);
const _lightBorderColor = Color(0xfff0f1f4);
const _fillColor = Color(0xfff4f5f7);
const _mutedColor = Color(0xff9aa0aa);
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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted && _index == 0) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
              backgroundColor: Colors.white,
              actions: _actions(),
            ),
      backgroundColor: _pageColor,
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _borderColor)),
          color: Colors.white,
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (value) => setState(() => _index = value),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.sms_outlined),
              label: '消息',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              label: '通讯录',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: '我',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    return [
      if (_index == 0 || _index == 1)
        IconButton(
          tooltip: '更多',
          onPressed: () =>
              _open(QuickActionsPage(controller: widget.controller)),
          icon: const Icon(Icons.add_circle_outline),
        ),
    ];
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
    final status = widget.controller.imStatusText;
    if (status == '连接中' || status == '重连中') {
      return status;
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

class MessagesTab extends StatefulWidget {
  const MessagesTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  late int _conversationRevision;
  List<Map<String, Object?>> _conversations = const [];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;
  StreamSubscription<BusinessImMessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _conversationRevision = widget.controller.conversationVersion;
    _conversations = widget.controller.cachedConversations();
    _precacheConversationAvatars(context, _conversations);
    _loading = _conversations.isEmpty;
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _loadConversations(showLoading: _conversations.isEmpty);
  }

  @override
  void didUpdateWidget(MessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _messageSub?.cancel();
      _conversations = widget.controller.cachedConversations();
      _loading = _conversations.isEmpty;
      _error = null;
      widget.controller.addListener(_onControllerChanged);
      _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
      _loadConversations(showLoading: _conversations.isEmpty);
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final next = widget.controller.conversationVersion;
    if (next != _conversationRevision) {
      _conversationRevision = next;
      _loadConversations(showLoading: false);
    }
  }

  Future<void> _loadConversations({required bool showLoading}) async {
    final token = ++_loadToken;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.controller.loadConversations();
      if (!mounted || token != _loadToken) {
        return;
      }
      _precacheConversationAvatars(context, list);
      setState(() {
        _conversations = list;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!mounted || event.conversation.isEmpty) {
      return;
    }
    final next = _upsertConversation(_conversations, event.conversation);
    _precacheConversationAvatars(context, next);
    setState(() {
      _conversations = next;
      _loading = false;
      _error = null;
      _conversationRevision = widget.controller.conversationVersion;
    });
  }

  Future<void> _refreshReadStateAfterChatPop(
    String channelId,
    int channelType,
  ) async {
    try {
      await widget.controller.markConversationRead(
        channelId: channelId,
        channelType: channelType,
      );
      if (!mounted) {
        return;
      }
      await _loadConversations(showLoading: false);
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'refresh read state after chat pop failed',
        error: error,
        stackTrace: stackTrace,
        data: {'channel_id': channelId, 'channel_type': channelType},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = _SearchBar(
      hintText: '搜索',
      onTap: () => _push(context, SearchPage(controller: widget.controller)),
    );
    if (_loading && _conversations.isEmpty) {
      return ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            header,
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }
    if (_error != null && _conversations.isEmpty) {
      return ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            header,
            Expanded(
              child: _ErrorState(
                text: _error!,
                onRetry: () => _loadConversations(showLoading: true),
              ),
            ),
          ],
        ),
      );
    }
    if (_conversations.isEmpty) {
      return ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            header,
            const Expanded(child: _EmptyState(text: '暂无会话')),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        itemCount: _conversations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return header;
          }
          return _conversationTile(context, _conversations[index - 1]);
        },
      ),
    );
  }

  Widget _conversationTile(BuildContext context, Map<String, Object?> item) {
    final title = _conversationTitle(item);
    final content = _conversationSubtitle(item);
    final time = item['msg_time']?.toString() ?? '';
    final unread = _intValue(item, ['unread_quantity']);
    final channelType = _channelTypeFromConversation(item);
    final channelId = _conversationChannelId(item, channelType);
    return _ConversationTile(
      title: title,
      subtitle: content.isEmpty ? '暂无最新消息' : content,
      time: time,
      unread: unread,
      isGroup: channelType == _groupChannelType,
      avatarUrl: _conversationAvatarUrl(item),
      onTap: () {
        if (channelId.isEmpty) {
          return;
        }
        unawaited(
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                    controller: widget.controller,
                    title: title,
                    channelId: channelId,
                    groupId: _value(item, [
                      'group_id',
                      'id',
                    ], fallback: channelId),
                    channelType: channelType,
                  ),
                ),
              )
              .then(
                (_) => _refreshReadStateAfterChatPop(channelId, channelType),
              ),
        );
      },
    );
  }

  List<Map<String, Object?>> _upsertConversation(
    List<Map<String, Object?>> current,
    Map<String, Object?> conversation,
  ) {
    final next = current
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final channelId = _value(conversation, ['channel_id']);
    final channelType = _channelTypeFromConversation(conversation);
    final index = next.indexWhere(
      (item) =>
          _value(item, ['channel_id']) == channelId &&
          _channelTypeFromConversation(item) == channelType,
    );
    if (index >= 0) {
      next[index] = {...next[index], ...conversation};
    } else {
      next.insert(0, Map<String, Object?>.from(conversation));
    }
    next.sort(
      (a, b) => _value(b, ['msg_time']).compareTo(_value(a, ['msg_time'])),
    );
    return next;
  }
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _friends = widget.controller.cachedFriends();
    _precacheContactAvatars(context, _friends, const []);
    _refresh(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final friends = widget.controller.cachedFriends();
    if (_sameMapList(_friends, friends)) {
      return;
    }
    _precacheContactAvatars(context, friends, const []);
    setState(() {
      _friends = friends;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final friends = await widget.controller.loadFriends();
      if (!mounted) {
        return;
      }
      _precacheContactAvatars(context, friends, const []);
      setState(() {
        _friends = friends;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _friends.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _friends.isEmpty) {
      return _ErrorState(text: _error!, onRetry: () => _refresh());
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _refresh(showLoading: false),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              _SearchBar(
                hintText: '搜索',
                onTap: () =>
                    _push(context, SearchPage(controller: widget.controller)),
              ),
              _MenuTile(
                icon: Icons.group_add,
                iconColor: const Color(0xffffa51f),
                title: '新的朋友',
                subtitle: '',
                onTap: () => _push(
                  context,
                  FriendRequestsPage(controller: widget.controller),
                ),
              ),
              _MenuTile(
                icon: Icons.groups,
                iconColor: const Color(0xff36c56f),
                title: '群聊',
                subtitle: '',
                onTap: () =>
                    _push(context, MyGroupsPage(controller: widget.controller)),
              ),
              _MenuTile(
                icon: Icons.sell_outlined,
                iconColor: const Color(0xff2f80ed),
                title: '标签',
                subtitle: '',
                onTap: () => _showSoon(context),
              ),
              _MenuTile(
                icon: Icons.person,
                iconColor: const Color(0xff3d8bff),
                title: '公众号',
                subtitle: '',
                onTap: () => _showSoon(context),
              ),
              const _SectionHeader(text: '我的企业'),
              _ContactTile(
                title: '产品设计部',
                subtitle: '',
                trailing: '',
                isGroup: true,
                avatarColor: const Color(0xff2f80ed),
                icon: Icons.business_center,
                onTap: () => _showSoon(context),
              ),
              _ContactTile(
                title: '运营部',
                subtitle: '',
                trailing: '',
                isGroup: true,
                avatarColor: const Color(0xff2f80ed),
                icon: Icons.diversity_3,
                onTap: () => _showSoon(context),
              ),
              _ContactTile(
                title: '技术部',
                subtitle: '',
                trailing: '',
                isGroup: true,
                avatarColor: const Color(0xff2f80ed),
                icon: Icons.grid_view,
                onTap: () => _showSoon(context),
              ),
              const _SectionHeader(text: '星标朋友'),
              if (_friends.isEmpty) const _EmptyRow(text: '暂无好友'),
              for (final item in _friends)
                _ContactTile(
                  title: _friendTitle(item),
                  subtitle: '',
                  trailing: '',
                  isGroup: false,
                  avatarUrl: _friendAvatarUrl(item),
                  onTap: () =>
                      _openPrivateChat(context, widget.controller, item),
                  onLongPress: () => _push(
                    context,
                    PrivateChatActionsPage(
                      controller: widget.controller,
                      title: _friendTitle(item),
                      receiverId: _friendUserId(item),
                      channelId: _friendChannelId(item),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Positioned(
          right: 4,
          top: 96,
          bottom: 74,
          child: IgnorePointer(child: _AlphabetIndex()),
        ),
        if (_error != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InfoBar(text: '通讯录刷新失败：$_error'),
          ),
      ],
    );
  }
}

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
      children: [
        _MenuTile(
          icon: Icons.camera_alt_outlined,
          iconColor: const Color(0xff45c463),
          title: '朋友圈',
          subtitle: '',
          trailing: const _Avatar(
            label: '我',
            size: 28,
            color: Color(0xff8e99a8),
          ),
          onTap: () => _showSoon(context),
        ),
        const _GroupGap(),
        _MenuTile(
          icon: Icons.crop_free,
          iconColor: const Color(0xff2f80ed),
          title: '扫一扫',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
        _MenuTile(
          icon: Icons.vibration_outlined,
          iconColor: const Color(0xff3d8bff),
          title: '摇一摇',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
        const _GroupGap(),
        _MenuTile(
          icon: Icons.explore_outlined,
          iconColor: const Color(0xffffb020),
          title: '看一看',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
        _MenuTile(
          icon: Icons.manage_search,
          iconColor: const Color(0xffff5c5c),
          title: '搜一搜',
          subtitle: '',
          onTap: () => _push(context, SearchPage(controller: controller)),
        ),
        const _GroupGap(),
        _MenuTile(
          icon: Icons.people_outline,
          iconColor: const Color(0xff3d8bff),
          title: '附近的人',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
        const _GroupGap(),
        _MenuTile(
          icon: Icons.sports_esports_outlined,
          iconColor: const Color(0xff45c463),
          title: '游戏',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
        const _GroupGap(),
        _MenuTile(
          icon: Icons.music_note_outlined,
          iconColor: const Color(0xff8a68ff),
          title: '小程序',
          subtitle: '',
          onTap: () => _showSoon(context),
        ),
      ],
    );
  }
}

class MineTab extends StatelessWidget {
  const MineTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 20, 26),
              child: Row(
                children: [
                  _Avatar(
                    label: _avatarText(session),
                    size: 68,
                    color: const Color(0xff8e99a8),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session?.nickname.isNotEmpty == true
                              ? session!.nickname
                              : session?.username ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(
                              Icons.check_circle,
                              size: 13,
                              color: Color(0xff36c56f),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '在线',
                              style: TextStyle(
                                color: _mutedColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '账号：${session?.username ?? ''}',
                          style: const TextStyle(color: _mutedColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '二维码',
                    onPressed: () => _showSoon(context),
                    icon: const Icon(Icons.qr_code_2),
                  ),
                ],
              ),
            ),
            _MenuTile(
              icon: Icons.security_outlined,
              iconColor: const Color(0xff20c997),
              title: '服务',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            const _GroupGap(),
            _MenuTile(
              icon: Icons.bookmark_border,
              iconColor: const Color(0xffff3b30),
              title: '收藏',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.photo_library_outlined,
              iconColor: const Color(0xff34c759),
              title: '朋友圈',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.wallet_outlined,
              iconColor: _primaryColor,
              title: '卡包',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.emoji_emotions_outlined,
              iconColor: const Color(0xffffc043),
              title: '表情',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            const _GroupGap(),
            _MenuTile(
              icon: Icons.settings_outlined,
              iconColor: _mutedColor,
              title: '设置',
              subtitle: '',
              onTap: () =>
                  _push(context, ConnectionInfoPage(controller: controller)),
            ),
            if (controller.imError != null)
              _MenuTile(
                icon: Icons.error_outline,
                iconColor: _dangerColor,
                title: '连接异常',
                subtitle: controller.imError!,
                onTap: controller.clearError,
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton(
                onPressed: controller.logout,
                child: const Text('退出登录'),
              ),
            ),
          ],
        );
      },
    );
  }

  String _avatarText(UserSession? session) {
    final name = session?.nickname.isNotEmpty == true
        ? session!.nickname
        : session?.username ?? '';
    if (name.isEmpty) {
      return 'B';
    }
    return name.characters.first;
  }
}

class QuickActionsPage extends StatelessWidget {
  const QuickActionsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionEntry(
        Icons.groups_outlined,
        '发起群聊',
        () => _push(context, CreateGroupPage(controller: controller)),
      ),
      _ActionEntry(
        Icons.person_add_alt_1,
        '添加朋友',
        () => _push(context, SearchPage(controller: controller)),
      ),
      _ActionEntry(Icons.qr_code_scanner, '扫一扫', () => _showSoon(context)),
      _ActionEntry(Icons.payments_outlined, '收付款', () => _showSoon(context)),
      _ActionEntry(Icons.note_add_outlined, '新建笔记', () => _showSoon(context)),
      _ActionEntry(Icons.phone_outlined, '语音通话', () => _showSoon(context)),
      _ActionEntry(Icons.videocam_outlined, '视频通话', () => _showSoon(context)),
      _ActionEntry(
        Icons.group_work_outlined,
        '创建群聊',
        () => _push(context, CreateGroupPage(controller: controller)),
      ),
      _ActionEntry(
        Icons.contacts_outlined,
        '通讯录',
        () => Navigator.of(context).pop(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('快捷操作')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: GridView.builder(
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              mainAxisExtent: 96,
            ),
            itemBuilder: (context, index) {
              final item = actions[index];
              return _ActionCircle(
                icon: item.icon,
                label: item.label,
                onTap: item.onTap,
              );
            },
          ),
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _keyword = TextEditingController();
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String? _loadError;
  Future<Map<String, Object?>>? _friendSearchFuture;
  String _friendSearchKeyword = '';
  String _message = '';
  String _error = '';
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _friends = widget.controller.cachedFriends();
    _refreshLocal(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _refreshLocal({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final friends = await widget.controller.loadFriends();
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = friends;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _searchRemoteFriends() {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    setState(() {
      _friendSearchKeyword = keyword;
      _friendSearchFuture = widget.controller.searchFriends(
        keyword: keyword,
        limit: 20,
      );
      _message = '';
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: SafeArea(
        child: _loading && _friends.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && _friends.isEmpty
            ? _ErrorState(text: _loadError!, onRetry: () => _refreshLocal())
            : _buildSearchList(),
      ),
    );
  }

  Widget _buildSearchList() {
    final keyword = _keyword.text.trim().toLowerCase();
    final friends = _friends.where((item) {
      return keyword.isEmpty ||
          _friendTitle(item).toLowerCase().contains(keyword) ||
          _friendUsername(item).toLowerCase().contains(keyword);
    }).toList();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: TextField(
            controller: _keyword,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _searchRemoteFriends(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '好友昵称/用户名，添加朋友用用户名',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ButtonRow(
            children: [
              FilledButton.icon(
                onPressed: _acting ? null : _searchRemoteFriends,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('按用户名搜索'),
              ),
              OutlinedButton.icon(
                onPressed: () => _refreshLocal(showLoading: false),
                icon: const Icon(Icons.refresh),
                label: const Text('刷新本地'),
              ),
            ],
          ),
        ),
        if (_acting) const _LinearBusy(),
        _ResultBlock(text: _message),
        _ErrorBlock(text: _error),
        if (_loadError != null) _InfoBar(text: '好友刷新失败：$_loadError'),
        const _SectionHeader(text: '添加朋友'),
        _RemoteFriendSearchBlock(
          controller: widget.controller,
          keyword: _friendSearchKeyword,
          future: _friendSearchFuture,
          onOpenChat: _openRemoteFriendChat,
          onApply: _applyRemoteFriend,
          onHandleIncoming: () =>
              _push(context, FriendRequestsPage(controller: widget.controller)),
        ),
        const _SectionHeader(text: '好友'),
        if (friends.isEmpty) const _EmptyRow(text: '没有匹配好友'),
        for (final item in friends)
          _ContactTile(
            title: _friendTitle(item),
            subtitle: _friendSubtitle(item),
            trailing: _friendUsername(item),
            isGroup: false,
            avatarUrl: _friendAvatarUrl(item),
            onTap: () => _openPrivateChat(context, widget.controller, item),
          ),
      ],
    );
  }

  Future<void> _applyRemoteFriend(Map<String, Object?> item) async {
    final friendId = _searchFriendId(item);
    if (friendId.isEmpty) {
      setState(() => _error = '用户信息为空');
      return;
    }
    setState(() {
      _acting = true;
      _message = '';
      _error = '';
    });
    try {
      final result = await widget.controller.applyFriend(
        friendId: friendId,
        remark: '通过搜索添加',
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
      if (_friendSearchKeyword.isNotEmpty) {
        _friendSearchFuture = widget.controller.searchFriends(
          keyword: _friendSearchKeyword,
          limit: 20,
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  void _openRemoteFriendChat(Map<String, Object?> item) {
    final user = _asObjectMap(item['user']);
    final friendId = _searchFriendId(item);
    final channelId = _value(item, [
      'channel_id',
      'uid',
    ], fallback: _uidFromUserId(friendId));
    if (friendId.isEmpty || channelId.isEmpty) {
      setState(() => _error = '用户 IM 信息为空');
      return;
    }
    _openPrivateChat(context, widget.controller, {
      ...user,
      'friend': user,
      'friend_id': friendId,
      'userid': friendId,
      'channel_id': channelId,
    });
  }
}

class _RemoteFriendSearchBlock extends StatelessWidget {
  const _RemoteFriendSearchBlock({
    required this.controller,
    required this.keyword,
    required this.future,
    required this.onOpenChat,
    required this.onApply,
    required this.onHandleIncoming,
  });

  final SessionController controller;
  final String keyword;
  final Future<Map<String, Object?>>? future;
  final void Function(Map<String, Object?> item) onOpenChat;
  final void Function(Map<String, Object?> item) onApply;
  final VoidCallback onHandleIncoming;

  @override
  Widget build(BuildContext context) {
    final request = future;
    if (request == null) {
      return const _EmptyRow(text: '输入用户名后搜索');
    }
    return FutureBuilder<Map<String, Object?>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString());
        }
        final items = _listFromResult(snapshot.data ?? const {});
        if (items.isEmpty) {
          return _EmptyRow(text: keyword.isEmpty ? '暂无搜索结果' : '未找到用户');
        }
        return Column(
          children: [
            for (final item in items)
              _PlainListTile(
                icon: Icons.person_outline,
                title: _searchFriendTitle(item),
                subtitle: _searchFriendSubtitle(item),
                trailing: _searchFriendActionText(item),
                onTap: () {
                  if (_boolValue(item['is_friend'])) {
                    onOpenChat(item);
                  } else if (_boolValue(item['pending_in_apply'])) {
                    onHandleIncoming();
                  } else {
                    onApply(item);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class ConnectionInfoPage extends StatelessWidget {
  const ConnectionInfoPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Scaffold(
      appBar: AppBar(title: const Text('消息连接')),
      body: SafeArea(
        child: ListView(
          children: [
            _MenuTile(
              icon: Icons.phone_android_outlined,
              iconColor: _primaryColor,
              title: '设备',
              subtitle: controller.device,
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.person_outline,
              iconColor: const Color(0xff7c5cff),
              title: '当前账号',
              subtitle: _sessionDisplayName(session),
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.router_outlined,
              iconColor: const Color(0xff20c997),
              title: '连接地址',
              subtitle: _gatewayStreamAddress(session?.chat),
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.ac_unit_outlined,
              iconColor: const Color(0xff5ac8fa),
              title: '冷启动',
              subtitle: _formatTime(controller.lastColdLaunchAt),
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.replay_circle_filled_outlined,
              iconColor: const Color(0xffff9f0a),
              title: '热启动',
              subtitle: _formatTime(controller.lastHotResumeAt),
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.bug_report_outlined,
              iconColor: const Color(0xff5e6ad2),
              title: '诊断日志',
              subtitle: '查看接口请求和连接错误',
              onTap: () => _push(context, const DiagnosticsLogPage()),
            ),
            _MenuTile(
              icon: Icons.delete_sweep_outlined,
              iconColor: _dangerColor,
              title: '清空聊天记录',
              subtitle: '只清空本账号单聊、群聊和会话列表',
              onTap: () => _confirmClearAllChats(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearAllChats(BuildContext context) async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空本账号在本机和服务端历史同步中的单聊、群聊记录，不影响好友、群资料和其他用户。',
      confirmText: '清空',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await controller.clearAllChatRecords();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class DiagnosticsLogPage extends StatelessWidget {
  const DiagnosticsLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志'),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: () => _copyLogs(context),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: AppLogger.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: AppLogger.revision,
          builder: (context, _, _) {
            final logs = AppLogger.entries.reversed.toList();
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '日志文件',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        AppLogger.filePath.isEmpty
                            ? '日志文件尚未初始化'
                            : AppLogger.filePath,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _mutedColor,
                        ),
                      ),
                      if (logs.isEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('暂无日志'),
                      ],
                    ],
                  );
                }
                final item = logs[index - 1];
                final isError = item.level == 'ERROR';
                final isWarn = item.level == 'WARN';
                return SelectableText(
                  item.line,
                  style: TextStyle(
                    fontSize: 12,
                    color: isError
                        ? _dangerColor
                        : isWarn
                        ? const Color(0xff8a5a00)
                        : _textColor,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyLogs(BuildContext context) async {
    final text = await AppLogger.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日志已复制')));
    }
  }
}

class _ActionEntry {
  const _ActionEntry(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _friendId = TextEditingController();
  final _remark = TextEditingController();
  bool _loading = false;
  String _message = '';
  String _error = '';

  @override
  void dispose() {
    _friendId.dispose();
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加好友')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _friendId,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '建议从搜索页选择用户',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remark,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '申请备注'),
            ),
            const SizedBox(height: 16),
            _ButtonRow(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _checkStatus,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('查询关系'),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _apply,
                  icon: const Icon(Icons.send),
                  label: const Text('发送申请'),
                ),
              ],
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _checkStatus() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.friendStatus(id);
      _message = _friendStatusText(result);
    });
  }

  Future<void> _apply() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.applyFriend(
        friendId: id,
        remark: _remark.text.trim(),
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  var _type = 'in';
  var _version = 0;
  String _error = '';
  String _message = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: _ButtonRow(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'in'),
                    child: Text(_type == 'in' ? '收到申请' : '收件箱'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'out'),
                    child: Text(_type == 'out' ? '发出申请' : '发件箱'),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () => setState(() => _version++),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            Expanded(
              child: FutureBuilder<Map<String, Object?>>(
                key: ValueKey('$_type-$_version'),
                future: widget.controller.friendApplyList(type: _type),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(text: snapshot.error.toString());
                  }
                  final items = _listFromResult(snapshot.data ?? const {});
                  if (items.isEmpty) {
                    return const _EmptyState(text: '暂无申请');
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final applyId = _value(item, ['apply_id', 'id']);
                      final title = _requestTitle(item, _type);
                      final status = _requestStatus(item);
                      return _PlainListTile(
                        icon: Icons.person_outline,
                        title: title,
                        subtitle:
                            '${_value(item, ['remark', 'handle_msg'])} $status',
                        trailing: applyId,
                        onTap: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, true)
                            : null,
                        onLongPress: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, false)
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(String applyId, bool accept) async {
    if (applyId.isEmpty) {
      setState(() => _error = '申请信息为空');
      return;
    }
    try {
      final result = await widget.controller.handleFriendApply(
        applyId: applyId,
        accept: accept,
      );
      setState(() {
        _message = _friendlyResult(result, successText: accept ? '已同意' : '已拒绝');
        _error = '';
        _version++;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _name = TextEditingController();
  final _notice = TextEditingController();
  final _avatar = TextEditingController();
  final _memberIds = TextEditingController();
  final _selected = <String>{};
  late Future<List<Map<String, Object?>>> _friendsFuture;
  bool _loading = false;
  String _error = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    _friendsFuture = _loadFriends();
  }

  @override
  void dispose() {
    _name.dispose();
    _notice.dispose();
    _avatar.dispose();
    _memberIds.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _loadFriends() {
    return widget.controller.loadFriends();
  }

  void _reloadFriends() {
    setState(() => _friendsFuture = _loadFriends());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建群聊')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '群名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notice,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '群公告'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatar,
              decoration: const InputDecoration(labelText: '群头像 URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memberIds,
              decoration: const InputDecoration(
                labelText: '成员',
                hintText: '从下方好友列表选择，调试可填内部账号',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('创建'),
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _SectionHeader(text: '选择好友'),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _friendsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    text: snapshot.error.toString(),
                    onRetry: _reloadFriends,
                  );
                }
                final friends = snapshot.data ?? [];
                if (friends.isEmpty) {
                  return const _EmptyRow(text: '暂无好友');
                }
                return Column(
                  children: [
                    for (final item in friends)
                      CheckboxListTile(
                        value: _selected.contains(_friendUserId(item)),
                        onChanged: (checked) {
                          final id = _friendUserId(item);
                          if (id.isEmpty) {
                            return;
                          }
                          setState(() {
                            if (checked == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                        },
                        title: Text(_friendTitle(item)),
                        subtitle: Text(_friendSubtitle(item)),
                        controlAffinity: ListTileControlAffinity.leading,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '群名称不能为空');
      return;
    }
    final memberIds = <String>{
      ..._selected,
      ..._idsFromText(_memberIds.text),
    }.toList();
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      final result = await widget.controller.createGroup(
        name: name,
        memberIds: memberIds,
        avatar: _avatar.text.trim(),
        notice: _notice.text.trim(),
      );
      setState(() => _message = _friendlyResult(result, successText: '群聊已创建'));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({
    required this.controller,
    required this.title,
    required this.groupId,
    required this.channelId,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String groupId;
  final String channelId;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  var _version = 0;
  String _error = '';
  String _message = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader(text: '群设置'),
            _PlainListTile(
              icon: Icons.edit_outlined,
              title: '更新群资料',
              subtitle: '群名、头像、公告',
              trailing: '',
              onTap: _updateGroup,
            ),
            _PlainListTile(
              icon: Icons.person_add_alt_1,
              title: '添加成员',
              subtitle: '添加好友到群聊',
              trailing: '',
              onTap: _addMembers,
            ),
            _PlainListTile(
              icon: Icons.logout,
              title: '退出群聊',
              subtitle: '群主需要先转让群主',
              trailing: '',
              onTap: () =>
                  _run(() => widget.controller.leaveGroup(widget.groupId)),
            ),
            _PlainListTile(
              icon: Icons.delete_forever_outlined,
              title: '解散群聊',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () =>
                  _run(() => widget.controller.deleteGroup(widget.groupId)),
            ),
            _PlainListTile(
              icon: Icons.delete_sweep_outlined,
              title: '清空聊天',
              subtitle: '只清空自己看到的群聊记录',
              trailing: '',
              onTap: _clearGroupConversation,
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _SectionHeader(text: '群成员'),
            FutureBuilder<Map<String, Object?>>(
              key: ValueKey(_version),
              future: widget.controller.groupMembers(widget.groupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorState(text: snapshot.error.toString());
                }
                final members = _listFromResult(snapshot.data ?? const {});
                if (members.isEmpty) {
                  return const _EmptyRow(text: '暂无成员');
                }
                return Column(
                  children: [
                    for (final member in members)
                      _PlainListTile(
                        icon: Icons.person_outline,
                        title: _memberTitle(member),
                        subtitle: _memberSubtitle(member),
                        trailing: _memberUsername(member),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => GroupMemberActionPage(
                                controller: widget.controller,
                                groupId: widget.groupId,
                                member: member,
                              ),
                            ),
                          );
                          if (mounted) {
                            setState(() => _version++);
                          }
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateGroup() async {
    final data = await _openInput(
      context,
      title: '更新群资料',
      fields: const [
        ActionInputField(id: 'name', label: '群名称'),
        ActionInputField(id: 'avatar', label: '群头像 URL'),
        ActionInputField(id: 'notice', label: '群公告', maxLines: 3),
      ],
    );
    if (data == null) {
      return;
    }
    await _run(
      () => widget.controller.updateGroup(
        groupId: widget.groupId,
        name: data['name'] ?? '',
        avatar: data['avatar'] ?? '',
        notice: data['notice'] ?? '',
      ),
    );
  }

  Future<void> _addMembers() async {
    final data = await _openInput(
      context,
      title: '添加群成员',
      fields: const [
        ActionInputField(id: 'member_ids', label: '成员', hint: '多个内部账号用逗号分隔'),
      ],
    );
    if (data == null) {
      return;
    }
    final ids = _idsFromText(data['member_ids'] ?? '');
    if (ids.isEmpty) {
      setState(() => _error = '成员不能为空');
      return;
    }
    await _run(
      () => widget.controller.addGroupMembers(
        groupId: widget.groupId,
        memberIds: ids,
      ),
    );
  }

  Future<void> _clearGroupConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空群聊记录',
      content: '将清空你自己看到的这个群聊记录和会话，不影响其他群成员。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deleteGroupConversation(
        groupId: widget.groupId,
        channelId: widget.channelId,
      ),
    );
  }

  Future<void> _run(Future<Map<String, Object?>> Function() task) async {
    try {
      final result = await task();
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
        _version++;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  List<Map<String, Object?>> _groups = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _groups = widget.controller.cachedGroups();
    _precacheContactAvatars(context, const [], _groups);
    _refresh(showLoading: _groups.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final groups = widget.controller.cachedGroups();
    if (_sameMapList(_groups, groups)) {
      return;
    }
    _precacheContactAvatars(context, const [], groups);
    setState(() {
      _groups = groups;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final groups = await widget.controller.loadGroups();
      if (!mounted) {
        return;
      }
      _precacheContactAvatars(context, const [], groups);
      setState(() {
        _groups = groups;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的群聊')),
      body: SafeArea(
        child: _loading && _groups.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _groups.isEmpty
            ? _ErrorState(text: _error!, onRetry: () => _refresh())
            : RefreshIndicator(
                onRefresh: () => _refresh(showLoading: false),
                child: ListView(
                  children: [
                    if (_groups.isEmpty) const _EmptyRow(text: '暂无群聊'),
                    for (final item in _groups)
                      _PlainListTile(
                        icon: Icons.groups_outlined,
                        title: _groupTitle(item),
                        subtitle: _value(item, ['notice', 'description']),
                        trailing:
                            '${_intValue(item, ['member_count', 'members'])}人',
                        avatarUrl: _groupAvatarUrl(item),
                        onTap: () =>
                            _openGroupChat(context, widget.controller, item),
                        onLongPress: () => _push(
                          context,
                          GroupDetailPage(
                            controller: widget.controller,
                            title: _groupTitle(item),
                            groupId: _groupIdFromItem(item),
                            channelId: _groupChannelId(item),
                          ),
                        ),
                      ),
                    if (_error != null) _InfoBar(text: '群聊刷新失败：$_error'),
                  ],
                ),
              ),
      ),
    );
  }
}

class GroupMemberActionPage extends StatefulWidget {
  const GroupMemberActionPage({
    required this.controller,
    required this.groupId,
    required this.member,
    super.key,
  });

  final SessionController controller;
  final String groupId;
  final Map<String, Object?> member;

  @override
  State<GroupMemberActionPage> createState() => _GroupMemberActionPageState();
}

class _GroupMemberActionPageState extends State<GroupMemberActionPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final memberId = _memberUserId(widget.member);
    return Scaffold(
      appBar: AppBar(title: Text(_memberTitle(widget.member))),
      body: SafeArea(
        child: ListView(
          children: [
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '成员',
              subtitle: _memberSubtitle(widget.member),
              trailing: _memberRoleText(widget.member),
            ),
            _PlainListTile(
              icon: Icons.volume_off_outlined,
              title: '永久禁言',
              subtitle: '由系统或管理员限制该成员发言',
              trailing: '',
              onTap: () => _mute(memberId, permanent: true),
            ),
            _PlainListTile(
              icon: Icons.timer_outlined,
              title: '限时禁言',
              subtitle: '设置禁言秒数和原因',
              trailing: '',
              onTap: () => _mute(memberId, permanent: false),
            ),
            _PlainListTile(
              icon: Icons.volume_up_outlined,
              title: '解除禁言',
              subtitle: '恢复该成员群内发言',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.unmuteGroupMember(
                  groupId: widget.groupId,
                  memberId: memberId,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.admin_panel_settings_outlined,
              title: '设为管理员',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.setGroupAdmin(
                  groupId: widget.groupId,
                  memberId: memberId,
                  isAdmin: true,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.remove_moderator_outlined,
              title: '取消管理员',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.setGroupAdmin(
                  groupId: widget.groupId,
                  memberId: memberId,
                  isAdmin: false,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.workspace_premium_outlined,
              title: '转让群主',
              subtitle: '新群主必须是当前成员',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.transferGroupOwner(
                  groupId: widget.groupId,
                  newOwnerId: memberId,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '移出群聊',
              subtitle: '同步移除频道订阅者',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.removeGroupMembers(
                  groupId: widget.groupId,
                  memberIds: [memberId],
                ),
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _mute(String memberId, {required bool permanent}) async {
    var seconds = 0;
    var reason = '';
    if (!permanent) {
      final data = await _openInput(
        context,
        title: '限时禁言',
        fields: const [
          ActionInputField(
            id: 'expire_seconds',
            label: '禁言秒数',
            keyboardType: TextInputType.number,
          ),
          ActionInputField(id: 'reason', label: '原因'),
        ],
      );
      if (data == null) {
        return;
      }
      seconds = int.tryParse(data['expire_seconds'] ?? '') ?? 0;
      reason = data['reason'] ?? '';
      if (seconds <= 0) {
        setState(() => _error = '限时禁言秒数必须大于 0');
        return;
      }
    }
    await _run(
      () => widget.controller.muteGroupMember(
        groupId: widget.groupId,
        memberId: memberId,
        expireSeconds: seconds,
        reason: reason,
      ),
    );
  }

  Future<void> _run(Future<Map<String, Object?>> Function() task) async {
    try {
      final result = await task();
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class PrivateChatActionsPage extends StatefulWidget {
  const PrivateChatActionsPage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;

  @override
  State<PrivateChatActionsPage> createState() => _PrivateChatActionsPageState();
}

class _PrivateChatActionsPageState extends State<PrivateChatActionsPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          children: [
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '对方',
              subtitle: widget.title,
              trailing: '',
            ),
            _PlainListTile(
              icon: Icons.manage_search,
              title: '好友状态',
              subtitle: '查看是否已添加为好友',
              trailing: '',
              onTap: _friendStatus,
            ),
            _PlainListTile(
              icon: Icons.delete_outline,
              title: '清空聊天',
              subtitle: '只清空自己看到的单聊记录',
              trailing: '',
              onTap: _deleteConversation,
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '删除好友',
              subtitle: '删除后重新按非好友规则执行',
              trailing: '',
              onTap: _deleteFriend,
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _friendStatus() async {
    try {
      final result = await widget.controller.friendStatus(widget.receiverId);
      setState(() {
        _message = _friendStatusText(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteFriend() async {
    await _run(() => widget.controller.deleteFriend(widget.receiverId));
  }

  Future<void> _deleteConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空你自己看到的这个单聊记录和会话，不影响对方。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deletePrivateConversation(
        receiverId: widget.receiverId,
        channelId: widget.channelId,
      ),
    );
  }

  Future<void> _run(Future<Map<String, Object?>> Function() task) async {
    try {
      final result = await task();
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.groupId,
    required this.channelType,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final String groupId;
  final int channelType;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  bool _sending = false;
  bool _toolsOpen = false;
  bool _burnAfterRead = false;
  bool _mentionAll = false;
  int _burnSeconds = 0;
  List<String> _mentionUserIds = const [];
  String _replyClientMsgNo = '';
  String _selectedClientMsgNo = '';
  int _selectedMessageSeq = 0;
  Map<String, Object?> _selectedPayload = const {};
  Map<String, Object?> _groupMuteState = const {};
  String? _error;
  String _message = '';
  List<Map<String, Object?>> _messages = const [];
  bool _messagesLoading = true;
  int _messageLoadToken = 0;
  late int _conversationRevision;
  late int _messageRevision;
  StreamSubscription<BusinessImMessageEvent>? _messageSub;
  bool _didInitialScroll = false;
  bool _peerOnline = false;
  bool _onlineStatusLoading = false;
  int _onlineStatusToken = 0;
  int? _groupMemberCount;
  int? _groupOnlineCount;
  bool _groupPresenceLoading = false;
  int _groupPresenceToken = 0;
  final Set<String> _burnTriggeredClientMsgNos = <String>{};

  bool get _isGroup => widget.channelType == _groupChannelType;
  String get _groupId =>
      widget.groupId.isEmpty ? widget.channelId : widget.groupId;
  String get _receiverId => _privateReceiverIdFromChannel(widget.channelId);
  bool get _composerEnabled =>
      !_isGroup || _groupMuteText(_groupMuteState).isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversationRevision = widget.controller.conversationVersion;
    _messageRevision = _currentMessageRevision();
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _inputFocusNode.addListener(_onInputFocusChanged);
    unawaited(
      widget.controller.openConversation(
        channelId: widget.channelId,
        channelType: widget.channelType,
      ),
    );
    _loadMessagesIntoState(showLoading: true);
    _refreshGroupMuteState();
    _refreshPeerOnlineStatus();
    if (_isGroup) {
      unawaited(_loadGroupMuteStatus());
      unawaited(_refreshGroupPresence());
    }
    _textController.text = widget.controller.readDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _textController.addListener(() {
      widget.controller.writeDraft(
        channelId: widget.channelId,
        channelType: widget.channelType,
        text: _textController.text,
      );
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_inputFocusNode.hasFocus && _isNearBottom()) {
      _stickToBottomDuringKeyboard();
    }
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) {
      return;
    }
    if (_toolsOpen) {
      setState(() => _toolsOpen = false);
    }
    if (_isNearBottom()) {
      _stickToBottomDuringKeyboard();
    }
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _messageSub?.cancel();
      _conversationRevision = widget.controller.conversationVersion;
      _messageRevision = _currentMessageRevision();
      widget.controller.addListener(_onControllerChanged);
      _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    } else if (oldWidget.channelId != widget.channelId ||
        oldWidget.channelType != widget.channelType) {
      _conversationRevision = widget.controller.conversationVersion;
      _messageRevision = _currentMessageRevision();
      _messages = const [];
      _didInitialScroll = false;
      _burnTriggeredClientMsgNos.clear();
      _groupMuteState = const {};
      _peerOnline = false;
      _onlineStatusLoading = false;
      _groupMemberCount = null;
      _groupOnlineCount = null;
      _groupPresenceLoading = false;
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      _loadMessagesIntoState(showLoading: true);
      _refreshGroupMuteState();
      _refreshPeerOnlineStatus();
      if (_isGroup) {
        unawaited(_loadGroupMuteStatus());
        unawaited(_refreshGroupPresence());
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final nextConversation = widget.controller.conversationVersion;
    final nextMessage = _currentMessageRevision();
    final muteChanged = _refreshGroupMuteState();
    if (nextConversation == _conversationRevision &&
        nextMessage == _messageRevision &&
        !muteChanged) {
      return;
    }
    _conversationRevision = nextConversation;
    _messageRevision = nextMessage;
    _loadMessagesIntoState(showLoading: false);
  }

  bool _refreshGroupMuteState() {
    if (!_isGroup) {
      if (_groupMuteState.isEmpty) {
        return false;
      }
      setState(() => _groupMuteState = const {});
      return true;
    }
    final state = widget.controller.groupMuteState(
      channelId: widget.channelId,
      groupId: _groupId,
    );
    if (_sameStringMap(_groupMuteState, state)) {
      return false;
    }
    if (mounted) {
      setState(() => _groupMuteState = state);
    } else {
      _groupMuteState = state;
    }
    return true;
  }

  Future<void> _loadGroupMuteStatus() async {
    try {
      await widget.controller.loadGroupMuteStatus(
        groupId: _groupId,
        channelId: widget.channelId,
      );
      if (mounted) {
        _refreshGroupMuteState();
      }
    } catch (error) {
      AppLogger.warn(
        'ui',
        'load group mute status failed',
        data: {'group_id': _groupId, 'error': error.toString()},
      );
    }
  }

  String _chatHeaderStatusText() {
    if (_isGroup) {
      if (_groupOnlineCount == null) {
        if (!_groupPresenceLoading) {
          return '在线人数获取失败';
        }
        return '在线人数同步中';
      }
      return '$_groupOnlineCount人在线';
    }
    if (_onlineStatusLoading) {
      return '检测中';
    }
    return _peerOnline ? '在线' : '离线';
  }

  String _chatHeaderTitle() {
    final title = widget.title.isEmpty ? '群聊' : widget.title;
    if (!_isGroup) {
      return widget.title;
    }
    final count = _groupMemberCount;
    return count == null ? title : '$title（$count）';
  }

  Future<void> _refreshGroupPresence() async {
    if (!_isGroup) {
      return;
    }
    final token = ++_groupPresenceToken;
    if (mounted) {
      setState(() => _groupPresenceLoading = true);
    }
    try {
      final groupMembersResult = await widget.controller.groupMembers(_groupId);
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      final members = _listFromResult(groupMembersResult);
      final onlineCount = await _loadGroupOnlineCount(members);
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      setState(() {
        _groupMemberCount = members.length;
        _groupOnlineCount = onlineCount;
        _groupPresenceLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'load group presence failed',
        data: {
          'group_id': _groupId,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      setState(() => _groupPresenceLoading = false);
    }
  }

  Future<int> _loadGroupOnlineCount(List<Map<String, Object?>> members) async {
    if (members.isEmpty) {
      return 0;
    }
    const limit = 500;
    var page = 1;
    final counted = <String>{};
    while (mounted) {
      final result = await widget.controller.onlineUsers(
        page: page,
        limit: limit,
      );
      final onlineUsers = _listFromResult(result);
      for (final member in members) {
        final key = _memberPresenceKey(member);
        if (counted.contains(key)) {
          continue;
        }
        if (onlineUsers.any((user) => _memberMatchesOnlineUser(member, user))) {
          counted.add(key);
        }
      }
      if (counted.length >= members.length || onlineUsers.length < limit) {
        break;
      }
      page += 1;
    }
    return counted.length;
  }

  Future<void> _refreshPeerOnlineStatus() async {
    if (_isGroup) {
      if (mounted) {
        setState(() {
          _peerOnline = false;
          _onlineStatusLoading = false;
        });
      }
      return;
    }
    final receiverId = _receiverId;
    if (receiverId.isEmpty) {
      return;
    }
    final token = ++_onlineStatusToken;
    if (mounted) {
      setState(() => _onlineStatusLoading = true);
    }
    try {
      final result = await widget.controller.onlineUsers(limit: 200);
      final list = _listFromResult(result);
      final online = list.any((item) => _onlineUserMatches(item, receiverId));
      if (!mounted || token != _onlineStatusToken) {
        return;
      }
      setState(() {
        _peerOnline = online;
        _onlineStatusLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'load peer online status failed',
        data: {
          'receiver_id': receiverId,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      if (!mounted || token != _onlineStatusToken) {
        return;
      }
      setState(() {
        _peerOnline = false;
        _onlineStatusLoading = false;
      });
    }
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!mounted ||
        event.channelId != widget.channelId ||
        event.channelType != widget.channelType) {
      return;
    }
    final shouldStickToBottom = _shouldAutoScrollForMessage(event);
    setState(() {
      if (_isMessageDeleteEvent(event.source)) {
        final target = _value(event.message, ['client_msg_no']);
        _messages = _messages
            .where((item) => _value(item, ['client_msg_no']) != target)
            .toList(growable: false);
      } else {
        _messages = _mergeMessageList(_messages, event.message, limit: 200);
      }
      _messagesLoading = false;
      _messageRevision = _currentMessageRevision();
      _conversationRevision = widget.controller.conversationVersion;
    });
    if (shouldStickToBottom) {
      _scrollToBottom(animated: event.source != 'send_local');
    }
    _scheduleBurnAfterReadForMessages(_messages);
    unawaited(
      widget.controller.openConversation(
        channelId: widget.channelId,
        channelType: widget.channelType,
      ),
    );
  }

  int _currentMessageRevision() {
    return widget.controller.messageVersion(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
  }

  Future<List<Map<String, Object?>>> _loadMessages() {
    return AppLogger.measure(
      'ui',
      'load chat messages',
      () => widget.controller.loadLocalMessages(
        channelId: widget.channelId,
        channelType: widget.channelType,
        groupId: widget.groupId,
      ),
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
      },
    );
  }

  Future<void> _loadMessagesIntoState({required bool showLoading}) async {
    final token = ++_messageLoadToken;
    final wasNearBottom = _isNearBottom();
    if (showLoading && mounted) {
      setState(() {
        _messagesLoading = true;
        _error = null;
      });
    }
    try {
      final messages = await _loadMessages();
      if (!mounted || token != _messageLoadToken) {
        return;
      }
      _precacheMessageAvatars(
        context,
        messages,
        widget.controller.session?.avatar ?? '',
      );
      setState(() {
        _messages = messages;
        _messagesLoading = false;
      });
      _scheduleBurnAfterReadForMessages(messages);
      if (showLoading && !_didInitialScroll) {
        _didInitialScroll = true;
        _scrollToBottom(animated: false);
      } else if (wasNearBottom) {
        _scrollToBottom(animated: false);
      }
    } catch (error) {
      if (!mounted || token != _messageLoadToken) {
        return;
      }
      setState(() {
        _messagesLoading = false;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    _scrollController.dispose();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    widget.controller.closeConversation(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.writeDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
      text: _textController.text,
    );
    _textController.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> _mergeMessageList(
    List<Map<String, Object?>> current,
    Map<String, Object?> incoming, {
    required int limit,
  }) {
    final next = current
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final clientMsgNo = _value(incoming, ['client_msg_no']);
    final index = clientMsgNo.isEmpty
        ? -1
        : next.indexWhere(
            (item) => _value(item, ['client_msg_no']) == clientMsgNo,
          );
    if (index >= 0) {
      next[index] = {...next[index], ...incoming};
    } else {
      next.add(Map<String, Object?>.from(incoming));
    }
    next.sort((a, b) {
      final seqA = _intValue(a, ['message_seq']);
      final seqB = _intValue(b, ['message_seq']);
      if (seqA > 0 && seqB > 0 && seqA != seqB) {
        return seqA.compareTo(seqB);
      }
      return _value(a, ['timestamp']).compareTo(_value(b, ['timestamp']));
    });
    if (next.length <= limit) {
      return next;
    }
    return next.sublist(next.length - limit);
  }

  bool _shouldAutoScrollForMessage(BusinessImMessageEvent event) {
    if (event.message['is_me'] == true || event.source.startsWith('send_')) {
      return true;
    }
    return _isNearBottom();
  }

  bool _isNearBottom({double threshold = 96}) {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.pixels - position.minScrollExtent <= threshold;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final bottom = _scrollController.position.minScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          bottom,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(bottom);
      }
    });
  }

  void _stickToBottomDuringKeyboard() {
    _scrollToBottom(animated: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inputFocusNode.hasFocus) {
        _scrollToBottom(animated: false);
      }
    });
  }

  void _toggleTools() {
    if (!_composerEnabled) {
      return;
    }
    final opening = !_toolsOpen;
    if (opening) {
      FocusScope.of(context).unfocus();
    }
    setState(() => _toolsOpen = opening);
    if (!opening) {
      _scrollToBottom(animated: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muteText = _groupMuteText(_groupMuteState);
    final composerEnabled = _composerEnabled;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _chatPageColor,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Column(
              children: [
                _ChatHeader(
                  title: _chatHeaderTitle(),
                  avatarUrl: _headerAvatarUrl(),
                  isGroup: _isGroup,
                  statusText: _chatHeaderStatusText(),
                  online: !_isGroup && _peerOnline,
                  groupPresenceLoading: _groupPresenceLoading,
                  onBack: () => Navigator.of(context).maybePop(),
                  onDetail: _openChatDetail,
                ),
                if (_error != null) _ChatError(text: _error!),
                if (_message.isNotEmpty) _InfoBar(text: _message),
                if (_replyClientMsgNo.isNotEmpty ||
                    _burnAfterRead ||
                    _mentionAll ||
                    _mentionUserIds.isNotEmpty)
                  _ChatOptionBar(text: _optionText(), onClear: _clearOptions),
                if (_selectedClientMsgNo.isNotEmpty)
                  _SelectedMessageBar(
                    onReply: () => setState(() {
                      _replyClientMsgNo = _selectedClientMsgNo;
                      _selectedClientMsgNo = '';
                    }),
                    onReceipt: _queryReceipt,
                    onRecall: _recallSelected,
                    onDelete: _deleteSelected,
                    onBurn: _burnSelected,
                    onReceiveRedPacket: _receiveSelectedRedPacket,
                    onReceiveTransfer: _receiveSelectedTransfer,
                    onClear: () => setState(() {
                      _selectedClientMsgNo = '';
                      _selectedPayload = const {};
                    }),
                  ),
                Expanded(
                  child: _messagesLoading && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                      ? const _EmptyState(text: '暂无消息')
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final messageIndex = _messages.length - 1 - index;
                            final item = _messages[messageIndex];
                            final showTime = _shouldShowTimeDivider(
                              _messages,
                              messageIndex,
                            );
                            return Column(
                              children: [
                                if (showTime)
                                  _TimeDivider(text: _messageTimeLabel(item)),
                                _MessageRow(
                                  item: item,
                                  showSenderName: _isGroup,
                                  currentUserAvatarUrl:
                                      widget.controller.session?.avatar ?? '',
                                  onLongPress: () => _selectMessage(item),
                                  onRetry: () => _retryMessage(item),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                _Composer(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  sending: _sending,
                  enabled: composerEnabled,
                  disabledText: muteText,
                  toolsOpen: _toolsOpen,
                  onVoice: () => _sendMedia(ChatContentTypes.voice),
                  onEmoji: () => _sendMedia(ChatContentTypes.emoji),
                  onTools: _toggleTools,
                  onSend: _sendText,
                ),
                if (_toolsOpen)
                  _ChatToolsPanel(
                    isGroup: _isGroup,
                    onTextOption: _openTextOptions,
                    onImage: () => _sendMedia(ChatContentTypes.image),
                    onEmoji: () => _sendMedia(ChatContentTypes.emoji),
                    onGif: () => _sendMedia(ChatContentTypes.gif),
                    onSticker: () => _sendMedia(ChatContentTypes.sticker),
                    onVoice: () => _sendMedia(ChatContentTypes.voice),
                    onVideo: () => _sendMedia(ChatContentTypes.video),
                    onFile: () => _sendMedia(ChatContentTypes.file),
                    onContactCard: _sendContactCard,
                    onTransfer: _sendTransfer,
                    onRedPacket: _sendRedPacket,
                    onGroupMembers: _isGroup ? _openGroupMembers : null,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _selectMessage(Map<String, Object?> item) {
    setState(() {
      _selectedClientMsgNo = _value(item, ['client_msg_no']);
      _selectedMessageSeq = _intValue(item, ['message_seq']);
      _selectedPayload = _asObjectMap(item['payload']);
      _message = _selectedClientMsgNo.isEmpty ? '当前消息暂不可操作' : '已选中消息';
    });
  }

  Future<void> _sendText() async {
    if (_sending) {
      return;
    }
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final mentionUserIds = List<String>.from(_mentionUserIds);
    final mentionAll = _mentionAll;
    final replyClientMsgNo = _replyClientMsgNo;
    final burnAfterRead = _burnAfterRead;
    final burnSeconds = _burnSeconds;
    final hadInputFocus = _inputFocusNode.hasFocus;
    await _runSending(
      () async {
        await widget.controller.sendTextMessage(
          channelId: widget.channelId,
          channelType: widget.channelType,
          groupId: widget.groupId,
          text: text,
          mentionUserIds: mentionUserIds,
          mentionAll: mentionAll,
          replyClientMsgNo: replyClientMsgNo,
          burnAfterRead: burnAfterRead,
          burnAfterReadSeconds: burnSeconds,
        );
      },
      beforeTask: () {
        _textController.clear();
        setState(() {
          _replyClientMsgNo = '';
          _mentionUserIds = const [];
          _mentionAll = false;
        });
        if (hadInputFocus) {
          _inputFocusNode.requestFocus();
        }
      },
      keepKeyboard: hadInputFocus,
    );
  }

  Future<void> _retryMessage(Map<String, Object?> item) async {
    if (_sending) {
      return;
    }
    if (_messageStatus(item) != 'failed') {
      return;
    }
    await _runSending(() => widget.controller.retryFailedMessage(item));
  }

  Future<void> _sendMedia(String contentType) async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _selectMediaPayload(contentType);
    if (data == null) {
      return;
    }
    final url = data['url'] ?? '';
    final filePath = data['file_path'] ?? '';
    final params = Map<String, Object?>.from(data)..remove('url');
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupMedia(
          groupId: _groupId,
          channelId: widget.channelId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      } else {
        await widget.controller.sendPrivateMedia(
          receiverId: _receiverId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      }
    });
  }

  Future<Map<String, String>?> _selectMediaPayload(String contentType) {
    if (contentType == ChatContentTypes.image ||
        contentType == ChatContentTypes.video) {
      return Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => _InAppMediaPickerPage(contentType: contentType),
        ),
      );
    }
    if (contentType == ChatContentTypes.file) {
      return Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(builder: (_) => const _InAppFilePickerPage()),
      );
    }
    return _openInput(
      context,
      title: _mediaTitle(contentType),
      fields: _mediaFields(contentType),
    );
  }

  Future<void> _sendContactCard() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送名片',
      fields: const [ActionInputField(id: 'card_user_id', label: '名片用户')],
    );
    if (data == null) {
      return;
    }
    final cardUserId = data['card_user_id'] ?? '';
    if (cardUserId.isEmpty) {
      setState(() => _error = '名片用户不能为空');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupContactCard(
          groupId: _groupId,
          channelId: widget.channelId,
          cardUserId: cardUserId,
        );
      } else {
        await widget.controller.sendPrivateContactCard(
          receiverId: _receiverId,
          cardUserId: cardUserId,
        );
      }
    });
  }

  Future<void> _sendTransfer() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送转账',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        const ActionInputField(id: 'remark', label: '备注'),
        if (_isGroup) const ActionInputField(id: 'receiver_id', label: '指定收款人'),
      ],
    );
    if (data == null) {
      return;
    }
    final money = (data['money'] ?? '').trim();
    if (!_isPositiveMoney(money)) {
      setState(() => _error = '金额必须大于 0');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupTransfer(
          groupId: _groupId,
          channelId: widget.channelId,
          receiverId: data['receiver_id'] ?? '',
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateTransfer(
          receiverId: _receiverId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      }
    });
  }

  Future<void> _sendRedPacket() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送红包',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        const ActionInputField(
          id: 'remark',
          label: '祝福语',
          initial: '恭喜发财，大吉大利',
        ),
        if (_isGroup)
          const ActionInputField(
            id: 'packet_type',
            label: '红包类型',
            hint: 'ordinary、luck、specified',
            initial: 'ordinary',
          ),
        if (_isGroup)
          const ActionInputField(
            id: 'quantity',
            label: '份数',
            keyboardType: TextInputType.number,
            initial: '1',
          ),
        if (_isGroup) const ActionInputField(id: 'receiver_id', label: '指定接收人'),
      ],
    );
    if (data == null) {
      return;
    }
    final money = (data['money'] ?? '').trim();
    if (!_isPositiveMoney(money)) {
      setState(() => _error = '金额必须大于 0');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupRedPacket(
          groupId: _groupId,
          channelId: widget.channelId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          packetType: data['packet_type'] ?? 'ordinary',
          quantity: int.tryParse(data['quantity'] ?? '') ?? 1,
          receiverId: data['receiver_id'] ?? '',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateRedPacket(
          receiverId: _receiverId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      }
    });
  }

  bool _isPositiveMoney(String value) {
    final amount = double.tryParse(value);
    return amount != null && amount > 0;
  }

  Future<void> _openTextOptions() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '文本选项',
      fields: [
        if (_isGroup)
          ActionInputField(
            id: 'mention_user_ids',
            label: '@成员',
            hint: '多个成员用逗号分隔',
            initial: _mentionUserIds.join(','),
          ),
        if (_isGroup)
          ActionInputField(
            id: 'mention_all',
            label: '@所有人',
            hint: '填 1 表示开启',
            initial: _mentionAll ? '1' : '',
          ),
        ActionInputField(
          id: 'burn_after_read',
          label: '阅后即焚',
          hint: '填 1 表示开启',
          initial: _burnAfterRead ? '1' : '',
        ),
        ActionInputField(
          id: 'burn_after_read_seconds',
          label: '倒计时秒数',
          keyboardType: TextInputType.number,
          initial: _burnSeconds > 0 ? _burnSeconds.toString() : '',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    setState(() {
      _mentionUserIds = _idsFromText(data['mention_user_ids'] ?? '');
      _mentionAll = (data['mention_all'] ?? '') == '1';
      _burnAfterRead = (data['burn_after_read'] ?? '') == '1';
      _burnSeconds = int.tryParse(data['burn_after_read_seconds'] ?? '') ?? 0;
    });
  }

  Future<void> _queryReceipt() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      await widget.controller.readReceipt(
        targetClientMsgNo: _selectedClientMsgNo,
        messageSeq: _selectedMessageSeq,
      );
      final status = await widget.controller.receiptStatus(
        _selectedClientMsgNo,
      );
      _message = _receiptText(status, isGroup: _isGroup);
    });
  }

  Future<void> _recallSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.recallMessage(
        targetClientMsgNo: _selectedClientMsgNo,
      );
      final target = _selectedClientMsgNo;
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '消息已撤回');
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    final confirmed = await _confirmDanger(
      context,
      title: '删除消息',
      content: '只删除你自己看到的这条消息，不影响其他人。',
      confirmText: '删除',
    );
    if (!confirmed) {
      return;
    }
    await _runAction(() async {
      final target = _selectedClientMsgNo;
      final result = await widget.controller.deleteMessageForSelf(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '消息已删除');
    });
  }

  Future<void> _burnSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.burnAfterRead(
        _selectedClientMsgNo,
      );
      final target = _selectedClientMsgNo;
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '已触发阅后即焚');
    });
  }

  Future<void> _receiveSelectedRedPacket() async {
    final id = _nestedValue(_selectedPayload, [
      'red_packet.red_packet_id',
      'red_packet_id',
    ]);
    if (id.isEmpty) {
      setState(() => _error = '当前消息没有红包 ID');
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.receiveRedPacket(
        redPacketId: id,
        group: _isGroup,
      );
      _message = _friendlyResult(result, successText: '红包已领取');
    });
  }

  Future<void> _receiveSelectedTransfer() async {
    final id = _nestedValue(_selectedPayload, [
      'transfer.transfer_id',
      'transfer_id',
    ]);
    if (id.isEmpty) {
      setState(() => _error = '当前消息没有转账 ID');
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.receiveTransfer(id);
      _message = _friendlyResult(result, successText: '转账已收款');
    });
  }

  Future<void> _openGroupMembers() async {
    await _push(
      context,
      GroupDetailPage(
        controller: widget.controller,
        title: widget.title,
        groupId: _groupId,
        channelId: widget.channelId,
      ),
    );
    if (mounted && _isGroup) {
      unawaited(_refreshGroupPresence());
    }
  }

  Future<void> _openChatDetail() async {
    await _push(
      context,
      _isGroup
          ? GroupDetailPage(
              controller: widget.controller,
              title: widget.title,
              groupId: _groupId,
              channelId: widget.channelId,
            )
          : PrivateChatActionsPage(
              controller: widget.controller,
              title: widget.title,
              receiverId: _receiverId,
              channelId: widget.channelId,
            ),
    );
    if (mounted && _isGroup) {
      unawaited(_refreshGroupPresence());
    }
  }

  Future<void> _runSending(
    Future<void> Function() task, {
    VoidCallback? beforeTask,
    bool keepKeyboard = false,
  }) async {
    if (_sending) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _message = '';
    });
    try {
      beforeTask?.call();
      await task();
      if (mounted) {
        setState(() {
          _conversationRevision = widget.controller.conversationVersion;
          _messageRevision = _currentMessageRevision();
        });
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        if (keepKeyboard) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _inputFocusNode.requestFocus();
            }
          });
        }
      }
    }
  }

  Future<void> _runAction(Future<void> Function() task) async {
    setState(() {
      _error = null;
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _clearOptions() {
    setState(() {
      _replyClientMsgNo = '';
      _mentionUserIds = const [];
      _mentionAll = false;
      _burnAfterRead = false;
      _burnSeconds = 0;
    });
  }

  bool _isMessageDeleteEvent(String source) {
    return source == 'burn_after_read_cmd' || source == 'recall_cmd';
  }

  void _scheduleBurnAfterReadForMessages(List<Map<String, Object?>> messages) {
    for (final item in messages) {
      if (_isSelfMessage(item)) {
        continue;
      }
      final clientMsgNo = _value(item, ['client_msg_no']);
      if (clientMsgNo.isEmpty ||
          _burnTriggeredClientMsgNos.contains(clientMsgNo)) {
        continue;
      }
      final burn = _asObjectMap(
        _asObjectMap(item['payload'])['burn_after_read'],
      );
      if (!_boolValue(burn['enabled'])) {
        continue;
      }
      _burnTriggeredClientMsgNos.add(clientMsgNo);
      final seconds = _intValue(burn, ['seconds']);
      Future<void>.delayed(Duration(seconds: seconds > 0 ? seconds : 1), () {
        return _triggerBurnAfterRead(clientMsgNo);
      });
    }
  }

  Future<void> _triggerBurnAfterRead(String clientMsgNo) async {
    if (!mounted ||
        !_messages.any(
          (item) => _value(item, ['client_msg_no']) == clientMsgNo,
        )) {
      return;
    }
    try {
      await widget.controller.burnAfterRead(clientMsgNo);
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: clientMsgNo,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((item) => _value(item, ['client_msg_no']) != clientMsgNo)
              .toList(growable: false);
        });
      }
    } catch (error, stackTrace) {
      _burnTriggeredClientMsgNos.remove(clientMsgNo);
      AppLogger.warn(
        'ui',
        'burn after read trigger failed',
        data: {
          'client_msg_no': clientMsgNo,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  bool _isSelfMessage(Map<String, Object?> item) {
    final value = item['is_me'];
    return value == true ||
        value?.toString() == '1' ||
        value?.toString() == 'true';
  }

  String _headerAvatarUrl() {
    for (final item in widget.controller.cachedConversations()) {
      if (_value(item, ['channel_id']) == widget.channelId &&
          _intValue(item, ['channel_type']) == widget.channelType) {
        final avatar = _conversationAvatarUrl(item);
        if (avatar.isNotEmpty) {
          return avatar;
        }
      }
    }
    for (final item in _messages) {
      if (!_isSelfMessage(item)) {
        final avatar = _messageSenderAvatarUrl(item);
        if (avatar.isNotEmpty) {
          return avatar;
        }
      }
    }
    return '';
  }

  String _optionText() {
    final parts = <String>[];
    if (_replyClientMsgNo.isNotEmpty) {
      parts.add('引用 ${_shortNo(_replyClientMsgNo)}');
    }
    if (_mentionAll) {
      parts.add('@所有人');
    }
    if (_mentionUserIds.isNotEmpty) {
      parts.add('@${_mentionUserIds.join(',')}');
    }
    if (_burnAfterRead) {
      parts.add(_burnSeconds > 0 ? '阅后即焚 ${_burnSeconds}s' : '阅后即焚');
    }
    return parts.join(' · ');
  }
}

class ActionInputField {
  const ActionInputField({
    required this.id,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.keyboardType,
    this.maxLines = 1,
  });

  final String id;
  final String label;
  final String hint;
  final String initial;
  final TextInputType? keyboardType;
  final int maxLines;
}

class ActionInputPage extends StatefulWidget {
  const ActionInputPage({required this.title, required this.fields, super.key});

  final String title;
  final List<ActionInputField> fields;

  @override
  State<ActionInputPage> createState() => _ActionInputPageState();
}

class _InAppMediaPickerPage extends StatefulWidget {
  const _InAppMediaPickerPage({required this.contentType});

  final String contentType;

  @override
  State<_InAppMediaPickerPage> createState() => _InAppMediaPickerPageState();
}

class _InAppMediaPickerPageState extends State<_InAppMediaPickerPage> {
  static const _pageSize = 120;

  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _selectedAlbum;
  bool _loading = true;
  bool _loadingAssets = false;
  String _error = '';
  String _selectingAssetId = '';

  bool get _isVideo => widget.contentType == ChatContentTypes.video;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAlbums());
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '需要授权访问相册后才能选择${_isVideo ? '视频' : '图片'}';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _isVideo ? RequestType.video : RequestType.image,
        hasAll: true,
      );
      if (!mounted) {
        return;
      }
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _albums = const [];
          _assets = const [];
          _selectedAlbum = null;
          _error = '';
        });
        return;
      }
      final selected = albums.firstWhere(
        (item) => item.isAll,
        orElse: () => albums.first,
      );
      setState(() {
        _albums = albums;
        _selectedAlbum = selected;
      });
      await _loadAssets(selected, showPageLoading: false);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '相册读取失败';
      });
    }
  }

  Future<void> _loadAssets(
    AssetPathEntity album, {
    bool showPageLoading = true,
  }) async {
    if (showPageLoading) {
      setState(() {
        _loadingAssets = true;
        _error = '';
      });
    }
    try {
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAlbum = album;
        _assets = assets;
        _loading = false;
        _loadingAssets = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media assets failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingAssets = false;
        _error = '媒体列表读取失败';
      });
    }
  }

  Future<void> _selectAsset(AssetEntity asset) async {
    if (_selectingAssetId.isNotEmpty) {
      return;
    }
    setState(() => _selectingAssetId = asset.id);
    try {
      final file = await asset.originFile ?? await asset.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('asset file is unavailable');
      }
      final stat = await file.stat();
      if (!mounted) {
        return;
      }
      final name = await asset.titleAsync;
      final payload = <String, String>{
        'file_path': file.path,
        'name': name.isNotEmpty ? name : _fileName(file.path),
        'size': stat.size.toString(),
        'mime': asset.mimeType ?? _mimeFromPath(file.path, widget.contentType),
        if (asset.width > 0) 'width': asset.width.toString(),
        if (asset.height > 0) 'height': asset.height.toString(),
        if (_isVideo) 'duration': asset.duration.toString(),
      };
      Navigator.of(context).pop(payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select media asset failed',
        error: error,
        stackTrace: stackTrace,
        data: {'asset_id': asset.id},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingAssetId = '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文件读取失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(_isVideo ? '选择视频' : '选择图片'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _ErrorState(
        text: _error,
        onRetry: _error.contains('授权')
            ? () async {
                await PhotoManager.openSetting();
                if (mounted) {
                  await _loadAlbums();
                }
              }
            : _loadAlbums,
      );
    }
    if (_assets.isEmpty) {
      return _EmptyState(text: _isVideo ? '暂无可发送视频' : '暂无可发送图片');
    }
    return Column(
      children: [
        _MediaAlbumBar(
          albums: _albums,
          selected: _selectedAlbum,
          onChanged: (album) => _loadAssets(album),
        ),
        if (_loadingAssets)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: _assets.length,
            itemBuilder: (context, index) {
              final asset = _assets[index];
              return _MediaAssetTile(
                asset: asset,
                selecting: _selectingAssetId == asset.id,
                onTap: () => _selectAsset(asset),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MediaAlbumBar extends StatelessWidget {
  const _MediaAlbumBar({
    required this.albums,
    required this.selected,
    required this.onChanged,
  });

  final List<AssetPathEntity> albums;
  final AssetPathEntity? selected;
  final ValueChanged<AssetPathEntity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AssetPathEntity>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: albums
              .map(
                (album) => DropdownMenuItem<AssetPathEntity>(
                  value: album,
                  child: Text(
                    album.isAll ? '全部' : album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (album) {
            if (album != null) {
              onChanged(album);
            }
          },
        ),
      ),
    );
  }
}

class _MediaAssetTile extends StatelessWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.selecting,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize.square(220),
              quality: 82,
            ),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(
                  color: const Color(0xffe8eaed),
                  child: Icon(
                    asset.type == AssetType.video
                        ? Icons.videocam_outlined
                        : Icons.image_outlined,
                    color: _mutedColor,
                  ),
                );
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          ),
          if (asset.type == AssetType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: const Color(0x99000000),
                child: Text(
                  _secondsLabel(asset.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          if (selecting)
            Container(
              color: const Color(0x66000000),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _InAppFilePickerPage extends StatefulWidget {
  const _InAppFilePickerPage();

  @override
  State<_InAppFilePickerPage> createState() => _InAppFilePickerPageState();
}

class _InAppFilePickerPageState extends State<_InAppFilePickerPage> {
  static const _maxFiles = 300;

  List<_LocalFileItem> _files = const [];
  bool _loading = true;
  String _error = '';
  String _selectingPath = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadFiles());
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final dirs = await _candidateFileDirectories();
      final files = <_LocalFileItem>[];
      final seen = <String>{};
      for (final dir in dirs) {
        if (files.length >= _maxFiles) {
          break;
        }
        await _scanDirectory(dir, files, seen, depth: 2);
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) {
        return;
      }
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load in-app files failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '文件列表读取失败';
      });
    }
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<_LocalFileItem> files,
    Set<String> seen, {
    required int depth,
  }) async {
    if (files.length >= _maxFiles || !await dir.exists()) {
      return;
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (files.length >= _maxFiles) {
          return;
        }
        final name = _fileName(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        if (entity is File) {
          if (!seen.add(entity.path)) {
            continue;
          }
          final stat = await entity.stat();
          if (stat.size <= 0) {
            continue;
          }
          files.add(
            _LocalFileItem(
              path: entity.path,
              name: name,
              size: stat.size,
              modified: stat.modified.millisecondsSinceEpoch,
            ),
          );
        } else if (entity is Directory && depth > 0) {
          await _scanDirectory(entity, files, seen, depth: depth - 1);
        }
      }
    } on FileSystemException {
      return;
    }
  }

  Future<void> _selectFile(_LocalFileItem file) async {
    if (_selectingPath.isNotEmpty) {
      return;
    }
    setState(() => _selectingPath = file.path);
    try {
      final current = File(file.path);
      final stat = await current.stat();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(<String, String>{
        'file_path': file.path,
        'name': file.name,
        'size': stat.size.toString(),
        'mime': _mimeFromPath(file.path, ChatContentTypes.file),
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select in-app file failed',
        error: error,
        stackTrace: stackTrace,
        data: {'path': file.path},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingPath = '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文件读取失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('选择文件'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _ErrorState(text: _error, onRetry: _loadFiles);
    }
    if (_files.isEmpty) {
      return const _EmptyState(text: '暂无可发送文件');
    }
    return ListView.separated(
      itemCount: _files.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _lightBorderColor),
      itemBuilder: (context, index) {
        final file = _files[index];
        final selecting = _selectingPath == file.path;
        return ListTile(
          leading: Icon(_fileIcon(file.name), color: _primaryColor),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textColor, fontSize: 15),
          ),
          subtitle: Text(
            '${_fileSizeLabel(file.size)} · ${_formatTime(file.modified)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _mutedColor, fontSize: 12),
          ),
          trailing: selecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right, color: _mutedColor),
          onTap: () => _selectFile(file),
        );
      },
    );
  }
}

class _LocalFileItem {
  const _LocalFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final int modified;
}

class _ActionInputPageState extends State<ActionInputPage> {
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _controllers[field.id] = TextEditingController(text: field.initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final field in widget.fields) ...[
              TextField(
                controller: _controllers[field.id],
                keyboardType: field.keyboardType,
                maxLines: field.maxLines,
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.hint.isEmpty ? null : field.hint,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _ButtonRow(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _controllers.map(
                        (key, value) => MapEntry(key, value.text.trim()),
                      ),
                    );
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AsyncList extends StatefulWidget {
  const _AsyncList({
    required this.loader,
    required this.itemBuilder,
    required this.emptyText,
  });

  final Future<List<Map<String, Object?>>> Function() loader;
  final Widget Function(BuildContext context, Map<String, Object?> item)
  itemBuilder;
  final String emptyText;

  @override
  State<_AsyncList> createState() => _AsyncListState();
}

class _AsyncListState extends State<_AsyncList> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_AsyncList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      _future = _load();
    }
  }

  Future<List<Map<String, Object?>>> _load() {
    return AppLogger.measure('ui', 'load list', widget.loader);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString(), onRetry: _reload);
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _EmptyState(text: widget.emptyText);
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            return widget.itemBuilder(context, items[index]);
          },
        );
      },
    );
  }
}

class _PlainListTile extends StatelessWidget {
  const _PlainListTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.icon,
    this.avatarUrl = '',
    this.onTap,
    this.onLongPress,
  });

  final IconData? icon;
  final String avatarUrl;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: ListTile(
        leading: avatarUrl.isNotEmpty
            ? _Avatar(label: title, imageUrl: avatarUrl, size: 38, icon: icon)
            : icon == null
            ? null
            : Icon(icon, color: _mutedColor),
        onTap: onTap,
        onLongPress: onLongPress,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing.isEmpty
            ? null
            : Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _mutedColor),
              ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.hintText, required this.onTap});

  final String hintText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xfff0f1f3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: _mutedColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  hintText,
                  style: const TextStyle(color: _mutedColor, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.unread,
    required this.isGroup,
    required this.avatarUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String time;
  final int unread;
  final bool isGroup;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 48,
              color: isGroup ? const Color(0xff34c759) : _primaryColor,
              icon: isGroup ? Icons.groups : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _ConversationSubtitleText(text: subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: const TextStyle(color: _mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xffff3b30),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : unread.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationSubtitleText extends StatelessWidget {
  const _ConversationSubtitleText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final prefixColor = _conversationPrefixColor(text);
    if (prefixColor == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _mutedColor, fontSize: 13),
      );
    }
    final prefix = text.startsWith('[红包]') ? '[红包]' : '[转账]';
    final suffix = text.substring(prefix.length);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: TextStyle(color: prefixColor, fontWeight: FontWeight.w700),
          ),
          if (suffix.isNotEmpty)
            TextSpan(
              text: suffix,
              style: const TextStyle(color: _mutedColor),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.isGroup,
    required this.onTap,
    this.avatarUrl = '',
    this.avatarColor,
    this.icon,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool isGroup;
  final VoidCallback onTap;
  final String avatarUrl;
  final Color? avatarColor;
  final IconData? icon;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 38,
              color:
                  avatarColor ??
                  (isGroup ? const Color(0xff34c759) : _primaryColor),
              icon: icon ?? (isGroup ? Icons.groups : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _mutedColor, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            const Icon(Icons.chevron_right, color: _mutedColor, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    this.size = 44,
    this.color = _primaryColor,
    this.icon,
    this.imageUrl = '',
    this.circle = false,
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;
  final String imageUrl;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final fallback = _AvatarFallback(
      label: label,
      size: size,
      color: color,
      icon: icon,
      circle: circle,
    );
    final url = _normalizeAvatarUrl(imageUrl);
    if (url.isEmpty) {
      return fallback;
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.28),
      ),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.label,
    required this.size,
    required this.color,
    this.icon,
    this.circle = false,
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.28),
      ),
      child: icon == null
          ? Text(
              _avatarInitial(label),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: _primaryColor, size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.item,
    required this.showSenderName,
    required this.currentUserAvatarUrl,
    required this.onLongPress,
    required this.onRetry,
  });

  final Map<String, Object?> item;
  final bool showSenderName;
  final String currentUserAvatarUrl;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isMe = item['is_me'] == true;
    final sender = _messageSenderName(item);
    final avatarUrl = isMe
        ? currentUserAvatarUrl
        : _messageSenderAvatarUrl(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(label: sender, imageUrl: avatarUrl, size: 38, circle: true),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe && showSenderName && sender.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Text(
                      sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _mutedColor, fontSize: 11),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onLongPress: onLongPress,
                      child: _MessageBubble(
                        item: item,
                        isMe: isMe,
                        status: _messageStatus(item),
                        onRetry: onRetry,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _Avatar(
              label: '我',
              imageUrl: avatarUrl,
              size: 38,
              color: _primaryColor,
              circle: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.avatarUrl,
    required this.isGroup,
    required this.statusText,
    required this.online,
    required this.groupPresenceLoading,
    required this.onBack,
    required this.onDetail,
  });

  final String title;
  final String avatarUrl;
  final bool isGroup;
  final String statusText;
  final bool online;
  final bool groupPresenceLoading;
  final VoidCallback onBack;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return Container(
        height: 64,
        color: _chatPageColor,
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 5),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _HeaderIconButton(
                tooltip: '返回',
                icon: Icons.chevron_left,
                iconSize: 31,
                onPressed: onBack,
              ),
            ),
            Positioned.fill(
              left: 86,
              right: 118,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isEmpty ? '群聊' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (groupPresenceLoading) ...[
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: Color(0xff8c939d),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff8c939d),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderIconButton(
                    tooltip: '语音通话',
                    icon: Icons.call_outlined,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 5),
                  _HeaderIconButton(
                    tooltip: '视频通话',
                    icon: Icons.videocam_outlined,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 5),
                  _HeaderIconButton(
                    tooltip: '群设置',
                    icon: Icons.more_horiz,
                    onPressed: onDetail,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 64,
      color: _chatPageColor,
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 5),
      child: Row(
        children: [
          _HeaderIconButton(
            tooltip: '返回',
            icon: Icons.chevron_left,
            iconSize: 31,
            onPressed: onBack,
          ),
          const SizedBox(width: 3),
          _Avatar(
            label: title,
            imageUrl: avatarUrl,
            size: 40,
            color: isGroup ? const Color(0xff34c759) : _primaryColor,
            circle: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '聊天' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: online || isGroup
                              ? _chatOnlineColor
                              : const Color(0xffb8bec8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Color(0xff8c939d),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            tooltip: '语音通话',
            icon: Icons.call_outlined,
            onPressed: () {},
          ),
          const SizedBox(width: 5),
          _HeaderIconButton(
            tooltip: '视频通话',
            icon: Icons.videocam_outlined,
            onPressed: () {},
          ),
          const SizedBox(width: 5),
          _HeaderIconButton(
            tooltip: isGroup ? '群设置' : '聊天设置',
            icon: Icons.more_horiz,
            onPressed: onDetail,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 42,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.black, size: iconSize),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.isMe,
    required this.status,
    required this.onRetry,
  });

  final Map<String, Object?> item;
  final bool isMe;
  final String status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final contentType = _messageContentType(item);
    final payload = _asObjectMap(item['payload']);
    final content = _messageContentText(item, payload);
    final isImageLike =
        contentType == ChatContentTypes.image ||
        contentType == ChatContentTypes.gif ||
        contentType == ChatContentTypes.sticker;
    final bubble = _MessageBubbleContent(
      contentType: contentType,
      content: content,
      payload: payload,
      isMe: isMe,
      status: status,
    );
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.64,
      ),
      padding: _bubblePadding(contentType),
      decoration: BoxDecoration(
        color: _bubbleColor(contentType),
        borderRadius: BorderRadius.circular(isImageLike ? 8 : 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bubble,
          if (!isImageLike) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: _MessageMeta(
                time: _messageBubbleTime(item),
                isMe: isMe,
                status: status,
                onRetry: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _bubbleColor(String contentType) {
    if (contentType == ChatContentTypes.redPacket) {
      return Colors.transparent;
    }
    return isMe ? _chatMineBubbleColor : Colors.white;
  }

  EdgeInsets _bubblePadding(String contentType) {
    return switch (contentType) {
      ChatContentTypes.redPacket => EdgeInsets.zero,
      ChatContentTypes.image ||
      ChatContentTypes.gif ||
      ChatContentTypes.sticker => const EdgeInsets.all(0),
      ChatContentTypes.file ||
      ChatContentTypes.voice ||
      ChatContentTypes.video ||
      ChatContentTypes.contactCard ||
      ChatContentTypes.transfer => const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      _ => const EdgeInsets.fromLTRB(14, 10, 10, 7),
    };
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.time,
    required this.isMe,
    required this.status,
    required this.onRetry,
  });

  final String time;
  final bool isMe;
  final String status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(
            color: isMe ? const Color(0xff73946f) : const Color(0xff9198a2),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 5),
          _MessageSendStatus(status: status, onRetry: onRetry),
        ],
      ],
    );
  }
}

class _RedPacketPreview extends StatelessWidget {
  const _RedPacketPreview({required this.remark});

  final String remark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 236,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xffffa34c), Color(0xffff963c)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Container(
                  width: 47,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xffe94632),
                    borderRadius: BorderRadius.all(Radius.circular(7)),
                  ),
                  child: const Icon(
                    Icons.redeem,
                    color: Color(0xffffd35b),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        remark.isEmpty ? '恭喜发财，大吉大利' : remark,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'BIM红包',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 28,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: const Text(
              'BIM红包',
              style: TextStyle(
                color: Color(0xffaeb4bd),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubbleContent extends StatelessWidget {
  const _MessageBubbleContent({
    required this.contentType,
    required this.content,
    required this.payload,
    required this.isMe,
    required this.status,
  });

  final String contentType;
  final String content;
  final Map<String, Object?> payload;
  final bool isMe;
  final String status;

  @override
  Widget build(BuildContext context) {
    return switch (contentType) {
      ChatContentTypes.image => _ImageMessagePreview(
        payload: payload,
        status: status,
      ),
      ChatContentTypes.gif => _MediaPreview(
        icon: Icons.gif_box_outlined,
        title: content.isEmpty ? 'GIF' : content,
        subtitle: _value(payload, ['url', 'file_path']),
        isMe: isMe,
      ),
      ChatContentTypes.sticker => _StickerPreview(
        text: _value(payload, ['sticker_id', 'emoji_code'], fallback: content),
      ),
      ChatContentTypes.emoji => Text(
        _value(payload, [
          'emoji_code',
        ], fallback: content.isEmpty ? '[表情]' : content),
        style: const TextStyle(fontSize: 24, height: 1.2),
      ),
      ChatContentTypes.voice => _VoicePreview(
        seconds: _value(payload, ['duration'], fallback: '0'),
        isMe: isMe,
      ),
      ChatContentTypes.video => _VideoMessagePreview(
        payload: payload,
        content: content,
        status: status,
      ),
      ChatContentTypes.file => _FilePreview(payload: payload, content: content),
      ChatContentTypes.contactCard => _ContactCardPreview(payload: payload),
      ChatContentTypes.transfer => _PaymentPreview(
        icon: Icons.payments_outlined,
        title: '转账',
        amount: _paymentAmount(payload),
        isMe: isMe,
      ),
      ChatContentTypes.redPacket => _RedPacketPreview(
        remark: _redPacketRemark(payload),
      ),
      _ => Text(
        content.isEmpty ? '[消息]' : content,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    };
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isMe,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _textColor, size: 24),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe
                          ? const Color(0xff477a35)
                          : const Color(0xff8b929e),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageMessagePreview extends StatelessWidget {
  const _ImageMessagePreview({required this.payload, required this.status});

  final Map<String, Object?> payload;
  final String status;

  @override
  Widget build(BuildContext context) {
    final localPath = _value(payload, ['file_path']);
    final url = _normalizeAvatarUrl(
      _value(payload, [
        'url',
        'image_path',
      ], fallback: _value(_asObjectMap(payload['media']), ['url'])),
    );
    final image = localPath.isNotEmpty && File(localPath).existsSync()
        ? Image.file(File(localPath), fit: BoxFit.cover)
        : url.isNotEmpty
        ? Image.network(url, fit: BoxFit.cover, gaplessPlayback: true)
        : null;
    if (image == null) {
      return const _MediaPreview(
        icon: Icons.image_outlined,
        title: '图片',
        subtitle: '',
        isMe: false,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMessagePreview extends StatelessWidget {
  const _VideoMessagePreview({
    required this.payload,
    required this.content,
    required this.status,
  });

  final Map<String, Object?> payload;
  final String content;
  final String status;

  @override
  Widget build(BuildContext context) {
    final media = _asObjectMap(payload['media']);
    final rawLocalPath = _value(payload, [
      'cover_file_path',
      'thumb_file_path',
      'thumbnail_file_path',
    ]);
    final rawCoverUrl = _value(
      payload,
      ['cover_url', 'thumb_url', 'thumbnail_url', 'image_path'],
      fallback: _value(media, [
        'cover_url',
        'thumb_url',
        'thumbnail_url',
        'image_path',
      ]),
    );
    final localPath = _looksLikeVideoPath(rawLocalPath) ? '' : rawLocalPath;
    final coverUrl = _looksLikeVideoPath(rawCoverUrl)
        ? ''
        : _normalizeAvatarUrl(rawCoverUrl);
    final image = localPath.isNotEmpty && File(localPath).existsSync()
        ? Image.file(File(localPath), fit: BoxFit.cover)
        : coverUrl.isNotEmpty
        ? Image.network(coverUrl, fit: BoxFit.cover, gaplessPlayback: true)
        : null;
    if (image == null) {
      final source = _videoPreviewSource(payload, media);
      if (source != null) {
        return _VideoFramePreview(
          source: source,
          payload: payload,
          content: content,
          status: status,
        );
      }
      return _VideoPlaceholderPreview(
        payload: payload,
        content: content,
        status: status,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewSource {
  const _VideoPreviewSource({required this.value, required this.isLocal});

  final String value;
  final bool isLocal;

  String get key => '${isLocal ? 'file' : 'url'}:$value';
}

class _VideoFramePreview extends StatefulWidget {
  const _VideoFramePreview({
    required this.source,
    required this.payload,
    required this.content,
    required this.status,
  });

  final _VideoPreviewSource source;
  final Map<String, Object?> payload;
  final String content;
  final String status;

  @override
  State<_VideoFramePreview> createState() => _VideoFramePreviewState();
}

class _VideoFramePreviewState extends State<_VideoFramePreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VideoFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.key != widget.source.key) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final previous = _controller;
    _controller = null;
    _ready = false;
    await previous?.dispose();

    final source = widget.source;
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = source.isLocal
        ? VideoPlayerController.file(
            File(source.value),
            videoPlayerOptions: options,
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(source.value),
            videoPlayerOptions: options,
          );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() => _ready = true);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'video preview initialize failed',
        error: error,
        stackTrace: stackTrace,
        data: {'source': source.key},
      );
      await controller.dispose();
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() {
        _controller = null;
        _ready = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return _VideoPlaceholderPreview(
        payload: widget.payload,
        content: widget.content,
        status: widget.status,
      );
    }
    final size = controller.value.size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width <= 0 ? 208 : size.width,
                  height: size.height <= 0 ? 124 : size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            if (widget.status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: widget.status,
              progress: _uploadProgress(widget.payload),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlaceholderPreview extends StatelessWidget {
  const _VideoPlaceholderPreview({
    required this.payload,
    required this.content,
    required this.status,
  });

  final Map<String, Object?> payload;
  final String content;
  final String status;

  @override
  Widget build(BuildContext context) {
    final title = _videoTitle(payload, content);
    final subtitle = _videoSubtitle(payload);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff222832), Color(0xff101317)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xccffffff),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaUploadOverlay extends StatelessWidget {
  const _MediaUploadOverlay({required this.status, required this.progress});

  final String status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (status != 'sending' && status != 'failed') {
      return const SizedBox.shrink();
    }
    final failed = status == 'failed';
    final hasProgress = progress > 0 && progress < 1;
    return ColoredBox(
      color: const Color(0x66000000),
      child: Center(
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xaa000000),
            shape: BoxShape.circle,
          ),
          child: failed
              ? const Icon(Icons.error_outline, color: Colors.white, size: 28)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        value: hasProgress ? progress : null,
                        strokeWidth: 2.4,
                        color: Colors.white,
                        backgroundColor: const Color(0x55ffffff),
                      ),
                    ),
                    if (hasProgress)
                      Text(
                        '${(progress * 100).clamp(1, 99).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StickerPreview extends StatelessWidget {
  const _StickerPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.isEmpty ? '[贴纸]' : text,
      style: const TextStyle(
        color: _textColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
  }
}

class _VoicePreview extends StatelessWidget {
  const _VoicePreview({required this.seconds, required this.isMe});

  final String seconds;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final label = seconds == '0' || seconds.isEmpty ? '' : '$seconds"';
    return SizedBox(
      width: 100,
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) const Icon(Icons.graphic_eq, size: 20),
          if (!isMe) const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe) const Icon(Icons.graphic_eq, size: 20),
        ],
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.payload, required this.content});

  final Map<String, Object?> payload;
  final String content;

  @override
  Widget build(BuildContext context) {
    final media = _asObjectMap(payload['media']);
    final name = _value(payload, [
      'file_name',
      'name',
      'filename',
    ], fallback: _value(media, ['name'], fallback: content));
    final size = _value(payload, [
      'file_size',
      'size',
    ], fallback: _value(media, ['size']));
    return SizedBox(
      width: 218,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xfff05045),
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            child: const Icon(
              Icons.article_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? '文件' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (size.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _fileSizeLabel(size),
                      style: const TextStyle(color: _mutedColor, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCardPreview extends StatelessWidget {
  const _ContactCardPreview({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final name = _value(payload, [
      'card_nickname',
      'nickname',
      'name',
      'card_user_id',
    ]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(label: name, size: 32, color: const Color(0xff34c759)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name.isEmpty ? '名片' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentPreview extends StatelessWidget {
  const _PaymentPreview({
    required this.icon,
    required this.title,
    required this.amount,
    required this.isMe,
  });

  final IconData icon;
  final String title;
  final String amount;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xffd46b08), size: 24),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (amount.isNotEmpty)
              Text(
                amount,
                style: TextStyle(
                  color: isMe
                      ? const Color(0xff477a35)
                      : const Color(0xff8b929e),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MessageSendStatus extends StatelessWidget {
  const _MessageSendStatus({required this.status, required this.onRetry});

  final String status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: switch (status) {
          'sending' => const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Color(0xff9aa0aa),
            ),
          ),
          'failed' => Tooltip(
            message: '重发',
            child: InkResponse(
              onTap: onRetry,
              radius: 18,
              child: const Icon(
                Icons.error_outline,
                size: 17,
                color: _dangerColor,
              ),
            ),
          ),
          'read' => const Icon(Icons.done_all, size: 17, color: _chatAckColor),
          'queued' ||
          'sent' => const Icon(Icons.done, size: 17, color: _chatAckColor),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xff8f96a3),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SelectedMessageBar extends StatelessWidget {
  const _SelectedMessageBar({
    required this.onReply,
    required this.onReceipt,
    required this.onRecall,
    required this.onDelete,
    required this.onBurn,
    required this.onReceiveRedPacket,
    required this.onReceiveTransfer,
    required this.onClear,
  });

  final VoidCallback onReply;
  final VoidCallback onReceipt;
  final VoidCallback onRecall;
  final VoidCallback onDelete;
  final VoidCallback onBurn;
  final VoidCallback onReceiveRedPacket;
  final VoidCallback onReceiveTransfer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: _fillColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('已选中消息'),
          _MiniButton(label: '引用', onTap: onReply),
          _MiniButton(label: '已读', onTap: onReceipt),
          _MiniButton(label: '撤回', onTap: onRecall),
          _MiniButton(label: '删除', onTap: onDelete),
          _MiniButton(label: '焚毁', onTap: onBurn),
          _MiniButton(label: '领红包', onTap: onReceiveRedPacket),
          _MiniButton(label: '收转账', onTap: onReceiveTransfer),
          IconButton(
            tooltip: '取消选择',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ChatOptionBar extends StatelessWidget {
  const _ChatOptionBar({required this.text, required this.onClear});

  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xfffffbeb),
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xff785800)),
            ),
          ),
          IconButton(
            tooltip: '清除选项',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ChatToolsPanel extends StatelessWidget {
  const _ChatToolsPanel({
    required this.isGroup,
    required this.onTextOption,
    required this.onImage,
    required this.onEmoji,
    required this.onGif,
    required this.onSticker,
    required this.onVoice,
    required this.onVideo,
    required this.onFile,
    required this.onContactCard,
    required this.onTransfer,
    required this.onRedPacket,
    this.onGroupMembers,
  });

  final bool isGroup;
  final VoidCallback onTextOption;
  final VoidCallback onImage;
  final VoidCallback onEmoji;
  final VoidCallback onGif;
  final VoidCallback onSticker;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onContactCard;
  final VoidCallback onTransfer;
  final VoidCallback onRedPacket;
  final VoidCallback? onGroupMembers;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ToolItem(
        Icons.photo_library_rounded,
        '相册',
        onImage,
        const Color(0xff8e6df7),
      ),
      _ToolItem(
        Icons.photo_camera_rounded,
        '拍摄',
        onImage,
        const Color(0xff2f7df6),
      ),
      _ToolItem(
        Icons.videocam_rounded,
        '视频通话',
        onVideo,
        const Color(0xff2fc86f),
      ),
      _ToolItem(
        Icons.location_on_rounded,
        '位置',
        onTextOption,
        const Color(0xffffa21a),
      ),
      _ToolItem(Icons.folder_rounded, '文件', onFile, const Color(0xff2f7df6)),
      _ToolItem(
        Icons.attach_money_rounded,
        '转账',
        onTransfer,
        const Color(0xff28b957),
      ),
      _ToolItem(
        Icons.redeem_rounded,
        '红包',
        onRedPacket,
        const Color(0xffff543c),
      ),
      _ToolItem(
        Icons.contact_page_rounded,
        '名片',
        onContactCard,
        const Color(0xff347cff),
      ),
      _ToolItem(
        Icons.emoji_emotions_rounded,
        '表情',
        onEmoji,
        const Color(0xffffc043),
      ),
      _ToolItem(Icons.gif_box_rounded, 'GIF', onGif, const Color(0xff20c997)),
      _ToolItem(
        Icons.sticky_note_2_rounded,
        '贴纸',
        onSticker,
        const Color(0xff7c5cff),
      ),
      _ToolItem(
        Icons.keyboard_voice_rounded,
        '语音',
        onVoice,
        const Color(0xff5ac8fa),
      ),
      _ToolItem(
        Icons.tune_rounded,
        '文本选项',
        onTextOption,
        const Color(0xff8e99a8),
      ),
      if (isGroup && onGroupMembers != null)
        _ToolItem(
          Icons.groups_rounded,
          '群成员',
          onGroupMembers!,
          const Color(0xff34c759),
        ),
    ];
    final pages = <List<_ToolItem>>[];
    for (var index = 0; index < items.length; index += 8) {
      pages.add(items.sublist(index, (index + 8).clamp(0, items.length)));
    }
    return Container(
      height: 174,
      color: _chatPageColor,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: PageView.builder(
          itemCount: pages.length,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, pageIndex) {
            final pageItems = pages[pageIndex];
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 12),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 66,
                crossAxisSpacing: 10,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) =>
                  _ToolButton(item: pageItems[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem(this.icon, this.label, this.onTap, this.color);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item});

  final _ToolItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(
                item.icon == Icons.attach_money_rounded ? 16 : 6,
              ),
            ),
            child: Icon(item.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 7),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xff2f3338),
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.disabledText,
    required this.toolsOpen,
    required this.onVoice,
    required this.onEmoji,
    required this.onTools,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final String disabledText;
  final bool toolsOpen;
  final VoidCallback onVoice;
  final VoidCallback onEmoji;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _chatPageColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _ComposerIconButton(
              tooltip: '语音',
              icon: Icons.mic_none,
              onPressed: sending || !enabled ? null : onVoice,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  readOnly: !enabled,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!sending && enabled) {
                      onSend();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: sending
                        ? '发送中'
                        : enabled
                        ? '输入消息'
                        : disabledText,
                    hintStyle: const TextStyle(
                      color: Color(0xffaeb4bd),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: !enabled
                        ? const Color(0xffeeeeee)
                        : Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ComposerIconButton(
              tooltip: '表情',
              icon: Icons.sentiment_satisfied_alt,
              onPressed: sending || !enabled ? null : onEmoji,
            ),
            const SizedBox(width: 4),
            _ComposerIconButton(
              tooltip: toolsOpen ? '收起' : '更多',
              icon: toolsOpen ? Icons.close : Icons.add_circle_outline,
              onPressed: sending || !enabled ? null : onTools,
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (!enabled || (!sending && value.text.trim().isEmpty)) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      height: 36,
                      child: TextButton(
                        onPressed: sending ? null : onSend,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: _chatAckColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(40, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          '发送',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 27,
          color: onPressed == null ? _mutedColor : Colors.black,
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: children);
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: _borderColor)),
      child: SelectableText(text),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffeef5ff),
      child: Text(text, maxLines: 5, overflow: TextOverflow.ellipsis),
    );
  }
}

class _LinearBusy extends StatelessWidget {
  const _LinearBusy();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _pageColor,
      child: Text(
        text,
        style: const TextStyle(
          color: _mutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 8);
  }
}

class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex();

  @override
  Widget build(BuildContext context) {
    const letters = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
      '#',
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final letter in letters)
          SizedBox(
            height: 13,
            width: 18,
            child: Center(
              child: Text(
                letter,
                style: const TextStyle(
                  color: Color(0xff6f7785),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _dangerColor),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<Map<String, String>?> _openInput(
  BuildContext context, {
  required String title,
  required List<ActionInputField> fields,
}) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => ActionInputPage(title: title, fields: fields),
    ),
  );
}

Future<void> _push(BuildContext context, Widget page) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

Future<bool> _confirmDanger(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result == true;
}

void _openPrivateChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final channelId = _friendChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            controller: controller,
            title: _friendTitle(item),
            channelId: channelId,
            groupId: '',
            channelType: _privateChannelType,
          ),
        ),
      )
      .then(
        (_) => _markConversationReadAfterPop(
          controller,
          channelId,
          _privateChannelType,
        ),
      );
}

void _openGroupChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final groupId = _groupIdFromItem(item);
  final channelId = _groupChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            controller: controller,
            title: _groupTitle(item),
            channelId: channelId,
            groupId: groupId,
            channelType: _groupChannelType,
          ),
        ),
      )
      .then(
        (_) => _markConversationReadAfterPop(
          controller,
          channelId,
          _groupChannelType,
        ),
      );
}

Future<void> _markConversationReadAfterPop(
  SessionController controller,
  String channelId,
  int channelType,
) async {
  try {
    await controller.markConversationRead(
      channelId: channelId,
      channelType: channelType,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'ui',
      'mark conversation read after pop failed',
      error: error,
      stackTrace: stackTrace,
      data: {'channel_id': channelId, 'channel_type': channelType},
    );
  }
}

void _showSoon(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('功能建设中')));
}

String _formatTime(int millis) {
  if (millis <= 0) {
    return '暂无';
  }
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _gatewayStreamAddress(ChatSession? chat) {
  if (chat == null) {
    return '';
  }
  final streamAddr = chat.stream?.httpsStreamAddr ?? '';
  return streamAddr.isNotEmpty ? streamAddr : chat.route.httpsStreamAddr;
}

bool _shouldShowTimeDivider(List<Map<String, Object?>> messages, int index) {
  if (index == 0) {
    return true;
  }
  final current = _messageDateTime(messages[index]);
  final previous = _messageDateTime(messages[index - 1]);
  if (current == null || previous == null) {
    return false;
  }
  return current.difference(previous).inMinutes.abs() >= 5;
}

String _messageTimeLabel(Map<String, Object?> item) {
  final time = _messageDateTime(item);
  if (time == null) {
    return '';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  final clock = '${two(time.hour)}:${two(time.minute)}';
  if (sameDay) {
    return clock;
  }
  return '${two(time.month)}-${two(time.day)} $clock';
}

String _messageBubbleTime(Map<String, Object?> item) {
  final label = _messageTimeLabel(item);
  if (label.length >= 5) {
    return label.substring(label.length - 5);
  }
  return label;
}

DateTime? _messageDateTime(Map<String, Object?> item) {
  final raw = _value(item, ['timestamp', 'create_time', 'msg_time']);
  if (raw.isEmpty) {
    return null;
  }
  final numeric = int.tryParse(raw);
  if (numeric != null) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

String _messageSenderName(Map<String, Object?> item) {
  final fromUser = _asObjectMap(item['from_user']);
  return _value(
    fromUser,
    ['nickname', 'username', 'name'],
    fallback: _value(item, ['from_nickname', 'from_username'], fallback: '成员'),
  );
}

String _messageSenderAvatarUrl(Map<String, Object?> item) {
  final fromUser = _asObjectMap(item['from_user']);
  return _avatarUrlFromMap(fromUser, fallback: _avatarUrlFromMap(item));
}

String _messageStatus(Map<String, Object?> item) {
  final status = _value(item, ['status']).toLowerCase();
  if (_hasReadReceiptState(item)) {
    return 'read';
  }
  return switch (status) {
    'read' || 'readed' || 'seen' => 'read',
    'queued' => 'queued',
    'sending' => 'sending',
    'failed' => 'failed',
    'sent' || 'success' || 'succeeded' || 'delivered' => 'sent',
    _ => status,
  };
}

bool _hasReadReceiptState(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final receipt = _asObjectMap(item['receipt']);
  final payloadReceipt = _asObjectMap(payload['receipt']);
  for (final source in [item, payload, receipt, payloadReceipt]) {
    if (_boolValue(source['is_read']) ||
        _boolValue(source['read']) ||
        _boolValue(source['readed']) ||
        _boolValue(source['has_read'])) {
      return true;
    }
    final status = _value(source, [
      'receipt_status',
      'read_status',
      'status',
    ]).toLowerCase();
    if (status == 'read' || status == 'readed' || status == 'seen') {
      return true;
    }
    if (_intValue(source, ['read_at']) > 0 ||
        _intValue(source, ['read_time']) > 0 ||
        _intValue(source, ['read_count']) > 0 ||
        _intValue(source, ['reader_count']) > 0) {
      return true;
    }
  }
  return false;
}

String _messageContentType(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  return _value(item, [
    'content_type',
  ], fallback: _value(payload, ['content_type']));
}

String _messageContentText(
  Map<String, Object?> item,
  Map<String, Object?> payload,
) {
  final content = _value(item, ['content']);
  if (content.isNotEmpty && content != '[消息]') {
    return content;
  }
  return _value(payload, ['content', 'text', 'remark'], fallback: content);
}

String _durationLabel(Map<String, Object?> payload) {
  final seconds = _value(payload, ['duration']);
  if (seconds.isEmpty) {
    return '';
  }
  return '$seconds 秒';
}

String _paymentAmount(Map<String, Object?> payload) {
  final redPacket = _asObjectMap(payload['red_packet']);
  final transfer = _asObjectMap(payload['transfer']);
  final source = redPacket.isNotEmpty
      ? redPacket
      : transfer.isNotEmpty
      ? transfer
      : payload;
  final money = _value(source, ['money', 'amount']);
  final asset = _value(source, ['asset_type']);
  if (money.isEmpty) {
    return '';
  }
  if (asset.isEmpty || asset == 'money' || asset == '金币') {
    final value = double.tryParse(money);
    return value == null ? '¥$money' : '¥${value.toStringAsFixed(2)}';
  }
  return '$money $asset';
}

String _redPacketRemark(Map<String, Object?> payload, {String fallback = ''}) {
  final redPacket = _asObjectMap(payload['red_packet']);
  for (final source in [redPacket, payload]) {
    final value = _value(source, [
      'remark',
      'blessing',
      'bless',
      'wish',
      'greeting',
      'greetings',
      'message',
      'content',
      'text',
      'note',
    ]);
    if (_isValidRedPacketRemark(value)) {
      return value;
    }
  }
  return _isValidRedPacketRemark(fallback) ? fallback.trim() : '';
}

bool _isValidRedPacketRemark(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text == '[红包]' ||
      text == '[消息]' ||
      text == '[red_packet]') {
    return false;
  }
  if (text.startsWith('{') || text.startsWith('[')) {
    return false;
  }
  final moneyLike = RegExp(
    r'^[¥￥]?\d+(\.\d+)?\s*(money|金币|integral|积分)?$',
    caseSensitive: false,
  );
  return !moneyLike.hasMatch(text);
}

Color? _conversationPrefixColor(String text) {
  if (text.startsWith('[红包]')) {
    return const Color(0xffe64340);
  }
  if (text.startsWith('[转账]')) {
    return const Color(0xffff8a00);
  }
  return null;
}

double _uploadProgress(Map<String, Object?> payload) {
  final raw = _value(payload, ['upload_progress', 'progress']);
  final parsed = double.tryParse(raw);
  if (parsed == null) {
    return 0;
  }
  if (parsed > 1) {
    return (parsed / 100).clamp(0, 1).toDouble();
  }
  return parsed.clamp(0, 1).toDouble();
}

String _fileSizeLabel(Object? raw) {
  final bytes = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (bytes == null || bytes <= 0) {
    return raw?.toString() ?? '';
  }
  if (bytes < 1024) {
    return '${bytes}B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

String _avatarInitial(String label) {
  final text = label.trim();
  if (text.isEmpty) {
    return 'B';
  }
  return text.characters.first.toUpperCase();
}

String _friendlyResult(
  Map<String, Object?> result, {
  String successText = '操作成功',
}) {
  final message = _value(result, ['message', 'msg']);
  if (message.isNotEmpty) {
    return message;
  }
  final data = result['data'];
  if (data is Map) {
    final nested = _value(
      data.map((key, value) => MapEntry(key.toString(), value)),
      ['message', 'msg'],
    );
    if (nested.isNotEmpty) {
      return nested;
    }
  }
  return successText;
}

String _friendStatusText(Map<String, Object?> result) {
  final isFriend = _boolValue(result['is_friend']);
  final pendingOut = _boolValue(result['pending_out_apply']);
  final pendingIn = _boolValue(result['pending_in_apply']);
  final count = _intValue(result, ['non_friend_message_count']);
  final limit = _intValue(result, ['non_friend_message_limit']);
  if (isFriend) {
    return '你们已经是好友，可以正常聊天。';
  }
  if (pendingOut) {
    return '好友申请已发送，等待对方通过。';
  }
  if (pendingIn) {
    return '对方已申请添加你为好友，请到新的朋友里处理。';
  }
  final max = limit <= 0 ? 3 : limit;
  return '还不是好友，只能先发送文字消息，当前已发送 $count/$max 条。';
}

String _receiptText(Map<String, Object?> result, {required bool isGroup}) {
  final receipt = _asObjectMap(result['receipt']);
  final redPacket = _asObjectMap(result['red_packet']);
  final transfer = _asObjectMap(result['transfer']);
  final parts = <String>[];
  final readCount = _intValue(receipt, ['read_count']);
  final unreadCount = _intValue(receipt, ['unread_count']);
  final total = _intValue(receipt, ['total_receivers']);
  if (isGroup) {
    if (total > 0) {
      parts.add('$readCount/$total 人已读');
    } else {
      parts.add('$readCount 人已读');
    }
  } else {
    parts.add(readCount > 0 ? '对方已读' : '对方未读');
  }
  if (unreadCount > 0 && isGroup) {
    parts.add('$unreadCount 人未读');
  }
  if (redPacket.isNotEmpty) {
    final receiveCount = _intValue(redPacket, ['receive_count']);
    final quantity = _intValue(redPacket, ['quantity']);
    final status = _value(redPacket, ['status']);
    final progress = quantity > 0 ? '$receiveCount/$quantity' : '$receiveCount';
    parts.add('红包领取 $progress${status.isEmpty ? '' : ' · $status'}');
  }
  if (transfer.isNotEmpty) {
    final status = _value(transfer, ['status']);
    parts.add(status.isEmpty ? '转账待处理' : '转账$status');
  }
  return parts.join('\n');
}

String _sessionDisplayName(UserSession? session) {
  if (session == null) {
    return '';
  }
  if (session.nickname.isNotEmpty) {
    return session.nickname;
  }
  return session.username;
}

String _conversationTitle(Map<String, Object?> item) {
  if (_channelTypeFromConversation(item) == _groupChannelType) {
    return _value(item, ['name', 'group_name'], fallback: '群聊');
  }
  return _value(item, ['nickname', 'username', 'name'], fallback: '私聊');
}

String _conversationSubtitle(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final contentType = _value(item, [
    'content_type',
  ], fallback: _value(payload, ['content_type']));
  final content = _value(item, ['content']);
  if (contentType == ChatContentTypes.redPacket) {
    return _redPacketConversationText(payload, content);
  }
  if (contentType == ChatContentTypes.transfer) {
    return _transferConversationText(payload, content);
  }
  return content;
}

String _redPacketConversationText(
  Map<String, Object?> payload,
  String content,
) {
  final direct = content.trim();
  if (direct.startsWith('[红包]') && direct.length > '[红包]'.length) {
    return direct;
  }
  final remark = _redPacketRemark(payload, fallback: direct);
  return remark.isEmpty ? '[红包]' : '[红包]$remark';
}

String _transferConversationText(Map<String, Object?> payload, String content) {
  return '[转账]请收款';
}

String _conversationAvatarUrl(Map<String, Object?> item) {
  if (_channelTypeFromConversation(item) == _groupChannelType) {
    return _groupAvatarUrl(item);
  }
  return _avatarUrlFromMap(item);
}

String _conversationChannelId(Map<String, Object?> item, int channelType) {
  if (channelType == _privateChannelType) {
    final receiverId = _value(item, [
      'receiver_id',
      'peer_id',
      'friend_id',
      'user_id',
      'userid',
    ]);
    if (receiverId.isNotEmpty) {
      return _uidFromUserId(receiverId);
    }
  }
  final raw = _value(item, ['channel_id', 'uid']);
  if (channelType != _privateChannelType || raw.isEmpty) {
    return raw;
  }
  return _uidFromUserId(_privateReceiverIdFromChannel(raw));
}

int _channelTypeFromConversation(Map<String, Object?> item) {
  final value = _intValue(item, ['channel_type']);
  if (value > 0) {
    return value;
  }
  return item['conversation_type']?.toString() == 'group'
      ? _groupChannelType
      : _privateChannelType;
}

String _friendTitle(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final remark = _value(item, ['remark']);
  if (remark.isNotEmpty) {
    return remark;
  }
  return _value(profile, [
    'nickname',
    'username',
    'name',
  ], fallback: _value(item, ['nickname', 'username', 'name'], fallback: '好友'));
}

String _friendUserId(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final raw = _value(item, ['friend_id', 'userid', 'user_id']);
  if (raw.isNotEmpty) {
    return raw;
  }
  final nested = _value(profile, ['userid', 'user_id', 'id']);
  if (nested.isNotEmpty) {
    return nested;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid', 'channel_id']));
}

String _friendUsername(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  return _value(profile, ['username'], fallback: _value(item, ['username']));
}

String _friendSubtitle(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final username = _friendUsername(item);
  final signature = _value(profile, [
    'signature',
    'bio',
  ], fallback: _value(item, ['signature']));
  return [
    if (username.isNotEmpty) '用户名 $username',
    if (signature.isNotEmpty) signature,
  ].join(' · ');
}

String _friendAvatarUrl(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  return _avatarUrlFromMap(profile, fallback: _avatarUrlFromMap(item));
}

Map<String, Object?> _friendProfile(Map<String, Object?> item) {
  final friend = _asObjectMap(item['friend']);
  if (friend.isNotEmpty) {
    return friend;
  }
  final user = _asObjectMap(item['user']);
  if (user.isNotEmpty) {
    return user;
  }
  return item;
}

String _searchFriendId(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  return _value(item, [
    'friend_id',
    'user_id',
    'userid',
    'id',
  ], fallback: _value(user, ['userid', 'user_id', 'id']));
}

String _searchFriendTitle(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  return _value(user, [
    'nickname',
    'username',
    'name',
  ], fallback: _value(item, ['nickname', 'username', 'name'], fallback: '用户'));
}

String _groupAvatarUrl(Map<String, Object?> item) {
  return _avatarUrlFromMap(item);
}

String _avatarUrlFromMap(Map<String, Object?> item, {String fallback = ''}) {
  return _normalizeAvatarUrl(
    _value(item, [
      'avatar',
      'usertx',
      'user_avatar',
      'group_avatar',
      'headimg',
      'head_img',
      'photo',
      'portrait',
    ], fallback: fallback),
  );
}

String _normalizeAvatarUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('data:')) {
    return value;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return value;
  }
  final base = Uri.tryParse(AppConfig.apiBaseUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    return value;
  }
  final origin = base.replace(path: '/', query: '', fragment: '');
  if (value.startsWith('/')) {
    return origin.resolve(value).toString();
  }
  return origin.resolve(value).toString();
}

void _precacheConversationAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> conversations,
) {
  _precacheAvatarUrls(context, conversations.map(_conversationAvatarUrl));
}

void _precacheContactAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> friends,
  Iterable<Map<String, Object?>> groups,
) {
  _precacheAvatarUrls(context, [
    ...friends.map(_friendAvatarUrl),
    ...groups.map(_groupAvatarUrl),
  ]);
}

void _precacheMessageAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> messages,
  String currentUserAvatarUrl,
) {
  _precacheAvatarUrls(context, [
    if (currentUserAvatarUrl.isNotEmpty) currentUserAvatarUrl,
    ...messages.map(_messageSenderAvatarUrl),
  ]);
}

void _precacheAvatarUrls(BuildContext context, Iterable<String> urls) {
  final unique = <String>{};
  for (final url in urls.map(_normalizeAvatarUrl)) {
    if (url.isEmpty || !unique.add(url)) {
      continue;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      unawaited(
        precacheImage(NetworkImage(url), context).catchError((Object _) {}),
      );
    });
  }
}

String _searchFriendSubtitle(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  final username = _value(user, ['username']);
  final signature = _value(user, ['signature']);
  return [
    if (username.isNotEmpty) username,
    if (signature.isNotEmpty) signature,
    _friendStatusText(item),
  ].join(' · ');
}

String _searchFriendActionText(Map<String, Object?> item) {
  if (_boolValue(item['is_friend'])) {
    return '发消息';
  }
  if (_boolValue(item['pending_out_apply'])) {
    return '已申请';
  }
  if (_boolValue(item['pending_in_apply'])) {
    return '待处理';
  }
  return '添加';
}

String _friendChannelId(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final channelId = _value(item, [
    'channel_id',
    'uid',
    'im_uid',
  ], fallback: _value(profile, ['channel_id', 'uid', 'im_uid']));
  if (channelId.isNotEmpty) {
    return channelId;
  }
  final userId = _friendUserId(item);
  if (userId.isEmpty) {
    return '';
  }
  return _uidFromUserId(userId);
}

String _groupTitle(Map<String, Object?> item) {
  return _value(item, ['name', 'group_name', 'title'], fallback: '群聊');
}

String _groupIdFromItem(Map<String, Object?> item) {
  return _value(item, ['group_id', 'id']);
}

String _groupChannelId(Map<String, Object?> item) {
  return _value(item, ['channel_id', 'uid'], fallback: _groupIdFromItem(item));
}

String _memberTitle(Map<String, Object?> item) {
  return _value(item, ['nickname', 'username', 'name'], fallback: '群成员');
}

String _memberUsername(Map<String, Object?> item) {
  return _value(item, ['username'], fallback: _memberRoleText(item));
}

String _memberUserId(Map<String, Object?> item) {
  final value = _value(item, ['user_id', 'userid', 'member_id', 'id']);
  if (value.isNotEmpty) {
    return value;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid']));
}

String _memberSubtitle(Map<String, Object?> item) {
  final username = _memberUsername(item);
  final parts = [
    if (username.isNotEmpty && username != _memberRoleText(item))
      '用户名 $username',
    _memberRoleText(item),
  ];
  final muted = _boolValue(item['muted']);
  if (muted) {
    final permanent = _boolValue(item['mute_permanent']);
    final expire = _value(item, ['mute_expire_time']);
    parts.add(permanent ? '永久禁言' : '禁言至 $expire');
  }
  return parts.where((part) => part.isNotEmpty).join(' · ');
}

String _memberRoleText(Map<String, Object?> item) {
  final role = _intValue(item, ['role']);
  return switch (role) {
    1 => '群主',
    2 => '管理员',
    _ => '成员',
  };
}

String _requestTitle(Map<String, Object?> item, String type) {
  if (type == 'in') {
    return _value(item, [
      'from_nickname',
      'from_username',
      'nickname',
      'username',
      'from_user_id',
    ], fallback: '申请人');
  }
  return _value(item, [
    'to_nickname',
    'to_username',
    'nickname',
    'username',
    'to_user_id',
  ], fallback: '接收人');
}

String _requestStatus(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return switch (status) {
    '0' => '待处理',
    '1' => '已通过',
    '2' => '已拒绝',
    '3' => '已过期',
    _ => status.isEmpty ? '待处理' : status,
  };
}

bool _requestPending(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return status.isEmpty || status == '0' || status == 'pending';
}

String _value(
  Map<String, Object?> item,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = item[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return fallback;
}

int _intValue(Map<String, Object?> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return 0;
}

bool _boolValue(Object? value) {
  if (value is Map) {
    return value.isNotEmpty;
  }
  if (value is Iterable) {
    return value.isNotEmpty;
  }
  final text = value?.toString().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}

bool _sameStringMap(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key]?.toString() != entry.value?.toString()) {
      return false;
    }
  }
  return true;
}

String _groupMuteText(Map<String, Object?> state) {
  if (!_boolValue(state['muted'])) {
    return '';
  }
  final expire = _value(state, ['expire_time', 'mute_expire_time']);
  if (expire.isNotEmpty) {
    final expireAt = _parseUiTime(expire);
    if (expireAt != null && !expireAt.isAfter(DateTime.now())) {
      return '';
    }
  }
  final notice = _value(state, ['notice']);
  if (notice.isNotEmpty) {
    return notice;
  }
  final reason = _value(state, ['reason']);
  final permanent =
      _boolValue(state['permanent']) || _boolValue(state['mute_permanent']);
  final parts = <String>['你已被管理员禁言'];
  if (reason.isNotEmpty) {
    parts.add('原因：$reason');
  }
  parts.add(permanent || expire.isEmpty ? '永久生效' : '至 $expire');
  return parts.join('，');
}

DateTime? _parseUiTime(String value) {
  final numeric = int.tryParse(value);
  if (numeric != null) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Map<String, Object?>> _listFromResult(Map<String, Object?> result) {
  Object? value = result['list'] ?? result['items'];
  final data = result['data'];
  if (value == null && data is Map) {
    value = data['list'] ?? data['items'] ?? data['rows'] ?? data['records'];
  }
  if (value == null && data is List) {
    value = data;
  }
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
  return const [];
}

bool _memberMatchesOnlineUser(
  Map<String, Object?> member,
  Map<String, Object?> onlineUser,
) {
  for (final id in _memberPresenceIds(member)) {
    if (_onlineUserMatches(onlineUser, id)) {
      return true;
    }
  }
  return false;
}

Iterable<String> _memberPresenceIds(Map<String, Object?> member) sync* {
  for (final key in [
    'uid',
    'im_uid',
    'wukong_uid',
    'channel_id',
    'user_uid',
    'member_uid',
  ]) {
    final value = _value(member, [key]);
    if (value.isNotEmpty) {
      yield value;
    }
  }
  final userId = _memberUserId(member);
  if (userId.isNotEmpty) {
    yield userId;
    yield _uidFromUserId(userId);
  }
  final user = _asObjectMap(member['user']);
  if (user.isNotEmpty) {
    yield* _memberPresenceIds(user);
  }
}

String _memberPresenceKey(Map<String, Object?> member) {
  for (final id in _memberPresenceIds(member)) {
    if (id.isNotEmpty) {
      return id;
    }
  }
  return jsonEncode(member);
}

bool _onlineUserMatches(Map<String, Object?> item, String receiverId) {
  if (_onlineFlagKnownFalse(item)) {
    return false;
  }
  final userId = _privateReceiverIdFromChannel(receiverId);
  final uid = _uidFromUserId(userId);
  for (final key in [
    'uid',
    'im_uid',
    'wukong_uid',
    'channel_id',
    'from_uid',
    'user_uid',
  ]) {
    final value = _value(item, [key]);
    if (value == uid || value == receiverId) {
      return true;
    }
  }
  for (final key in [
    'user_id',
    'userid',
    'id',
    'friend_id',
    'receiver_id',
    'member_id',
  ]) {
    if (_value(item, [key]) == userId) {
      return true;
    }
  }
  final user = _asObjectMap(item['user']);
  return user.isNotEmpty && _onlineUserMatches(user, receiverId);
}

bool _onlineFlagKnownFalse(Map<String, Object?> item) {
  for (final key in ['online', 'is_online', 'connected']) {
    final value = item[key];
    if (value != null && !_boolValue(value)) {
      return true;
    }
  }
  final status = _value(item, [
    'status',
    'online_status',
    'state',
  ]).toLowerCase();
  return status == 'offline' || status == '离线' || status == '0';
}

bool _sameMapList(
  List<Map<String, Object?>> left,
  List<Map<String, Object?>> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (jsonEncode(left[index]) != jsonEncode(right[index])) {
      return false;
    }
  }
  return true;
}

List<String> _idsFromText(String text) {
  return text
      .split(RegExp(r'[,，\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String _uidFromUserId(String userId) {
  if (userId.startsWith('app')) {
    return userId;
  }
  return 'app${AppConfig.appId}user$userId';
}

String _privateReceiverIdFromChannel(String channelId) {
  final match = RegExp(r'user(\d+)$').firstMatch(channelId);
  return match?.group(1) ?? channelId;
}

String _nestedValue(Map<String, Object?> payload, List<String> paths) {
  for (final path in paths) {
    Object? current = payload;
    for (final key in path.split('.')) {
      if (current is Map) {
        current = current[key];
      } else {
        current = null;
      }
    }
    if (current != null && current.toString().isNotEmpty) {
      return current.toString();
    }
  }
  return '';
}

String _shortNo(String value) {
  if (value.length <= 10) {
    return value;
  }
  return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
}

String _mediaTitle(String contentType) {
  return switch (contentType) {
    ChatContentTypes.image => '发送图片',
    ChatContentTypes.emoji => '发送表情',
    ChatContentTypes.gif => '发送 GIF',
    ChatContentTypes.sticker => '发送贴纸',
    ChatContentTypes.voice => '发送语音',
    ChatContentTypes.video => '发送视频',
    ChatContentTypes.file => '发送文件',
    _ => '发送媒体',
  };
}

String _mimeFromPath(String path, String contentType) {
  final ext = path.split('.').last.toLowerCase();
  if (contentType == ChatContentTypes.image) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/*',
    };
  }
  if (contentType == ChatContentTypes.video) {
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'webm' => 'video/webm',
      _ => 'video/*',
    };
  }
  return switch (ext) {
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

String _videoSubtitle(Map<String, Object?> payload) {
  final name = _value(_asObjectMap(payload['media']), [
    'name',
  ], fallback: _value(payload, ['name', 'file_name']));
  final duration = _durationLabel(payload);
  if (name.isNotEmpty && duration.isNotEmpty) {
    return '$name · $duration';
  }
  return name.isNotEmpty ? name : duration;
}

String _videoTitle(Map<String, Object?> payload, String content) {
  if (content.isNotEmpty && content != '[视频]' && content != '[消息]') {
    return content;
  }
  final media = _asObjectMap(payload['media']);
  final name = _value(payload, [
    'name',
    'file_name',
  ], fallback: _value(media, ['name', 'file_name']));
  if (name.isNotEmpty) {
    return name;
  }
  final path = _value(payload, [
    'file_path',
    'url',
  ], fallback: _value(media, ['url', 'file_path']));
  return path.isEmpty ? '视频' : _fileName(path);
}

_VideoPreviewSource? _videoPreviewSource(
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  final localPath = _value(payload, [
    'file_path',
    'video_file_path',
  ], fallback: _value(media, ['file_path', 'video_file_path']));
  if (localPath.isNotEmpty &&
      _looksLikeVideoPath(localPath) &&
      File(localPath).existsSync()) {
    return _VideoPreviewSource(value: localPath, isLocal: true);
  }

  final rawUrl = _value(payload, [
    'video_url',
    'file_url',
    'url',
    'video_path',
  ], fallback: _value(media, ['video_url', 'file_url', 'url', 'video_path']));
  final url = _normalizeAvatarUrl(rawUrl);
  if (url.isNotEmpty && !_looksLikeImagePath(url)) {
    return _VideoPreviewSource(value: url, isLocal: false);
  }
  return null;
}

bool _looksLikeImagePath(String value) {
  final clean = value.split('?').first.toLowerCase();
  return clean.endsWith('.jpg') ||
      clean.endsWith('.jpeg') ||
      clean.endsWith('.png') ||
      clean.endsWith('.gif') ||
      clean.endsWith('.webp') ||
      clean.endsWith('.bmp') ||
      clean.endsWith('.heic');
}

bool _looksLikeVideoPath(String value) {
  final clean = value.split('?').first.toLowerCase();
  return clean.endsWith('.mp4') ||
      clean.endsWith('.mov') ||
      clean.endsWith('.m4v') ||
      clean.endsWith('.webm') ||
      clean.endsWith('.avi') ||
      clean.endsWith('.mkv');
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty || parts.last.isEmpty ? normalized : parts.last;
}

String _secondsLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

IconData _fileIcon(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => Icons.image_outlined,
    'mp4' || 'mov' || 'm4v' || 'webm' => Icons.videocam_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' => Icons.description_outlined,
    'xls' || 'xlsx' => Icons.table_chart_outlined,
    'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

Future<List<Directory>> _candidateFileDirectories() async {
  final dirs = <Directory>[];
  final seen = <String>{};

  Future<void> add(Directory? dir) async {
    if (dir == null || dir.path.isEmpty || !seen.add(dir.path)) {
      return;
    }
    if (await dir.exists()) {
      dirs.add(dir);
    }
  }

  Future<void> addRequired(Future<Directory> future) async {
    try {
      await add(await future);
    } on Object {
      return;
    }
  }

  Future<void> addOptional(Future<Directory?> future) async {
    try {
      await add(await future);
    } on Object {
      return;
    }
  }

  Future<void> addPath(String path) => add(Directory(path));

  await addRequired(getApplicationDocumentsDirectory());
  await addRequired(getApplicationSupportDirectory());
  await addRequired(getTemporaryDirectory());
  await addOptional(getDownloadsDirectory());

  if (Platform.isAndroid) {
    for (final path in const [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Movies',
    ]) {
      await addPath(path);
    }
  }

  return dirs;
}

List<ActionInputField> _mediaFields(String contentType) {
  final fields = <ActionInputField>[
    const ActionInputField(id: 'url', label: '资源 URL'),
    const ActionInputField(id: 'file_path', label: '本地文件路径'),
  ];
  switch (contentType) {
    case ChatContentTypes.emoji:
      fields.add(const ActionInputField(id: 'emoji_code', label: '表情编码'));
      break;
    case ChatContentTypes.sticker:
      fields.add(const ActionInputField(id: 'sticker_id', label: '贴纸 ID'));
      break;
    case ChatContentTypes.voice:
      fields.add(
        const ActionInputField(
          id: 'duration',
          label: '时长秒数',
          keyboardType: TextInputType.number,
        ),
      );
      break;
    case ChatContentTypes.video:
      fields
        ..add(const ActionInputField(id: 'cover_url', label: '封面 URL'))
        ..add(
          const ActionInputField(
            id: 'duration',
            label: '时长秒数',
            keyboardType: TextInputType.number,
          ),
        );
      break;
    case ChatContentTypes.file:
      fields
        ..add(const ActionInputField(id: 'name', label: '文件名'))
        ..add(const ActionInputField(id: 'mime', label: 'MIME 类型'))
        ..add(
          const ActionInputField(
            id: 'size',
            label: '文件大小',
            keyboardType: TextInputType.number,
          ),
        );
      break;
  }
  return fields;
}
