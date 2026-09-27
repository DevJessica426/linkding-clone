/// Enough of Python's `idna.encode` for linkding's auto-tagging, which
/// compares a rule's domain with a bookmark's host after encoding both.
///
/// ASCII labels follow the package exactly: lower-case letters, digits and
/// hyphens only, no hyphen at either end or in positions 3 and 4, at most 63
/// characters, no empty labels. Non-ASCII labels are Punycode-encoded after
/// a simplified code point check (letters, marks and digits) in place of the
/// full IDNA 2008 tables.
library;

final class IdnaError implements Exception {
  const IdnaError(this.message);
  final String message;
  @override
  String toString() => 'IDNAError: $message';
}

final _dots = RegExp('[.。．｡]');
final _asciiPvalid = RegExp(r'^[a-z0-9-]+$');
final _unicodePvalid = RegExp(
  r'^[\p{Ll}\p{Lo}\p{Lm}\p{Mn}\p{Mc}\p{Nd}\-]+$',
  unicode: true,
);

/// Encodes [domain] as `idna.encode` does, or throws.
String idnaEncode(String domain) {
  final labels = domain.split(_dots);
  if (labels.isEmpty || (labels.length == 1 && labels.first.isEmpty)) {
    throw const IdnaError('Empty domain');
  }
  var trailingDot = false;
  if (labels.last.isEmpty) {
    labels.removeLast();
    trailingDot = true;
  }
  final result = <String>[];
  for (final label in labels) {
    final encoded = _alabel(label);
    if (encoded.isEmpty) throw const IdnaError('Empty label');
    result.add(encoded);
  }
  if (trailingDot) result.add('');
  final joined = result.join('.');
  if (joined.length > (trailingDot ? 254 : 253)) {
    throw const IdnaError('Domain too long');
  }
  return joined;
}

bool _isAscii(String s) => s.codeUnits.every((c) => c < 128);

String _alabel(String label) {
  if (_isAscii(label)) {
    _ulabelAscii(label);
    if (label.length > 63) throw const IdnaError('Label too long');
    return label;
  }
  _checkLabel(label);
  final ace = 'xn--${_punycode(label)}';
  if (ace.length > 63) throw const IdnaError('Label too long');
  return ace;
}

void _ulabelAscii(String label) {
  final lower = label.toLowerCase();
  if (lower.startsWith('xn--')) {
    final rest = lower.substring(4);
    if (rest.isEmpty) {
      throw const IdnaError(
        'Malformed A-label, no Punycode eligible content found',
      );
    }
    if (rest.endsWith('-')) {
      throw const IdnaError('A-label must not end with a hyphen');
    }
    return; // decoding and re-checking the Unicode form is not modelled
  }
  _checkLabel(lower);
}

void _checkLabel(String label) {
  if (label.isEmpty) throw const IdnaError('Empty Label');
  if (label.length >= 4 && label.substring(2, 4) == '--') {
    throw const IdnaError(
      'Label has disallowed hyphens in 3rd and 4th position',
    );
  }
  if (label.startsWith('-') || label.endsWith('-')) {
    throw const IdnaError('Label must not start or end with a hyphen');
  }
  final valid = _isAscii(label)
      ? _asciiPvalid.hasMatch(label)
      : _unicodePvalid.hasMatch(label);
  if (!valid) throw const IdnaError('Codepoint not allowed');
}

/// RFC 3492 Punycode.
String _punycode(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  const initialBias = 72, initialN = 128;
  final codePoints = input.runes.toList();
  final output = StringBuffer();
  for (final c in codePoints) {
    if (c < 128) output.writeCharCode(c);
  }
  final basicCount = output.length;
  var handled = basicCount;
  if (basicCount > 0) output.write('-');

  String digit(int d) => String.fromCharCode(d < 26 ? 97 + d : 22 + d);
  int adapt(int delta, int points, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ points;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + (base - tMin + 1) * delta ~/ (delta + skew);
  }

  var n = initialN;
  var delta = 0;
  var bias = initialBias;
  while (handled < codePoints.length) {
    final m = codePoints.where((c) => c >= n).reduce((a, b) => a < b ? a : b);
    delta += (m - n) * (handled + 1);
    n = m;
    for (final c in codePoints) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base; ; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          output.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        output.write(digit(q));
        bias = adapt(delta, handled + 1, handled == basicCount);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return output.toString();
}
