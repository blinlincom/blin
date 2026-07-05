import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../core/app_logger.dart';

class MessageNotificationSound {
  MessageNotificationSound({
    this.minInterval = const Duration(milliseconds: 900),
  }) : _player = AudioPlayer(playerId: 'im_message_notification');

  final Duration minInterval;
  final AudioPlayer _player;
  DateTime? _lastPlayedAt;

  Future<void> play() async {
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastPlayedAt = now;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/message_ding.wav'), volume: 0.8);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'im',
        'message notification sound failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  Future<void> dispose() {
    return _player.dispose();
  }
}
