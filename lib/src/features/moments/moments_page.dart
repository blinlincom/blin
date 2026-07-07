import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../app/session_controller.dart';
import '../../core/app_config.dart';
import '../../core/app_logger.dart';
import '../../core/models.dart';

const _momentsPageColor = Color(0xfff5f6f8);
const _momentsSurface = Color(0xffffffff);
const _momentsText = Color(0xff202124);
const _momentsSecondary = Color(0xff687282);
const _momentsMuted = Color(0xff9aa0aa);
const _momentsBorder = Color(0xffe7e8ec);
const _momentsFill = Color(0xfff1f2f5);
const _momentsPrimary = Color(0xff1677ff);
const _momentsLike = Color(0xff526996);

class MomentsPage extends StatefulWidget {
  const MomentsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, Object?>> _posts = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String _error = '';
  int _page = 1;
  int _pageCount = 1;

  @override
  void initState() {
    super.initState();
    _posts = widget.controller.cachedMomentsFeed();
    _loading = _posts.isEmpty;
    _scrollController.addListener(_onScroll);
    unawaited(_loadFirst(showLoading: _posts.isEmpty));
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading || _refreshing || _page >= _pageCount) {
      return;
    }
    if (_scrollController.position.extentAfter < 520) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFirst({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final data = await widget.controller.loadMomentsFeed(page: 1);
      final posts = _listFromPayload(data);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
        _page = _intValue(data, ['current_number'], fallback: 1);
        _pageCount = _intValue(data, ['pagecount'], fallback: 1);
        _loading = false;
        _refreshing = false;
        _error = '';
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'load first feed failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    await _loadFirst(showLoading: false);
  }

  Future<void> _loadMore() async {
    if (_page >= _pageCount) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final data = await widget.controller.loadMomentsFeed(page: nextPage);
      final posts = _listFromPayload(data);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = [..._posts, ...posts];
        _page = _intValue(data, ['current_number'], fallback: nextPage);
        _pageCount = _intValue(data, ['pagecount'], fallback: _pageCount);
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'moments',
        'load more feed failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
      if (mounted) {
        setState(() => _loadingMore = false);
        _showMomentMessage(context, error.toString(), error: true);
      }
    }
  }

  Future<void> _openComposer() async {
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => MomentComposerPage(controller: widget.controller),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final post = _mapValue(result, ['post'], fallback: result);
    if (post.isEmpty) {
      await _loadFirst(showLoading: false);
      return;
    }
    setState(() {
      _posts = [
        post,
        ..._posts.where(
          (item) =>
              _intValue(item, ['post_id', 'id']) !=
              _intValue(post, ['post_id', 'id']),
        ),
      ];
    });
  }

  void _replacePost(Map<String, Object?> post) {
    final postId = _intValue(post, ['post_id', 'id']);
    if (postId <= 0) {
      return;
    }
    final next = [..._posts];
    final index = next.indexWhere(
      (item) => _intValue(item, ['post_id', 'id']) == postId,
    );
    if (index >= 0) {
      next[index] = post;
    } else {
      next.insert(0, post);
    }
    setState(() => _posts = next);
  }

  Future<void> _toggleLike(Map<String, Object?> post) async {
    final postId = _intValue(post, ['post_id', 'id']);
    if (postId <= 0) {
      return;
    }
    try {
      final data = await widget.controller.likeMoment(
        postId,
        liked: _boolValue(post, ['liked']),
      );
      final updated = _mapValue(data, ['post']);
      if (updated.isNotEmpty && mounted) {
        _replacePost(updated);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'toggle like failed',
        error: error,
        stackTrace: stackTrace,
        data: {'post_id': postId},
      );
      if (mounted) {
        _showMomentMessage(context, error.toString(), error: true);
      }
    }
  }

  Future<void> _comment(
    Map<String, Object?> post, {
    Map<String, Object?> reply = const {},
  }) async {
    final text = await _openMomentCommentSheet(
      context,
      replyName: _displayName(_mapValue(reply, ['user'])),
    );
    if (text == null || text.trim().isEmpty) {
      return;
    }
    final postId = _intValue(post, ['post_id', 'id']);
    try {
      final data = await widget.controller.commentMoment(
        postId: postId,
        content: text.trim(),
        replyCommentId: _intValue(reply, ['id']),
        replyUserId: _intValue(reply, ['user_id']),
      );
      final updated = _mapValue(data, ['post']);
      if (updated.isNotEmpty && mounted) {
        _replacePost(updated);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'comment failed',
        error: error,
        stackTrace: stackTrace,
        data: {'post_id': postId},
      );
      if (mounted) {
        _showMomentMessage(context, error.toString(), error: true);
      }
    }
  }

