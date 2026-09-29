/// One entry of the search menu.
final class Suggestion {
  Suggestion.tag(this.index, this.tagName)
    : type = 'tag',
      label = '#$tagName',
      value = null,
      url = null;

  Suggestion.search(this.index, String this.value)
    : type = 'search',
      label = value,
      tagName = null,
      url = null;

  Suggestion.bookmark(this.index, this.label, String this.url)
    : type = 'bookmark',
      tagName = null,
      value = null;

  final String type;
  final int index;
  final String label;
  final String? tagName;
  final String? value;
  final String? url;
}

/// The menu's three sections, and every entry in the order they are shown.
final class SuggestionSet {
  SuggestionSet([
    this.tags = const [],
    this.recentSearches = const [],
    this.bookmarks = const [],
  ]) : all = [...tags, ...recentSearches, ...bookmarks];

  final List<Suggestion> tags;
  final List<Suggestion> recentSearches;
  final List<Suggestion> bookmarks;
  final List<Suggestion> all;
}
