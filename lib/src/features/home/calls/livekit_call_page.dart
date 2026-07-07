part of 'package:bim/src/features/home/home_page.dart';

const _privateCallVideoDimensions = lk.VideoDimensions(1920, 1080);
const _groupCallVideoDimensions = lk.VideoDimensions(1280, 720);
const _privateCallVideoEncoding = lk.VideoEncoding(
  maxBitrate: 3600 * 1000,
  maxFramerate: 30,
);
const _groupCallVideoEncoding = lk.VideoEncoding(
  maxBitrate: 2200 * 1000,
  maxFramerate: 30,
);
const _callCloseAfterToneDelay = Duration(milliseconds: 360);
const _remoteCallCloseDelay = Duration(milliseconds: 680);

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
    simulcast: true,
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
    super.key,
  }) : initialCall = null,
       incoming = false;

  const LiveKitCallPage.incoming({
    required this.controller,
    required LiveKitCallInfo this.initialCall,
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

  @override
  State<LiveKitCallPage> createState() => _LiveKitCallPageState();
}

class _LiveKitCallPageState extends State<LiveKitCallPage> {
  LiveKitCallInfo? _call;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  StreamSubscription<BusinessImCallEvent>? _callSub;
  late final _sound = _CallSoundController();
  Timer? _durationTimer;
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

  bool get _connected => _connectedAt != null;
  bool get _incomingWaiting => widget.incoming && !_connected && !_connecting;
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
    final room = _room;
    if (room != null && !_ending) {
      unawaited(room.disconnect());
      final callId = _call?.callId ?? 0;
      if (callId > 0) {
        unawaited(widget.controller.hangupLiveKitCall(callId));
      }
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
        unawaited(_preferHighQualityRemoteVideo(source: 'subscribed'));
      })
      ..on<lk.TrackUnsubscribedEvent>((_) => _onRoomChanged())
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
    Navigator.of(context).pop();
  }

  Future<void> _disconnectRoom() async {
    final room = _room;
    if (room == null) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
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
            unawaited(_hangup());
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xff08090c),
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
                        onBack: _hangup,
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
    );
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
  });

  final lk.Room room;
  final LiveKitCallInfo? call;
  final bool videoCall;
  final LiveKitCallParticipant? fallbackProfile;

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
    return Stack(
      children: [
        Positioned.fill(
          child: remote == null
              ? _NoVideoSurface(
                  label: _participantDisplayName(
                    null,
                    fallbackProfile,
                    fallback: '等待对方加入',
                  ),
                  avatar: fallbackProfile?.avatar ?? '',
                )
              : _ParticipantVideoSurface(
                  participant: remote,
                  profile: _participantProfile(call, remote.identity),
                  fit: lk.VideoViewFit.cover,
                ),
        ),
        if (local != null)
          Positioned(
            top: 78,
            right: 14,
            child: SizedBox(
              width: 108,
              height: 160,
              child: _ParticipantVideoSurface(
                participant: local,
                profile: _participantProfile(call, local.identity),
                compact: true,
              ),
            ),
          ),
      ],
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
      color: const Color(0xff141821),
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
                      : const Color(0xffd9dde6),
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
      color: const Color(0xff11151d),
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
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

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
        ],
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
            color: const Color(0xfff04438),
            onTap: connecting ? null : onReject,
          ),
          _RoundCallButton(
            icon: connecting ? Icons.more_horiz_rounded : Icons.call_rounded,
            label: connecting ? '接听中' : '接听',
            color: const Color(0xff28c76f),
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
              color: const Color(0xff242a36),
              onTap: connecting ? null : onMic,
            ),
            if (videoCall)
              _RoundCallButton(
                icon: cameraEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: cameraEnabled ? '摄像头' : '开摄像头',
                color: const Color(0xff242a36),
                onTap: connecting ? null : onCamera,
              ),
            _RoundCallButton(
              icon: speakerEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: '扬声器',
              color: const Color(0xff242a36),
              onTap: connecting ? null : onSpeaker,
            ),
            if (videoCall)
              _RoundCallButton(
                icon: Icons.cameraswitch_rounded,
                label: '翻转',
                color: const Color(0xff242a36),
                onTap: connecting ? null : onSwitchCamera,
              ),
            _RoundCallButton(
              icon: Icons.call_end_rounded,
              label: '挂断',
              color: const Color(0xfff04438),
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
                color: enabled
                    ? const Color(0xffdfe4ed)
                    : const Color(0xff777f8d),
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
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
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
        color: const Color(0xff2a3140),
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
