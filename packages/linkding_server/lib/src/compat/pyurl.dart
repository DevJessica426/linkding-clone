/// The parts of Python's `urllib.parse` that linkding's behaviour rests on.
///
/// linkding normalizes URLs, matches auto-tagging rules and builds DRF's
/// pagination links with `urlparse`, `parse_qsl` and `urlencode`. A Dart `Uri`
/// disagrees with them in many small ways (it rejects what Python accepts,
/// lower-cases and decodes differently), and each difference would be a
/// bookmark the clone thinks is new when linkding thinks it is a duplicate.
/// So this is a port of Python 3.13's implementation, not an approximation
/// on top of `Uri`. `test/logic_test.dart` checks it through its callers
/// against output recorded from linkding itself.
library;

import 'dart:convert';

/// Python raises `ValueError` for URLs it cannot split.
final class PyValueError implements Exception {
  const PyValueError(this.message);
  final String message;
  @override
  String toString() => 'ValueError: $message';
}

const _usesNetloc = {
  '', 'ftp', 'http', 'gopher', 'nntp', 'telnet', 'imap', 'wais', 'file', //
  'mms', 'https', 'shttp', 'snews', 'prospero', 'rtsp', 'rtsps', 'rtspu',
  'rsync', 'svn', 'svn+ssh', 'sftp', 'nfs', 'git', 'git+ssh', 'ws', 'wss',
  'itms-services',
};

const _usesParams = {
  '', 'ftp', 'hdl', 'prospero', 'http', 'imap', 'https', 'shttp', 'rtsp', //
  'rtsps', 'rtspu', 'sip', 'sips', 'mms', 'sftp', 'tel',
};

final _schemeChars = RegExp(r'^[a-zA-Z0-9+\-.]+$');
final _asciiAlpha = RegExp(r'^[a-zA-Z]$');

/// `urlsplit` / `urlparse` results, with Python's netloc properties.
final class PyUrl {
  const PyUrl(
    this.scheme,
    this.netloc,
    this.path,
    this.params,
    this.query,
    this.fragment,
  );

  final String scheme;
  final String netloc;
  final String path;

  /// `;params` of the last path segment; always empty from [urlsplit].
  final String params;

  final String query;
  final String fragment;

  (String?, String?) get _userinfo {
    final at = netloc.lastIndexOf('@');
    if (at < 0) return (null, null);
    final userinfo = netloc.substring(0, at);
    final colon = userinfo.indexOf(':');
    if (colon < 0) return (userinfo, null);
    return (userinfo.substring(0, colon), userinfo.substring(colon + 1));
  }

  (String, String?) get _hostinfo {
    final at = netloc.lastIndexOf('@');
    final hostinfo = at < 0 ? netloc : netloc.substring(at + 1);
    String hostname;
    String port;
    final open = hostinfo.indexOf('[');
    if (open >= 0) {
      final bracketed = hostinfo.substring(open + 1);
      final close = bracketed.indexOf(']');
      if (close < 0) {
        hostname = bracketed;
        port = '';
      } else {
        hostname = bracketed.substring(0, close);
        final rest = bracketed.substring(close + 1);
        final colon = rest.indexOf(':');
        port = colon < 0 ? '' : rest.substring(colon + 1);
      }
    } else {
      final colon = hostinfo.indexOf(':');
      hostname = colon < 0 ? hostinfo : hostinfo.substring(0, colon);
      port = colon < 0 ? '' : hostinfo.substring(colon + 1);
    }
    return (hostname, port.isEmpty ? null : port);
  }

  String? get username => _userinfo.$1;
  String? get password => _userinfo.$2;

  /// Lower-cased, without brackets, or null when empty. An IPv6 zone after
  /// `%` keeps its case.
  String? get hostname {
    final hostname = _hostinfo.$1;
    if (hostname.isEmpty) return null;
    final percent = hostname.indexOf('%');
    if (percent < 0) return hostname.toLowerCase();
    return hostname.substring(0, percent).toLowerCase() +
        hostname.substring(percent);
  }

  /// The port, or null. Throws [PyValueError] when it is not a number from
  /// 0 to 65535, as Python does.
  int? get port {
    final port = _hostinfo.$2;
    if (port == null) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(port)) {
      throw PyValueError('Port could not be cast to integer value as $port');
    }
    final value = int.parse(port);
    if (value > 65535) throw const PyValueError('Port out of range 0-65535');
    return value;
  }
}

