/// Python raises `ValueError` for URLs it cannot split.
final class PyValueError implements Exception {
  const PyValueError(this.message);
  final String message;
  @override
  String toString() => 'ValueError: $message';
}

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
