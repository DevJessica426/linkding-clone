import '../../pages/session/visitor.dart';
import '../../pages/support/widgets.dart';
import 'list_page.dart';
import 'search_params.dart';

/// What `bookmark-search` reads: the search box and the search
/// preferences dropdown (`bookmarks/search.html`).
Map<String, Object?> searchValues(Visitor visitor, ListPage p) {
  final s = p.search;
  final modified = {for (final (name, _) in modifiedSearchParams(s)) name};
  final sharedMode = p.kind.searchMode == 'shared';
  final editable = sharedMode
      ? const {'sort'}
      : const {'sort', 'shared', 'unread'};

  Map<String, Object?> filter(
    String name,
    String label,
    List<(String, String)> choices,
    String value,
  ) => {
    'name': name,
    'label': label,
    'bold': modified.contains(name),
    'radios': [
      for (final (i, (choice, text)) in choices.indexed)
        {
          'id': 'id_${name}_$i',
          'radio': radioInput(name, i, choice, choice == value),
          'label': text,
        },
    ],
  };

  return {
    'q': s.q,
    'target': visitor.profile.row.bookmarkLinkTarget,
    'mode': p.kind.searchMode,
    'user': s.user,
    'shared': s.shared,
    'unread': s.unread,
    'searchHidden': hiddenFields(s, const {'q'}),
    'badge':
        modified.contains('sort') ||
        modified.contains('shared') ||
        modified.contains('unread'),
    'sortBold': modified.contains('sort'),
    'sortSelect': selectField(
      'sort',
      sortChoices,
      s.sort,
      classes: 'form-select select-sm',
    ),
    'filters': [
      if (!sharedMode) ...[
        filter('shared', 'Shared filter', sharedChoices, s.shared),
        filter('unread', 'Unread filter', unreadChoices, s.unread),
      ],
    ],
    'preferencesHidden': hiddenFields(s, editable),
  };
}
