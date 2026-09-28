/// linkding's `humanize_*_date` helpers and Django's `Paginator` window.
library;

export '../pages/paginator.dart' show Page;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

({int years, int months, int weeks}) _delta(DateTime now, DateTime value) {
  var years = now.year - value.year;
  if (now.month < value.month ||
      (now.month == value.month && now.day < value.day)) {
    years--;
  }
  var months = (now.year - value.year) * 12 + (now.month - value.month);
  if (now.day < value.day) months--;
  final weeks = now.difference(value).inDays ~/ 7;
  return (
    years: years < 0 ? 0 : years,
    months: months < 0 ? 0 : months,
    weeks: weeks < 0 ? 0 : weeks,
  );
}

String _plural(int n) => n == 1 ? '' : 's';

/// "Today", "Yesterday", a weekday, or "3 weeks ago", "2 months ago"...
String humanizeRelativeDate(DateTime value, [DateTime? now]) {
  now = (now ?? DateTime.now()).toUtc();
  value = value.toUtc();
  final d = _delta(now, value);
  if (d.years > 0) return '${d.years} year${_plural(d.years)} ago';
  if (d.months > 0) return '${d.months} month${_plural(d.months)} ago';
  if (d.weeks > 0) return '${d.weeks} week${_plural(d.weeks)} ago';
  final yesterday = now.subtract(const Duration(days: 1));
  if (value.day == now.day) return 'Today';
  if (value.day == yesterday.day) return 'Yesterday';
  return _weekdays[value.weekday - 1];
}

/// "Today", "Yesterday", a weekday, or the date as `MM/DD/YYYY` once it is
/// more than a week old.
String humanizeAbsoluteDate(DateTime value, [DateTime? now]) {
  now = (now ?? DateTime.now()).toUtc();
  value = value.toUtc();
  final d = _delta(now, value);
  if (d.years > 0 || d.months > 0 || d.weeks > 0) return shortDate(value);
  final yesterday = now.subtract(const Duration(days: 1));
  if (value.day == now.day) return 'Today';
  if (value.day == yesterday.day) return 'Yesterday';
  return _weekdays[value.weekday - 1];
}

/// Django's `SHORT_DATE_FORMAT` for English: `m/d/Y`.
String shortDate(DateTime value) {
  final v = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(v.month)}/${two(v.day)}/${v.year}';
}

const _apMonths = [
  'Jan.',
  'Feb.',
  'March',
  'April',
  'May',
  'June',
  'July',
  'Aug.',
  'Sept.',
  'Oct.',
  'Nov.',
  'Dec.',
];

/// Django's `DATETIME_FORMAT` for English, `N j, Y, P`: "Feb. 3, 2021,
/// 4:05 a.m.", with "noon" and "midnight" and no minutes on the hour.
String djangoDateTime(DateTime value) {
  final v = value.toUtc();
  final String time;
  if (v.minute == 0 && v.hour == 0) {
    time = 'midnight';
  } else if (v.minute == 0 && v.hour == 12) {
    time = 'noon';
  } else {
    final hour = v.hour % 12 == 0 ? 12 : v.hour % 12;
    final clock = v.minute == 0
        ? '$hour'
        : '$hour:${v.minute.toString().padLeft(2, '0')}';
    time = '$clock ${v.hour < 12 ? 'a.m.' : 'p.m.'}';
  }
  return '${_apMonths[v.month - 1]} ${v.day}, ${v.year}, $time';
}

/// Django's `filesizeformat`: "123 bytes", "1.2 KB", "3.4 MB"...
String fileSize(int bytes) {
  if (bytes < 1024) return bytes == 1 ? '1 byte' : '$bytes bytes';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
