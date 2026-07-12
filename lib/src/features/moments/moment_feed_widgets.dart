part of 'moments_page.dart';

class _MomentHeader extends StatelessWidget {
  const _MomentHeader({
    required this.name,
    required this.avatarUrl,
    required this.backgroundUrl,
    required this.onCoverTap,
  });

  final String name;
  final String avatarUrl;
  final String backgroundUrl;
  final VoidCallback onCoverTap;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final coverHeight = viewport.height
        .clamp(640, 920)
        .toDouble()
        .lerp(292, 362, inverse: true);
    final avatarSize = viewport.width < 360 ? 68.0 : 76.0;
    return SizedBox(
      height: coverHeight + 82,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: coverHeight,
            child: const ColoredBox(color: _momentsSurface),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCoverTap,
            child: _MomentCoverImage(
              imageUrl: backgroundUrl,
              height: coverHeight,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x4d000000),
                      Color(0x0d000000),
                      Color(0x59000000),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 16,
            top: coverHeight - avatarSize * 0.5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(top: avatarSize * 0.12),
                    child: Text(
                      name.isEmpty ? 'BIM' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2.5),
                    color: _momentsSurface,
                    borderRadius: BorderRadius.circular(
                      _momentAvatarRadius(avatarSize),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _MomentAvatar(
                    label: name,
                    imageUrl: avatarUrl,
                    size: avatarSize - 5,
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

extension _MomentDoubleLerp on double {
  double lerp(double min, double max, {bool inverse = false}) {
    final t = ((this - 640) / (920 - 640)).clamp(0, 1).toDouble();
    return min + (max - min) * (inverse ? t : 1 - t);
  }
}

class _MomentCoverImage extends StatelessWidget {
  const _MomentCoverImage({
    required this.imageUrl,
    required this.height,
    required this.child,
  });

  final String imageUrl;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final url = _mediaUrl(imageUrl);
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => const _MomentCoverFallback(),
            errorWidget: (_, __, ___) => const _MomentCoverFallback(),
          )
        else
          const _MomentCoverFallback(),
        const DecoratedBox(decoration: BoxDecoration(color: Color(0x33000000))),
        child,
      ],
    );
    if (height.isInfinite) {
      return SizedBox.expand(child: content);
    }
    return SizedBox(height: height, width: double.infinity, child: content);
  }
}

class _MomentCoverFallback extends StatelessWidget {
  const _MomentCoverFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xff9aa3af),
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 34),
          child: Icon(Icons.image_outlined, color: Color(0x66ffffff), size: 34),
        ),
      ),
    );
  }
}

class _MomentCoverPreviewPage extends StatefulWidget {
  const _MomentCoverPreviewPage({
    required this.imageUrl,
    required this.onChangeCover,
  });

  final String imageUrl;
  final Future<String?> Function(ValueChanged<double> onProgress) onChangeCover;

  @override
  State<_MomentCoverPreviewPage> createState() =>
      _MomentCoverPreviewPageState();
}

class _MomentCoverPreviewPageState extends State<_MomentCoverPreviewPage> {
  late String _imageUrl = widget.imageUrl;
  bool _changing = false;
  double _progress = 0;