String _lstripC0(String url) {
  var i = 0;
  while (i < url.length && url.codeUnitAt(i) <= 0x20) {
    i++;
  }
  return url.substring(i);
}

/// `urllib.parse.urlsplit`.
PyUrl urlsplit(String url, {String scheme = ''}) {
  url = _lstripC0(url);
  for (final unsafe in const ['\t', '\r', '\n']) {
    url = url.replaceAll(unsafe, '');
  }
  var netloc = '';
  var query = '';
  var fragment = '';
  final colon = url.indexOf(':');
  if (colon > 0 &&
      _asciiAlpha.hasMatch(url[0]) &&
      _schemeChars.hasMatch(url.substring(0, colon))) {
    scheme = url.substring(0, colon).toLowerCase();
    url = url.substring(colon + 1);
  }
  if (url.startsWith('//')) {
    var delim = url.length;
    for (final c in const ['/', '?', '#']) {
      final at = url.indexOf(c, 2);
      if (at >= 0 && at < delim) delim = at;
    }
    netloc = url.substring(2, delim);
    url = url.substring(delim);
    final hasOpen = netloc.contains('[');
    final hasClose = netloc.contains(']');
    if (hasOpen != hasClose) throw const PyValueError('Invalid IPv6 URL');
    if (hasOpen && hasClose) _checkBracketedNetloc(netloc);
  }
  final hash = url.indexOf('#');
  if (hash >= 0) {
    fragment = url.substring(hash + 1);
    url = url.substring(0, hash);
  }
  final question = url.indexOf('?');
  if (question >= 0) {
    query = url.substring(question + 1);
    url = url.substring(0, question);
  }
  return PyUrl(scheme, netloc, url, '', query, fragment);
}

void _checkBracketedNetloc(String netloc) {
  final at = netloc.lastIndexOf('@');
  final hostAndPort = at < 0 ? netloc : netloc.substring(at + 1);
  final open = hostAndPort.indexOf('[');
  String hostname;
  if (open >= 0) {
    if (open > 0) throw const PyValueError('Invalid IPv6 URL');
    final bracketed = hostAndPort.substring(open + 1);
    final close = bracketed.indexOf(']');
    hostname = close < 0 ? bracketed : bracketed.substring(0, close);
    final port = close < 0 ? '' : bracketed.substring(close + 1);
    if (port.isNotEmpty && !port.startsWith(':')) {
      throw const PyValueError('Invalid IPv6 URL');
    }
  } else {
    final colon = hostAndPort.indexOf(':');
    hostname = colon < 0 ? hostAndPort : hostAndPort.substring(0, colon);
  }
  if (hostname.startsWith('v')) {
    if (!RegExp(r'^v[a-fA-F0-9]+\..+$').hasMatch(hostname)) {
      throw const PyValueError('IPvFuture address is invalid');
    }
    return;
  }
  if (!isIpv6Address(hostname)) {
    throw PyValueError('$hostname does not appear to be an IPv6 address');
  }
}

/// Whether [value] is an IPv6 address as Python's `ipaddress` reads one,
/// optionally with a `%zone`.
bool isIpv6Address(String value) {
  final percent = value.indexOf('%');
  final address = percent < 0 ? value : value.substring(0, percent);
  if (percent >= 0 && percent == value.length - 1) return false;
  if (!address.contains(':')) return false;
  try {
    Uri.parseIPv6Address(address);
    return true;
  } on FormatException {
    return false;
  }
}

/// `urllib.parse.urlparse`: [urlsplit] plus `;params` on the last segment.
PyUrl urlparse(String url) {
  final split = urlsplit(url);
  var path = split.path;
  var params = '';
  if (_usesParams.contains(split.scheme) && path.contains(';')) {
    final slash = path.lastIndexOf('/');
    final semicolon = slash >= 0 ? path.indexOf(';', slash) : path.indexOf(';');
    if (semicolon >= 0) {
      params = path.substring(semicolon + 1);
      path = path.substring(0, semicolon);
    }
  }
  return PyUrl(
    split.scheme,
    split.netloc,
    path,
    params,
    split.query,
    split.fragment,
  );
}

