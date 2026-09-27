import 'package:dust_dart/serde.dart';

/// Timestamps the way linkding's REST API writes them.
///
/// linkding is Django REST Framework, which renders a UTC datetime with
/// Python's `isoformat()` and swaps `+00:00` for `Z`: six fractional digits,
/// or none at all when the microseconds are zero. Dart's `toIso8601String`
/// writes three or six, so clients comparing strings would see a difference
/// where there is none.
final class DrfDateTimeCodec implements SerDeCodec<DateTime, String> {
  const DrfDateTimeCodec();

  @override
  String serialize(DateTime value) => formatDrfDateTime(value);

  @override
  DateTime deserialize(String value) => DateTime.parse(value).toUtc();
}

const drfDateTime = DrfDateTimeCodec();

/// `2020-09-26T09:46:23.006313Z`, or `2020-09-26T09:46:23Z`.
String formatDrfDateTime(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}';
  final time = '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  final micros = utc.millisecond * 1000 + utc.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return '${date}T$time${fraction}Z';
}
