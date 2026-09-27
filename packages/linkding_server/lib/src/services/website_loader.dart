import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:linkding_shared/linkding_shared.dart';

import 'http_client.dart';

/// Reads a page's title, description and preview image; linkding's
/// `website_loader`.
abstract interface class WebsiteMetadataLoader {
  /// Never fails: a page that cannot be loaded or parsed gives empty
  /// metadata, as in linkding.
  Future<WebsiteMetadata> load(String? url, {bool ignoreCache = false});
}

/// The loader that fetches pages, with linkding's cache of the last ten.
final class HttpWebsiteMetadataLoader implements WebsiteMetadataLoader {
  HttpWebsiteMetadataLoader(this.client);

  final GuardedHttpClient client;

  // Python's lru_cache(maxsize=10) on the URL.
  final _cache = <String, WebsiteMetadata>{};

  static const _chunkLimit = 5000 * 1024;
  static const _headers = {
    'Accept': 'text/html,application/xhtml+xml,application/xml',
    'Accept-Encoding': 'gzip, deflate',
    'Dnt': '1',
    'Upgrade-Insecure-Requests': '1',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36',
  };

  @override
  Future<WebsiteMetadata> load(String? url, {bool ignoreCache = false}) async {
    if (url == null) return const WebsiteMetadata();
    if (!ignoreCache) {
      final cached = _cache.remove(url);
      if (cached != null) {
        _cache[url] = cached;
        return cached;
      }
    }
    final metadata = await _load(url);
    _cache[url] = metadata;
    while (_cache.length > 10) {
      _cache.remove(_cache.keys.first);
    }
    return metadata;
  }

  Future<WebsiteMetadata> _load(String url) async {
    final String page;
    try {
      page = await _loadHead(url);
    } on Object catch (error) {
      stderr.writeln('Failed to load metadata for $url: $error');
      return WebsiteMetadata(url: url);
    }
    return parseWebsiteMetadata(url, page);
  }

  /// The document up to `</head>`, at most 5000 KiB of it.
  Future<String> _loadHead(String url) async {
    final uri = Uri.parse(url);
    final response = await client.get(uri, headers: _headers);
    final bytes = <int>[];
    const endOfHead = '</head>';
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      final text = latin1.decode(bytes, allowInvalid: true);
      final end = text.indexOf(endOfHead);
      if (end >= 0) {
        bytes.length = end + endOfHead.length;
        break;
      }
      if (bytes.length > _chunkLimit) break;
    }
    return _decode(bytes, response.headers.contentType?.charset);
  }

  /// linkding guesses the encoding from the bytes and ignores the header,
  /// because sites often declare it wrongly: UTF-8 when it decodes cleanly,
  /// otherwise the declared charset, otherwise Latin-1.
  static String _decode(List<int> bytes, String? declared) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      final encoding = declared == null
          ? null
          : Encoding.getByName(declared.toLowerCase());
      return (encoding ?? latin1).decode(bytes);
    }
  }
}

/// Title, description and preview image from a page's HTML, with
/// BeautifulSoup's quirks: a `<meta>` without `content` stops the parse
/// there, and a relative image URL is resolved against the page.
WebsiteMetadata parseWebsiteMetadata(String url, String page) {
  String? title;
  String? description;
  String? previewImage;
  try {
    final document = html.parse(page);
    final titleElement = document.querySelector('title');
    if (titleElement != null && titleElement.nodes.length == 1) {
      final text = titleElement.nodes.single.text ?? '';
      if (text.isNotEmpty) title = text.trim();
    }

    String? content(dom.Element? element) {
      if (element == null) return null;
      final value = element.attributes['content'];
      if (value == null) throw const FormatException('meta without content');
      return value.isEmpty ? null : value.trim();
    }

    description = content(document.querySelector('meta[name="description"]'));
    description ??= content(
      document.querySelector('meta[property="og:description"]'),
    );

    final image = document.querySelector('meta[property="og:image"]');
    if (image != null) {
      final value = image.attributes['content'];
      if (value == null) throw const FormatException('meta without content');
      previewImage = value.trim();
      if (previewImage.isNotEmpty &&
          !previewImage.startsWith('http://') &&
          !previewImage.startsWith('https://')) {
        previewImage = Uri.parse(url).resolve(previewImage).toString();
      }
      if (previewImage.isEmpty) previewImage = null;
    }
  } on Object {
    // linkding swallows any parse failure and keeps what it found so far.
  }
  return WebsiteMetadata(
    url: url,
    title: title,
    description: description,
    previewImage: previewImage,
  );
}

/// A loader that never touches the network, for tests.
final class NoWebsiteMetadataLoader implements WebsiteMetadataLoader {
  const NoWebsiteMetadataLoader();

  @override
  Future<WebsiteMetadata> load(String? url, {bool ignoreCache = false}) async =>
      WebsiteMetadata(url: url);
}
