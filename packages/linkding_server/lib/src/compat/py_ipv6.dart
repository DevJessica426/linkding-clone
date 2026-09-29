import 'py_url.dart';

void checkBracketedNetloc(String netloc) {
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
