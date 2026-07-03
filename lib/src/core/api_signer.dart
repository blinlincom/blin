import 'dart:convert';

import 'package:crypto/crypto.dart';

class ApiSigner {
  const ApiSigner(this.appKey);

  final String appKey;

  String sign(Map<String, Object?> params) {
    final normalized = <String, Object>{};
    for (final entry in params.entries) {
      if (entry.key == 'sign' ||
          entry.key == 'callback' ||
          entry.key == 'action') {
        continue;
      }
      final value = entry.value;
      if (value == null) {
        continue;
      }
      normalized[entry.key] = _normalize(value);
    }

    final keys = normalized.keys.toList()..sort();
    final source =
        '${keys.map((key) => '$key=${jsonEncode(normalized[key])}').join('&')}&secretKey=$appKey'
            .replaceAll(r'\/', '/');
    return md5.convert(utf8.encode(source)).toString().toLowerCase();
  }

  Object _normalize(Object value) {
    if (value is bool) {
      return value ? '1' : '0';
    }
    if (value is Map) {
      final sorted = <String, Object>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        final raw = value[key];
        if (raw != null) {
          sorted[key] = _normalize(raw as Object);
        }
      }
      return sorted;
    }
    if (value is Iterable) {
      return value
          .where((item) => item != null)
          .map((item) => _normalize(item as Object))
          .toList();
    }
    return value.toString();
  }
}
