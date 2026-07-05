import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogEntry {
  const AppLogEntry({
    required this.time,
    required this.level,
    required this.scope,
    required this.message,
    this.data = const {},
  });

  final DateTime time;
  final String level;
  final String scope;
  final String message;
  final Map<String, Object?> data;

  String get line {
    final buffer = StringBuffer()
      ..write(_formatTime(time))
      ..write(' [$level] ')
      ..write(scope)
      ..write(' - ')
      ..write(message);
    if (data.isNotEmpty) {
      buffer.write(' ');
      buffer.write(jsonEncode(AppLogger._jsonReady(data)));
    }
    return buffer.toString();
  }

  static String _formatTime(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    String three(int input) => input.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.${three(value.millisecond)}';
  }
}

class AppLogger {
  AppLogger._();

  static const _maxEntries = 1000;
  static const _maxFileBytes = 8 * 1024 * 1024;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final List<AppLogEntry> _entries = <AppLogEntry>[];
  static File? _file;
  static String _filePath = '';
  static Future<void> _writeQueue = Future<void>.value();

  static List<AppLogEntry> get entries => List.unmodifiable(_entries);
  static String get filePath => _filePath;

  static Future<void> initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _file = File('${logDir.path}/bim.log');
      _filePath = _file!.path;
      await _rotateIfNeeded();
      info('log', 'file logger ready', data: {'path': _filePath});
    } catch (error, stackTrace) {
      debugPrint('[BIM] logger init failed: $error');
      debugPrint(stackTrace.toString());
    }
  }

  static void info(
    String scope,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _add('INFO', scope, message, data);
  }

  static void warn(
    String scope,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _add('WARN', scope, message, data);
  }

  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _add('ERROR', scope, message, {
      ...data,
      if (error != null) 'error': error.toString(),
    });
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static Future<T> measure<T>(
    String scope,
    String message,
    Future<T> Function() task, {
    Map<String, Object?> data = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    info(scope, '$message start', data: data);
    try {
      final result = await task();
      info(
        scope,
        '$message success',
        data: {...data, 'ms': stopwatch.elapsedMilliseconds},
      );
      return result;
    } catch (error, stackTrace) {
      AppLogger.error(
        scope,
        '$message failed',
        error: error,
        stackTrace: stackTrace,
        data: {...data, 'ms': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
  }

  static Map<String, Object?> sanitize(Map<String, Object?> input) {
    return input.map((key, value) {
      final lower = key.toLowerCase();
      if (lower.contains('password') ||
          lower.contains('token') ||
          lower == 'sign' ||
          lower.contains('secret') ||
          lower.contains('key')) {
        return MapEntry(key, _mask(value));
      }
      if (value is Map) {
        return MapEntry(
          key,
          sanitize(value.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
      if (value is Iterable) {
        return MapEntry(
          key,
          value.map((item) {
            if (item is Map) {
              return sanitize(item.map((k, v) => MapEntry(k.toString(), v)));
            }
            return item;
          }).toList(),
        );
      }
      return MapEntry(key, _jsonReady(value));
    });
  }

  static String dump() => _entries.map((entry) => entry.line).join('\n');

  static Future<String> readFile() async {
    final file = _file;
    if (file == null || !await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  static Future<String> exportText() async {
    final fileText = await readFile();
    if (fileText.trim().isNotEmpty) {
      return fileText;
    }
    return dump();
  }

  static void clear() {
    _entries.clear();
    final file = _file;
    if (file != null) {
      _enqueueWrite(() => file.writeAsString('', flush: true));
    }
    revision.value++;
  }

  static void _add(
    String level,
    String scope,
    String message,
    Map<String, Object?> data,
  ) {
    final entry = AppLogEntry(
      time: DateTime.now(),
      level: level,
      scope: scope,
      message: message,
      data: sanitize(data),
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    revision.value++;
    debugPrint('[BIM] ${entry.line}');
    final file = _file;
    if (file != null) {
      _enqueueWrite(
        () => file.writeAsString('${entry.line}\n', mode: FileMode.append),
      );
    }
  }

  static void _enqueueWrite(Future<void> Function() task) {
    _writeQueue = _writeQueue.then((_) => task()).catchError((Object error) {
      debugPrint('[BIM] log write failed: $error');
    });
  }

  static Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null || !await file.exists()) {
      return;
    }
    final length = await file.length();
    if (length <= _maxFileBytes) {
      return;
    }
    final rotated = File('${file.path}.1');
    if (await rotated.exists()) {
      await rotated.delete();
    }
    await file.rename(rotated.path);
    _file = File(_filePath);
  }

  static String _mask(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) {
      return '';
    }
    if (text.length <= 8) {
      return '***';
    }
    return '${text.substring(0, 3)}***${text.substring(text.length - 3)}';
  }

  static Object? _jsonReady(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonReady(item)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonReady).toList();
    }
    return value.toString();
  }
}
