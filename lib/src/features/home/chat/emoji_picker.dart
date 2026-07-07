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
  return _value(
    payload,
    ['emoji_asset', 'asset', 'emoji_path'],
    fallback: _value(_asObjectMap(payload['media']), ['emoji_asset', 'asset']),
  );
}

class _EmojiPickerPage extends StatefulWidget {
  const _EmojiPickerPage();

  @override
  State<_EmojiPickerPage> createState() => _EmojiPickerPageState();
}

class _EmojiPickerPageState extends State<_EmojiPickerPage> {
  late final Future<List<_EmojiAsset>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadEmojiAssets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择表情')),
      body: SafeArea(
        child: FutureBuilder<List<_EmojiAsset>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(text: snapshot.error.toString());
            }
            final items = snapshot.data ?? const <_EmojiAsset>[];
            if (items.isEmpty) {
              return const _EmptyRow(text: '暂无表情');
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Semantics(
                  button: true,
                  label: '发送表情 ${item.tag}',
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(<String, String>{
                      'emoji_id': item.id,
                      'emoji_code': item.tag,
                      'emoji_asset': item.asset,
                      'content': item.tag,
                    }),
                    borderRadius: BorderRadius.circular(BimRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        item.asset,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
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
