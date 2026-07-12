part of 'package:bim/src/features/home/home_page.dart';

class _IncomingCallStage extends StatelessWidget {
  const _IncomingCallStage({required this.call, required this.statusText});

  final LiveKitCallInfo? call;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final participant = call?.participants.firstOrNullByUserId(call?.creatorId);
    final title = participant?.name ?? call?.title ?? 'BIM';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 54, 24, 150),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CallAvatar(
              label: title,
              imageUrl: participant?.avatar ?? '',
              size: 86,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xffaeb4c0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallWaitingStage extends StatelessWidget {
  const _CallWaitingStage({
    required this.title,
    required this.statusText,
    required this.videoCall,
    this.avatarUrl = '',
  });

  final String title;
  final String statusText;
  final bool videoCall;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 54, 24, 150),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: videoCall
                        ? const Color(0xff66d9ef)
                        : const Color(0xff6ee786),
                    backgroundColor: const Color(0xff232733),
                  ),
                ),
                _CallAvatar(label: title, imageUrl: avatarUrl, size: 76),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: const TextStyle(
                color: Color(0xffaeb4c0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivateCallStage extends StatelessWidget {
  const _PrivateCallStage({
    required this.room,
    required this.call,
    required this.videoCall,
    required this.fallbackProfile,
    required this.localVideoPrimary,
    required this.previewOffset,
    required this.previewDragging,
    required this.onPreviewTap,
    required this.onPreviewDragStart,
    required this.onPreviewDragUpdate,
    required this.onPreviewDragEnd,
  });

  final lk.Room room;
  final LiveKitCallInfo? call;
  final bool videoCall;
  final LiveKitCallParticipant? fallbackProfile;
  final bool localVideoPrimary;
  final Offset? previewOffset;
  final bool previewDragging;
  final VoidCallback onPreviewTap;
  final GestureDragStartCallback onPreviewDragStart;
  final void Function(DragUpdateDetails details, BoxConstraints constraints)
  onPreviewDragUpdate;
  final void Function(DragEndDetails details, BoxConstraints constraints)
  onPreviewDragEnd;

  @override
  Widget build(BuildContext context) {
    final remote = room.remoteParticipants.values.isEmpty
        ? null
        : room.remoteParticipants.values.first;
    final local = room.localParticipant;
    if (!videoCall) {
      final profile =
          _participantProfile(call, remote?.identity) ?? fallbackProfile;
      final title = _participantDisplayName(
        remote,
        profile,
        fallback: call?.title ?? '语音通话',
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 62, 24, 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CallAvatar(
                label: title,
                imageUrl: profile?.avatar ?? '',
                size: 96,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                remote == null ? '等待对方加入' : '语音通话中',
                style: const TextStyle(color: Color(0xffaeb4c0), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _callPreviewSizeFor(constraints);
        final offset =
            previewOffset ?? _defaultCallPreviewOffset(context, constraints);
        final lk.Participant? mainParticipant = localVideoPrimary
            ? local
            : remote;
        final lk.Participant? smallParticipant = localVideoPrimary
            ? remote
            : local;
        final mainProfile = mainParticipant == null
            ? fallbackProfile
            : _participantProfile(call, mainParticipant.identity);
        return Stack(
          children: [
            Positioned.fill(
              child: mainParticipant == null
                  ? _NoVideoSurface(
                      label: _participantDisplayName(
                        null,
                        mainProfile,
                        fallback: localVideoPrimary ? '本地视频' : '等待对方加入',
                      ),
                      avatar: mainProfile?.avatar ?? '',
                    )
                  : _ParticipantVideoSurface(
                      participant: mainParticipant,
                      profile: mainProfile,
                      fit: lk.VideoViewFit.cover,
                    ),
            ),
            if (smallParticipant != null)
              AnimatedPositioned(
                duration: previewDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 210),
                curve: Curves.easeOutCubic,
                left: offset.dx,
                top: offset.dy,
                width: size.width,
                height: size.height,
                child: _DraggableCallPreview(
                  dragging: previewDragging,
                  onTap: onPreviewTap,
                  onPanStart: onPreviewDragStart,
                  onPanUpdate: (details) =>
                      onPreviewDragUpdate(details, constraints),
                  onPanEnd: (details) => onPreviewDragEnd(details, constraints),
                  child: _ParticipantVideoSurface(
                    participant: smallParticipant,
                    profile: _participantProfile(
                      call,
                      smallParticipant.identity,
                    ),
                    compact: true,
                    fit: lk.VideoViewFit.cover,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ParticipantGridStage extends StatelessWidget {
  const _ParticipantGridStage({
    required this.room,
    required this.call,
    required this.maxWidth,
  });

  final lk.Room room;
  final LiveKitCallInfo? call;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final participants = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    if (participants.isEmpty) {
      return const _NoVideoSurface(label: '正在进入通话');
    }
    final columns = maxWidth >= 720
        ? 3
        : participants.length <= 2
        ? 1
        : 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 72, 8, 126),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
          childAspectRatio: columns == 1 ? 0.86 : 0.78,
        ),
        itemCount: participants.length,
        itemBuilder: (context, index) {
          final participant = participants[index];
          return _ParticipantVideoSurface(
            participant: participant,
            profile: _participantProfile(call, participant.identity),
            compact: participants.length > 4,
          );
        },
      ),
    );
  }
}

class _DraggableCallPreview extends StatelessWidget {
  const _DraggableCallPreview({
    required this.dragging,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.child,
  });

  final bool dragging;
  final VoidCallback onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '切换通话主画面',
      child: GestureDetector(
        onTap: onTap,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: AnimatedScale(
          scale: dragging ? 1.03 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x99ffffff), width: 1),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantVideoSurface extends StatelessWidget {
  const _ParticipantVideoSurface({
    required this.participant,
    required this.profile,
    this.compact = false,
    this.fit = lk.VideoViewFit.cover,
  });

  final lk.Participant participant;
  final LiveKitCallParticipant? profile;
  final bool compact;
  final lk.VideoViewFit fit;

  @override
  Widget build(BuildContext context) {
    final track = _participantVideoTrack(participant);
    final name = _participantDisplayName(participant, profile);
    return ColoredBox(
      color: BimColors.inverseSurface,
      child: Stack(
        children: [
          Positioned.fill(
            child: track == null
                ? _NoVideoSurface(label: name, avatar: profile?.avatar ?? '')
                : lk.VideoTrackRenderer(
                    track,
                    fit: fit,
                    renderMode: lk.VideoRenderMode.auto,
                  ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                Icon(
                  participant.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  size: compact ? 13 : 15,
                  color: participant.isMuted
                      ? const Color(0xffff7b7b)
                      : BimColors.inverseText,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
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

class _NoVideoSurface extends StatelessWidget {
  const _NoVideoSurface({required this.label, this.avatar = ''});

  final String label;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BimColors.inverseSurface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CallAvatar(label: label, imageUrl: avatar, size: 58),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffcbd1dd),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallTopBar extends StatelessWidget {
  const _CallTopBar({
    required this.title,
    required this.subtitle,
    required this.canMinimize,
    required this.onBack,
    required this.onMinimize,
  });

  final String title;
  final String subtitle;
  final bool canMinimize;
  final VoidCallback onBack;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffb4bac6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (canMinimize)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: '缩小通话',
                onPressed: onMinimize,
                icon: const Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DraggableCallMiniWindow extends StatelessWidget {
  const _DraggableCallMiniWindow({
    required this.title,
    required this.subtitle,
    required this.videoCall,
    required this.dragging,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final String title;
  final String subtitle;
  final bool videoCall;
  final bool dragging;
  final VoidCallback onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '恢复通话',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: AnimatedScale(
          scale: dragging ? 1.03 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Container(
            width: _callMiniWindowSize.width,
            height: _callMiniWindowSize.height,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: BimColors.inverseSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33ffffff)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: BimColors.inverseSurfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    videoCall ? Icons.videocam_rounded : Icons.call_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffb6bdc9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
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

class _IncomingCallControls extends StatelessWidget {
  const _IncomingCallControls({
    required this.connecting,
    required this.onAccept,
    required this.onReject,
  });

  final bool connecting;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        30,
        14,
        30,
        max(20, MediaQuery.paddingOf(context).bottom + 12).toDouble(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _RoundCallButton(
            icon: Icons.call_end_rounded,
            label: '拒绝',
            color: BimColors.danger,
            onTap: connecting ? null : onReject,
          ),
          _RoundCallButton(
            icon: connecting ? Icons.more_horiz_rounded : Icons.call_rounded,
            label: connecting ? '接听中' : '接听',
            color: BimColors.success,
            onTap: connecting ? null : onAccept,
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.micEnabled,
    required this.cameraEnabled,
    required this.speakerEnabled,
    required this.videoCall,
    required this.connecting,
    required this.onMic,
    required this.onCamera,
    required this.onSpeaker,
    required this.onSwitchCamera,
    required this.onHangup,
  });

  final bool micEnabled;
  final bool cameraEnabled;
  final bool speakerEnabled;
  final bool videoCall;
  final bool connecting;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    final bottom = max(
      16,
      MediaQuery.paddingOf(context).bottom + 10,
    ).toDouble();
    return ColoredBox(
      color: const Color(0xcc08090c),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundCallButton(
              icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: micEnabled ? '静音' : '取消静音',
              color: BimColors.inverseSurfaceMuted,
              onTap: connecting ? null : onMic,
            ),
            if (videoCall)
              _RoundCallButton(
                icon: cameraEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: cameraEnabled ? '摄像头' : '开摄像头',
                color: BimColors.inverseSurfaceMuted,
                onTap: connecting ? null : onCamera,
              ),
            _RoundCallButton(
              icon: speakerEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: '扬声器',
              color: BimColors.inverseSurfaceMuted,
              onTap: connecting ? null : onSpeaker,
            ),
            if (videoCall)
              _RoundCallButton(
                icon: Icons.cameraswitch_rounded,
                label: '翻转',
                color: BimColors.inverseSurfaceMuted,
                onTap: connecting ? null : onSwitchCamera,
              ),
            _RoundCallButton(
              icon: Icons.call_end_rounded,
              label: '挂断',
              color: BimColors.danger,
              onTap: onHangup,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? color : color.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? BimColors.inverseText : BimColors.mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({
    required this.label,
    required this.imageUrl,
    required this.size,
  });

  final String label;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _normalizeAvatarUrl(imageUrl);
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BimColors.inverseSurfaceMuted,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Text(
        _avatarInitial(label),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

extension _LiveKitCallParticipantList on List<LiveKitCallParticipant> {
  LiveKitCallParticipant? firstOrNullByUserId(int? userId) {
    if (userId == null || userId <= 0) {
      return null;
    }
    for (final item in this) {
      if (item.userId == userId) {
        return item;
      }
    }
    return null;
  }
}

LiveKitCallParticipant? _participantProfile(
  LiveKitCallInfo? call,
  String? identity,
) {
  if (call == null || identity == null || identity.isEmpty) {
    return null;
  }
  for (final participant in call.participants) {
    if (participant.uid == identity ||
        identity.endsWith('user${participant.userId}')) {
      return participant;
    }
  }
  return null;
}

String _participantDisplayName(
  lk.Participant? participant,
  LiveKitCallParticipant? profile, {
  String fallback = 'BIM',
}) {
  final profileName = profile?.name.trim() ?? '';
  if (profileName.isNotEmpty) {
    return profileName;
  }
  final participantName = participant?.name.trim() ?? '';
  if (participantName.isNotEmpty) {
    return participantName;
  }
  final identity = participant?.identity.trim() ?? '';
  if (identity.isNotEmpty) {
    final match = RegExp(r'user(\d+)$').firstMatch(identity);
    return match == null ? identity : '用户${match.group(1)}';
  }
  return fallback;
}

lk.VideoTrack? _participantVideoTrack(lk.Participant participant) {
  for (final publication in participant.trackPublications.values) {
    final track = publication.track;
    if (track is lk.VideoTrack && !publication.muted) {
      return track;
    }
  }
  return null;
}

Size _callPreviewSizeFor(BoxConstraints constraints) {
  final width = (constraints.maxWidth * 0.27).clamp(96.0, 140.0).toDouble();
  return Size(width, width * 1.48);
}

Offset _defaultCallPreviewOffset(
  BuildContext context,
  BoxConstraints constraints,
) {
  final size = _callPreviewSizeFor(constraints);
  return Offset(
    constraints.maxWidth - size.width - 14,
    MediaQuery.paddingOf(context).top + 64,
  );
}
