import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../pages/paginator.dart';
import '../pages/query.dart';
import '../pages/render.dart';
import '../pages/session_data.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';
import '../web/html.dart' show q;
import '../web/query_params.dart';
import 'tag_forms.dart';

/// `/tags`: search, filter, sort and page through the tags, or remove one.
Future<Result<Response, Rejection>> tagIndex(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final tags = TagsRepo((await request.state<LinkdingDatabase>()).connection);
  final user = visitor.signedIn;
  final form = await request.extract(const PostedForm());
  if (form.has('delete_tag')) {
    final tag = await ownedTag(tags, form['delete_tag'], user.id);
    if (tag == null) return const Err(Rejection.notFound('No Tag matches'));
    (await tags.delete(tag.id, user.id)).orThrow;
    return Ok(Redirect.found(withQuery('/tags', request)).intoResponse());
  }

  final search = (visitor.query['search'] ?? '').trim();
  final unusedOnly = visitor.query['unused'] == 'true';
  final sort = visitor.query['sort'] ?? 'name-asc';
  final total = (await tags.count(user.id)).orThrow;
  final rows = (await tags.listing(
    user.id,
    search.isEmpty ? '' : '%${_escapeLike(search)}%',
    unusedOnly,
    sort,
  )).orThrow;
  final page = Page.of(rows, 50, visitor.query['page']);
  final messages = await (await SessionData.of(request)).takeMessages();
  final filtered = search.isNotEmpty || unusedOnly;
  final query = QueryParams.parse(request.requestedUri.query).encode();
  return Ok(
    renderPage(
      await request.state<TemplateEngine>(),
      visitor,
      title: 'Tags - Linkding',
      template: 'tags/index',
      values: {
        ...messageValues(messages),
        'search': search,
        'unusedOnly': unusedOnly,
        'sortOptions': [
          for (final (value, label) in _sorts)
            {'value': value, 'label': label, 'selected': value == sort},
        ],
        'summary': filtered
            ? 'Showing ${page.total} of $total tags'
            : '$total tags total',
        'hasTags': page.items.isNotEmpty,
        'tags': [for (final tag in page.items) _row(tag)],
        'query': query,
        'pagination': page.items.isEmpty
            ? false
            : paginationValues(visitor, page),
        'emptyTitle': filtered ? 'No tags found' : 'You have no tags yet',
        'emptySubtitle': filtered
            ? 'Try adjusting your search or filters'
            : 'Tags will appear here when you add bookmarks with tags',
      },
    ),
  );
}

const _sorts = [
  ('name-asc', 'Name A-Z'),
  ('name-desc', 'Name Z-A'),
  ('count-asc', 'Fewest bookmarks'),
  ('count-desc', 'Most bookmarks'),
];

Map<String, Object?> _row(TagUsageRow tag) => {
  'id': tag.id,
  'name': tag.name,
  'nameQuery': q(tag.name),
  'count': tag.bookmarkCount,
};

/// Django's escaping of `icontains` values for `LIKE`.
String _escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
