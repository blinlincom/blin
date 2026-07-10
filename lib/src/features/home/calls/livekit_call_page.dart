part of 'package:bim/src/features/home/home_page.dart';

const _privateCallVideoDimensions = lk.VideoDimensions(1920, 1080);
const _groupCallVideoDimensions = lk.VideoDimensions(1280, 720);
const _privateCallVideoEncoding = lk.VideoEncoding(
  maxBitrate: 5200 * 1000,
  maxFramerate: 30,
);
const _groupCallVideoEncoding = lk.VideoEncoding(
  maxBitrate: 2200 * 1000,
  maxFramerate: 30,
);
const _callCloseAfterToneDelay = Duration(milliseconds: 360);
const _remoteCallCloseDelay = Duration(milliseconds: 680);
const _callMiniWindowSize = Size(154, 64);

lk.RoomOptions _callRoomOptions(LiveKitCallInfo call) {
  return lk.RoomOptions(
    defaultCameraCaptureOptions: _callCameraCaptureOptions(call),
    defaultVideoPublishOptions: _callVideoPublishOptions(call),
    adaptiveStream: !call.isPrivate,
    dynacast: !call.isPrivate,
  );
}

lk.CameraCaptureOptions _callCameraCaptureOptions(LiveKitCallInfo? call) {
  return lk.CameraCaptureOptions(
    params: lk.VideoParameters(
      dimensions: _callVideoDimensions(call),
      encoding: _callVideoEncoding(call),
    ),
    maxFrameRate: 30,
  );
}

lk.VideoPublishOptions _callVideoPublishOptions(LiveKitCallInfo? call) {
  return lk.VideoPublishOptions(
    videoEncoding: _callVideoEncoding(call),
    simulcast: !(call?.isPrivate ?? true),
    videoSimulcastLayers: _callVideoSimulcastLayers(call),
    degradationPreference: lk.DegradationPreference.maintainResolution,
  );
}

lk.VideoDimensions _callVideoDimensions(LiveKitCallInfo? call) {
  return call?.isPrivate ?? true
      ? _privateCallVideoDimensions
      : _groupCallVideoDimensions;
}

lk.VideoEncoding _callVideoEncoding(LiveKitCallInfo? call) {
  return call?.isPrivate ?? true
      ? _privateCallVideoEncoding
      : _groupCallVideoEncoding;
}

List<lk.VideoParameters> _callVideoSimulcastLayers(LiveKitCallInfo? call) {
  if (call?.isPrivate ?? true) {
    return const [
      lk.VideoParameters(
        dimensions: lk.VideoDimensions(320, 180),
        encoding: lk.VideoEncoding(maxBitrate: 180 * 1000, maxFramerate: 15),
      ),
      lk.VideoParameters(
        dimensions: lk.VideoDimensions(640, 360),
        encoding: lk.VideoEncoding(maxBitrate: 520 * 1000, maxFramerate: 20),
      ),
      lk.VideoParameters(
        dimensions: lk.VideoDimensions(1280, 720),
        encoding: lk.VideoEncoding(maxBitrate: 1800 * 1000, maxFramerate: 30),
      ),
      lk.VideoParameters(
        dimensions: lk.VideoDimensions(1920, 1080),
        encoding: lk.VideoEncoding(maxBitrate: 3600 * 1000, maxFramerate: 30),
      ),
    ];
  }
  return const [
    lk.VideoParameters(
      dimensions: lk.VideoDimensions(320, 180),
      encoding: lk.VideoEncoding(maxBitrate: 180 * 1000, maxFramerate: 15),
    ),
    lk.VideoParameters(
      dimensions: lk.VideoDimensions(640, 360),
      encoding: lk.VideoEncoding(maxBitrate: 520 * 1000, maxFramerate: 20),
    ),
  ];
}

class _CallSoundController {
  _CallSoundController()
    : _ringPlayer = AudioPlayer(),
      _effectPlayer = AudioPlayer();

  final AudioPlayer _ringPlayer;
  final AudioPlayer _effectPlayer;
  String _loopingAsset = '';
  bool _disposed = false;

  Future<void> playOutgoing() {
    return _playLoop('sounds/call_outgoing.wav', volume: 0.62);
  }

  Future<void> playIncoming() {
    return _playLoop('sounds/call_incoming.wav', volume: 0.78);
  }

