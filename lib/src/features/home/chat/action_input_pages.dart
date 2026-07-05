part of 'package:bim/src/features/home/home_page.dart';

class ActionInputField {
  const ActionInputField({
    required this.id,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.keyboardType,
    this.maxLines = 1,
  });

  final String id;
  final String label;
  final String hint;
  final String initial;
  final TextInputType? keyboardType;
  final int maxLines;
}

void _showChatSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      elevation: 0,
      backgroundColor: error ? _dangerColor : const Color(0xff1f2329),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ActionInputPage extends StatefulWidget {
  const ActionInputPage({required this.title, required this.fields, super.key});

  final String title;
  final List<ActionInputField> fields;

  @override
  State<ActionInputPage> createState() => _ActionInputPageState();
}

class _InAppMediaPickerPage extends StatefulWidget {
  const _InAppMediaPickerPage({required this.contentType});

  final String contentType;

  @override
  State<_InAppMediaPickerPage> createState() => _InAppMediaPickerPageState();
}

class _InAppMediaPickerPageState extends State<_InAppMediaPickerPage> {
  static const _pageSize = 120;

  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _selectedAlbum;
  bool _loading = true;
  bool _loadingAssets = false;
  String _error = '';
  String _selectingAssetId = '';

  bool get _isVideo => widget.contentType == ChatContentTypes.video;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAlbums());
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '需要授权访问相册后才能选择${_isVideo ? '视频' : '图片'}';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _isVideo ? RequestType.video : RequestType.image,
        hasAll: true,
      );
      if (!mounted) {
        return;
      }
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _albums = const [];
          _assets = const [];
          _selectedAlbum = null;
          _error = '';
        });
        return;
      }
      final selected = albums.firstWhere(
        (item) => item.isAll,
        orElse: () => albums.first,
      );
      setState(() {
        _albums = albums;
        _selectedAlbum = selected;
      });
      await _loadAssets(selected, showPageLoading: false);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '相册读取失败';
      });
    }
  }

  Future<void> _loadAssets(
    AssetPathEntity album, {
    bool showPageLoading = true,
  }) async {
    if (showPageLoading) {
      setState(() {
        _loadingAssets = true;
        _error = '';
      });
    }
    try {
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAlbum = album;
        _assets = assets;
        _loading = false;
        _loadingAssets = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media assets failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingAssets = false;
        _error = '媒体列表读取失败';
      });
    }
  }

  Future<void> _selectAsset(AssetEntity asset) async {
    if (_selectingAssetId.isNotEmpty) {
      return;
    }
    setState(() => _selectingAssetId = asset.id);
    try {
      final file = await asset.originFile ?? await asset.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('asset file is unavailable');
      }
      final stat = await file.stat();
      if (!mounted) {
        return;
      }
      final name = await asset.titleAsync;
      final payload = <String, String>{
        'file_path': file.path,
        'name': name.isNotEmpty ? name : _fileName(file.path),
        'size': stat.size.toString(),
        'mime': asset.mimeType ?? _mimeFromPath(file.path, widget.contentType),
        if (asset.width > 0) 'width': asset.width.toString(),
        if (asset.height > 0) 'height': asset.height.toString(),
        if (_isVideo) 'duration': asset.duration.toString(),
      };
      Navigator.of(context).pop(payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select media asset failed',
        error: error,
        stackTrace: stackTrace,
        data: {'asset_id': asset.id},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingAssetId = '');
      _showChatSnack(context, '文件读取失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(_isVideo ? '选择视频' : '选择图片'),
        centerTitle: true,
        toolbarHeight: 50,
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          color: _textColor,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _lightBorderColor),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _ErrorState(
        text: _error,
        onRetry: _error.contains('授权')
            ? () async {
                await PhotoManager.openSetting();
                if (mounted) {
                  await _loadAlbums();
                }
              }
            : _loadAlbums,
      );
    }
    if (_assets.isEmpty) {
      return _EmptyState(text: _isVideo ? '暂无可发送视频' : '暂无可发送图片');
    }
    return Column(
      children: [
        _MediaAlbumBar(
          albums: _albums,
          selected: _selectedAlbum,
          onChanged: (album) => _loadAssets(album),
        ),
        if (_loadingAssets)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: _assets.length,
            itemBuilder: (context, index) {
              final asset = _assets[index];
              return _MediaAssetTile(
                asset: asset,
                selecting: _selectingAssetId == asset.id,
                onTap: () => _selectAsset(asset),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MediaAlbumBar extends StatelessWidget {
  const _MediaAlbumBar({
    required this.albums,
    required this.selected,
    required this.onChanged,
  });

  final List<AssetPathEntity> albums;
  final AssetPathEntity? selected;
  final ValueChanged<AssetPathEntity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AssetPathEntity>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: albums
              .map(
                (album) => DropdownMenuItem<AssetPathEntity>(
                  value: album,
                  child: Text(
                    album.isAll ? '全部' : album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (album) {
            if (album != null) {
              onChanged(album);
            }
          },
        ),
      ),
    );
  }
}

class _MediaAssetTile extends StatelessWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.selecting,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize.square(220),
              quality: 82,
            ),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(
                  color: const Color(0xffe8eaed),
                  child: Icon(
                    asset.type == AssetType.video
                        ? Icons.videocam_outlined
                        : Icons.image_outlined,
                    color: _mutedColor,
                  ),
                );
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          ),
          if (asset.type == AssetType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: const Color(0x99000000),
                child: Text(
                  _secondsLabel(asset.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          if (selecting)
            Container(
              color: const Color(0x66000000),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _InAppFilePickerPage extends StatefulWidget {
  const _InAppFilePickerPage();

  @override
  State<_InAppFilePickerPage> createState() => _InAppFilePickerPageState();
}

class _InAppFilePickerPageState extends State<_InAppFilePickerPage> {
  static const _maxFiles = 300;

  List<_LocalFileItem> _files = const [];
  bool _loading = true;
  String _error = '';
  String _selectingPath = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadFiles());
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final dirs = await _candidateFileDirectories();
      final files = <_LocalFileItem>[];
      final seen = <String>{};
      for (final dir in dirs) {
        if (files.length >= _maxFiles) {
          break;
        }
        await _scanDirectory(dir, files, seen, depth: 2);
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) {
        return;
      }
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load in-app files failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '文件列表读取失败';
      });
    }
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<_LocalFileItem> files,
    Set<String> seen, {
    required int depth,
  }) async {
    if (files.length >= _maxFiles || !await dir.exists()) {
      return;
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (files.length >= _maxFiles) {
          return;
        }
        final name = _fileName(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        if (entity is File) {
          if (!seen.add(entity.path)) {
            continue;
          }
          final stat = await entity.stat();
          if (stat.size <= 0) {
            continue;
          }
          files.add(
            _LocalFileItem(
              path: entity.path,
              name: name,
              size: stat.size,
              modified: stat.modified.millisecondsSinceEpoch,
            ),
          );
        } else if (entity is Directory && depth > 0) {
          await _scanDirectory(entity, files, seen, depth: depth - 1);
        }
      }
    } on FileSystemException {
      return;
    }
  }

  Future<void> _selectFile(_LocalFileItem file) async {
    if (_selectingPath.isNotEmpty) {
      return;
    }
    setState(() => _selectingPath = file.path);
    try {
      final current = File(file.path);
      final stat = await current.stat();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(<String, String>{
        'file_path': file.path,
        'name': file.name,
        'size': stat.size.toString(),
        'mime': _mimeFromPath(file.path, ChatContentTypes.file),
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select in-app file failed',
        error: error,
        stackTrace: stackTrace,
        data: {'path': file.path},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingPath = '');
      _showChatSnack(context, '文件读取失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('选择文件'),
        centerTitle: true,
        toolbarHeight: 50,
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          color: _textColor,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _lightBorderColor),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _ErrorState(text: _error, onRetry: _loadFiles);
    }
    if (_files.isEmpty) {
      return const _EmptyState(text: '暂无可发送文件');
    }
    return ListView.separated(
      itemCount: _files.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _lightBorderColor),
      itemBuilder: (context, index) {
        final file = _files[index];
        final selecting = _selectingPath == file.path;
        return ListTile(
          leading: Icon(_fileIcon(file.name), color: _primaryColor),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textColor, fontSize: 15),
          ),
          subtitle: Text(
            '${_fileSizeLabel(file.size)} · ${_formatTime(file.modified)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _mutedColor, fontSize: 12),
          ),
          trailing: selecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right, color: _mutedColor),
          onTap: () => _selectFile(file),
        );
      },
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