  Future<void> _changeCover() async {
    if (_changing) {
      return;
    }
    setState(() {
      _changing = true;
      _progress = 0;
    });
    final nextUrl = await widget.onChangeCover((value) {
      if (!mounted) {
        return;
      }
      setState(() => _progress = value.clamp(0, 1).toDouble());
    });
    if (!mounted) {
      return;
    }
    setState(() {
      if (nextUrl != null && nextUrl.isNotEmpty) {
        _imageUrl = nextUrl;
      }
      _changing = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overlayStyle = const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: overlayStyle,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _MomentCoverImage(
              imageUrl: _imageUrl,
              height: double.infinity,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x73000000),
                      Color(0x22000000),
                      Color(0xcc000000),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 22, 34),
                  child: InkWell(
                    onTap: _changing ? null : _changeCover,
                    child: SizedBox(
                      width: 84,
                      height: 64,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_changing)
                            SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                value: _progress <= 0 ? null : _progress,
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          else
                            const Icon(
                              Icons.image_outlined,
                              color: Colors.white,
                              size: 30,
                            ),
                          const SizedBox(height: 6),
                          Text(
                            _changing ? '上传中' : '换封面',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _MomentPostTile extends StatelessWidget {
  const _MomentPostTile({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onReply,
    required this.onDeletePost,
    required this.onDeleteComment,
    super.key,
  });

  final Map<String, Object?> post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final ValueChanged<Map<String, Object?>> onReply;
  final VoidCallback onDeletePost;
  final ValueChanged<Map<String, Object?>> onDeleteComment;

  @override
  Widget build(BuildContext context) {
    final user = _mapValue(post, ['user']);
    final media = _listFromValue(post['media']);
    final comments = _listFromValue(post['comments']);
    final likes = _listFromValue(post['likes']);
    final liked = _boolValue(post, ['liked']);
    return ColoredBox(
      color: _momentsSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MomentAvatar(
              label: _displayName(user),
              imageUrl: _textValue(user, ['usertx', 'avatar']),
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _momentsBorder)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _momentsLike,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_textValue(post, ['content']).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _textValue(post, ['content']),
                          style: const TextStyle(
                            color: _momentsText,
                            fontSize: 15.5,
                            height: 1.38,
                          ),
                        ),
                      ],
                      if (media.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _MomentMediaGrid(media: media),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Text(
                            _momentTime(_textValue(post, ['create_time'])),
                            style: const TextStyle(
                              color: _momentsMuted,
                              fontSize: 12,
                            ),
                          ),
                          if (_boolValue(post, ['can_delete'])) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: onDeletePost,
                              child: const Text(
                                '删除',
                                style: TextStyle(
                                  color: _momentsLike,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          _MomentActionButton(
                            liked: liked,
                            onLike: onLike,
                            onComment: onComment,
                          ),
                        ],
                      ),
                      if (likes.isNotEmpty || comments.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _MomentSocialPanel(
                          likes: likes,
                          comments: comments,
                          onReply: onReply,
                          onDeleteComment: onDeleteComment,
                        ),
                      ],
                    ],
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

class _MomentActionButton extends StatelessWidget {
  const _MomentActionButton({
    required this.liked,
    required this.onLike,
    required this.onComment,
  });

  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      elevation: 0,
      color: const Color(0xff303644),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'like') {
          onLike();
          return;
        }
        if (value == 'comment') {
          onComment();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'like',
          child: _MomentPopupAction(
            icon: liked ? Icons.favorite : Icons.favorite_border,
            label: liked ? '取消' : '赞',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'comment',
          child: _MomentPopupAction(
            icon: Icons.mode_comment_outlined,
            label: '评论',
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 28,
        alignment: Alignment.center,
        color: _momentsFill,
        child: const Icon(Icons.more_horiz, size: 21, color: _momentsLike),
      ),
    );
  }
}

class _MomentPopupAction extends StatelessWidget {
  const _MomentPopupAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentSocialPanel extends StatelessWidget {
  const _MomentSocialPanel({
    required this.likes,
    required this.comments,
    required this.onReply,
    required this.onDeleteComment,
  });

  final List<Map<String, Object?>> likes;
  final List<Map<String, Object?>> comments;
  final ValueChanged<Map<String, Object?>> onReply;
  final ValueChanged<Map<String, Object?>> onDeleteComment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _momentsFill,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (likes.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite, size: 15, color: _momentsLike),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    likes
                        .map((item) => _displayName(_mapValue(item, ['user'])))
                        .join('、'),
                    style: const TextStyle(
                      color: _momentsLike,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (likes.isNotEmpty && comments.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1, color: _momentsBorder),
            ),
          for (final comment in comments)
            GestureDetector(
              onTap: () => onReply(comment),
              onLongPress: _boolValue(comment, ['can_delete'])
                  ? () => onDeleteComment(comment)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: _MomentCommentText(comment: comment),
              ),
            ),
        ],
      ),
    );
  }
}

class _MomentCommentText extends StatelessWidget {
  const _MomentCommentText({required this.comment});

  final Map<String, Object?> comment;

  @override
  Widget build(BuildContext context) {
    final user = _mapValue(comment, ['user']);
    final reply = _mapValue(comment, ['reply_user']);
    final hasReply = reply.isNotEmpty && _displayName(reply).isNotEmpty;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _displayName(user),
            style: const TextStyle(
              color: _momentsLike,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasReply) ...[
            const TextSpan(text: ' 回复 '),
            TextSpan(
              text: _displayName(reply),
              style: const TextStyle(
                color: _momentsLike,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          TextSpan(text: '：${_textValue(comment, ['content'])}'),
        ],
      ),
      style: const TextStyle(color: _momentsText, fontSize: 13.2, height: 1.32),
    );
  }
}

class _MomentMediaGrid extends StatelessWidget {
  const _MomentMediaGrid({required this.media});

  final List<Map<String, Object?>> media;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width - 78;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        if (media.length == 1) {
          final size = _singleMomentMediaSize(
            context,
            media.first,
            availableWidth,
          );
          return _MomentMediaTile(
            media: media.first,
            width: size.width,
            height: size.height,
          );
        }

        final spacing = 4.0;
        final columns = media.length == 2 || media.length == 4 ? 2 : 3;
        final gridWidth = availableWidth
            .clamp(160, columns * 106 + (columns - 1) * spacing)
            .toDouble();
        final tile = ((gridWidth - (columns - 1) * spacing) / columns)
            .clamp(72, 106)
            .toDouble();
        return SizedBox(
          width: columns * tile + (columns - 1) * spacing,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in media)
                _MomentMediaTile(media: item, width: tile, height: tile),
            ],
          ),
        );
      },
    );
  }
}

class _MomentMediaTile extends StatelessWidget {
  const _MomentMediaTile({
    required this.media,
    required this.width,
    required this.height,
  });

