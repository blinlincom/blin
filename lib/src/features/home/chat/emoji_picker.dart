part of 'package:bim/src/features/home/home_page.dart';

const _emojiManifestAsset = 'assets/emoji/emoji.xml';
const _emojiAssetRoot = 'assets/emoji/default';

class _EmojiAsset {
  const _EmojiAsset({required this.id, required this.tag, required this.asset});

  final String id;
  final String tag;
  final String asset;
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
    ['emoji_asset', 'asset', 'emoji_path'],
    fallback: _value(_asObjectMap(payload['media']), ['emoji_asset', 'asset']),
  );
  if (asset.isNotEmpty) {
    return asset;
  }
  final id = _value(payload, ['emoji_id']);
  if (RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(id)) {
    final file = id.endsWith('.png') ? id : '$id.png';
    return '$_emojiAssetRoot/$file';
  }
  return '';
}

class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({required this.onSelected});

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();

  final ValueChanged<Map<String, String>> onSelected;
}

class _EmojiPanelState extends State<_EmojiPanel> {
  late final Future<List<_EmojiAsset>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadEmojiAssets();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700
        ? 10
        : width >= 520
        ? 8
        : 7;
    return Container(
      height: BimDimensions.chatToolsPanel,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      child: SafeArea(
        top: false,
        child: FutureBuilder<List<_EmojiAsset>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              );
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
                return Semantics(
                  button: true,
                  label: '发送表情 ${item.id}',
                  child: InkWell(
                    onTap: () => widget.onSelected(<String, String>{
                      'emoji_id': item.id,
                      'emoji_asset': item.asset,
                      'content': '[表情]',
                    }),
                    borderRadius: BorderRadius.circular(BimRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        item.asset,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.none,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            item.tag,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
