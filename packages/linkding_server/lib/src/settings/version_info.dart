import 'dart:convert';
import 'dart:io';

import '../config.dart';

({int hour, String text})? _version;

/// linkding's version, with the latest release from GitHub when it can be
/// read, cached for the hour as linkding caches it.
Future<String> versionInfo() async {
  final hour = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
  final cached = _version;
  if (cached != null && cached.hour == hour) return cached.text;
  String? latest;
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client
        .getUrl(
          Uri.parse(
            'https://api.github.com/repos/sissbruecker/linkding/releases/latest',
          ),
        )
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    final json = jsonDecode(body);
    if (response.statusCode == 200 &&
        json is Map &&
        json['name'] is String &&
        (json['name'] as String).isNotEmpty) {
      latest = (json['name'] as String).substring(1);
    }
  } on Object {
    // No network, or not the answer expected: the version alone.
  } finally {
    client.close(force: true);
  }
  final text = latest == null
      ? linkdingVersion
      : latest == linkdingVersion
      ? '$linkdingVersion (latest)'
      : '$linkdingVersion (latest: $latest)';
  _version = (hour: hour, text: text);
  return text;
}
