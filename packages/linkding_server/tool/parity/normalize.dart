import 'dart:convert';

import 'package:http/http.dart' as http;

Map<String, Object?> normalize(String base, http.Response response) {
  final type = response.statusCode == 204
      ? null
      : response.headers['content-type']?.split(';').first;
  Object? body;
  if (type == 'application/json' && response.body.isNotEmpty) {
    body = _clean(jsonDecode(response.body), base);
  } else if (response.statusCode == 200 && response.body.isNotEmpty) {
    // A downloaded file: its content counts.
    body = response.body;
  } else if (response.body.isNotEmpty) {
    body = '<$type>';
  }
  final location = response.headers['location'];
  return {
    'status': response.statusCode,
    'content-type': ?type,
    if (location != null) 'location': location.replaceAll(base, '<base>'),
    'allow': ?response.headers['allow'],
    'www-authenticate': ?response.headers['www-authenticate'],
    'content-disposition': ?response.headers['content-disposition'],
    'body': ?body,
  };
}

final _timestamp = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{6})?Z$');
final _archiveStamp = RegExp(r'https://web\.archive\.org/web/(\d{14})/');

Object? _clean(Object? value, String base, [String? key]) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key as String: _clean(e.value, base, e.key as String),
    };
  }
  if (value is List) {
    final cleaned = [for (final item in value) _clean(item, base)];
    if (key == 'auto_tags') cleaned.sort((a, b) => '$a'.compareTo('$b'));
    return cleaned;
  }
  if (value is String) {
    if (key == 'detail' && value.startsWith('JSON parse error - ')) {
      return 'JSON parse error - <python message>';
    }
    if (_timestamp.hasMatch(value)) {
      final at = DateTime.parse(value);
      if (DateTime.now().toUtc().difference(at).inHours.abs() < 24) {
        return '<now>';
      }
    }
    final stamp = _archiveStamp.firstMatch(value);
    if (stamp != null && stamp[1]!.startsWith(_today())) {
      return value.replaceFirst(stamp[1]!, '<now>');
    }
    return value.replaceAll(base, '<base>');
  }
  return value;
}

/// [right] with each `file_size` taken from [left] when the two are within
/// two bytes: a gzipped asset's size depends on the zlib build (the Dart SDK
/// bundles Chromium's), not on what was stored.
Object? sameSizes(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return {
      for (final MapEntry(:key, :value) in right.entries)
        key:
            key == 'file_size' &&
                value is int &&
                left[key] is int &&
                (value - (left[key] as int)).abs() <= 2
            ? left[key]
            : sameSizes(left[key], value),
    };
  }
  if (left is List && right is List && left.length == right.length) {
    return [
      for (var i = 0; i < right.length; i++) sameSizes(left[i], right[i]),
    ];
  }
  return right;
}

String _today() {
  final now = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}