/// `urllib.parse.urlunsplit`.
String urlunsplit(
  String scheme,
  String netloc,
  String path,
  String query,
  String fragment,
) {
  var url = path;
  if (netloc.isNotEmpty) {
    if (url.isNotEmpty && !url.startsWith('/')) url = '/$url';
    url = '//$netloc$url';
  } else if (url.startsWith('//')) {
    url = '//$url';
  } else if (scheme.isNotEmpty &&
      _usesNetloc.contains(scheme) &&
      (url.isEmpty || url.startsWith('/'))) {
    url = '//$url';
  }
  if (scheme.isNotEmpty) url = '$scheme:$url';
  if (query.isNotEmpty) url = '$url?$query';
  if (fragment.isNotEmpty) url = '$url#$fragment';
  return url;
}

/// `urllib.parse.urlunparse`.
String urlunparse(
  String scheme,
  String netloc,
  String path,
  String params,
  String query,
  String fragment,
) => urlunsplit(
  scheme,
  netloc,
  params.isEmpty ? path : '$path;$params',
  query,
  fragment,
);

const _hex = '0123456789ABCDEFabcdef';

List<int> _unquoteBytes(List<int> bytes) {
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x25 &&
        i + 2 < bytes.length &&
        _hex.contains(String.fromCharCode(bytes[i + 1])) &&
        _hex.contains(String.fromCharCode(bytes[i + 2]))) {
      out.add(
        int.parse(
          String.fromCharCodes([bytes[i + 1], bytes[i + 2]]),
          radix: 16,
        ),
      );
      i += 2;
    } else {
      out.add(b);
    }
  }
  return out;
}

/// `urllib.parse.unquote`: `%XX` sequences decoded as UTF-8, invalid bytes
/// replaced with U+FFFD. Runs of non-ASCII text are left as they are.
String unquote(String string) {
  if (!string.contains('%')) return string;
  final out = StringBuffer();
  final ascii = RegExp(r'[\x00-\x7f]+');
  var previous = 0;
  for (final match in ascii.allMatches(string)) {
    out.write(string.substring(previous, match.start));
    out.write(
      utf8.decode(_unquoteBytes(match[0]!.codeUnits), allowMalformed: true),
    );
    previous = match.end;
  }
  out.write(string.substring(previous));
  return out.toString();
}

/// `urllib.parse.unquote_plus`.
String unquotePlus(String string) => unquote(string.replaceAll('+', ' '));

/// `urllib.parse.parse_qsl` with `&` as the only separator.
List<(String, String)> parseQsl(String qs, {bool keepBlankValues = false}) {
  if (qs.isEmpty) return const [];
  final result = <(String, String)>[];
  for (final nameValue in qs.split('&')) {
    if (nameValue.isEmpty) continue;
    final eq = nameValue.indexOf('=');
    final name = eq < 0 ? nameValue : nameValue.substring(0, eq);
    final value = eq < 0 ? '' : nameValue.substring(eq + 1);
    if (value.isNotEmpty || keepBlankValues) {
      result.add((unquotePlus(name), unquotePlus(value)));
    }
  }
  return result;
}

/// `urllib.parse.parse_qs`, keeping the first-seen order of names.
Map<String, List<String>> parseQs(String qs, {bool keepBlankValues = false}) {
  final result = <String, List<String>>{};
  for (final (name, value) in parseQsl(qs, keepBlankValues: keepBlankValues)) {
    (result[name] ??= []).add(value);
  }
  return result;
}

bool _alwaysSafe(int b) =>
    (b >= 0x41 && b <= 0x5a) ||
    (b >= 0x61 && b <= 0x7a) ||
    (b >= 0x30 && b <= 0x39) ||
    b == 0x5f ||
    b == 0x2e ||
    b == 0x2d ||
    b == 0x7e;

/// `urllib.parse.quote`.
String quote(String string, {String safe = '/'}) {
  final safeBytes = safe.codeUnits.toSet();
  final out = StringBuffer();
  for (final b in utf8.encode(string)) {
    if (_alwaysSafe(b) || (b < 128 && safeBytes.contains(b))) {
      out.writeCharCode(b);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// `urllib.parse.quote_plus`.
String quotePlus(String string, {String safe = ''}) {
  if (!string.contains(' ')) return quote(string, safe: safe);
  return quote(string, safe: '$safe ').replaceAll(' ', '+');
}

/// `urllib.parse.urlencode` over pairs, with `quote_plus` unless [quoteVia]
/// says otherwise and `safe=''`.
String urlencode(
  Iterable<(String, String)> pairs, {
  String Function(String value, {String safe}) quoteVia = quotePlus,
}) => [
  for (final (k, v) in pairs)
    '${quoteVia(k, safe: '')}=${quoteVia(v, safe: '')}',
].join('&');
