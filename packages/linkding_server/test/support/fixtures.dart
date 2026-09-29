import 'dart:convert';
import 'dart:io';

/// A recorded fixture from `test/fixtures/`, written by the tool of the
/// same name in `/tool` from the original Python.
Map<String, Object?> loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// The rows recorded under [key].
List<List<Object?>> fixtureRows(Map<String, Object?> fixture, String key) =>
    (fixture[key]! as List<Object?>).cast<List<Object?>>();

/// Python's `datetime.isoformat()` for an aware UTC value (dates from
/// `parse_date` are naive dates, written without a time).
String pythonIso(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}$fraction+00:00';
}
