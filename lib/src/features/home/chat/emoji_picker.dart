part of 'package:bim/src/features/home/home_page.dart';

const _emojiManifestAsset = 'assets/emoji/emoji.xml';
const _emojiAssetRoot = 'assets/emoji/default';

class _EmojiAsset {
  const _EmojiAsset({required this.id, required this.tag, required this.asset});

  final String id;
  final String tag;
  final String asset;
}

class _StickerPack {
  const _StickerPack({
    required this.id,
    required this.title,
    required this.cover,
    required this.priceText,
    required this.owned,
    required this.items,
  });

  final String id;
  final String title;
  final String cover;
  final String priceText;
  final bool owned;
  final List<_StickerItem> items;
}

class _StickerItem {
  const _StickerItem({
    required this.id,
    required this.packId,
    required this.asset,
    required this.url,
    required this.name,
    required this.format,
    required this.animated,
  });

  final String id;
  final String packId;
  final String asset;
  final String url;
  final String name;
  final String format;
  final bool animated;
}

Future<List<_EmojiAsset>> _loadEmojiAssets() async {
  final xml = await rootBundle.loadString(_emojiManifestAsset);
  return _parseEmojiManifest(xml);
}

List<_EmojiAsset> _parseEmojiManifest(String xml) {
  final items = <_EmojiAsset>[];
  final pattern = RegExp(
    r'<Emoticon\s+[^>]*ID="([^"]+)"[^>]*Tag="([^"]*)"[^>]*File="([^"]+)"[^>]*/>',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(xml)) {
    final id = match.group(1)?.trim() ?? '';
    final tag = _decodeXmlAttribute(match.group(2) ?? '').trim();
    final file = match.group(3)?.trim() ?? '';
    if (id.isEmpty || tag.isEmpty || file.isEmpty) {
      continue;
    }
    items.add(_EmojiAsset(id: id, tag: tag, asset: '$_emojiAssetRoot/$file'));
  }
  return items;
}

String _decodeXmlAttribute(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

String _emojiAssetForPayload(Map<String, Object?> payload) {
  final asset = _value(
    payload,
    ['emoji_asset', 'asset', 'emoji_path', 'sticker_asset'],
    fallback: _value(_asObjectMap(payload['media']), [
      'emoji_asset',
      'asset',
      'emoji_path',
      'sticker_asset',
    ]),
  );
  if (asset.isNotEmpty) {
    return asset;
  }
  final id = _value(payload, ['emoji_id']);
  final media = _asObjectMap(payload['media']);
  final code = _value(payload, [
    'emoji_code',
    'sticker_id',
  ], fallback: _value(media, ['emoji_code', 'sticker_id']));
  final resolved = id.isNotEmpty ? id : code;
  final packId = _value(payload, [
    'pack_id',
  ], fallback: _value(media, ['pack_id']));
  if (packId.isNotEmpty && packId != 'default' && asset.isEmpty) {
    return '';
  }
  if (RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(resolved)) {
    final file = resolved.endsWith('.png') ? resolved : '$resolved.png';
    return '$_emojiAssetRoot/$file';
  }
  return '';
}

class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({
    required this.controller,
    required this.height,
    required this.initialTab,
    required this.onSelected,
    super.key,
  });

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();

  final SessionController controller;
  final double height;
  final int initialTab;
  final ValueChanged<Map<String, String>> onSelected;
}

class _EmojiPanelState extends State<_EmojiPanel> {
  late final Future<List<_EmojiAsset>> _emojiFuture;
  Future<List<_StickerPack>>? _stickerFuture;
  Future<List<_StickerPack>>? _storeFuture;
  var _tab = 0;
  Set<String> _ownedPackIds = const {};

  @override
  void initState() {
    super.initState();
    _emojiFuture = _loadEmojiAssets();
    _tab = widget.initialTab.clamp(0, 2);
    _ownedPackIds = widget.controller.cachedOwnedStickerPackIds();
    _stickerFuture = _loadStickerPacks(refresh: false);
    if (_tab == 2) {
      _storeFuture = _loadStorePacks();
    }
  }

