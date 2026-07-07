part of 'package:bim/src/features/home/home_page.dart';

String _mediaTitle(String contentType) {
  return switch (contentType) {
    ChatContentTypes.image => '发送图片',
    ChatContentTypes.emoji => '发送表情',
    ChatContentTypes.gif => '发送 GIF',
    ChatContentTypes.sticker => '发送贴纸',
    ChatContentTypes.voice => '发送语音',
    ChatContentTypes.video => '发送视频',
    ChatContentTypes.file => '发送文件',
    _ => '发送媒体',
  };
}

String _mimeFromPath(String path, String contentType) {
  final ext = path.split('.').last.toLowerCase();
  if (contentType == ChatContentTypes.image) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/*',
    };
  }
  if (contentType == ChatContentTypes.video) {
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'webm' => 'video/webm',
      _ => 'video/*',
    };
  }
  return switch (ext) {
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

_VideoPreviewSource? _videoPreviewSource(
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  final localPath = _value(payload, [
    'file_path',
    'video_file_path',
  ], fallback: _value(media, ['file_path', 'video_file_path']));
  if (localPath.isNotEmpty &&
      _looksLikeVideoPath(localPath) &&
      File(localPath).existsSync()) {
    return _VideoPreviewSource(value: localPath, isLocal: true);
  }

  final rawUrl = _value(payload, [
    'video_url',
    'file_url',
    'url',
    'video_path',
  ], fallback: _value(media, ['video_url', 'file_url', 'url', 'video_path']));
  final url = _normalizeAvatarUrl(rawUrl);
  if (url.isNotEmpty && !_looksLikeImagePath(url)) {
    return _VideoPreviewSource(value: url, isLocal: false);
  }
  return null;
}

bool _looksLikeImagePath(String value) {
  final clean = value.split('?').first.toLowerCase();
  return clean.endsWith('.jpg') ||
      clean.endsWith('.jpeg') ||
      clean.endsWith('.png') ||
      clean.endsWith('.gif') ||
      clean.endsWith('.webp') ||
      clean.endsWith('.bmp') ||
      clean.endsWith('.heic');
}

bool _looksLikeVideoPath(String value) {
  final clean = value.split('?').first.toLowerCase();
  return clean.endsWith('.mp4') ||
      clean.endsWith('.mov') ||
      clean.endsWith('.m4v') ||
      clean.endsWith('.webm') ||
      clean.endsWith('.avi') ||
      clean.endsWith('.mkv');
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty || parts.last.isEmpty ? normalized : parts.last;
}

String _secondsLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

IconData _fileIcon(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => Icons.image_outlined,
    'mp4' || 'mov' || 'm4v' || 'webm' => Icons.videocam_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' => Icons.description_outlined,
    'xls' || 'xlsx' => Icons.table_chart_outlined,
    'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

Future<List<Directory>> _candidateFileDirectories() async {
  final dirs = <Directory>[];
  final seen = <String>{};

  Future<void> add(Directory? dir) async {
    if (dir == null || dir.path.isEmpty || !seen.add(dir.path)) {
      return;
    }
    if (await dir.exists()) {
      dirs.add(dir);
    }
  }

  Future<void> addRequired(Future<Directory> future) async {
    try {
      await add(await future);
    } on Object {
      return;
    }
  }

  Future<void> addOptional(Future<Directory?> future) async {
    try {
      await add(await future);
    } on Object {
      return;
    }
  }

  Future<void> addPath(String path) => add(Directory(path));

  await addRequired(getApplicationDocumentsDirectory());
  await addRequired(getApplicationSupportDirectory());
  await addRequired(getTemporaryDirectory());
  await addOptional(getDownloadsDirectory());

  if (Platform.isAndroid) {
    for (final path in const [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Movies',
    ]) {
      await addPath(path);
    }
  }

  return dirs;
}

List<ActionInputField> _mediaFields(String contentType) {
  final fields = <ActionInputField>[];
  switch (contentType) {
    case ChatContentTypes.emoji:
      fields.add(const ActionInputField(id: 'emoji_code', label: '表情编码'));
      break;
    case ChatContentTypes.sticker:
      fields.add(const ActionInputField(id: 'sticker_id', label: '贴纸 ID'));
      break;
    case ChatContentTypes.voice:
      fields.add(
        const ActionInputField(
          id: 'duration',
          label: '时长秒数',
          keyboardType: TextInputType.number,
        ),
      );
      break;
    case ChatContentTypes.video:
      fields.add(
        const ActionInputField(
          id: 'duration',
          label: '时长秒数',
          keyboardType: TextInputType.number,
        ),
      );
      break;
    case ChatContentTypes.file:
      fields
        ..add(const ActionInputField(id: 'name', label: '文件名'))
        ..add(const ActionInputField(id: 'mime', label: 'MIME 类型'))
        ..add(
          const ActionInputField(
            id: 'size',
            label: '文件大小',
            keyboardType: TextInputType.number,
          ),
        );
      break;
  }
  return fields;
}
