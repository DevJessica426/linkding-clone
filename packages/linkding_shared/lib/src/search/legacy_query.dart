/// The query as legacy search reads it: space-separated words, `#tags`, and
/// the two `!` commands, all combined with `and`. Bundles still use it.
final class LegacyQuery {
  const LegacyQuery({
    required this.searchTerms,
    required this.tagNames,
    required this.untagged,
    required this.unread,
  });

  factory LegacyQuery.parse(String? query) {
    final words = (query ?? '')
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    final tags = <String, String>{};
    for (final word in words.where((w) => w.startsWith('#'))) {
      tags[word.substring(1).toLowerCase()] = word.substring(1);
    }
    return LegacyQuery(
      searchTerms: [
        for (final word in words)
          if (!word.startsWith('#') && !word.startsWith('!')) word,
      ],
      tagNames: tags.values.toList(),
      untagged: words.contains('!untagged'),
      unread: words.contains('!unread'),
    );
  }

  final List<String> searchTerms;
  final List<String> tagNames;
  final bool untagged;
  final bool unread;
}