  final Map<String, Object?> media;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isVideo = _isMomentVideo(media);
    final url = _momentMediaSourceUrl(media);
    final thumb = _momentMediaCoverUrl(media);
    return GestureDetector(
      onTap: () => _openMomentMediaViewer(context, media),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: BimColors.mediaPlaceholder,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo)
                  _MomentVideoFramePreview(
                    videoUrl: url,
                    coverUrl: thumb,
                    fallback: const _MomentMediaFallback(isVideo: true),
                  )
                else if (url.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, __, ___) =>
                        const _MomentMediaFallback(isVideo: false),
                    placeholder: (_, _) =>
                        const _MomentMediaFallback(isVideo: false),
                  )
                else
                  _MomentMediaFallback(isVideo: isVideo),
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 42,
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

Size _singleMomentMediaSize(
  BuildContext context,
  Map<String, Object?> media,
  double availableWidth,
) {
  final isVideo = _isMomentVideo(media);
  final viewport = MediaQuery.sizeOf(context);
  final maxWidth = availableWidth.clamp(140, isVideo ? 260 : 236).toDouble();
  final maxHeight = (viewport.height * 0.28)
      .clamp(150, isVideo ? 206 : 236)
      .toDouble();
  final ratio = _momentMediaAspectRatio(media, isVideo: isVideo);
  var width = maxWidth;
  var height = width / ratio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  return Size(width.clamp(112, maxWidth).toDouble(), height);
}

double _momentMediaAspectRatio(
  Map<String, Object?> media, {
  required bool isVideo,
}) {
  final width = _doubleValue(media, [
    'width',
    'media_width',
    'image_width',
    'video_width',
    'w',
  ]);
  final height = _doubleValue(media, [
    'height',
    'media_height',
    'image_height',
    'video_height',
    'h',
  ]);
  final fallback = isVideo ? 16 / 9 : 1.0;
  if (width <= 0 || height <= 0) {
    return fallback;
  }
  final ratio = width / height;
  final minRatio = isVideo ? 1.0 : 0.68;
  final maxRatio = isVideo ? 16 / 9 : 1.78;
  return ratio.clamp(minRatio, maxRatio).toDouble();
}

bool _isMomentVideo(Map<String, Object?> media) {
  final type = _textValue(media, ['type', 'media_type']).toLowerCase();
  if (type == 'video' || type == 'videos') {
    return true;
  }
  final mime = _textValue(media, ['mime', 'mime_type']).toLowerCase();
  if (mime.startsWith('video/')) {
    return true;
  }
  final url = _textValue(media, ['url', 'video_url', 'file_url']).toLowerCase();
  return url.endsWith('.mp4') ||
      url.endsWith('.mov') ||
      url.endsWith('.m4v') ||
      url.endsWith('.webm');
}

class _MomentMediaViewerScaffold extends StatelessWidget {
  const _MomentMediaViewerScaffold({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MomentMediaFallback extends StatelessWidget {
  const _MomentMediaFallback({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BimColors.mediaPlaceholder,
      child: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: _momentsMuted,
      ),
    );
  }
}

class _ComposerMediaGrid extends StatelessWidget {
  const _ComposerMediaGrid({
    required this.media,
    required this.publishing,
    required this.onAddImage,
    required this.onAddVideo,
    required this.onRemove,
  });

  final List<_MomentLocalMedia> media;
  final bool publishing;
  final VoidCallback onAddImage;
  final VoidCallback onAddVideo;
  final ValueChanged<_MomentLocalMedia> onRemove;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 32;
    final tile = ((width - 12) / 3).clamp(86, 116).toDouble();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in media)
          _ComposerMediaTile(
            item: item,
            size: tile,
            publishing: publishing,
            onRemove: () => onRemove(item),
          ),
        if (!publishing &&
            media.length < 9 &&
            !media.any((item) => item.mediaType == 'video'))
          _ComposerAddTile(
            size: tile,
            icon: Icons.image_outlined,
            label: '图片',
            onTap: onAddImage,
          ),
        if (!publishing && media.isEmpty)
          _ComposerAddTile(
            size: tile,
            icon: Icons.videocam_outlined,
            label: '视频',
            onTap: onAddVideo,
          ),
      ],
    );
  }
}

class _ComposerMediaTile extends StatelessWidget {
  const _ComposerMediaTile({
    required this.item,
    required this.size,
    required this.publishing,
    required this.onRemove,
  });

  final _MomentLocalMedia item;
  final double size;
  final bool publishing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: BimColors.mediaPlaceholder,
            child: item.mediaType == 'image'
                ? Image.file(File(item.filePath), fit: BoxFit.cover)
                : _MomentVideoFramePreview(
                    filePath: item.filePath,
                    fallback: const _MomentMediaFallback(isVideo: true),
                  ),
          ),
          if (item.mediaType == 'video')
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 42,
                color: Colors.white,
              ),
            ),
          if (!publishing)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  width: 28,
                  height: 28,
                  color: BimColors.scrimStrong,
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComposerAddTile extends StatelessWidget {
  const _ComposerAddTile({
    required this.size,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        color: _momentsFill,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _momentsSecondary, size: 30),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: _momentsSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
