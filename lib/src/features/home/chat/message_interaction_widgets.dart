part of 'package:bim/src/features/home/home_page.dart';

class _MessageSendStatus extends StatelessWidget {
  const _MessageSendStatus({
    required this.status,
    required this.readText,
    required this.onRetry,
  });

  final String status;
  final String readText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == 'read' && readText.isNotEmpty) {
      return Text(
        readText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _chatAckColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
    }
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xff8f96a3),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageActionItem {
  const _MessageActionItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.anchor,
    required this.actions,
    required this.onDismiss,
  });

  final Offset anchor;
  final List<_MessageActionItem> actions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const actionWidth = 58.0;
            const menuHeight = 64.0;
            final maxWidth = max(120.0, constraints.maxWidth - 24);
            final menuWidth = min(maxWidth, actions.length * actionWidth + 12);
            final left = (anchor.dx - menuWidth / 2)
                .clamp(12.0, max(12.0, constraints.maxWidth - menuWidth - 12))
                .toDouble();
            final showAbove = anchor.dy > menuHeight + 92;
            final rawTop = showAbove
                ? anchor.dy - menuHeight - 14
                : anchor.dy + 14;
            final top = rawTop
                .clamp(8.0, max(8.0, constraints.maxHeight - menuHeight - 14))
                .toDouble();
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: menuWidth,
                  height: menuHeight,
                  child: _MessageActionMenu(actions: actions),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MessageActionMenu extends StatelessWidget {
  const _MessageActionMenu({required this.actions});

  final List<_MessageActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BimColors.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                _MessageActionButton(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({required this.action});

  final _MessageActionItem action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? const Color(0xffffb4ab) : Colors.white;
    return Semantics(
      button: true,
      label: action.label,
      child: SizedBox(
        width: 58,
        height: 64,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: action.onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: color, size: 20),
                const SizedBox(height: 5),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xffb87f00)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff785800),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              tooltip: '清除选项',
              padding: EdgeInsets.zero,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