  Future<void> _deletePost(Map<String, Object?> post) async {
    final postId = _intValue(post, ['post_id', 'id']);
    final confirmed = await _confirmMomentAction(
      context,
      title: '删除这条朋友圈？',
      content: '删除后自己和好友都无法再看到。',
      confirmText: '删除',
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteMoment(postId);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = _posts
            .where((item) => _intValue(item, ['post_id', 'id']) != postId)
            .toList(growable: false);
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'delete post failed',
        error: error,
        stackTrace: stackTrace,
        data: {'post_id': postId},
      );
      if (mounted) {
        _showMomentMessage(context, error.toString(), error: true);
      }
    }
  }

  Future<void> _deleteComment(
    Map<String, Object?> post,
    Map<String, Object?> comment,
  ) async {
    final confirmed = await _confirmMomentAction(
      context,
      title: '删除这条评论？',
      content: '删除后该评论不会继续显示。',
      confirmText: '删除',
    );
    if (!confirmed) {
      return;
    }
    final commentId = _intValue(comment, ['id']);
    try {
      final data = await widget.controller.deleteMomentComment(commentId);
      final updated = _mapValue(data, ['post']);
      if (updated.isNotEmpty && mounted) {
        _replacePost(updated);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'delete comment failed',
        error: error,
        stackTrace: stackTrace,
        data: {'comment_id': commentId},
      );
      if (mounted) {
        _showMomentMessage(context, error.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session;
    return Scaffold(
      backgroundColor: _momentsPageColor,
      appBar: AppBar(
        title: const Text('朋友圈'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _momentsSurface,
        foregroundColor: _momentsText,
        actions: [
          IconButton(
            tooltip: '发表',
            onPressed: _openComposer,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 0,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MomentHeader(
                name: _sessionName(
                  session?.nickname ?? '',
                  session?.username ?? '',
                ),
                avatarUrl: session?.avatar ?? '',
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _MomentLoadingState(),
              )
            else if (_error.isNotEmpty && _posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _MomentErrorState(
                  error: _error,
                  onRetry: () => _loadFirst(),
                ),
              )
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _MomentEmptyState(),
              )
            else
              SliverList.builder(
                itemCount: _posts.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _posts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final post = _posts[index];
                  return _MomentPostTile(
                    key: ValueKey(_intValue(post, ['post_id', 'id'])),
                    post: post,
                    onLike: () => _toggleLike(post),
                    onComment: () => _comment(post),
                    onReply: (comment) => _comment(post, reply: comment),
                    onDeletePost: () => _deletePost(post),
                    onDeleteComment: (comment) => _deleteComment(post, comment),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _momentsSurface,
      appBar: AppBar(
        title: const Text('发表朋友圈'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _momentsSurface,
        foregroundColor: _momentsText,
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
    );
  }
}

class _MomentHeader extends StatelessWidget {
  const _MomentHeader({required this.name, required this.avatarUrl});

  final String name;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          Container(
            height: 194,
            color: const Color(0xffcfd5de),
            alignment: Alignment.bottomRight,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 34),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 154,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                color: _momentsSurface,
              ),
              clipBehavior: Clip.antiAlias,
              child: _MomentAvatar(label: name, imageUrl: avatarUrl, size: 66),
            ),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MomentAvatar(
              label: _displayName(user),
              imageUrl: _textValue(user, ['usertx', 'avatar']),
              size: 44,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _momentsBorder)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
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
                        const SizedBox(height: 6),
                        Text(
                          _textValue(post, ['content']),
                          style: const TextStyle(
                            color: _momentsText,
                            fontSize: 15.5,
                            height: 1.42,
                          ),
                        ),
                      ],
                      if (media.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _MomentMediaGrid(media: media),
                      ],
                      const SizedBox(height: 9),
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
                        const SizedBox(height: 8),
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
    return DecoratedBox(
      decoration: const BoxDecoration(color: _momentsFill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmallTextAction(
            icon: liked ? Icons.favorite : Icons.favorite_border,
            label: liked ? '取消' : '赞',
            onTap: onLike,
          ),
          Container(width: 1, height: 18, color: _momentsBorder),
          _SmallTextAction(
            icon: Icons.mode_comment_outlined,
            label: '评论',
            onTap: onComment,
          ),
        ],
      ),
    );
  }
}

class _SmallTextAction extends StatelessWidget {
  const _SmallTextAction({
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
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: _momentsLike),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: _momentsLike,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
              padding: EdgeInsets.symmetric(vertical: 5),
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
                padding: const EdgeInsets.symmetric(vertical: 2),
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
      style: const TextStyle(color: _momentsText, fontSize: 13.5, height: 1.35),
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
    final url = _mediaUrl(_textValue(media, ['url', 'image_url', 'video_url']));
    final thumb = _mediaUrl(_textValue(media, ['thumb_url', 'cover_url']));
    return GestureDetector(
      onTap: () => _openMomentMediaViewer(context, media),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: const Color(0xffdfe3e8),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if ((isVideo ? thumb : url).isNotEmpty)
                  Image.network(
                    isVideo && thumb.isNotEmpty ? thumb : url,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        _MomentMediaFallback(isVideo: isVideo),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : _MomentMediaFallback(isVideo: isVideo),
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
  final maxWidth = availableWidth.clamp(150, isVideo ? 292 : 256).toDouble();
  final maxHeight = (viewport.height * 0.34)
      .clamp(180, isVideo ? 240 : 280)
      .toDouble();
  final ratio = _momentMediaAspectRatio(media, isVideo: isVideo);
  var width = maxWidth;
  var height = width / ratio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  return Size(width.clamp(120, maxWidth).toDouble(), height);
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
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
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
      color: const Color(0xffdfe3e8),
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
            color: const Color(0xffdde2e8),
            child: item.mediaType == 'image'
                ? Image.file(File(item.filePath), fit: BoxFit.cover)
                : const Icon(
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
                  color: const Color(0x99000000),
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

class _MomentMediaPickerPage extends StatefulWidget {
  const _MomentMediaPickerPage({required this.mediaType});

  final String mediaType;

  @override
  State<_MomentMediaPickerPage> createState() => _MomentMediaPickerPageState();
}

class _MomentMediaPickerPageState extends State<_MomentMediaPickerPage> {
  static const _pageSize = 120;

  final ScrollController _controller = ScrollController();
  List<AssetEntity> _assets = const [];
  AssetEntity? _selected;
  bool _loading = true;
  bool _selecting = false;
  String _error = '';

  bool get _isVideo => widget.mediaType == 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        setState(() {
          _loading = false;
          _error = '需要授权访问相册';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _isVideo ? RequestType.video : RequestType.image,
        hasAll: true,
      );
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _assets = const [];
        });
        return;
      }
      final album = albums.firstWhere(
        (item) => item.isAll,
        orElse: () => albums.first,
      );
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'load picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '媒体读取失败';
        });
      }
    }
  }

  Future<void> _confirm() async {
    final selected = _selected;
    if (selected == null || _selecting) {
      return;
    }
    setState(() => _selecting = true);
    try {
      final file = await selected.originFile ?? await selected.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('media file unavailable');
      }
      final stat = await file.stat();
      final title = await selected.titleAsync;
      final media = _MomentLocalMedia(
        filePath: file.path,
        mediaType: widget.mediaType,
        name: title.isNotEmpty ? title : _fileName(file.path),
        mime: selected.mimeType ?? '',
        size: stat.size,
        width: selected.width,
        height: selected.height,
        duration: selected.duration,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(media);
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'select media failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _selecting = false);
        _showMomentMessage(context, '媒体读取失败', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _momentsSurface,
      appBar: AppBar(
        title: Text(_isVideo ? '选择视频' : '选择图片'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _momentsSurface,
        foregroundColor: _momentsText,
        actions: [
          TextButton(
            onPressed: _selected == null || _selecting ? null : _confirm,
            child: _selecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确定'),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error.isNotEmpty
            ? _MomentErrorState(error: _error, onRetry: _load)
            : _assets.isEmpty
            ? Center(child: Text(_isVideo ? '没有可选择的视频' : '没有可选择的图片'))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 6 : 4;
                  return GridView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.all(4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      final selected = _selected?.id == asset.id;
                      return _PickerAssetTile(
                        asset: asset,
                        selected: selected,
                        isVideo: _isVideo,
                        onTap: () => setState(() => _selected = asset),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _PickerAssetTile extends StatelessWidget {
  const _PickerAssetTile({
    required this.asset,
    required this.selected,
    required this.isVideo,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final bool isVideo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return const ColoredBox(color: Color(0xffdde2e8));
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          ),
          if (isVideo)
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 32,
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _momentsPrimary : const Color(0x66000000),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentAvatar extends StatelessWidget {
  const _MomentAvatar({
    required this.label,
    required this.imageUrl,
    required this.size,
  });

  final String label;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _avatarUrl(imageUrl);
    final fallback = ColoredBox(
      color: const Color(0xff8e99a8),
      child: Center(
        child: Text(
          _avatarInitial(label),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.34,
          ),
        ),
      ),
    );
    if (url.isEmpty) {
      return SizedBox(width: size, height: size, child: fallback);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _MomentLoadingState extends StatelessWidget {
  const _MomentLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _MomentErrorState extends StatelessWidget {
  const _MomentErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _momentsSecondary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _MomentEmptyState extends StatelessWidget {
  const _MomentEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '暂无朋友圈动态',
        style: TextStyle(color: _momentsSecondary, fontSize: 14),
      ),
    );
  }
}

class _MomentLocalMedia {
  const _MomentLocalMedia({
    required this.filePath,
    required this.mediaType,
    required this.name,
    required this.mime,
    required this.size,
    required this.width,
    required this.height,
    required this.duration,
  });

  final String filePath;
  final String mediaType;
  final String name;
  final String mime;
  final int size;
  final int width;
  final int height;
  final int duration;
}

class _MomentVideoViewer extends StatefulWidget {
  const _MomentVideoViewer({required this.url});

  final String url;

  @override
  State<_MomentVideoViewer> createState() => _MomentVideoViewerState();
}

class _MomentVideoViewerState extends State<_MomentVideoViewer> {
  VideoPlayerController? _controller;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'video viewer init failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = '视频播放失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: _error.isNotEmpty
              ? Text(_error, style: const TextStyle(color: Colors.white70))
              : controller == null
              ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final ratio = controller.value.aspectRatio
                        .clamp(0.56, 16 / 9)
                        .toDouble();
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: VideoPlayer(controller),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              elevation: 0,
              backgroundColor: const Color(0x66000000),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
              child: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
    );
  }
}

Future<String?> _openMomentCommentSheet(
  BuildContext context, {
  String replyName = '',
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _momentsSurface,
    builder: (context) {
      final bottom = MediaQuery.viewInsetsOf(context).bottom;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: replyName.isEmpty ? '评论' : '回复 $replyName',
                      filled: true,
                      fillColor: _momentsFill,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

Future<bool> _confirmMomentAction(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result == true;
}

void _openMomentMediaViewer(BuildContext context, Map<String, Object?> media) {
  final url = _mediaUrl(_textValue(media, ['url', 'image_url', 'video_url']));
  if (url.isEmpty) {
    return;
  }
  if (_isMomentVideo(media)) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _MomentVideoViewer(url: url)),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _MomentMediaViewerScaffold(url: url),
    ),
  );
}

void _showMomentMessage(
  BuildContext context,
  String text, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xffb42318) : null,
      duration: const Duration(seconds: 2),
    ),
  );
}

List<Map<String, Object?>> _listFromPayload(Map<String, Object?> data) {
  return _listFromValue(
    data['list'] ?? data['items'] ?? data['rows'] ?? data['records'],
  );
}

List<Map<String, Object?>> _listFromValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    value = decoded;
  }
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

Map<String, Object?> _mapValue(
  Map<String, Object?> source,
  List<String> keys, {
  Map<String, Object?> fallback = const {},
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
  }
  return fallback;
}

String _textValue(Map<String, Object?> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key]?.toString() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

int _intValue(
  Map<String, Object?> source,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is int) {
      return value;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback;
}

double _doubleValue(
  Map<String, Object?> source,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) {
      return value.toDouble();
    }
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback;
}

bool _boolValue(Map<String, Object?> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is bool) {
      return value;
    }
    final text = value?.toString().toLowerCase() ?? '';
    if (text == '1' || text == 'true' || text == 'yes') {
      return true;
    }
    if (text == '0' || text == 'false' || text == 'no') {
      return false;
    }
  }
  return false;
}

String _displayName(Map<String, Object?> user) {
  return _textValue(user, ['nickname', 'username', 'name']);
}

String _sessionName(String nickname, String username) {
  return nickname.trim().isNotEmpty ? nickname.trim() : username.trim();
}

String _avatarInitial(String label) {
  final text = label.trim();
  if (text.isEmpty) {
    return 'B';
  }
  return text.characters.first.toUpperCase();
}

String _avatarUrl(String value) {
  return _absoluteUrl(value);
}

String _mediaUrl(String value) {
  return _absoluteUrl(value);
}

String _absoluteUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  if (text.startsWith('http://') || text.startsWith('https://')) {
    return text;
  }
  if (text.startsWith('//')) {
    return 'https:$text';
  }
  final base = Uri.parse(AppConfig.apiBaseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  if (text.startsWith('/')) {
    return '$origin$text';
  }
  return '$origin/$text';
}

String _momentTime(String value) {
  final time = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (time == null) {
    return value;
  }
  final now = DateTime.now();
  final local = time.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (sameDay) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == local.year &&
      yesterday.month == local.month &&
      yesterday.day == local.day) {
    return '昨天';
  }
  if (now.year == local.year) {
    return '${local.month}月${local.day}日';
  }
  return '${local.year}年${local.month}月${local.day}日';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index >= 0 ? normalized.substring(index + 1) : normalized;
}
