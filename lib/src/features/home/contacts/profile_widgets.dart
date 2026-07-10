part of 'package:bim/src/features/home/home_page.dart';

class _ChatInfoMemberStrip extends StatelessWidget {
  const _ChatInfoMemberStrip({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.onOpenProfile,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChatInfoMemberItem(
              title: title.isEmpty ? '好友' : title,
              avatarUrl: avatarUrl,
              online: online,
              onTap: onOpenProfile,
            ),
            const SizedBox(width: 28),
            const _ChatInfoAddMemberItem(),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoMemberItem extends StatelessWidget {
  const _ChatInfoMemberItem({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.onTap,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 58,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            _PresencePill(online: online),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoAddMemberItem extends StatelessWidget {
  const _ChatInfoAddMemberItem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surfaceColor,
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(_avatarRadius(58)),
            ),
            child: const Icon(Icons.add, color: _mutedColor, size: 30),
          ),
          const SizedBox(height: 8),
          const Text(
            '添加',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, onTap: onTap);
  }
}

class _SettingsValueNavTile extends StatelessWidget {
  const _SettingsValueNavTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, value: value, onTap: onTap);
  }
}

class _SettingsDangerTile extends StatelessWidget {
  const _SettingsDangerTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      onTap: onTap,
      tone: BimSettingsTileTone.danger,
      showChevron: false,
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      value: value,
      showChevron: false,
      valueMaxLines: 4,
    );
  }
}

class _FriendProfileHero extends StatelessWidget {
  const _FriendProfileHero({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.username,
    required this.signature,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final String username;
  final String signature;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 72,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? '好友' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PresencePill(online: online),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (username.isNotEmpty)
                    Text(
                      '账号：${_atName(username)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  if (signature.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendMomentsPreview extends StatelessWidget {
  const _FriendMomentsPreview({required this.future, required this.onTap});

  final Future<Map<String, Object?>>? future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _lightBorderColor)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  '朋友圈',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: _MomentPreviewImages(future: future)),
              const Icon(Icons.chevron_right, color: _mutedColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentPreviewImages extends StatelessWidget {
  const _MomentPreviewImages({required this.future});

  final Future<Map<String, Object?>>? future;

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, Object?>>(
      future: future,
      builder: (context, snapshot) {
        final urls = snapshot.connectionState == ConnectionState.done
            ? _momentPreviewUrls(snapshot.data ?? const {})
            : const <String>[];
        if (urls.isEmpty) {
          return const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '暂无动态',
              style: TextStyle(color: _mutedColor, fontSize: 14),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 6,
            children: [
              for (final url in urls.take(4))
                _MomentPreviewThumb(imageUrl: url),
            ],
          ),
        );
      },
    );
  }
}

class _MomentPreviewThumb extends StatelessWidget {
  const _MomentPreviewThumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _fillColor,
        borderRadius: BorderRadius.circular(BimRadius.xs),
      ),
      child: Image.network(
        _normalizeAvatarUrl(imageUrl),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(color: _fillColor),
      ),
    );
  }
}

class _FriendMomentTile extends StatelessWidget {
  const _FriendMomentTile({required this.post, required this.showDivider});

  final Map<String, Object?> post;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final content = _momentContent(post);
    final media = _momentMediaFromPost(post);
    final date = _momentTimelineDate(post);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: BimColors.surface,
        border: showDivider
            ? const Border(bottom: BorderSide(color: BimColors.borderLight))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date.$1,
                  style: const TextStyle(
                    color: BimColors.textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date.$2,
                  style: const TextStyle(
                    color: BimColors.secondaryText,
                    fontSize: BimTypography.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: BimSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (content.isNotEmpty)
                  Text(
                    content,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                if (media.isNotEmpty) ...[
                  if (content.isNotEmpty) const SizedBox(height: 10),
                  _FriendMomentMediaGrid(media: media),
                ],
                if (content.isEmpty && media.isEmpty)
                  const Text(
                    '分享了一条动态',
                    style: TextStyle(
                      color: BimColors.secondaryText,
                      fontSize: BimTypography.meta,
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

class _FriendMomentMediaGrid extends StatelessWidget {
  const _FriendMomentMediaGrid({required this.media});

  final List<Map<String, Object?>> media;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = min(media.length, 9);
        final tileSize = count == 1
            ? min(constraints.maxWidth, 260.0)
            : (constraints.maxWidth - 12) / 3;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in media.take(9))
              _FriendMomentMediaThumb(item: item, size: tileSize),
          ],
        );
      },
    );
  }
}

(String, String) _momentTimelineDate(Map<String, Object?> post) {
  final time = _parseUiTime(
    _value(post, ['created_at', 'create_time', 'publish_time', 'timestamp']),
  );
  if (time == null) {
    return ('--', '');
  }
  final now = DateTime.now();
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return (
      '今天',
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    );
  }
  return (
    time.day.toString().padLeft(2, '0'),
    time.year == now.year ? '${time.month}月' : '${time.year}.${time.month}',
  );
}

class _FriendMomentMediaThumb extends StatelessWidget {
  const _FriendMomentMediaThumb({required this.item, required this.size});

  final Map<String, Object?> item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _momentMediaUrl(item);
    final type = _value(item, ['type', 'media_type', 'content_type']);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _fillColor,
        borderRadius: BorderRadius.circular(BimRadius.xs),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            Image.network(
              _normalizeAvatarUrl(url),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const ColoredBox(color: _fillColor),
            )
          else
            const ColoredBox(color: _fillColor),
          if (type.toLowerCase().contains('video'))
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 34,
              ),
            ),
        ],
      ),
    );
  }
}

List<String> _momentPreviewUrls(Map<String, Object?> data) {
  final urls = <String>[];
  for (final post in _listFromResult(data)) {
    final media = _momentMediaFromPost(post);
    for (final item in media) {
      final url = _value(item, [
        'thumb_url',
        'cover_url',
        'thumbnail_url',
        'poster_url',
        'preview_url',
        'image_url',
        'url',
        'file_url',
        'media_url',
        'path',
      ]);
      if (url.isNotEmpty) {
        urls.add(url);
      }
      if (urls.length >= 4) {
        return urls;
      }
    }
  }
  return urls;
}

String _momentContent(Map<String, Object?> post) {
  return _value(post, ['content', 'text', 'body', 'desc', 'description']);
}

String _momentMediaUrl(Map<String, Object?> item) {
  return _value(item, [
    'thumb_url',
    'cover_url',
    'thumbnail_url',
    'poster_url',
    'preview_url',
    'image_url',
    'url',
    'file_url',
    'media_url',
    'path',
  ]);
}

List<Map<String, Object?>> _momentMediaFromPost(Map<String, Object?> post) {
  final media = post['media'];
  if (media is List) {
    return media
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
  if (media is String && media.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(media);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false);
      }
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

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

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: _mutedColor, fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          color: online ? _chatOnlineColor : _mutedColor,
          size: 8,
        ),
        const SizedBox(width: 6),
        Text(
          online ? '在线' : '离线',
          style: const TextStyle(color: _mutedColor, fontSize: 12),
        ),
      ],
    );
  }
}
