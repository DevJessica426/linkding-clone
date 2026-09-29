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

export 'py_ipv6.dart' show isIpv6Address;
export 'py_quote.dart';
export 'py_url.dart';
export 'py_urlsplit.dart' show urlparse, urlsplit, urlunparse, urlunsplit;
