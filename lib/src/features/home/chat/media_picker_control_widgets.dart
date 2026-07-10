part of 'package:bim/src/features/home/home_page.dart';

class _FilePickerToolbar extends StatelessWidget {
  const _FilePickerToolbar({
    required this.controller,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _FileTypeFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_FileTypeFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: '搜索文件名',
                hintStyle: const TextStyle(color: _mutedColor, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search,
                  color: _secondaryTextColor,
                  size: 20,
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                filled: true,
                fillColor: _fillColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              scrollDirection: Axis.horizontal,
              itemCount: _FileTypeFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _FileTypeFilter.values[index];
                return Center(
                  child: _PickerFilterButton(
                    label: item.label,
                    selected: filter == item,
                    onTap: filter == item ? null : () => onFilterChanged(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePickerTile extends StatelessWidget {
  const _FilePickerTile({
    required this.file,
    required this.selected,
    required this.sending,
    required this.onTap,
  });

  final _LocalFileItem file;
  final bool selected;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = _compactFilePath(file.path);
    return Semantics(
      button: true,
      selected: selected,
      label: file.name,
      child: Material(
        color: selected ? BimColors.primaryWeak : _surfaceColor,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BimColors.primaryWeak,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _fileIcon(file.name),
                      color: _primaryColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_fileSizeLabel(file.size)} · ${_formatTime(file.modified)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      if (path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _mutedColor,
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SelectionMark(selected: selected, busy: sending),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPickerFooter extends StatelessWidget {
  const _MediaPickerFooter({
    required this.selectedCount,
    required this.maxSelection,
    required this.videoSelected,
    required this.sending,
    required this.onClear,
    required this.onPreview,
    required this.onSend,
  });

  final int selectedCount;
  final int maxSelection;
  final bool videoSelected;
  final bool sending;
  final VoidCallback? onClear;
  final VoidCallback? onPreview;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !sending;
    final leadingText = selectedCount == 0
        ? '未选择'
        : videoSelected
        ? '已选择 1 个视频'
        : '已选择 $selectedCount/$maxSelection 张';
    return _PickerFooterShell(
      leading: Text(
        leadingText,
        style: const TextStyle(
          color: _secondaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        _PickerSecondaryButton(
          label: '清空',
          onPressed: enabled ? onClear : null,
        ),
        _PickerSecondaryButton(
          label: '预览',
          onPressed: enabled ? onPreview : null,
        ),
        _PickerSendButton(onPressed: enabled ? onSend : null, sending: sending),
      ],
    );
  }
}

class _FilePickerFooter extends StatelessWidget {
  const _FilePickerFooter({
    required this.selected,
    required this.sending,
    required this.onClear,
    required this.onSend,
  });

  final _LocalFileItem? selected;
  final bool sending;
  final VoidCallback? onClear;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = selected != null && !sending;
    return _PickerFooterShell(
      leading: Text(
        selected == null
            ? '请选择一个文件'
            : '${selected!.name} · ${_fileSizeLabel(selected!.size)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _secondaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        _PickerSecondaryButton(
          label: '清空',
          onPressed: enabled ? onClear : null,
        ),
        _PickerSendButton(onPressed: enabled ? onSend : null, sending: sending),
      ],
    );
  }
}

class _PickerFooterShell extends StatelessWidget {
  const _PickerFooterShell({required this.leading, required this.actions});

  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: compact ? 2 : 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 14,
              8,
              compact ? 10 : 14,
              8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: leading),
                ),
                SizedBox(width: compact ? 8 : 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) SizedBox(width: compact ? 6 : 8),
                      actions[index],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSecondaryButton extends StatelessWidget {
  const _PickerSecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return SizedBox(
      width: compact ? 56 : 64,
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

class _PickerSendButton extends StatelessWidget {
  const _PickerSendButton({required this.onPressed, required this.sending});

  final VoidCallback? onPressed;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return SizedBox(
      width: compact ? 72 : 84,
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const FittedBox(fit: BoxFit.scaleDown, child: Text('发送')),
      ),
    );
  }
}

class _PickerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PickerAppBar({required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(BimDimensions.appBar);

  @override
  Widget build(BuildContext context) {
    return BimTopBar(title: title, actions: actions ?? const []);
  }
}

class _PickerFilterButton extends StatelessWidget {
  const _PickerFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _textColor : _fillColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32, minWidth: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _textColor,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({
    required this.selected,
    required this.busy,
    this.label = '',
  });

  final bool selected;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? _primaryColor : BimColors.scrim,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: selected
          ? label.isEmpty
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  )
          : const SizedBox.shrink(),
    );
  }
}

class _MediaAssetPlaceholder extends StatelessWidget {
  const _MediaAssetPlaceholder({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BimColors.mediaPlaceholder,
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          color: _mutedColor,
          size: 28,
        ),
      ),
    );
  }
}

class _VideoDurationBadge extends StatelessWidget {
  const _VideoDurationBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x99000000)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white, size: 13),
            const SizedBox(width: 2),
            Text(
              _secondsLabel(seconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTopBar extends StatelessWidget {
  const _PreviewTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x66000000)),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 50),
          ],
        ),
      ),
    );
  }
}

class _PreviewBottomBar extends StatelessWidget {
  const _PreviewBottomBar({required this.asset, required this.onSelect});

