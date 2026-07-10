part of 'moments_page.dart';

class MomentComposerPage extends StatefulWidget {
  const MomentComposerPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MomentComposerPage> createState() => _MomentComposerPageState();
}

class _MomentComposerPageState extends State<MomentComposerPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<_MomentLocalMedia> _media = const [];
  bool _publishing = false;
  String _error = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.controller.readMomentsDraft();
    _textController.addListener(_saveDraft);
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_saveDraft)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveDraft() {
    widget.controller.writeMomentsDraft(_textController.text);
    setState(() {});
  }

  bool get _canPublish =>
      !_publishing &&
      (_textController.text.trim().isNotEmpty || _media.isNotEmpty);

  Future<void> _pick(String type) async {
    if (_publishing) {
      return;
    }
    if (type == 'video' && _media.isNotEmpty) {
      _showMomentMessage(context, '视频不能和图片同时发布', error: true);
      return;
    }
    if (type == 'image' && _media.any((item) => item.mediaType == 'video')) {
      _showMomentMessage(context, '已选择视频，不能继续添加图片', error: true);
      return;
    }
    if (type == 'image' && _media.length >= 9) {
      _showMomentMessage(context, '最多选择9张图片', error: true);
      return;
    }
    final selected = await Navigator.of(context).push<_MomentLocalMedia>(
      MaterialPageRoute(
        builder: (_) => _MomentMediaPickerPage(mediaType: type),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _media = type == 'video'
          ? [selected]
          : [..._media, selected].take(9).toList();
    });
  }

  Future<void> _publish() async {
    if (!_canPublish) {
      return;
    }
    setState(() {
      _publishing = true;
      _error = '';
      _progress = 0;
    });
    try {
      final uploaded = <Map<String, Object?>>[];
      for (var i = 0; i < _media.length; i++) {
        final item = _media[i];
        final data = await widget.controller.uploadMomentMedia(
          filePath: item.filePath,
          mediaType: item.mediaType,
          name: item.name,
          mime: item.mime,
          size: item.size,
          width: item.width,
          height: item.height,
          duration: item.duration,
          onUploadProgress: (value) {
            if (!mounted) {
              return;
            }
            setState(() {
              _progress = ((i + value) / _media.length).clamp(0, 1).toDouble();
            });
          },
        );
        final media = _mapValue(data, ['media']);
        if (media.isEmpty) {
          throw ApiException('媒体上传失败');
        }
        uploaded.add(media);
      }
      final result = await widget.controller.publishMoment(
        content: _textController.text.trim(),
        mediaJson: jsonEncode(uploaded),
      );
      if (!mounted) {
        return;
      }
      widget.controller.clearMomentsDraft();
      Navigator.of(context).pop(result);
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'publish failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _publishing = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _momentsSurface,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _momentsSurface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _momentsSurface,
        appBar: BimTopBar(
          title: '发表朋友圈',
          actions: [
            TextButton(
              onPressed: _canPublish ? _publish : null,
              child: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发表'),
            ),
          ],
        ),
        body: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottom),
            child: Column(
              children: [
                if (_publishing)
                  LinearProgressIndicator(
                    value: _media.isEmpty ? null : _progress,
                    minHeight: 2,
                    backgroundColor: _momentsFill,
                    color: _momentsPrimary,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        enabled: !_publishing,
                        maxLines: null,
                        minLines: 6,
                        maxLength: 2000,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: '这一刻的想法...',
                          border: InputBorder.none,
                          counterText: '',
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: _momentsText,
                          fontSize: 17,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ComposerMediaGrid(
                        media: _media,
                        publishing: _publishing,
                        onAddImage: () => _pick('image'),
                        onAddVideo: () => _pick('video'),
                        onRemove: (item) => setState(
                          () => _media = _media
                              .where((media) => media != item)
                              .toList(),
                        ),
                      ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error,
                          style: const TextStyle(
                            color: Color(0xffc0392b),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
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