  Future<void> playEndTone() async {
    if (_disposed) {
      return;
    }
    await stopRing();
    try {
      await _effectPlayer.stop();
      await _effectPlayer.setReleaseMode(ReleaseMode.release);
      await _effectPlayer.play(
        AssetSource('sounds/call_end.wav'),
        volume: 0.72,
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'call',
        'call end tone failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  Future<void> stopRing() async {
    if (_disposed) {
      return;
    }
    _loopingAsset = '';
    await _ringPlayer.stop().catchError((Object error) {
      AppLogger.warn(
        'call',
        'call ring stop failed',
        data: {'error': '$error'},
      );
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await Future.wait([
      _ringPlayer.dispose().catchError((Object _) {}),
      _effectPlayer.dispose().catchError((Object _) {}),
    ]);
  }

  Future<void> _playLoop(String asset, {required double volume}) async {
    if (_disposed || _loopingAsset == asset) {
      return;
    }
    _loopingAsset = asset;
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(AssetSource(asset), volume: volume);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'call',
        'call ring play failed',
        data: {
          'asset': asset,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }
}

class LiveKitCallPage extends StatefulWidget {
  const LiveKitCallPage.create({
    required this.controller,
    required this.callType,
    required this.mediaType,
    this.receiverId = '',
    this.groupId = '',
    this.title = '',
    this.inviteUserIds = const [],
    this.onClosed,
    super.key,
  }) : initialCall = null,
       incoming = false;

  const LiveKitCallPage.incoming({
    required this.controller,
    required LiveKitCallInfo this.initialCall,
    this.onClosed,
    super.key,
  }) : callType = '',
       mediaType = '',
       receiverId = '',
       groupId = '',
       title = '',
       inviteUserIds = const [],
       incoming = true;

  final SessionController controller;
  final String callType;
  final String mediaType;
  final String receiverId;
  final String groupId;
  final String title;
  final List<String> inviteUserIds;
  final LiveKitCallInfo? initialCall;
  final bool incoming;
  final ValueChanged<int>? onClosed;

  LiveKitCallPage withHost({
    required GlobalKey<LiveKitCallPageState> key,
    required ValueChanged<int> onClosed,
  }) {
    if (incoming) {
      return LiveKitCallPage.incoming(
        key: key,
        controller: controller,
        initialCall: initialCall!,
        onClosed: onClosed,
      );
    }
    return LiveKitCallPage.create(
      key: key,
      controller: controller,
      callType: callType,
      mediaType: mediaType,
      receiverId: receiverId,
      groupId: groupId,
      title: title,
      inviteUserIds: inviteUserIds,
      onClosed: onClosed,
    );
  }

  @override
  State<LiveKitCallPage> createState() => LiveKitCallPageState();
}

class LiveKitCallPageState extends State<LiveKitCallPage> {
  LiveKitCallInfo? _call;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  lk.EventsListener<lk.TrackEvent>? _localVideoStatsListener;
  lk.LocalVideoTrack? _localVideoStatsTrack;
  final Map<String, lk.EventsListener<lk.TrackEvent>>
  _remoteVideoStatsListeners = <String, lk.EventsListener<lk.TrackEvent>>{};
  StreamSubscription<BusinessImCallEvent>? _callSub;
  late final _sound = _CallSoundController();
  Timer? _durationTimer;
  DateTime? _lastLocalQualityLogAt;
  DateTime? _lastRemoteQualityLogAt;
  DateTime? _connectedAt;
  var _statusText = '正在准备通话';
  var _connecting = false;
  var _ending = false;
  var _micEnabled = true;
  var _cameraEnabled = false;
  var _speakerEnabled = true;
  var _cameraFront = true;
  var _durationLabel = '00:00';
  var _pageClosing = false;
  var _callAnswered = false;
  var _minimized = false;
  var _privatePreviewDragging = false;
  var _floatingDragging = false;
  var _localVideoPrimary = false;
  Offset? _privatePreviewOffset;
  Offset? _floatingOffset;

  bool get _connected => _connectedAt != null;
  bool get _incomingWaiting => widget.incoming && !_connected && !_connecting;
  bool get _canMinimize => !_incomingWaiting && !_ending && _call != null;
  bool get _videoCall =>
      (_call?.isVideo ?? false) || widget.mediaType == 'video';
  bool get _gridCall =>
      (_call?.isGroup ?? false) ||
      (_call?.isMeeting ?? false) ||
      widget.callType == 'group' ||
      widget.callType == 'meeting';

  @override
  void initState() {
    super.initState();
    _call = widget.initialCall;
    _cameraEnabled = _videoCall;
    _callSub = widget.controller.callEvents.listen(_onCallEvent);
    if (widget.incoming) {
      _statusText = _incomingStatusText;
      unawaited(_sound.playIncoming());
    } else {
      unawaited(_sound.playOutgoing());
      unawaited(_createAndConnect());
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callSub?.cancel();
    unawaited(_sound.dispose());
    _room?.removeListener(_onRoomChanged);
    unawaited(_listener?.dispose());
    unawaited(_disposeVideoStatsListeners());
    if (_room != null && !_ending && !_pageClosing) {
      AppLogger.warn(
        'call',
        'call page disposed while call is still active',
        data: {'call_id': _call?.callId, 'minimized': _minimized},
      );
      unawaited(
        _room?.disconnect().catchError((Object error) {
          AppLogger.warn(
            'call',
            'room disconnected on active page dispose failed',
            data: {'call_id': _call?.callId, 'error': '$error'},
          );
        }),
      );
    }
    super.dispose();
  }

  Future<void> _createAndConnect() async {
    setState(() {
      _connecting = true;
      _statusText = widget.callType == 'meeting' ? '正在创建会议' : '正在呼叫';
    });
    try {
      final call = await widget.controller.createLiveKitCall(
        callType: widget.callType,
        mediaType: widget.mediaType,
        receiverId: widget.receiverId,
        groupId: widget.groupId,
        title: widget.title,
        inviteUserIds: widget.inviteUserIds,
      );
      if (_ending) {
        unawaited(widget.controller.cancelLiveKitCall(call.callId));
        return;
      }
      if (!mounted) {
        unawaited(widget.controller.cancelLiveKitCall(call.callId));
        return;
      }
      setState(() => _call = call);
      await _connectRoom(call);
    } catch (error, stackTrace) {
      AppLogger.error(
        'call',
        'create call failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'call_type': widget.callType,
          'media_type': widget.mediaType,
          'receiver_id': widget.receiverId,
          'group_id': widget.groupId,
        },
      );
      if (mounted) {
        unawaited(_sound.stopRing());
        setState(() {
          _connecting = false;
          _statusText = error.toString();
        });
      }
    }
  }

  Future<void> _accept() async {
    final callId = _call?.callId ?? 0;
    if (callId <= 0) {
      return;
    }
    unawaited(_sound.stopRing());
    setState(() {
      _connecting = true;
      _statusText = '正在接听';
    });
    try {
      final call = await widget.controller.acceptLiveKitCall(callId);
      if (!mounted || _ending) {
        return;
      }
      _callAnswered = true;
      setState(() => _call = call);
      await _connectRoom(call);
    } catch (error, stackTrace) {
      AppLogger.error(
        'call',
        'accept call failed',
        error: error,
        stackTrace: stackTrace,
        data: {'call_id': callId},
      );
      if (mounted) {
        if (!_ending) {
          unawaited(_sound.playIncoming());
        }
        setState(() {
          _connecting = false;
          _statusText = error.toString();
        });
      }
    }
  }

  Future<void> _reject() async {
    if (_ending) {
      return;
    }
    final callId = _call?.callId ?? 0;
    _ending = true;
    setState(() {
      _connecting = true;
      _statusText = '正在拒绝';
    });
    if (callId > 0) {
      try {
        await widget.controller.rejectLiveKitCall(callId);
      } catch (error, stackTrace) {
        AppLogger.error(
          'call',
          'reject call failed',
          error: error,
          stackTrace: stackTrace,
          data: {'call_id': callId},
        );
        if (mounted) {
          setState(() {
            _ending = false;
            _connecting = false;
            _statusText = '拒绝失败，请重试';
          });
        }
        return;
      }
    }
    await _finishAndClose(playEndTone: true);
  }

  Future<void> _connectRoom(LiveKitCallInfo call) async {
    if (call.liveKitUrl.isEmpty || call.liveKitToken.isEmpty) {
      throw ApiException('音视频连接参数缺失');
    }
    final room = lk.Room(roomOptions: _callRoomOptions(call));
    _listener = room.createListener()
      ..on<lk.RoomConnectedEvent>((_) {
        _onRoomConnected();
        unawaited(_preferHighQualityRemoteVideo(source: 'connected'));
      })
      ..on<lk.RoomReconnectingEvent>((_) => _setStatus('正在重连音视频'))
      ..on<lk.RoomReconnectedEvent>((_) {
        _setStatus('通话中');
        unawaited(_preferHighQualityRemoteVideo(source: 'reconnected'));
      })
      ..on<lk.ParticipantConnectedEvent>((_) {
        _onRoomChanged();
        _maybeMarkConnected(source: 'participant_connected');
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) {
        _onRoomChanged();
        _closePrivateCallWhenRemoteLeft();
      })
      ..on<lk.TrackSubscribedEvent>((_) {
        _onRoomChanged();
        _syncVideoStatsListeners();
        unawaited(_preferHighQualityRemoteVideo(source: 'subscribed'));
      })
      ..on<lk.TrackUnsubscribedEvent>((_) {
        _onRoomChanged();
        _syncVideoStatsListeners();
      })
      ..on<lk.LocalTrackPublishedEvent>((_) => _syncVideoStatsListeners())
      ..on<lk.LocalTrackUnpublishedEvent>((_) => _syncVideoStatsListeners())
      ..on<lk.TrackMutedEvent>((_) => _onRoomChanged())
      ..on<lk.TrackUnmutedEvent>((_) => _onRoomChanged())
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!_ending) {
          unawaited(_finishRemoteCall('通话已断开'));
        }
      });
    room.addListener(_onRoomChanged);
    setState(() {
      _room = room;
      _connecting = true;
      _statusText = '正在连接音视频';
    });
    await room.connect(
      call.liveKitUrl,
      call.liveKitToken,
      fastConnectOptions: lk.FastConnectOptions(
        microphone: const lk.TrackOption(enabled: true),
        camera: lk.TrackOption(enabled: call.isVideo),
      ),
    );
    if (_ending || !mounted) {
      await room.disconnect().catchError((Object _) {});
      return;
    }
    AppLogger.info(
      'call',
      'livekit video quality configured',
      data: {
        'call_id': call.callId,
        'call_type': call.callType,
        'media_type': call.mediaType,
        'capture_width': _callVideoDimensions(call).width,
        'capture_height': _callVideoDimensions(call).height,
        'max_bitrate': _callVideoEncoding(call).maxBitrate,
        'max_framerate': _callVideoEncoding(call).maxFramerate,
        'adaptive_stream': !call.isPrivate,
        'dynacast': !call.isPrivate,
      },
    );
    _syncVideoStatsListeners();
    await room.setSpeakerOn(true, forceSpeakerOutput: false).catchError((
      Object error,
    ) {
      AppLogger.warn('call', 'set speaker failed', data: {'error': '$error'});
    });
  }

  Future<void> _preferHighQualityRemoteVideo({required String source}) async {
    final room = _room;
    final call = _call;
    if (room == null || call == null || !call.isVideo) {
      return;
    }
    final dimensions = _callVideoDimensions(call);
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        try {
          await publication.enable();
          await publication.setVideoDimensions(dimensions);
          await publication.setVideoFPS(30);
          AppLogger.info(
            'call',
            'remote video quality requested',
            data: {
              'source': source,
              'call_id': call.callId,
              'participant': participant.identity,
              'track_sid': publication.sid,
              'width': dimensions.width,
              'height': dimensions.height,
              'fps': 30,
            },
          );
        } catch (error, stackTrace) {
          AppLogger.warn(
            'call',
            'remote video quality request failed',
            data: {
              'source': source,
              'call_id': call.callId,
              'participant': participant.identity,
              'track_sid': publication.sid,
              'error': error.toString(),
              'stack': stackTrace.toString(),
            },
          );
        }
      }
    }
  }

