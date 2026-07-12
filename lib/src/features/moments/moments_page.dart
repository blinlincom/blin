import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../app/session_controller.dart';
import '../../core/app_config.dart';
import '../../core/app_logger.dart';
import '../../core/design_tokens.dart';
import '../../core/models.dart';
import '../../ui/bim_ui.dart';
part 'moment_composer_page.dart';
part 'moment_feed_widgets.dart';
part 'moment_media_pages.dart';

const _momentsPageColor = BimColors.background;
const _momentsSurface = BimColors.surface;
const _momentsText = BimColors.text;
const _momentsSecondary = BimColors.secondaryText;
const _momentsMuted = BimColors.mutedText;
const _momentsBorder = BimColors.border;
const _momentsFill = BimColors.fill;
const _momentsPrimary = BimColors.primary;
const _momentsLike = BimColors.momentsAction;

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
  bool _appBarOnCover = true;
  bool _coverUploading = false;
  String _error = '';
  String _profileBackgroundUrl = '';
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
    _syncAppBarStyle();
    if (_loadingMore || _loading || _refreshing || _page >= _pageCount) {
      return;
    }
    if (_scrollController.position.extentAfter < 520) {
      unawaited(_loadMore());
    }
  }

  void _syncAppBarStyle() {
    if (!_scrollController.hasClients) {
      return;
    }
    final onCover = _scrollController.offset < 220;
    if (onCover != _appBarOnCover && mounted) {
      setState(() => _appBarOnCover = onCover);
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
        _profileBackgroundUrl = _momentProfileBackground(data);
        _page = _intValue(data, ['current_number'], fallback: 1);
        _pageCount = _intValue(data, ['pagecount'], fallback: 1);
        _loading = false;
        _refreshing = false;
        _error = '';
      });
      _cacheCurrentFeed();
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
      _cacheCurrentFeed();
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
    _cacheCurrentFeed();
  }

  Future<void> _openCoverPreview(String imageUrl) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MomentCoverPreviewPage(
          imageUrl: imageUrl,
          onChangeCover: _pickAndUploadCover,
        ),
      ),
    );
  }

  Future<String?> _pickAndUploadCover(ValueChanged<double> onProgress) async {
    if (_coverUploading) {
      return null;
    }
    final selected = await Navigator.of(context).push<_MomentLocalMedia>(
      MaterialPageRoute(
        builder: (_) => const _MomentMediaPickerPage(mediaType: 'image'),
      ),
    );
    if (selected == null || !mounted) {
      return null;
    }
    setState(() => _coverUploading = true);
    onProgress(0);
    try {
      final data = await widget.controller.uploadProfileBackground(
        filePath: selected.filePath,
        onUploadProgress: onProgress,
      );
      final url = _uploadedProfileBackground(data);
      if (!mounted) {
        return url.isEmpty ? null : url;
      }
      if (url.isEmpty) {
        await _loadFirst(showLoading: false);
        _showMomentMessage(context, '封面已提交审核');
        return null;
      }
      setState(() => _profileBackgroundUrl = url);
      _showMomentMessage(context, '封面已更新');
      return url;
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'upload profile background failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showMomentMessage(context, error.toString(), error: true);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _coverUploading = false);
      }
    }
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
    _cacheCurrentFeed();
  }

  void _cacheCurrentFeed() {
    widget.controller.writeMomentsFeed(_posts);
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
      _cacheCurrentFeed();
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
    final backgroundUrl = _profileBackgroundUrl.isNotEmpty
        ? _profileBackgroundUrl
        : session?.profileBackground ?? '';
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _appBarOnCover
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: _appBarOnCover ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: _momentsSurface,
      systemNavigationBarIconBrightness: Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: _momentsPageColor,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: AnimatedOpacity(
            opacity: _appBarOnCover ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: const Text('朋友圈'),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: _appBarOnCover
              ? Colors.transparent
              : _momentsSurface,
          foregroundColor: _appBarOnCover ? Colors.white : _momentsText,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          systemOverlayStyle: overlayStyle,
          bottom: _appBarOnCover
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(0.5),
                  child: Divider(height: 0.5, color: _momentsBorder),
                ),
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
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
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
                  backgroundUrl: backgroundUrl,
                  onCoverTap: () => _openCoverPreview(backgroundUrl),
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
                      onDeleteComment: (comment) =>
                          _deleteComment(post, comment),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }
}
