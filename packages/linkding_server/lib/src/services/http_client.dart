import 'dart:async';
import 'dart:io';

/// Refused because the host resolves to an address that is not public.
final class BlockedAddressError implements Exception {
  const BlockedAddressError(this.host, this.address);
  final String host;
  final InternetAddress address;

  @override
  String toString() =>
      'Refusing to connect to $host, which resolves to the non-public address '
      '${address.address}. Use the LD_ALLOWED_INTERNAL_HOSTS option to allow '
      'requests to this host.';
}

/// `LD_ALLOWED_INTERNAL_HOSTS`: `*`, host names (`.example.com` includes
/// subdomains), addresses and CIDR ranges.
final class Allowlist {
  Allowlist(Iterable<String> entries) {
    for (var entry in entries) {
      entry = entry.trim().toLowerCase();
      if (entry.isEmpty) continue;
      if (entry == '*') {
        allowAll = true;
        continue;
      }
      if (entry.startsWith('[')) entry = entry.substring(1);
      if (entry.endsWith(']')) entry = entry.substring(0, entry.length - 1);
      final network = _Network.tryParse(entry);
      if (network != null) {
        networks.add(network);
      } else if (!entry.contains('/')) {
        hostnames.add(entry);
      }
    }
  }

  bool allowAll = false;
  final hostnames = <String>[];
  final networks = <_Network>[];

  bool matchesHost(String host) {
    host = host.toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    for (final name in hostnames) {
      if (name.startsWith('.')) {
        if (host == name.substring(1) || host.endsWith(name)) return true;
      } else if (host == name) {
        return true;
      }
    }
    return false;
  }

  bool matchesAddress(InternetAddress address) {
    final bytes = _unmapped(address.rawAddress);
    return networks.any((n) => n.contains(bytes));
  }
}

/// An IPv4-mapped IPv6 address as its IPv4 bytes; anything else unchanged.
List<int> _unmapped(List<int> raw) {
  if (raw.length == 16 &&
      raw.sublist(0, 10).every((b) => b == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff) {
    return raw.sublist(12);
  }
  return raw;
}

final class _Network {
  _Network(this.bytes, this.prefix);

  static _Network? tryParse(String value) {
    final slash = value.indexOf('/');
    final address = InternetAddress.tryParse(
      slash < 0 ? value : value.substring(0, slash),
    );
    if (address == null) return null;
    final bits = address.rawAddress.length * 8;
    final prefix = slash < 0 ? bits : int.tryParse(value.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > bits) return null;
    return _Network(address.rawAddress, prefix);
  }

  final List<int> bytes;
  final int prefix;

  bool contains(List<int> address) {
    if (address.length != bytes.length) return false;
    var remaining = prefix;
    for (var i = 0; i < bytes.length && remaining > 0; i++) {
      final take = remaining >= 8 ? 8 : remaining;
      final mask = (0xff << (8 - take)) & 0xff;
      if ((address[i] & mask) != (bytes[i] & mask)) return false;
      remaining -= take;
    }
    return true;
  }
}

final _nonPublic = [
  for (final cidr in const [
    // IPv4 special-purpose registry
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
    '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24',
    '192.88.99.0/24', '192.168.0.0/16', '198.18.0.0/15', '198.51.100.0/24',
    '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4', '255.255.255.255/32',
    // IPv6 special-purpose registry, plus the ranges linkding adds
    '::/128', '::1/128', '::/96', '::ffff:0:0/96', '64:ff9b::/96',
    '64:ff9b:1::/48', '100::/64', '2001::/23', '2001:db8::/32', '2002::/16',
    'fc00::/7', 'fe80::/10', 'fec0::/10', 'ff00::/8',
  ])
    _Network.tryParse(cidr)!,
];

/// Whether [address] is publicly routable, as Python's `is_global` decides
/// with linkding's additions. IPv4-mapped IPv6 addresses are judged by the
/// IPv4 address they carry.
bool isPublicAddress(InternetAddress address) {
  final bytes = _unmapped(address.rawAddress);
  return !_nonPublic.any((n) => n.contains(bytes));
}

/// An HTTP client for URLs users supply, refusing internal addresses the
/// way linkding's `http_client` does: after DNS resolution, for every
/// redirect hop, unless the allowlist says otherwise. As in linkding, a
/// configured HTTP proxy does the connecting, and then the check is skipped.
final class GuardedHttpClient {
  GuardedHttpClient(this.allowlist) {
    _client.findProxy = HttpClient.findProxyFromEnvironment;
  }

  final Allowlist allowlist;
  final _client = HttpClient()..autoUncompress = true;

  Future<HttpClientResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    int maxRedirects = 30,
  }) async {
    var current = url;
    for (var hop = 0; ; hop++) {
      await _check(current);
      final request = await _client.getUrl(current).timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.isRedirect && location != null && hop < maxRedirects) {
        await response.drain<void>();
        current = current.resolve(location);
        continue;
      }
      return response;
    }
  }

  Future<void> _check(Uri url) async {
    if (allowlist.allowAll || allowlist.matchesHost(url.host)) return;
    final proxy = HttpClient.findProxyFromEnvironment(url);
    if (proxy != 'DIRECT') return;
    final literal = InternetAddress.tryParse(url.host);
    final addresses = literal != null
        ? [literal]
        : await InternetAddress.lookup(url.host);
    for (final address in addresses) {
      if (!allowlist.matchesAddress(address) && !isPublicAddress(address)) {
        throw BlockedAddressError(url.host, address);
      }
    }
  }

  void close() => _client.close(force: true);
}