  void _syncVideoStatsListeners() {
    final room = _room;
    if (room == null || !_videoCall) {
      return;
    }
    _bindLocalVideoStats(room.localParticipant);
    final activeRemoteKeys = <String>{};
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is! lk.RemoteVideoTrack) {
          continue;
        }
        final key = '${participant.sid}:${publication.sid}';
        activeRemoteKeys.add(key);
        _remoteVideoStatsListeners.putIfAbsent(key, () {
          AppLogger.info(
            'call',
            'remote video stats monitor attached',
            data: {
              'call_id': _call?.callId,
              'participant': participant.identity,
              'track_sid': publication.sid,
            },
          );
          return track.createListener()..on<lk.VideoReceiverStatsEvent>(
            (event) => _logRemoteVideoStats(
              event,
              participant: participant,
              trackSid: publication.sid,
            ),
          );
        });
      }
    }
    final staleKeys = _remoteVideoStatsListeners.keys
        .where((key) => !activeRemoteKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      unawaited(_remoteVideoStatsListeners.remove(key)?.dispose());
    }
  }

  void _bindLocalVideoStats(lk.LocalParticipant? participant) {
    if (participant == null) {
      return;
    }
    lk.LocalVideoTrack? activeTrack;
    String activeTrackSid = '';
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack) {
        activeTrack = track;
        activeTrackSid = publication.sid;
        break;
      }
    }
    if (activeTrack == null) {
      final oldListener = _localVideoStatsListener;
      _localVideoStatsListener = null;
      _localVideoStatsTrack = null;
      if (oldListener != null) {
        unawaited(_disposeTrackListener(oldListener));
      }
      return;
    }
    if (_localVideoStatsTrack == activeTrack &&
        _localVideoStatsListener != null) {
      return;
    }
    final oldListener = _localVideoStatsListener;
    if (oldListener != null) {
      unawaited(_disposeTrackListener(oldListener));
    }
    _localVideoStatsTrack = activeTrack;
    _localVideoStatsListener = activeTrack.createListener()
      ..on<lk.VideoSenderStatsEvent>(_logLocalVideoStats);
    AppLogger.info(
      'call',
      'local video stats monitor attached',
      data: {'call_id': _call?.callId, 'track_sid': activeTrackSid},
    );
  }

  void _logLocalVideoStats(lk.VideoSenderStatsEvent event) {
    if (!_shouldLogVideoQuality(local: true)) {
      return;
    }
    final first = event.stats.values.isEmpty ? null : event.stats.values.first;
    AppLogger.info(
      'call',
      'local video quality stats',
      data: {
        'call_id': _call?.callId,
        'bitrate_bps': event.currentBitrate.round(),
        'layers': event.bitrateForLayers,
        'frame_width': first?.frameWidth,
        'frame_height': first?.frameHeight,
        'fps': first?.framesPerSecond,
        'quality_limited_by': first?.qualityLimitationReason,
        'rtt': first?.roundTripTime,
        'codec': first?.mimeType,
      },
    );
  }

  void _logRemoteVideoStats(
    lk.VideoReceiverStatsEvent event, {
    required lk.RemoteParticipant participant,
    required String trackSid,
  }) {
    if (!_shouldLogVideoQuality(local: false)) {
      return;
    }
    AppLogger.info(
      'call',
      'remote video quality stats',
      data: {
        'call_id': _call?.callId,
        'participant': participant.identity,
        'track_sid': trackSid,
        'bitrate_bps': event.currentBitrate.round(),
        'frame_width': event.stats.frameWidth,
        'frame_height': event.stats.frameHeight,
        'fps': event.stats.framesPerSecond,
        'frames_dropped': event.stats.framesDropped,
        'packets_lost': event.stats.packetsLost,
        'jitter': event.stats.jitter,
        'codec': event.stats.mimeType,
      },
    );
  }

  bool _shouldLogVideoQuality({required bool local}) {
    final now = DateTime.now();
    final last = local ? _lastLocalQualityLogAt : _lastRemoteQualityLogAt;
    if (last != null && now.difference(last) < const Duration(seconds: 6)) {
      return false;
    }
    if (local) {
      _lastLocalQualityLogAt = now;
    } else {
      _lastRemoteQualityLogAt = now;
    }
    return true;
  }

  void _onRoomConnected() {
    if (!mounted) {
      return;
    }
    if (_gridCall) {
      _maybeMarkConnected(source: 'room_connected');
      return;
    }
    if (_room?.remoteParticipants.isNotEmpty == true) {
      _maybeMarkConnected(source: 'room_connected_with_remote');
      return;
    }
    setState(() {
      _connecting = false;
      _statusText = '等待对方加入';
    });
  }

  void _maybeMarkConnected({required String source}) {
    if (!mounted || _connectedAt != null) {
      return;
    }
    final room = _room;
    if (!_gridCall && (room == null || room.remoteParticipants.isEmpty)) {
      AppLogger.info(
        'call',
        'call connected delayed until remote joins',
        data: {'source': source, 'call_id': _call?.callId},
      );
      return;
    }
    _callAnswered = true;
    unawaited(_sound.stopRing());
    _durationTimer?.cancel();
    _connectedAt = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) {
        return;
      }
      final seconds = DateTime.now().difference(_connectedAt!).inSeconds;
      final minutes = seconds ~/ 60;
      final remain = seconds % 60;
      setState(() {
        _durationLabel =
            '${minutes.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
      });
    });
    setState(() {
      _connecting = false;
      _statusText = '通话中';
      _durationLabel = '00:00';
    });
  }

  void _setStatus(String text) {
    if (!mounted) {
      return;
    }
    setState(() => _statusText = text);
  }

  void _onRoomChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCallEvent(BusinessImCallEvent event) {
    final callId = _call?.callId ?? 0;
    if (callId <= 0 || event.event.call.callId != callId) {
      return;
    }
    if (event.event.event == 'call.accept') {
      _callAnswered = true;
      _mergeCallInfo(event.event.call);
      unawaited(_sound.stopRing());
      if (!_connected) {
        _setStatus('正在连接音视频');
      }
      return;
    }
    if (event.event.isCancel || event.event.isReject || event.event.isHangup) {
      unawaited(_finishRemoteCall(_remoteEndText(event.event)));
    }
  }

  void _closePrivateCallWhenRemoteLeft() {
    final call = _call;
    final room = _room;
    if (call == null ||
        room == null ||
        !call.isPrivate ||
        !_connected ||
        room.remoteParticipants.isNotEmpty ||
        _ending) {
      return;
    }
    unawaited(_finishRemoteCall('对方已挂断'));
  }

  String _remoteEndText(LiveKitCallEvent event) {
    if (event.isCancel) {
      return '对方已取消';
    }
    if (event.isReject) {
      return '对方已拒绝';
    }
    return '通话已结束';
  }

  void _mergeCallInfo(LiveKitCallInfo next) {
    final current = _call;
    if (!mounted || current == null || current.callId != next.callId) {
      return;
    }
    setState(() => _call = next.withConnectionFrom(current));
  }

  LiveKitCallParticipant? get _peerProfile {
    final call = _call;
    if (call == null || !call.isPrivate) {
      return null;
    }
    final currentUserId = widget.controller.session?.userId ?? 0;
    for (final participant in call.participants) {
      if (participant.userId > 0 && participant.userId != currentUserId) {
        return participant;
      }
    }
    return call.participants.isEmpty ? null : call.participants.first;
  }

  Future<void> _toggleMic() async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return;
    }
    final next = !_micEnabled;
    await participant.setMicrophoneEnabled(next);
    if (mounted) {
      setState(() => _micEnabled = next);
    }
  }

  Future<void> _toggleCamera() async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return;
    }
    final next = !_cameraEnabled;
    await participant.setCameraEnabled(
      next,
      cameraCaptureOptions: _callCameraCaptureOptions(_call),
    );
    if (next) {
      await _preferHighQualityRemoteVideo(source: 'camera_enabled');
    }
    if (mounted) {
      setState(() => _cameraEnabled = next);
    }
  }

  Future<void> _toggleSpeaker() async {
    final room = _room;
    if (room == null) {
      return;
    }
    final next = !_speakerEnabled;
    await room.setSpeakerOn(next, forceSpeakerOutput: false);
    if (mounted) {
      setState(() => _speakerEnabled = next);
    }
  }

  Future<void> _switchCamera() async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return;
    }
    lk.LocalVideoTrack? track;
    for (final publication in participant.videoTrackPublications) {
      final current = publication.track;
      if (current is lk.LocalVideoTrack) {
        track = current;
        break;
      }
    }
    if (track == null) {
      return;
    }
    final next = _cameraFront
        ? lk.CameraPosition.back
        : lk.CameraPosition.front;
    await track.setCameraPosition(next);
    if (mounted) {
      setState(() => _cameraFront = next == lk.CameraPosition.front);
    }
  }

  Future<void> _hangup() async {
    if (_ending) {
      return;
    }
    _ending = true;
    final call = _call;
    setState(() {
      _connecting = true;
      _statusText = '正在结束通话';
    });
    _sendEndRequestInBackground(call);
    await _finishAndClose(playEndTone: true);
  }

  void _leaveCallPage() {
    if (_canMinimize) {
      _minimizeCallPage();
      return;
    }
    if (_incomingWaiting) {
      unawaited(_reject());
      return;
    }
    unawaited(_hangup());
  }

  bool handleSystemBack() {
    if (_minimized) {
      return false;
    }
    _leaveCallPage();
    return true;
  }

  void _sendEndRequestInBackground(LiveKitCallInfo? call) {
    if (call == null || call.callId <= 0) {
      return;
    }
    Future<void> request;
    if (!_connected && !_callAnswered && !widget.incoming) {
      request = widget.controller.cancelLiveKitCall(call.callId).then((_) {});
    } else if (!_connected && !_callAnswered && widget.incoming) {
      request = widget.controller.rejectLiveKitCall(call.callId).then((_) {});
    } else {
      request = widget.controller
          .hangupLiveKitCall(call.callId, endCall: call.isPrivate)
          .then((_) {});
    }
    unawaited(
      request.catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'call',
          'hangup request failed after local close',
          error: error,
          stackTrace: stackTrace,
          data: {
            'call_id': call.callId,
            'connected': _connected,
            'incoming': widget.incoming,
            'call_type': call.callType,
          },
        );
      }),
    );
  }

  Future<void> _finishRemoteCall(String statusText) async {
    if (_ending) {
      return;
    }
    _ending = true;
    unawaited(_disconnectRoom());
    unawaited(_sound.playEndTone());
    if (mounted) {
      setState(() {
        _connecting = false;
        _statusText = statusText;
      });
    }
    await Future<void>.delayed(_remoteCallCloseDelay);
    _popCallPage();
  }

  Future<void> _finishAndClose({required bool playEndTone}) async {
    await _disconnectRoom();
    if (playEndTone) {
      await _sound.playEndTone();
      await Future<void>.delayed(_callCloseAfterToneDelay);
    } else {
      await _sound.stopRing();
    }
    _popCallPage();
  }

  void _popCallPage() {
    if (_pageClosing || !mounted) {
      return;
    }
    _pageClosing = true;
    final callId = _call?.callId ?? 0;
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed(callId);
      return;
    }
    Navigator.of(context).pop(callId);
  }

  Future<void> _disconnectRoom() async {
    final room = _room;
    if (room == null) {
      return;
    }
    await _disposeVideoStatsListeners();
    await room.disconnect().catchError((Object error) {
      AppLogger.warn(
        'call',
        'room disconnect failed',
        data: {'error': '$error'},
      );
    });
    _durationTimer?.cancel();
    _connectedAt = null;
    if (mounted) {
      setState(() {
        _room = null;
        _connecting = false;
      });
    }
  }

  Future<void> _disposeVideoStatsListeners() async {
    final local = _localVideoStatsListener;
    _localVideoStatsListener = null;
    _localVideoStatsTrack = null;
    final remote = _remoteVideoStatsListeners.values.toList(growable: false);
    _remoteVideoStatsListeners.clear();
    await Future.wait([
      if (local != null) _disposeTrackListener(local),
      for (final listener in remote) _disposeTrackListener(listener),
    ]);
  }

  Future<void> _disposeTrackListener(
    lk.EventsListener<lk.TrackEvent> listener,
  ) async {
    try {
      await listener.dispose();
    } catch (_) {
      // Listener cleanup must not block call teardown.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_minimized) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _restoreCallPage();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _buildMinimizedOverlay(constraints),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xff08090c),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xff08090c),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _leaveCallPage();
          }
        },
        child: Scaffold(
          backgroundColor: BimColors.inverseSurface,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned.fill(child: _buildStage(constraints)),
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 8,
                      child: _CallTopBar(
                        title: _callTitle,
                        subtitle: _connected ? _durationLabel : _statusText,
                        canMinimize: _canMinimize,
                        onBack: _leaveCallPage,
                        onMinimize: _minimizeCallPage,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _incomingWaiting
                          ? _IncomingCallControls(
                              connecting: _connecting,
                              onAccept: _accept,
                              onReject: _reject,
                            )
                          : _CallControls(
                              micEnabled: _micEnabled,
                              cameraEnabled: _cameraEnabled,
                              speakerEnabled: _speakerEnabled,
                              videoCall: _videoCall,
                              connecting: _connecting,
                              onMic: _toggleMic,
                              onCamera: _toggleCamera,
                              onSpeaker: _toggleSpeaker,
                              onSwitchCamera: _switchCamera,
                              onHangup: _hangup,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BoxConstraints constraints) {
    if (_incomingWaiting) {
      return _IncomingCallStage(call: _call, statusText: _incomingStatusText);
    }
    final room = _room;
    if (room == null) {
      final peer = _peerProfile;
      return _CallWaitingStage(
        title: peer?.name.isNotEmpty == true ? peer!.name : _callTitle,
        statusText: _statusText,
        videoCall: _videoCall,
        avatarUrl: peer?.avatar ?? '',
      );
    }
    if (_gridCall) {
      return _ParticipantGridStage(
        room: room,
        call: _call,
        maxWidth: constraints.maxWidth,
      );
    }
    return _PrivateCallStage(
      room: room,
      call: _call,
      videoCall: _videoCall,
      fallbackProfile: _peerProfile,
      localVideoPrimary: _localVideoPrimary,
      previewOffset: _privatePreviewOffset,
      previewDragging: _privatePreviewDragging,
      onPreviewTap: _togglePrivateVideoPrimary,
      onPreviewDragStart: _startPrivatePreviewDrag,
      onPreviewDragUpdate: _updatePrivatePreviewDrag,
      onPreviewDragEnd: _endPrivatePreviewDrag,
    );
  }

  Widget _buildMinimizedOverlay(BoxConstraints constraints) {
    final position = _floatingOffset ?? _defaultFloatingOffset(constraints);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: _DraggableCallMiniWindow(
            title: _callTitle,
            subtitle: _connected ? _durationLabel : _statusText,
            videoCall: _videoCall,
            dragging: _floatingDragging,
            onTap: _restoreCallPage,
            onPanStart: (_) => setState(() => _floatingDragging = true),
            onPanUpdate: (details) {
              setState(() {
                final current =
                    _floatingOffset ?? _defaultFloatingOffset(constraints);
                _floatingOffset = _clampFloatingOffset(
                  current + details.delta,
                  constraints,
                );
              });
            },
            onPanEnd: (_) {
              setState(() {
                _floatingDragging = false;
                _floatingOffset = _snapFloatingOffset(
                  _floatingOffset ?? _defaultFloatingOffset(constraints),
                  constraints,
                );
              });
              AppLogger.info(
                'call',
                'call floating window snapped',
                data: {
                  'call_id': _call?.callId,
                  'dx': _floatingOffset?.dx,
                  'dy': _floatingOffset?.dy,
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _minimizeCallPage() {
    if (!_canMinimize || _minimized) {
      return;
    }
    AppLogger.info(
      'call',
      'call page minimized',
      data: {'call_id': _call?.callId, 'video_call': _videoCall},
    );
    setState(() => _minimized = true);
  }

  void _restoreCallPage() {
    if (!_minimized) {
      return;
    }
    AppLogger.info(
      'call',
      'call page restored',
      data: {'call_id': _call?.callId},
    );
    setState(() => _minimized = false);
  }

  void _togglePrivateVideoPrimary() {
    if (!_videoCall) {
      return;
    }
    setState(() => _localVideoPrimary = !_localVideoPrimary);
  }

  void _startPrivatePreviewDrag(DragStartDetails details) {
    setState(() => _privatePreviewDragging = true);
  }

  void _updatePrivatePreviewDrag(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    setState(() {
      final current =
          _privatePreviewOffset ?? _defaultPrivatePreviewOffset(constraints);
      _privatePreviewOffset = _clampPrivatePreviewOffset(
        current + details.delta,
        constraints,
      );
    });
  }

  void _endPrivatePreviewDrag(
    DragEndDetails details,
    BoxConstraints constraints,
  ) {
    setState(() {
      _privatePreviewDragging = false;
      _privatePreviewOffset = _snapPrivatePreviewOffset(
        _privatePreviewOffset ?? _defaultPrivatePreviewOffset(constraints),
        constraints,
      );
    });
    AppLogger.info(
      'call',
      'private preview snapped',
      data: {
        'call_id': _call?.callId,
        'dx': _privatePreviewOffset?.dx,
        'dy': _privatePreviewOffset?.dy,
      },
    );
  }

  Size _privatePreviewSize(BoxConstraints constraints) {
    return _callPreviewSizeFor(constraints);
  }

  Offset _defaultPrivatePreviewOffset(BoxConstraints constraints) {
    return _defaultCallPreviewOffset(context, constraints);
  }

  Offset _clampPrivatePreviewOffset(Offset offset, BoxConstraints constraints) {
    final size = _privatePreviewSize(constraints);
    final minX = 12.0;
    final maxX = max(minX, constraints.maxWidth - size.width - 12);
    final minY = _privatePreviewTopInset(context) + 8;
    final maxY = max(
      minY,
      constraints.maxHeight - _privatePreviewBottomInset(context) - size.height,
    );
    return Offset(
      offset.dx.clamp(minX, maxX).toDouble(),
      offset.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _snapPrivatePreviewOffset(Offset offset, BoxConstraints constraints) {
    final size = _privatePreviewSize(constraints);
    final minX = 12.0;
    final maxX = max(minX, constraints.maxWidth - size.width - 12);
    final minY = _privatePreviewTopInset(context) + 8;
    final maxY = max(
      minY,
      constraints.maxHeight - _privatePreviewBottomInset(context) - size.height,
    );
    final snapX = offset.dx + size.width / 2 < constraints.maxWidth / 2
        ? minX
        : maxX;
    final snapY = offset.dy + size.height / 2 < constraints.maxHeight / 2
        ? minY
        : maxY;
    return Offset(snapX, snapY);
  }

  double _privatePreviewTopInset(BuildContext context) {
    return MediaQuery.paddingOf(context).top;
  }

  double _privatePreviewBottomInset(BuildContext context) {
    return max(142, MediaQuery.paddingOf(context).bottom + 126).toDouble();
  }

  Offset _defaultFloatingOffset(BoxConstraints constraints) {
    return Offset(14, _floatingTopInset(context) + 12);
  }

  Offset _clampFloatingOffset(Offset offset, BoxConstraints constraints) {
    const size = _callMiniWindowSize;
    final minX = 12.0;
    final maxX = max(minX, constraints.maxWidth - size.width - 12);
    final minY = _floatingTopInset(context) + 8;
    final maxY = max(
      minY,
      constraints.maxHeight - _floatingBottomInset(context) - size.height,
    );
    return Offset(
      offset.dx.clamp(minX, maxX).toDouble(),
      offset.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _snapFloatingOffset(Offset offset, BoxConstraints constraints) {
    const size = _callMiniWindowSize;
    final minX = 12.0;
    final maxX = max(minX, constraints.maxWidth - size.width - 12);
    final minY = _floatingTopInset(context) + 8;
    final maxY = max(
      minY,
      constraints.maxHeight - _floatingBottomInset(context) - size.height,
    );
    final snapX = offset.dx + size.width / 2 < constraints.maxWidth / 2
        ? minX
        : maxX;
    final snapY = offset.dy + size.height / 2 < constraints.maxHeight / 2
        ? minY
        : maxY;
    return Offset(snapX, snapY);
  }

  double _floatingTopInset(BuildContext context) {
    return MediaQuery.paddingOf(context).top;
  }

  double _floatingBottomInset(BuildContext context) {
    return max(24, MediaQuery.paddingOf(context).bottom + 12).toDouble();
  }

  String get _callTitle {
    final call = _call;
    if (call == null) {
      if (widget.callType == 'meeting') {
        return widget.mediaType == 'video' ? '视频会议' : '语音会议';
      }
      return widget.mediaType == 'video' ? '视频通话' : '语音通话';
    }
    if (call.title.isNotEmpty) {
      return call.title;
    }
    if (call.isMeeting) {
      return call.isVideo ? '视频会议' : '语音会议';
    }
    return call.isVideo ? '视频通话' : '语音通话';
  }

  String get _incomingStatusText {
    final call = _call;
    final media = (call?.isVideo ?? _videoCall) ? '视频通话' : '语音通话';
    return '邀请你进行$media';
  }
}