  final AssetEntity asset;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    final label = isVideo ? '选择此视频' : '选择此图片';
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x99000000)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isVideo ? _secondsLabel(asset.duration) : '图片预览',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton(onPressed: onSelect, child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaGridSkeleton extends StatelessWidget {
  const _MediaGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _mediaGridColumns(context, constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: columns * 5,
          itemBuilder: (_, __) => const _MediaSkeletonTile(),
        );
      },
    );
  }
}

class _MediaSkeletonTile extends StatelessWidget {
  const _MediaSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xffe8eaed)),
    );
  }
}

class _FileListSkeleton extends StatelessWidget {
  const _FileListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: 10,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _lightBorderColor),
      itemBuilder: (_, __) => const _FileSkeletonRow(),
    );
  }
}

class _FileSkeletonRow extends StatelessWidget {
  const _FileSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xffe8eaed)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SizedBox(
                  width: double.infinity,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xffe8eaed)),
                  ),
                ),
                SizedBox(height: 9),
                SizedBox(
                  width: 180,
                  height: 11,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xffeef0f3)),
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

class _LocalFileItem {
  const _LocalFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final int modified;
}

enum _FileTypeFilter {
  all('全部'),
  document('文档'),
  image('图片'),
  video('视频'),
  archive('压缩包'),
  other('其他');

  const _FileTypeFilter(this.label);

  final String label;

  bool matches(_LocalFileItem file) {
    return switch (this) {
      _FileTypeFilter.all => true,
      _FileTypeFilter.document =>
        _fileKind(file.name) == _FileTypeKind.document,
      _FileTypeFilter.image => _fileKind(file.name) == _FileTypeKind.image,
      _FileTypeFilter.video => _fileKind(file.name) == _FileTypeKind.video,
      _FileTypeFilter.archive => _fileKind(file.name) == _FileTypeKind.archive,
      _FileTypeFilter.other => _fileKind(file.name) == _FileTypeKind.other,
    };
  }
}

enum _FileTypeKind { document, image, video, archive, other }

Map<String, String> _mediaAssetSelectionPayload(AssetEntity asset) {
  final title = asset.title ?? '';
  final contentType = _assetIsVideo(asset)
      ? ChatContentTypes.video
      : ChatContentTypes.image;
  return <String, String>{
    'asset_id': asset.id,
    'content_type': contentType,
    'name': title.isNotEmpty ? title : asset.id,
    if ((asset.mimeType ?? '').isNotEmpty) 'mime': asset.mimeType!,
    if (asset.width > 0) 'width': asset.width.toString(),
    if (asset.height > 0) 'height': asset.height.toString(),
    if (_assetIsVideo(asset) && asset.duration > 0)
      'duration': asset.duration.toString(),
  };
}

Future<Map<String, String>> _mediaAssetPayload(
  AssetEntity asset,
  String contentType,
) async {
  final file = await asset.originFile ?? await asset.file;
  if (file == null || file.path.isEmpty) {
    throw const FileSystemException('asset file is unavailable');
  }
  final stat = await file.stat();
  if (stat.size <= 0) {
    throw const FileSystemException('asset file is empty');
  }
  final name = await asset.titleAsync;
  return <String, String>{
    'file_path': file.path,
    'content_type': _assetIsVideo(asset)
        ? ChatContentTypes.video
        : ChatContentTypes.image,
    'name': name.isNotEmpty ? name : _fileName(file.path),
    'size': stat.size.toString(),
    'mime': asset.mimeType ?? _mimeFromPath(file.path, contentType),
    if (asset.width > 0) 'width': asset.width.toString(),
    if (asset.height > 0) 'height': asset.height.toString(),
    if (contentType == ChatContentTypes.video)
      'duration': asset.duration.toString(),
  };
}

bool _assetIsVideo(AssetEntity asset) => asset.type == AssetType.video;

int _mediaAssetRecentCompare(AssetEntity a, AssetEntity b) {
  final bTime = b.createDateSecond ?? b.modifiedDateSecond ?? 0;
  final aTime = a.createDateSecond ?? a.modifiedDateSecond ?? 0;
  final byTime = bTime.compareTo(aTime);
  if (byTime != 0) {
    return byTime;
  }
  return b.id.compareTo(a.id);
}

int _selectedMaxSelectionForAssets(List<AssetEntity> assets) {
  return assets.any(_assetIsVideo) ? 1 : _mediaMaxImageSelection;
}

int _mediaGridColumns(BuildContext context, double width) {
  final orientation = MediaQuery.orientationOf(context);
  if (width >= 1100) {
    return 9;
  }
  if (width >= 900) {
    return 8;
  }
  if (width >= 700) {
    return 6;
  }
  if (width >= 520 || orientation == Orientation.landscape) {
    return 5;
  }
  return 4;
}

_FileTypeKind _fileKind(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' => _FileTypeKind.image,
    'mp4' || 'mov' || 'm4v' || 'webm' || 'avi' || 'mkv' => _FileTypeKind.video,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => _FileTypeKind.archive,
    'pdf' ||
    'txt' ||
    'md' ||
    'doc' ||
    'docx' ||
    'xls' ||
    'xlsx' ||
    'ppt' ||
    'pptx' => _FileTypeKind.document,
    _ => _FileTypeKind.other,
  };
}

String _compactFilePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((item) => item.isNotEmpty).toList();
  if (parts.length <= 2) {
    return '';
  }
  final parent = parts[parts.length - 2];
  if (parent.isEmpty) {
    return '';
  }
  return parent;
}