class _ActionInputPageState extends State<ActionInputPage> {
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _controllers[field.id] = TextEditingController(text: field.initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        toolbarHeight: 50,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        titleTextStyle: const TextStyle(
          color: _textColor,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _lightBorderColor),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                itemCount: widget.fields.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildField(widget.fields[index]),
              ),
            ),
            _ActionInputFooter(
              onCancel: () => Navigator.of(context).pop(),
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(ActionInputField field) {
    final controller = _controllers[field.id]!;
    final choices = _choicesForField(field.id);
    if (choices.isNotEmpty) {
      var current = controller.text.trim();
      if (current.isEmpty) {
        current = choices.first.value;
      }
      return _ActionFieldShell(
        label: field.label,
        hint: field.hint,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              _ActionChoiceButton(
                label: choice.label,
                selected: current == choice.value,
                onTap: () {
                  controller.text = choice.value;
                  setState(() {});
                },
              ),
          ],
        ),
      );
    }
    if (_isSwitchField(field.id)) {
      final enabled = controller.text.trim() == '1';
      return _ActionFieldShell(
        label: field.label,
        hint: field.hint,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lightBorderColor),
          ),
          child: SwitchListTile.adaptive(
            value: enabled,
            onChanged: (value) {
              controller.text = value ? '1' : '';
              setState(() {});
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
            title: Text(
              enabled ? '已开启' : '未开启',
              style: const TextStyle(
                color: _textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeThumbColor: _chatAckColor,
            activeTrackColor: const Color(0xffd8f4df),
          ),
        ),
      );
    }
    return _ActionFieldShell(
      label: field.label,
      hint: field.hint,
      child: TextField(
        controller: controller,
        keyboardType: field.keyboardType,
        maxLines: field.maxLines,
        minLines: field.maxLines > 1 ? 2 : 1,
        style: const TextStyle(
          color: _textColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        decoration: InputDecoration(
          hintText: field.hint.isEmpty ? null : field.hint,
          hintStyle: const TextStyle(color: _mutedColor, fontSize: 14),
          filled: true,
          fillColor: _surfaceColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _lightBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _lightBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _primaryColor),
          ),
        ),
      ),
    );
  }

  void _submit() {
    Navigator.of(
      context,
    ).pop(_controllers.map((key, value) => MapEntry(key, value.text.trim())));
  }

  bool _isSwitchField(String id) {
    return id == 'mention_all' || id == 'burn_after_read';
  }

  List<_ActionChoice> _choicesForField(String id) {
    return switch (id) {
      'asset_type' => const [
        _ActionChoice('money', '余额'),
        _ActionChoice('integral', '积分'),
      ],
      'packet_type' => const [
        _ActionChoice('ordinary', '普通'),
        _ActionChoice('luck', '拼手气'),
        _ActionChoice('specified', '指定'),
      ],
      _ => const [],
    };
  }
}

class _ActionChoice {
  const _ActionChoice(this.value, this.label);

  final String value;
  final String label;
}

class _ActionFieldShell extends StatelessWidget {
  const _ActionFieldShell({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint.isNotEmpty && !_hintDuplicatedInInput(hint))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint,
              style: const TextStyle(
                color: _secondaryTextColor,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  bool _hintDuplicatedInInput(String value) {
    return value.length <= 18;
  }
}

class _ActionChoiceButton extends StatelessWidget {
  const _ActionChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xffe9f8ed) : _surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _chatAckColor : _lightBorderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xff208a45) : _textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ActionInputFooter extends StatelessWidget {
  const _ActionInputFooter({required this.onCancel, required this.onSubmit});

  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom > 0 ? bottom : 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: _secondaryTextColor,
                side: const BorderSide(color: _borderColor),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: _chatAckColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
  }
}
