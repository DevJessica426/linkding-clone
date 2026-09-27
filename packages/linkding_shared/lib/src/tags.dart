/// Tag names as linkding reads them from forms and the API.
library;

/// Trims [name] and joins its words with `-`: tags cannot contain spaces.
String sanitizeTagName(String name) => name.trim().replaceAll(' ', '-');

/// Splits a tag string such as `"java, web dev,Java"` into tag names.
///
/// Empty names are dropped and the rest sanitized. Duplicates are compared
/// ignoring case, and — as with Python's dict, which linkding uses — the
/// *last* spelling wins at the *first* one's position. The result is sorted
/// ignoring case: `["java", "web-dev"]`.
List<String> parseTagString(String? tagString, {String delimiter = ','}) {
  if (tagString == null || tagString.isEmpty) return const [];
  final byLower = <String, String>{};
  for (final raw in tagString.trim().split(delimiter)) {
    if (raw.trim().isEmpty) continue;
    final name = sanitizeTagName(raw);
    byLower[name.toLowerCase()] = name;
  }
  return byLower.values.toList()..sort(compareIgnoringCase);
}

/// The inverse of [parseTagString].
String buildTagString(List<String> names, {String delimiter = ','}) =>
    names.join(delimiter);

/// Orders like Python's `sorted(key=str.lower)`: stable, by lower case only.
int compareIgnoringCase(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());
