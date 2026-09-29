final _datetimeRe = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})'
  r'[T ](\d{1,2}):(\d{1,2})'
  r'(?::(\d{1,2})(?:[.,](\d{1,6})\d{0,6})?)?'
  r'\s*(Z|[+-]\d{2}(?::?\d{2})?)?$',
);

final _dateRe = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// Python's `datetime.fromisoformat` for the forms linkding meets: a date,
/// or a date and time with `T` or a space, optional seconds and fraction,
/// and `Z` or an offset. Returns null when it does not apply.
DateTime? _fromIsoFormat(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})'
    r'(?:[T ](\d{2})(?::?(\d{2})(?::?(\d{2})(?:[.,](\d{1,9}))?)?)?'
    r'(Z|[+-]\d{2}(?::?\d{2}(?::?\d{2})?)?)?)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final micros = match[7] == null
      ? 0
      : int.parse(match[7]!.padRight(6, '0').substring(0, 6));
  return _build(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    int.parse(match[4] ?? '0'),
    int.parse(match[5] ?? '0'),
    int.parse(match[6] ?? '0'),
    micros,
    match[8],
  );
}

/// Builds a UTC instant, or throws [FormatException] for an impossible
/// date or time, as Python's `datetime(...)` raises `ValueError`.
DateTime _build(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  int micros,
  String? tz,
) {
  final daysInMonth = month >= 1 && month <= 12
      ? DateTime.utc(year, month + 1, 0).day
      : 0;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > daysInMonth ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw const FormatException('out of range');
  }
  var offsetMinutes = 0;
  if (tz != null && tz != 'Z') {
    final digits = tz.substring(1).replaceAll(':', '');
    final hours = int.parse(digits.substring(0, 2));
    final minutes = digits.length >= 4 ? int.parse(digits.substring(2, 4)) : 0;
    offsetMinutes = hours * 60 + minutes;
    if (tz.startsWith('-')) offsetMinutes = -offsetMinutes;
  }
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    0,
    micros,
  ).subtract(Duration(minutes: offsetMinutes));
}

/// Django's `parse_datetime`: naive values are taken as UTC, linkding's time
/// zone. Returns null when [value] is not a datetime, and throws
/// [FormatException] when it looks like one but is out of range.
DateTime? parseDjangoDateTime(String value) {
  try {
    final iso = _fromIsoFormat(value);
    if (iso != null) return iso;
  } on FormatException {
    // fromisoformat raised; Django falls back to its own pattern.
  }
  final match = _datetimeRe.firstMatch(value);
  if (match == null) return null;
  final micros = match[7] == null ? 0 : int.parse(match[7]!.padRight(6, '0'));
  return _build(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6] ?? '0'),
    micros,
    match[8],
  );
}

/// Django's `parse_date`, as midnight UTC. Null when [value] is not a date;
/// throws [FormatException] for an impossible one.
DateTime? parseDjangoDate(String value) {
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  final match = iso ?? _dateRe.firstMatch(value);
  if (match == null) return null;
  return _build(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    0,
    0,
    0,
    0,
    null,
  );
}

/// How linkding filters by `modified_since` and `added_since`: Django's
/// `DateTimeField.to_python`, where anything it cannot read makes the filter
/// silently disappear. Null means "no filter".
DateTime? parseSinceFilter(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return parseDjangoDateTime(value) ?? parseDjangoDate(value);
  } on FormatException {
    return null;
  }
}

/// DRF's `DateTimeField(input_formats=[ISO_8601])` on a request value.
/// Returns the instant, or the error message DRF would report.
({DateTime? value, String? error}) parseDrfDateTime(Object? value) {
  const message =
      'Datetime has wrong format. Use one of these formats instead: '
      'YYYY-MM-DDThh:mm[:ss[.uuuuuu]][+HH:MM|-HH:MM|Z].';
  if (value is! String) return (value: null, error: message);
  try {
    final parsed = parseDjangoDateTime(value);
    if (parsed != null) return (value: parsed, error: null);
  } on FormatException {
    // falls through to the error
  }
  return (value: null, error: message);
}
