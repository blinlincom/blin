part of 'package:bim/src/features/home/home_page.dart';

enum _ChatEmptyScene { conversations, privateChat, groupChat }

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({
    required this.scene,
    this.peerName = '',
    this.onAction,
  });

  final _ChatEmptyScene scene;
  final String peerName;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final title = switch (scene) {
      _ChatEmptyScene.conversations => '消息从这里开始',
      _ChatEmptyScene.privateChat =>
        peerName.isEmpty ? '开始这段对话' : '和 $peerName 打个招呼',
      _ChatEmptyScene.groupChat => '群聊还没有消息',
    };
    final message = switch (scene) {
      _ChatEmptyScene.conversations => '添加联系人或进入群聊后，新的消息会按时间出现在这里',
      _ChatEmptyScene.privateChat => '发出的第一条消息会保存在当前设备，并按同步设置保留历史',
      _ChatEmptyScene.groupChat => '发送第一条消息，让群成员开始交流',
    };
    final action = switch (scene) {
      _ChatEmptyScene.conversations => '添加联系人',
      _ChatEmptyScene.privateChat || _ChatEmptyScene.groupChat => '发消息',
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          BimSpacing.x6,
          BimSpacing.x8,
          BimSpacing.x6,
          BimSpacing.x8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChatEmptyAnimation(scene: scene),
              const SizedBox(height: BimSpacing.x6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BimColors.textDark,
                  fontSize: BimTypography.profile,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: BimSpacing.x2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(height: BimSpacing.x5),
                SizedBox(
                  width: scene == _ChatEmptyScene.conversations ? 148 : 120,
                  child: BimButton(
                    label: action,
                    onPressed: onAction,
                    icon: scene == _ChatEmptyScene.conversations
                        ? Icons.person_add_alt_1_outlined
                        : Icons.edit_outlined,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatEmptyAnimation extends StatelessWidget {
  const _ChatEmptyAnimation({required this.scene});

  final _ChatEmptyScene scene;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final asset = switch (scene) {
      _ChatEmptyScene.conversations => 'assets/lottie/empty_conversations.json',
      _ChatEmptyScene.privateChat => 'assets/lottie/empty_private_chat.json',
      _ChatEmptyScene.groupChat => 'assets/lottie/empty_group_chat.json',
    };
    return Semantics(
      image: true,
      label: switch (scene) {
        _ChatEmptyScene.conversations => '消息列表动画',
        _ChatEmptyScene.privateChat => '私聊消息动画',
        _ChatEmptyScene.groupChat => '群聊消息动画',
      },
      child: SizedBox(
        width: 214,
        height: 132,
        child: Lottie.asset(
          asset,
          fit: BoxFit.contain,
          repeat: !reduceMotion,
          animate: !reduceMotion,
          frameRate: FrameRate.composition,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
