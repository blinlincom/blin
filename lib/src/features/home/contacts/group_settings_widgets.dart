part of 'package:bim/src/features/home/home_page.dart';

class _GroupInfoMemberGrid extends StatelessWidget {
  const _GroupInfoMemberGrid({
    required this.loading,
    required this.expectedMemberCount,
    required this.members,
    required this.onOpenAll,
    required this.onAdd,
  });

  final bool loading;
  final int? expectedMemberCount;
  final List<Map<String, Object?>> members;
  final VoidCallback onOpenAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const columns = 4;
              const maxRows = 4;
              const horizontalPadding = BimSpacing.x4;
              const columnSpacing = BimSpacing.x2;
              const rowSpacing = BimSpacing.x5;
              const previewCapacity = columns * maxRows - 1;
              final availableWidth = max(
                0.0,
                constraints.maxWidth - horizontalPadding * 2,
              );
              final itemWidth =
                  (availableWidth - columnSpacing * (columns - 1)) / columns;
              final avatarSize = min(BimDimensions.avatarLg, itemWidth - 8);
              final preview = members
                  .take(previewCapacity)
                  .toList(growable: false);
              final resolvedCount = expectedMemberCount ?? members.length;
              final showMore = resolvedCount > previewCapacity;
              final placeholderCount = loading && members.isEmpty
                  ? min(
                      previewCapacity,
                      max(3, resolvedCount > 0 ? resolvedCount : 7),
                    )
                  : 0;
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalPadding,
                  BimSpacing.x5,
                  horizontalPadding,
                  BimSpacing.x3,
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: columnSpacing,
                      runSpacing: rowSpacing,
                      children: [
                        for (final member in preview)
                          _GroupMemberGridItem(
                            width: itemWidth,
                            avatarSize: avatarSize,
                            title: _memberTitle(member),
                            avatarUrl: _avatarUrlFromMap(member),
                            onTap: onOpenAll,
                          ),
                        for (var index = 0; index < placeholderCount; index++)
                          _GroupMemberPlaceholderItem(
                            width: itemWidth,
                            avatarSize: avatarSize,
                          ),
                        _GroupMemberAddItem(
                          width: itemWidth,
                          avatarSize: avatarSize,
                          onTap: onAdd,
                        ),
                      ],
                    ),
                    if (showMore) ...[
                      const SizedBox(height: BimSpacing.x4),
                      _GroupMemberMoreButton(
                        memberCount: resolvedCount,
                        onTap: onOpenAll,
                      ),
                    ] else
                      const SizedBox(height: BimSpacing.x2),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GroupMemberPlaceholderItem extends StatelessWidget {
  const _GroupMemberPlaceholderItem({
    required this.width,
    required this.avatarSize,
  });

  final double width;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: BimColors.fill,
              borderRadius: BorderRadius.circular(_avatarRadius(avatarSize)),
            ),
          ),
          const SizedBox(height: BimSpacing.x2),
          Container(
            width: min(48, width - 8),
            height: 12,
            color: BimColors.fill,
          ),
        ],
      ),
    );
  }
}

class _GroupMemberMoreButton extends StatelessWidget {
  const _GroupMemberMoreButton({
    required this.memberCount,
    required this.onTap,
  });

  final int memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimPressable(
      onTap: onTap,
      semanticLabel: '查看全部群成员，共$memberCount人',
      child: SizedBox(
        height: BimDimensions.touchTarget,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '查看全部群成员 ($memberCount)',
              style: const TextStyle(
                color: BimColors.secondaryText,
                fontSize: BimTypography.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: BimSpacing.x1),
            const Icon(
              Icons.chevron_right,
              color: BimColors.mutedText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMemberGridItem extends StatelessWidget {
  const _GroupMemberGridItem({
    required this.width,
    required this.avatarSize,
    required this.title,
    required this.avatarUrl,
    required this.onTap,
  });

  final double width;
  final double avatarSize;
  final String title;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: avatarSize,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMemberAddItem extends StatelessWidget {
  const _GroupMemberAddItem({
    required this.width,
    required this.avatarSize,
    required this.onTap,
  });

  final double width;
  final double avatarSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _surfaceColor,
                border: Border.all(color: _mutedColor.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(_avatarRadius(56)),
              ),
              child: const Icon(Icons.add, color: _mutedColor, size: 30),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSettingsNavTile extends StatelessWidget {
  const _GroupSettingsNavTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, onTap: onTap, minHeight: 62);
  }
}

class _GroupSettingsInfoTile extends StatelessWidget {
  const _GroupSettingsInfoTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      value: value,
      onTap: onTap,
      valueMaxLines: 2,
      minHeight: 62,
    );
  }
}

class _GroupSettingsSwitchTile extends StatelessWidget {
  const _GroupSettingsSwitchTile({
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSettingsSwitchTile(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GroupSettingsDangerTile extends StatelessWidget {
  const _GroupSettingsDangerTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      onTap: onTap,
      tone: BimSettingsTileTone.danger,
      showChevron: false,
      minHeight: 62,
    );
  }
}
