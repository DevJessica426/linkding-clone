import 'package:dust_server/server.dart';

import '../../pages/support/paginator.dart';
import '../../pages/support/render.dart';
import '../../pages/session/visitor.dart';
import 'item_values.dart';
import 'list_page.dart';

/// `bookmarks/bookmark_list.html`: the page's bookmarks, or why there are
/// none, and the pagination.
String renderList(TemplateEngine engine, Visitor visitor, ListPage p) {
  final profile = visitor.profile.row;
  return engine.render('bookmarks/list', {
    ...commonValues(visitor),
    'hasItems': p.page.total > 0,
    'showNotes': profile.permanentNotes,
    'maxLines': profile.bookmarkDescriptionMaxLines,
    'total': p.page.total,
    'target': profile.bookmarkLinkTarget,
    'displayUrl': profile.displayUrl,
    'inlineDescription': profile.bookmarkDescriptionDisplay == 'inline',
    'previewImages': profile.enablePreviewImages,
    'showActions': !p.isPreview,
    'viewAction': profile.displayViewBookmarkAction,
    'editAction': profile.displayEditBookmarkAction,
    'archiveAction': profile.displayArchiveBookmarkAction,
    'removeAction': profile.displayRemoveBookmarkAction,
    'items': [for (final item in p.page.items) itemValues(visitor, p, item)],
    'stickyPagination': profile.stickyPagination,
    'pagination': paginationValues(visitor, p.page, frame: p.paginationFrame),
    'invalidQuery': !p.links.queryIsValid,
    'queryError': p.links.queryError ?? '',
  });
}

/// `bookmarks/tag_cloud.html`: the tags to add to the search, grouped, and
/// the ones it names, to remove.
String renderTagCloud(TemplateEngine engine, ListPage p) {
  final cloud = p.tagCloud;
  final links = p.links;
  return engine.render('bookmarks/tag-cloud', {
    'hasSelected': cloud.selected.isNotEmpty,
    'selected': [
      for (final tag in cloud.selected)
        {'name': tag, 'query': links.removeTag(tag, p.query)},
    ],
    'groups': [
      for (final group in cloud.groups)
        {
          'tags': [
            for (final (i, tag) in group.tags.indexed)
              {
                'highlight': group.highlightFirstChar && i == 0,
                'first': String.fromCharCode(tag.runes.first),
                'rest': String.fromCharCodes(tag.runes.skip(1)),
                'name': tag,
                'query': links.addTag(tag),
              },
          ],
        },
    ],
  });
}
