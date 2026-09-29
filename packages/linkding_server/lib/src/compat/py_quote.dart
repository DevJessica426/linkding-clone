import 'dart:convert';

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
