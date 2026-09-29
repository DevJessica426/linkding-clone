import 'py_ipv6.dart';
import 'py_url.dart';

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
    if (hasOpen && hasClose) checkBracketedNetloc(netloc);
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
