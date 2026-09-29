import '../../dom.dart';
import 'suggestion.dart';

/// The skeleton `<ld-search-autocomplete>` renders into its host.
const searchAutocompleteTemplate = '''
      <div class="form-autocomplete">
        <div
          class="form-autocomplete-input form-input "
        >
          <input
            type="search"
            class="form-input"
            autocomplete="off"
          />
        </div>

        <ul class="menu ">
        </ul>
      </div>
    ''';

/// linkding's `renderSuggestions`: a heading, then one link per
/// suggestion, [selected] marked; nothing for no suggestions.
({String html, List<Suggestion> items}) searchSection(
  List<Suggestion> items,
  String title,
  int? selected,
) {
  if (items.isEmpty) return (html: '', items: const []);
  final entries = [
    for (final s in items)
      '''
          <li
            class="menu-item ${selected == s.index ? 'selected' : ''}"
          >
            <a
              href="#"
            >
              ${escapeHtml(s.label)}
            </a>
          </li>
        ''',
  ];
  return (
    html:
        '\n      <li class="menu-item group-item">${escapeHtml(title)}</li>\n'
        '      ${entries.join()}\n    ',
    items: items,
  );
}

/// The menu's content: the template's own text around the three sections,
/// as Lit keeps it, and the entries in the order they were drawn.
({String html, List<Suggestion> items}) searchMenuMarkup(
  SuggestionSet suggestions,
  int? selected,
) {
  final sections = [
    searchSection(suggestions.tags, 'Tags', selected),
    searchSection(suggestions.recentSearches, 'Recent Searches', selected),
    searchSection(suggestions.bookmarks, 'Bookmarks', selected),
  ];
  return (
    html:
        '\n          ${sections.map((s) => s.html).join('\n          ')}\n        ',
    items: [for (final s in sections) ...s.items],
  );
}
