import 'pyurl.dart';

/// Python's `int(str)`: surrounding whitespace and `_` between digits
/// allowed, a sign allowed. Null where Python raises `ValueError`.
int? pythonInt(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (!RegExp(r'^[+-]?\d+(?:_\d+)*$').hasMatch(trimmed)) return null;
  return int.tryParse(trimmed.replaceAll('_', ''));
}

/// Django's `iri_to_uri`: everything but the characters a URI may hold
/// percent-encoded as UTF-8; existing `%` escapes are kept.
String iriToUri(String iri) => quote(iri, safe: "/#%[]=:;\$&()+,!?*@'~");

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Django's `rfc2822_date` for a UTC instant, as `email.utils` writes it:
/// `Sun, 27 Sep 2026 07:11:14 +0000`.
String rfc2822Date(DateTime date) {
  final d = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[d.weekday - 1]}, ${two(d.day)} ${_months[d.month - 1]} '
      '${d.year.toString().padLeft(4, '0')} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)} +0000';
}
