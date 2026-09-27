import 'package:dio/dio.dart';

import 'linkding_api.dart';

/// A [LinkdingApi] with its connection: base URL and API token.
///
/// The token goes into `Dio.options.headers` as `Authorization: Token ...`,
/// which is the one form every linkding version accepts.
final class LinkdingClient {
  LinkdingClient({required String baseUrl, String? token, Dio? dio})
    : dio = dio ?? Dio() {
    this.dio.options.baseUrl = baseUrl;
    this.token = token;
  }

  final Dio dio;
  late final LinkdingApi api = LinkdingApi(dio);

  String? _token;
  String? get token => _token;
  set token(String? value) {
    _token = value;
    if (value == null) {
      dio.options.headers.remove('authorization');
    } else {
      dio.options.headers['authorization'] = 'Token $value';
    }
  }
}
