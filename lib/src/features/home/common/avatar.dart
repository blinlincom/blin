part of 'package:bim/src/features/home/home_page.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    this.size = 44,
    this.color = _primaryColor,
    this.icon,
    this.imageUrl = '',
    this.compositeMembers = const [],
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;
  final String imageUrl;
  final List<Map<String, Object?>> compositeMembers;

  @override
  Widget build(BuildContext context) {
    final radius = _avatarRadius(size);
    final fallback = _AvatarFallback(
      label: label,
      size: size,
      color: color,
      icon: icon,
    );
    final url = _normalizeAvatarUrl(imageUrl);
    if (url.isEmpty) {
      if (compositeMembers.isNotEmpty) {
        return _CompositeGroupAvatar(members: compositeMembers, size: size);
      }
      return fallback;
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          fallback,
          Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return const SizedBox.shrink();
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CompositeGroupAvatar extends StatelessWidget {
  const _CompositeGroupAvatar({required this.members, required this.size});

  final List<Map<String, Object?>> members;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visible = members.take(4).toList(growable: false);
    final gap = max(1.0, size * 0.035);
    final cellSize = visible.length == 1 ? size : (size - gap) / 2;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(gap),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: BimColors.fill,
        borderRadius: BorderRadius.circular(_avatarRadius(size)),
      ),
      child: visible.length == 1
          ? _groupAvatarMember(visible.first, cellSize)
          : Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final member in visible)
                  SizedBox(
                    width: cellSize - gap,
                    height: cellSize - gap,
                    child: _groupAvatarMember(member, cellSize - gap),
                  ),
              ],
            ),
    );
  }

  Widget _groupAvatarMember(Map<String, Object?> member, double cellSize) {
    final label = _value(member, [
      'nickname',
      'name',
      'username',
    ], fallback: '群成员');
    return ClipRRect(
      borderRadius: BorderRadius.circular(max(2, cellSize * 0.12)),
      child: _Avatar(
        label: label,
        imageUrl: _avatarUrlFromMap(member),
        size: cellSize,
        color: BimColors.primary,
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
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final radius = _avatarRadius(size);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
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

double _avatarRadius(double size) {
  return (size * 0.18).clamp(BimRadius.sm, BimRadius.md).toDouble();
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
      borderRadius: BorderRadius.circular(BimRadius.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(BimRadius.md),
              border: Border.all(color: _lightBorderColor),
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
