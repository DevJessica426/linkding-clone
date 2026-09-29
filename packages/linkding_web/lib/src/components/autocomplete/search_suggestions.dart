import 'package:web/web.dart' as web;

import '../../api.dart';
import '../../input.dart';
import '../../tag_cache.dart';
import 'suggestion.dart';

/// Loads the menu's three sections, numbering their entries in order: tags
/// (after a `#`), recent searches, and bookmarks (from three characters on).
/// The word at the caret of [input] is read once the tags are loaded; [user], [shared] and [unread] narrow
/// the bookmarks the way the page's own search is narrowed.
Future<SuggestionSet> loadSearchSuggestions({
  required web.HTMLInputElement input,
  required String inputValue,
  required String mode,
  required String? user,
  required String? shared,
  required String? unread,
  required SearchHistory history,
}) async {
  var index = 0;

  // Tags, after a `#`.
  final tags = await tagCache.getTags();
  var tagSuggestions = <Suggestion>[];
  final word = currentWord(input);
  if (word.length > 1 && word.startsWith('#')) {
    final search = word.substring(1).toLowerCase();
    tagSuggestions = [
      for (final tag
          in tags.where((t) => t.name.toLowerCase().startsWith(search)).take(5))
        Suggestion.tag(index++, tag.name),
    ];
  }

  final recentSearches = [
    for (final value in history.recentSearches(inputValue, 5))
      Suggestion.search(index++, value),
  ];

  // Bookmarks, from three characters on.
  var bookmarks = <Suggestion>[];
  if (inputValue.length >= 3) {
    final found = await api.listBookmarks(
      {'user': user, 'shared': shared, 'unread': unread, 'q': inputValue},
      limit: 5,
      path: mode.isEmpty ? '' : '/$mode',
    );
    bookmarks = [
      for (final bookmark in found)
        Suggestion.bookmark(
          index++,
          clampText(
            bookmark.title.isNotEmpty ? bookmark.title : bookmark.url,
            60,
          ),
          bookmark.url,
        ),
    ];
  }
  return SuggestionSet(tagSuggestions, recentSearches, bookmarks);
}
