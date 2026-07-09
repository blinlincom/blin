part of 'package:bim/src/features/home/home_page.dart';

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
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _fillColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                const Icon(Icons.search, color: _mutedColor, size: 17),
                const SizedBox(width: 8),
                Text(
                  hintText,
                  style: const TextStyle(
                    color: _mutedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.unread,
    required this.isGroup,
    required this.avatarUrl,
    required this.onTap,
    this.onLongPress,
    this.isPinned = false,
  });

  final String title;
  final String subtitle;
  final String time;
  final int unread;
  final bool isGroup;
  final String avatarUrl;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: BimDimensions.conversationRow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isPinned ? const Color(0xfff4f5f7) : _surfaceColor,
          border: const Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 2,
                    child: _Avatar(
                      label: title,
                      imageUrl: avatarUrl,
                      size: 48,
                      color: isGroup ? const Color(0xff34c759) : _primaryColor,
                      icon: isGroup ? Icons.groups : null,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _UnreadBadge(count: unread),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPinned) ...[
                        const Icon(
                          Icons.push_pin,
                          size: 13,
                          color: Color(0xff8d95a3),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          title,
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
                  ),
                  const SizedBox(height: 4),
                  _ConversationSubtitleText(text: subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  time,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffb1b6c0),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationSwipeActions extends StatelessWidget {
  const _ConversationSwipeActions({required this.pinned});

  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConversationSwipeActionCell(
              color: const Color(0xff8d95a3),
              icon: pinned ? Icons.push_pin_outlined : Icons.push_pin,
              label: pinned ? '取消置顶' : '置顶',
            ),
            const _ConversationSwipeActionCell(
              color: BimColors.danger,
              icon: Icons.delete_outline,
              label: '删除',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationSwipeActionCell extends StatelessWidget {
  const _ConversationSwipeActionCell({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: double.infinity,
      color: color,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    final label = count > 99 ? '99+' : count.toString();
    final height = compact ? 16.0 : 19.0;
    final minWidth = compact ? 16.0 : 19.0;
    return Semantics(
      label: '$count 条未读消息',
      child: ExcludeSemantics(
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: minWidth),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xffdc2626),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: _surfaceColor, width: compact ? 1.5 : 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
    final prefix = _conversationPrefix(text);
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

String _conversationPrefix(String text) {
  for (final prefix in [
    '[红包]',
    '[转账]',
    '[收款]',
    '[付款]',
    '[表情]',
    '[GIF]',
    '[贴纸]',
  ]) {
    if (text.startsWith(prefix)) {
      return prefix;
    }
  }
  return '';
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.isGroup,
    required this.onTap,
    this.avatarUrl = '',
    this.onLongPress,
    super.key,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool isGroup;
  final VoidCallback onTap;
  final String avatarUrl;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: BimDimensions.contactRow),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: _surfaceColor,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 38,
              color: isGroup ? const Color(0xff34c759) : _primaryColor,
              icon: isGroup ? Icons.groups : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

class _SelectableContactTile extends StatelessWidget {
  const _SelectableContactTile({
    required this.title,
    required this.subtitle,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: const BoxDecoration(
          color: _surfaceColor,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 40,
              color: _primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _primaryColor : _surfaceColor,
                border: Border.all(
                  color: selected ? _primaryColor : _borderColor,
                ),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
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
        constraints: const BoxConstraints(minHeight: BimDimensions.menuRow),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: _surfaceColor,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
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
                      fontWeight: FontWeight.w600,
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
