import 'package:linkding_server/src/compat/django_convert.dart';
import 'package:test/test.dart';

/// The small Python and Django conversions the feeds and pages rest on,
/// against what Django 6.0 wrote for the same input.
void main() {
  test('iri_to_uri', () {
    expect(
      iriToUri('http://ex.com/päth?q=a b&x=%20#frag|{}'),
      'http://ex.com/p%C3%A4th?q=a%20b&x=%20#frag%7C%7B%7D',
    );
  });

  test('rfc2822_date', () {
    expect(
      rfc2822Date(DateTime.utc(2026, 1, 5, 3, 4, 5, 0, 999)),
      'Mon, 05 Jan 2026 03:04:05 +0000',
    );
  });

  test('int() as Python reads a query value', () {
    expect(pythonInt(' 1_0 '), 10);
    expect(pythonInt('+3'), 3);
    expect(pythonInt('-0'), 0);
    for (final bad in ['', 'x', '1.5', '1__0', '_1', '1_']) {
      expect(pythonInt(bad), isNull, reason: bad);
    }
  });
}
