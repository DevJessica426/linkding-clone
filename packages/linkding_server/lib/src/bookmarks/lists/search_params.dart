import '../../search/search.dart';

const sortChoices = [
  ('added_asc', 'Added ↑'),
  ('added_desc', 'Added ↓'),
  ('modified_asc', 'Modified ↑'),
  ('modified_desc', 'Modified ↓'),
  ('title_asc', 'Title ↑'),
  ('title_desc', 'Title ↓'),
];
const sharedChoices = [('off', 'Off'), ('yes', 'Shared'), ('no', 'Unshared')];
const unreadChoices = [('off', 'Off'), ('yes', 'Unread'), ('no', 'Read')];

/// The search parameters in `BookmarkSearch.params` order, with their
/// values and whether each differs from its default.
List<(String, String, bool)> searchParams(BookmarkSearch s) => [
  ('q', s.q, s.q.isNotEmpty),
  ('user', s.user, s.user.isNotEmpty),
  ('bundle', '${s.bundle?.id}', s.bundle != null),
  ('sort', s.sort, s.sort != s.defaults['sort']),
  ('shared', s.shared, s.shared != s.defaults['shared']),
  ('unread', s.unread, s.unread != s.defaults['unread']),
  ('modified_since', s.modifiedSince ?? '', s.modifiedSince != null),
  ('added_since', s.addedSince ?? '', s.addedSince != null),
];

/// `BookmarkSearch.query_params`: the parameters that differ from the
/// defaults.
List<(String, String)> modifiedSearchParams(BookmarkSearch s) => [
  for (final (name, value, modified) in searchParams(s))
    if (modified) (name, value),
];

/// What `bookmark-hidden-fields` reads: the modified parameters a form does
/// not edit, which it passes on as hidden inputs.
List<Map<String, String>> hiddenFields(
  BookmarkSearch s,
  Set<String> editable,
) => [
  for (final (name, value, modified) in searchParams(s))
    if (modified && !editable.contains(name)) {'name': name, 'value': value},
];