  @override
  void didUpdateWidget(covariant _EmojiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ownedPackIds = widget.controller.cachedOwnedStickerPackIds();
      _stickerFuture = _loadStickerPacks(refresh: false);
      _storeFuture = null;
    }
  }

  Future<List<_StickerPack>> _loadStickerPacks({required bool refresh}) async {
    final cached = widget.controller.cachedStickerPacks();
    final owned = widget.controller.cachedOwnedStickerPackIds();
    if (!refresh && cached.isNotEmpty) {
      return _normalizeStickerPacks(cached, owned);
    }
    try {
      final ownedIds = await widget.controller.loadOwnedStickerPackIds(
        refresh: refresh,
      );
      final packs = await widget.controller.loadStickerPacks(refresh: refresh);
      _ownedPackIds = ownedIds;
      return _normalizeStickerPacks(packs, ownedIds);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'load sticker packs failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
      if (cached.isNotEmpty) {
        return _normalizeStickerPacks(cached, owned);
      }
      rethrow;
    }
  }

  Future<List<_StickerPack>> _loadStorePacks() async {
    final owned = await widget.controller.loadOwnedStickerPackIds(
      refresh: true,
    );
    final packs = await widget.controller.loadStickerPacks(refresh: true);
    _ownedPackIds = owned;
    return _normalizeStickerPacks(packs, owned);
  }

  void _openTab(int tab) {
    setState(() {
      _tab = tab;
      if (tab == 1) {
        _stickerFuture ??= _loadStickerPacks(refresh: false);
      } else if (tab == 2) {
        _storeFuture ??= _loadStorePacks();
      }
    });
  }

  Future<void> _buyPack(_StickerPack pack) async {
    try {
      await widget.controller.buyStickerPack(pack.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _ownedPackIds = {..._ownedPackIds, pack.id};
        _stickerFuture = _loadStickerPacks(refresh: true);
        _storeFuture = _loadStorePacks();
      });
      _showChatSnack(context, '已添加表情包');
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'buy sticker pack failed',
        error: error,
        stackTrace: stackTrace,
        data: {'pack_id': pack.id},
      );
      if (mounted) {
        _showChatSnack(context, error.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _EmojiPanelTabs(current: _tab, onChanged: _openTab),
            Expanded(
              child: switch (_tab) {
                1 => _StickerPackGrid(
                  future: _stickerFuture!,
                  ownedOnly: true,
                  ownedPackIds: _ownedPackIds,
                  onSelected: widget.onSelected,
                  onBuy: _buyPack,
                ),
                2 => _StickerPackGrid(
                  future: _storeFuture ??= _loadStorePacks(),
                  ownedOnly: false,
                  ownedPackIds: _ownedPackIds,
                  onSelected: widget.onSelected,
                  onBuy: _buyPack,
                ),
                _ => _EmojiAssetGrid(
                  future: _emojiFuture,
                  onSelected: widget.onSelected,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPanelTabs extends StatelessWidget {
  const _EmojiPanelTabs({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            _EmojiPanelTab(
              icon: Icons.emoji_emotions_outlined,
              label: '表情',
              selected: current == 0,
              onTap: () => onChanged(0),
            ),
            _EmojiPanelTab(
              icon: Icons.auto_awesome_outlined,
              label: '贴纸',
              selected: current == 1,
              onTap: () => onChanged(1),
            ),
            _EmojiPanelTab(
              icon: Icons.storefront_outlined,
              label: '商店',
              selected: current == 2,
              onTap: () => onChanged(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPanelTab extends StatelessWidget {
  const _EmojiPanelTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _primaryColor : _secondaryTextColor;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 22 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiAssetGrid extends StatelessWidget {
  const _EmojiAssetGrid({required this.future, required this.onSelected});

  final Future<List<_EmojiAsset>> future;
  final ValueChanged<Map<String, String>> onSelected;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700
        ? 10
        : width >= 520
        ? 8
        : width >= 390
        ? 7
        : 6;
    return FutureBuilder<List<_EmojiAsset>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PanelLoading();
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString());
        }
        final items = snapshot.data ?? const <_EmojiAsset>[];
        if (items.isEmpty) {
          return const _EmptyRow(text: '暂无表情');
        }
        return GridView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _EmojiAssetButton(asset: item, onSelected: onSelected);
          },
        );
      },
    );
  }
}

class _EmojiAssetButton extends StatelessWidget {
  const _EmojiAssetButton({required this.asset, required this.onSelected});

  final _EmojiAsset asset;
  final ValueChanged<Map<String, String>> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '输入表情 ${asset.tag}',
      child: InkWell(
        onTap: () => onSelected(<String, String>{
          'kind': ChatContentTypes.text,
          'content': asset.tag,
          'text': asset.tag,
        }),
        borderRadius: BorderRadius.circular(BimRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Image.asset(
            asset.asset,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => Center(
              child: Text(asset.tag, style: const TextStyle(fontSize: 24)),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPackGrid extends StatelessWidget {
  const _StickerPackGrid({
    required this.future,
    required this.ownedOnly,
    required this.ownedPackIds,
    required this.onSelected,
    required this.onBuy,
  });

  final Future<List<_StickerPack>> future;
  final bool ownedOnly;
  final Set<String> ownedPackIds;
  final ValueChanged<Map<String, String>> onSelected;
  final ValueChanged<_StickerPack> onBuy;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_StickerPack>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PanelLoading();
        }
        if (snapshot.hasError) {
          return _StickerPanelError(text: '表情商店接口不可用：${snapshot.error}');
        }
        final allPacks = snapshot.data ?? const <_StickerPack>[];
        final packs = ownedOnly
            ? allPacks
                  .where((pack) => pack.owned || ownedPackIds.contains(pack.id))
                  .toList(growable: false)
            : allPacks;
        if (packs.isEmpty) {
          return _EmptyRow(text: ownedOnly ? '暂无贴纸包' : '暂无可用表情包');
        }
        if (ownedOnly) {
          final items = packs
              .expand((pack) => pack.items)
              .toList(growable: false);
          if (items.isEmpty) {
            return const _EmptyRow(text: '暂无贴纸');
          }
          return _StickerItemGrid(items: items, onSelected: onSelected);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          itemCount: packs.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _lightBorderColor),
          itemBuilder: (context, index) {
            final pack = packs[index];
            final owned = pack.owned || ownedPackIds.contains(pack.id);
            return _StickerStorePackTile(
              pack: pack,
              owned: owned,
              onBuy: () => onBuy(pack),
            );
          },
        );
      },
    );
  }
}

class _StickerItemGrid extends StatelessWidget {
  const _StickerItemGrid({required this.items, required this.onSelected});

  final List<_StickerItem> items;
  final ValueChanged<Map<String, String>> onSelected;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700
        ? 6
        : width >= 520
        ? 5
        : width >= 390
        ? 4
        : 3;
    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _StickerItemButton(item: item, onSelected: onSelected);
      },
    );
  }
}

class _StickerItemButton extends StatelessWidget {
  const _StickerItemButton({required this.item, required this.onSelected});

  final _StickerItem item;
  final ValueChanged<Map<String, String>> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '发送贴纸 ${item.name}',
      child: InkWell(
        onTap: () => onSelected(<String, String>{
          'kind': item.animated
              ? ChatContentTypes.gif
              : ChatContentTypes.sticker,
          'pack_id': item.packId,
          'format': item.format,
          'sticker_id': item.id,
          'emoji_id': item.id,
          'emoji_code': item.id,
          if (item.asset.isNotEmpty) 'sticker_asset': item.asset,
          if (item.asset.isNotEmpty) 'emoji_asset': item.asset,
          if (item.url.isNotEmpty) 'url': item.url,
          'name': item.name,
          'content': item.animated ? '[GIF]' : '[贴纸]',
        }),
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xfff3f5f8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: _StickerThumb(item: item, size: 72),
          ),
        ),
      ),
    );
  }
}

