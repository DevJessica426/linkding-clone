import 'pyurl.dart';

const _ul = '¡-￿';
const _ipv4 =
    r'(?:0|25[0-5]|2[0-4][0-9]|1[0-9]?[0-9]?|[1-9][0-9]?)'
    r'(?:\.(?:0|25[0-5]|2[0-4][0-9]|1[0-9]?[0-9]?|[1-9][0-9]?)){3}';
const _ipv6 = r'\[[0-9a-f:.]+\]';
const _hostname = '[a-z${_ul}0-9](?:[a-z${_ul}0-9-]{0,61}[a-z${_ul}0-9])?';
const _domain = '(?:\\.(?!-)[a-z${_ul}0-9-]{1,63}(?<!-))*';
const _tld = '\\.(?!-)(?:[a-z$_ul-]{2,63}|xn--[a-z0-9]{1,59})(?<!-)\\.?';

final _urlRegex = RegExp(
  r'^(?:[a-z0-9.+-]*)://'
  r'(?:[^\s:@/]+(?::[^\s:@/]*)?@)?'
  '(?:$_ipv4|$_ipv6|($_hostname$_domain$_tld|localhost))'
  r'(?::[0-9]{1,5})?'
  r'(?:[/?#][^\s]*)?'
  r'$',
  caseSensitive: false,
  unicode: true,
);

const _schemes = {'http', 'https', 'ftp', 'ftps'};

/// Django's `URLValidator()` with its default schemes, as linkding's
/// `BookmarkURLValidator` applies it: "Enter a valid URL." when false.
bool isValidUrl(String value) {
  if (value.length > 2048) return false;
  if (value.contains('\t') || value.contains('\r') || value.contains('\n')) {
    return false;
  }
  final scheme = value.split('://').first.toLowerCase();
  if (!_schemes.contains(scheme)) return false;
  final PyUrl split;
  try {
    split = urlsplit(value);
  } on PyValueError {
    return false;
  }
  if (!_urlRegex.hasMatch(value)) return false;
  final bracketed = RegExp(r'^\[(.+)\](?::[0-9]{1,5})?$')
      .firstMatch(split.netloc);
  if (bracketed != null && !isIpv6Address(bracketed[1]!)) return false;
  final hostname = split.hostname;
  return hostname != null && hostname.length <= 253;
}
