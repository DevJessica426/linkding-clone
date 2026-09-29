import '../compat/django.dart';
import '../compat/xml_writer.dart';
import '../search/search.dart';
import 'feed_items.dart';

/// `latest_post_date`: the newest item, or now for an empty feed.
DateTime latestPostDate(List<Candidate> items) {
  DateTime? latest;
  for (final item in items) {
    final added = item.row.dateAdded;
    if (latest == null || added.isAfter(latest)) latest = added;
  }
  return latest ?? DateTime.now().toUtc();
}

/// Django's `Rss201rev2Feed.write` for one of linkding's feeds.
String writeRss(
  FeedKind kind, {
  required String link,
  required String feedUrl,
  required List<Candidate> items,
  required String base,
}) {
  final xml = SimplerXmlGenerator()
    ..startDocument()
    ..startElement('rss', {
      'version': '2.0',
      'xmlns:atom': 'http://www.w3.org/2005/Atom',
    })
    ..startElement('channel')
    ..addQuickElement('title', kind.title)
    ..addQuickElement('link', link)
    ..addQuickElement('description', kind.description)
    ..addQuickElement('atom:link', null, {'rel': 'self', 'href': feedUrl})
    // Django's `get_language()`: without translations, English.
    ..addQuickElement('language', 'en')
    ..addQuickElement('lastBuildDate', rfc2822Date(latestPostDate(items)));
  for (final item in items) {
    final b = item.row;
    // `unique_id` is the link before `add_item` passes it through
    // `iri_to_uri`.
    final guid = addDomain(base, b.url);
    xml
      ..startElement('item')
      ..addQuickElement('title', _sanitize(b.title.isEmpty ? b.url : b.title))
      ..addQuickElement('link', iriToUri(guid))
      ..addQuickElement('description', _sanitize(b.description))
      ..addQuickElement('pubDate', rfc2822Date(b.dateAdded))
      ..addQuickElement('guid', guid);
    for (final tag in [...item.tags]..sort(_compareCodePoints)) {
      xml.addQuickElement('category', tag);
    }
    xml.endElement('item');
  }
  xml
    ..endElement('channel')
    ..endElement('rss');
  return xml.toString();
}

/// Django's `add_domain`: a path gets the site's scheme and host, a
/// network-path reference gets `http:`, and absolute `http`, `https` and
/// `mailto` URLs are kept as they are.
String addDomain(String base, String url) {
  if (url.startsWith('//')) return 'http:$url';
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('mailto:')) {
    return url;
  }
  return iriToUri('$base$url');
}

/// linkding's `sanitize`: control and other invisible characters (Unicode
/// category C) removed, except line breaks and tabs.
final _invisible = RegExp(r'[^\P{C}\n\r\t]', unicode: true);
String _sanitize(String text) => text.replaceAll(_invisible, '');

/// Python's string order, by code point.
int _compareCodePoints(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}