class _StickerStorePackTile extends StatelessWidget {
  const _StickerStorePackTile({
    required this.pack,
    required this.owned,
    required this.onBuy,
  });

  final _StickerPack pack;
  final bool owned;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Row(
        children: [
          _StickerPackCover(pack: pack),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  owned
                      ? '${pack.items.length} 个贴纸，已添加'
                      : (pack.priceText.isEmpty ? '免费添加' : pack.priceText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: owned ? null : onBuy,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(66, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(owned ? '已添加' : '添加'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerPackCover extends StatelessWidget {
  const _StickerPackCover({required this.pack});

  final _StickerPack pack;

  @override
  Widget build(BuildContext context) {
    final first = pack.items.isEmpty ? null : pack.items.first;
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xfff3f5f8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: first == null
              ? const Icon(Icons.auto_awesome_outlined, color: _mutedColor)
              : _StickerThumb(item: first, size: 42),
        ),
      ),
    );
  }
}

class _StickerThumb extends StatelessWidget {
  const _StickerThumb({required this.item, required this.size});

  final _StickerItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = item.asset;
    final url = _normalizeAvatarUrl(item.url);
    if (asset.isNotEmpty) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _stickerFallback,
      );
    }
    if (url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _stickerFallback,
      );
    }
    return _stickerFallback;
  }

  Widget get _stickerFallback {
    return const Center(
      child: Icon(Icons.auto_awesome_outlined, color: _mutedColor, size: 24),
    );
  }
}

