part of 'package:bim/src/features/home/home_page.dart';

class MineTab extends StatelessWidget {
  const MineTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        return ColoredBox(
          color: _pageColor,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
            children: [
              ColoredBox(
                color: _surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
                  child: Row(
                    children: [
                      _Avatar(
                        label: _avatarText(session),
                        imageUrl: session?.avatar ?? '',
                        size: 68,
                        color: const Color(0xff8e99a8),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _sessionDisplayName(session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _MineStatusLine(controller: controller),
                            const SizedBox(height: 6),
                            Text(
                              _atName(session?.username ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '我的二维码',
                        onPressed: () => _push(
                          context,
                          MyFriendQrPage(controller: controller),
                        ),
                        icon: const Icon(Icons.qr_code_2, size: 24),
                      ),
                    ],
                  ),
                ),
              ),
              const _GroupGap(),
              _MenuTile(
                icon: Icons.qr_code_2,
                iconColor: const Color(0xff2563eb),
                title: '我的二维码',
                subtitle: '让朋友扫码添加我',
                onTap: () =>
                    _push(context, MyFriendQrPage(controller: controller)),
              ),
              _MenuTile(
                icon: Icons.qr_code_scanner,
                iconColor: const Color(0xff111827),
                title: '扫一扫',
                subtitle: '扫描好友二维码',
                onTap: () =>
                    _push(context, FriendQrScannerPage(controller: controller)),
              ),
              const _GroupGap(),
              _MenuTile(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xff0f766e),
                title: '钱包',
                subtitle: '余额、收付款、账单',
                onTap: () => _push(context, WalletPage(controller: controller)),
              ),
              const _GroupGap(),
              _MenuTile(
                icon: Icons.photo_library_outlined,
                iconColor: const Color(0xff34c759),
                title: '朋友圈',
                subtitle: '查看和发布动态',
                onTap: () =>
                    _push(context, MomentsPage(controller: controller)),
              ),
              const _GroupGap(),
              _MenuTile(
                icon: Icons.settings_outlined,
                iconColor: _mutedColor,
                title: '设置与存储',
                subtitle: '聊天记录、后台接收、连接日志',
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: controller.logout,
                    child: const Text('退出登录'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _avatarText(UserSession? session) {
    final name = _sessionDisplayName(session);
    if (name.isEmpty) {
      return 'B';
    }
    return name.characters.first;
  }
}

class _MineStatusLine extends StatelessWidget {
  const _MineStatusLine({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final text = _statusText;
    final connected = text == '在线';
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: connected ? _chatOnlineColor : _mutedColor,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _mutedColor, fontSize: 12),
        ),
      ],
    );
  }

  String get _statusText {
    if (controller.imError != null) {
      return '连接异常';
    }
    final status = controller.imStatusText;
    if (status == '已连接') {
      return '在线';
    }
    if (status == '连接中') {
      return '连接中...';
    }
    if (status == '重连中') {
      return '重连中...';
    }
    if (status == '同步中') {
      return '同步中...';
    }
    return status.isEmpty ? '离线' : status;
  }
}