class _StickerPanelError extends StatelessWidget {
  const _StickerPanelError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _dangerColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _PanelLoading extends StatelessWidget {
  const _PanelLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      ),
    );
  }
}

List<_StickerPack> _normalizeStickerPacks(
  List<Map<String, Object?>> rawPacks,
  Set<String> ownedIds,
) {
  final packs = <_StickerPack>[];
  for (final raw in rawPacks) {
    final id = _stickerPackIdFromMap(raw);
    if (id.isEmpty) {
      continue;
    }
    final items = _stickerItemsFromPack(raw, id);
    packs.add(
      _StickerPack(
        id: id,
        title: _value(raw, [
          'title',
          'name',
          'pack_name',
          'package_name',
        ], fallback: '表情包'),
        cover: _value(raw, ['cover', 'cover_url', 'image', 'icon']),
        priceText: _stickerPriceText(raw),
        owned:
            _boolValue(raw['owned']) ||
            _boolValue(raw['is_owned']) ||
            ownedIds.contains(id),
        items: items,
      ),
    );
  }
  return packs;
}

String _stickerPackIdFromMap(Map<String, Object?> item) {
  final nested = _asObjectMap(item['pack']);
  for (final source in [item, nested]) {
    final value = _value(source, [
      'pack_id',
      'id',
      'package_id',
      'sticker_pack_id',
    ]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

List<_StickerItem> _stickerItemsFromPack(
  Map<String, Object?> pack,
  String packId,
) {
  Object? rawItems = pack['items'] ?? pack['stickers'] ?? pack['list'];
  if (rawItems == null && pack['data'] is Map) {
    final data = _asObjectMap(pack['data']);
    rawItems = data['items'] ?? data['stickers'] ?? data['list'];
  }
  if (rawItems is! List) {
    final cover = _value(pack, ['cover', 'cover_url', 'image', 'icon']);
    if (cover.isEmpty) {
      return const [];
    }
    return [
      _StickerItem(
        id: '${packId}_cover',
        packId: packId,
        asset: '',
        url: cover,
        name: _value(pack, ['title', 'name'], fallback: '贴纸'),
        format: _formatFromPath(cover),
        animated: _pathLooksAnimated(cover),
      ),
    ];
  }
  return rawItems
      .whereType<Map>()
      .map((item) {
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        return _stickerItemFromMap(map, packId);
      })
      .where((item) => item.id.isNotEmpty)
      .toList(growable: false);
}

_StickerItem _stickerItemFromMap(Map<String, Object?> item, String packId) {
  final id = _value(item, ['sticker_id', 'emoji_id', 'id', 'code']);
  final asset = _value(item, ['asset', 'emoji_asset', 'sticker_asset']);
  final url = _value(item, ['url', 'file_url', 'image_url', 'gif_url']);
  final format = _value(item, [
    'format',
    'mime',
  ], fallback: _formatFromPath(asset.isNotEmpty ? asset : url)).toLowerCase();
  return _StickerItem(
    id: id,
    packId: _value(item, ['pack_id'], fallback: packId),
    asset: asset,
    url: url,
    name: _value(item, ['name', 'title', 'tag'], fallback: id),
    format: format,
    animated:
        _boolValue(item['animated']) ||
        _pathLooksAnimated(asset) ||
        _pathLooksAnimated(url) ||
        format.contains('gif') ||
        format.contains('webp'),
  );
}

String _stickerPriceText(Map<String, Object?> item) {
  final priceText = _value(item, ['price_text', 'price_label']);
  if (priceText.isNotEmpty) {
    return priceText;
  }
  final price = _value(item, ['price', 'money', 'amount']);
  if (price.isEmpty || price == '0' || price == '0.00') {
    return '免费添加';
  }
  return '￥$price';
}

String _formatFromPath(String value) {
  final lower = value.toLowerCase();
  if (lower.contains('.gif') || lower.contains('image/gif')) {
    return 'gif';
  }
  if (lower.contains('.webp') || lower.contains('image/webp')) {
    return 'webp';
  }
  if (lower.contains('.png') || lower.contains('image/png')) {
    return 'png';
  }
  if (lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('image/jpeg')) {
    return 'jpg';
  }
  return '';
}

bool _pathLooksAnimated(String value) {
  final lower = value.toLowerCase();
  return lower.contains('.gif') || lower.contains('.webp');
}
