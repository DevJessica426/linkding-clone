/// The bookmark list pages: linkding's `views/contexts.py` and the
/// templates of `bookmark_page.html`, rendered from plain values.
library;

import 'package:linkding_shared/linkding_shared.dart';

import '../config.dart';
import '../core/profile.dart';
import '../core/urls.dart';
import '../db/rows.dart';
import '../services/search.dart';
import 'context.dart';
import 'format.dart';
import 'forms.dart';
import 'html.dart';
import 'markdown.dart';
import 'query_params.dart';

/// One of the three lists, with its addresses and texts.
enum ListKind {
  active(BookmarkList.active, '/bookmarks', 'Bookmarks', '', 'bulk_unarchive'),
  archived(
    BookmarkList.archived,
    '/bookmarks/archived',
    'Archived bookmarks',
    'archived',
    'bulk_archive',
  ),
  shared(
    BookmarkList.shared,
    '/bookmarks/shared',
    'Shared bookmarks',
    'shared',
    '',
  );

  const ListKind(
    this.list,
    this.indexUrl,
    this.title,
    this.searchMode,
    this.disabledBulkAction,
  );

  final BookmarkList list;
  final String indexUrl;
  final String title;
  final String searchMode;
  final String disabledBulkAction;

  String get actionUrl => '$indexUrl/action';
  bool get bulkEdit => this != shared;
}

/// linkding's `RequestContext`: the links a list page builds from its own
/// query string, without `details`.
final class ListLinks {
  ListLinks(this.kind, QueryParams query, this.profile)
    : params = query.copy()..remove('details') {
    if (!profile.legacySearch) {
      try {
        expression = parseSearchQuery(query['q'] ?? '');
      } on SearchQueryParseError catch (error) {
        queryError = error.message;
      }
    }
  }

  final ListKind kind;
  final QueryParams params;
  final Profile profile;

  SearchExpression? expression;
  String? queryError;

  bool get queryIsValid => queryError == null;

  String _url(String base, [Map<String, String> add = const {}]) {
    final p = params.copy();
    add.forEach(p.add);
    final encoded = p.encode();
    return encoded.isEmpty ? base : '$base?$encoded';
  }

  String index() => _url(kind.indexUrl);
  String action([Map<String, String> add = const {}]) =>
      _url(kind.actionUrl, add);
  String details(int id) => _url(kind.indexUrl, {'details': '$id'});

  /// `AddTagItem.query_string`: the search with `#tag` added.
  String addTag(String tag) {
    final p = params.copy();
    var q = p['q'] ?? '';
    if (expression is OrExpression) q = '($q)';
    p['q'] = '$q #$tag'.trim();
    p
      ..remove('details')
      ..remove('page');
    return p.encode();
  }

  /// `RemoveTagItem.query_string`: the search without the tag.
  String removeTag(String tag, QueryParams query) {
    if (profile.legacySearch) {
      final p = query.copy();
      if (p['q'] case final q?) {
        final lower = tag.toLowerCase();
        p['q'] = q
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .where((part) => part.toLowerCase() != '#$lower')
            .where((part) => !profile.laxTags || part.toLowerCase() != lower)
            .join(' ');
      }
      p
        ..remove('details')
        ..remove('page');
      return p.encode();
    }
    final p = params.copy();
    p['q'] = stripTagFromQuery(p['q'] ?? '', tag, laxTags: profile.laxTags);
    p
      ..remove('details')
      ..remove('page');
    return p.encode();
  }
}

/// A tag cloud group: tags sharing a first letter, or all of them.
final class TagGroup {
  TagGroup(this.char, {this.highlightFirstChar = true});

  final String char;
  final bool highlightFirstChar;
  final List<String> tags = [];
}

final _cjk = RegExp(r'^[一-鿿]');

/// `TagGroup.create_tag_groups`.
List<TagGroup> tagGroups(String mode, Iterable<String> names) {
  final sorted = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (mode != 'alphabetical') {
    if (sorted.isEmpty) return const [];
    return [
      TagGroup('Ungrouped', highlightFirstChar: false)..tags.addAll(sorted),
    ];
  }
  final groups = <TagGroup>[];
  final cjk = TagGroup('Ideographic');
  for (final name in sorted) {
    final char = String.fromCharCode(name.runes.first).toLowerCase();
    if (_cjk.hasMatch(char)) {
      cjk.tags.add(name);
    } else if (groups.isEmpty || groups.last.char != char) {
      groups.add(TagGroup(char)..tags.add(name));
    } else {
      groups.last.tags.add(name);
    }
  }
  if (cjk.tags.isNotEmpty) groups.add(cjk);
  return groups;
}

/// `TagCloudContext`: the tags of every match, less the ones the search
/// already names, which are listed to remove instead.
final class TagCloud {
  TagCloud(this.groups, this.selected);

  /// [candidateTags] are the tags on the matches, [selectedTags] the tags
  /// the query names; both are compared by name ignoring case, keeping the
  /// last of each, and by identity for what is left.
  factory TagCloud.of(
    String grouping,
    List<BookmarkTagRow> candidateTags,
    List<TagRow> selectedTags,
  ) {
    final unique = <String, (int, String)>{};
    final byId = {for (final t in candidateTags) t.tagId: t}.values.toList()
      ..sort((a, b) => a.tagId.compareTo(b.tagId));
    for (final tag in byId) {
      unique[tag.name.toLowerCase()] = (tag.tagId, tag.name);
    }
    final selected = <String, (int, String)>{};
    for (final tag in selectedTags) {
      selected[tag.name.toLowerCase()] = (tag.id, tag.name);
    }
    final uniqueIds = {for (final t in unique.values) t.$1};
    final selectedIds = {for (final t in selected.values) t.$1};
    final unselected = [
      for (final t in unique.values)
        if (!selectedIds.contains(t.$1)) t.$2,
      for (final t in selected.values)
        if (!uniqueIds.contains(t.$1)) t.$2,
    ];
    return TagCloud(tagGroups(grouping, unselected), [
      for (final t in selected.values) t.$2,
    ]);
  }

  final List<TagGroup> groups;
  final List<String> selected;
}

/// Everything the list page shows.
final class ListPage {
  ListPage({
    required this.kind,
    required this.links,
    required this.query,
    required this.search,
    required this.page,
    required this.owners,
    required this.tagCloud,
    required this.bundles,
    required this.selectedBundleId,
    required this.users,
    required this.details,
    this.isPreview = false,
    this.paginationFrame = '_top',
  });

  final ListKind kind;
  final ListLinks links;
  final QueryParams query;
  final BookmarkSearch search;
  final Page<Candidate> page;

  /// Usernames of the owners of the bookmarks on this page.
  final Map<int, String> owners;
  final TagCloud tagCloud;

  /// The user's bundles, or null on the shared page.
  final List<BundleRow>? bundles;
  final int? selectedBundleId;

  /// Owners with shared bookmarks matching the search, on the shared page.
  final List<String>? users;
  final Details? details;

  /// The bundle editor's preview: the bookmarks without their actions.
  final bool isPreview;

  /// The Turbo frame the pagination links load into.
  final String paginationFrame;
}

/// `BookmarkDetailsContext`.
final class Details {
  Details({
    required this.bookmark,
    required this.tags,
    required this.assets,
    required this.isEditable,
    required this.uploadsEnabled,
  });

  final BookmarkRow bookmark;
  final List<String> tags;
  final List<AssetRow> assets;
  final bool isEditable;
  final bool uploadsEnabled;
}

const _sortChoices = [
  ('added_asc', 'Added ↑'),
  ('added_desc', 'Added ↓'),
  ('modified_asc', 'Modified ↑'),
  ('modified_desc', 'Modified ↓'),
  ('title_asc', 'Title ↑'),
  ('title_desc', 'Title ↓'),
];
const _sharedChoices = [('off', 'Off'), ('yes', 'Shared'), ('no', 'Unshared')];
const _unreadChoices = [('off', 'Off'), ('yes', 'Unread'), ('no', 'Read')];

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

/// Hidden inputs for the modified parameters a form does not edit.
String _hiddenFields(BookmarkSearch s, Set<String> editable) => [
  for (final (name, value, modified) in searchParams(s))
    if (modified && !editable.contains(name)) hiddenInput(name, value),
].join();

String _icon(String name) => '${static('icons.svg')}?v=$linkdingVersion#$name';

/// `bookmarks/bookmark_page.html`.
String bookmarkPageContent(PageContext c, ListPage p) {
  final kind = p.kind;
  final profile = c.profile.row;
  final bundles = p.bundles ?? const [];
  final bulkToggle = kind.bulkEdit
      ? '''
          <button class="btn hide-sm ml-2 bulk-edit-active-toggle" title="Bulk edit">
            <svg width="20px" height="20px">
              <use href="${_icon('bulk-edit')}"></use>
            </svg>
          </button>'''
      : '';
  return '''
  <ld-bookmark-page ${kind.bulkEdit ? '' : 'no-bulk-edit'}
                    class="bookmarks-page grid columns-md-1 ${profile.collapseSidePanel ? 'collapse-side-panel' : ''}">
    <main class="main col-2" aria-labelledby="main-heading">
      <div class="section-header ${kind.bulkEdit ? 'mb-0' : ''}">
        <h1 id="main-heading">${kind.title}</h1>
        <div class="header-controls">
${_search(c, p)}
$bulkToggle
          <ld-filter-drawer-trigger>
            <button class="btn ml-2">Filters</button>
          </ld-filter-drawer-trigger>
        </div>
      </div>
      <form class="bookmark-actions"
            action="${p.links.action()}"
            method="post"
            autocomplete="off">
        ${c.csrfInput}
${kind.bulkEdit ? _bulkEditBar(c, p) : ''}
        <div id="bookmark-list-container">${bookmarkList(c, p)}</div>
      </form>
    </main>
    <div class="side-panel col-1 hide-md">
${bundles.isNotEmpty ? _bundleSection(c, p, bundles) : ''}
${p.users != null ? _userSection(p) : ''}
${_tagSection(c, p)}
    </div>
  </ld-bookmark-page>''';
}

/// `bookmarks/search.html`.
String _search(PageContext c, ListPage p) {
  final s = p.search;
  final modified = {for (final (name, _) in modifiedSearchParams(s)) name};
  final sharedMode = p.kind.searchMode == 'shared';
  final editable = sharedMode
      ? const {'sort'}
      : const {'sort', 'shared', 'unread'};
  String bold(String name) => modified.contains(name) ? ' text-bold' : '';
  String radios(String name, List<(String, String)> choices, String value) {
    var i = 0;
    return [
      for (final (choice, label) in choices)
        '''
              <label for="id_${name}_$i" class="form-radio form-inline">
                ${radioInput(name, i++, choice, choice == value)}
                <i class="form-icon"></i>
                $label
              </label>''',
    ].join('\n');
  }

  final hasModifiedPreferences =
      modified.contains('sort') ||
      modified.contains('shared') ||
      modified.contains('unread');
  return '''
<div class="search-container">
  <form id="search" action="" method="get" role="search">
    <ld-search-autocomplete input-name="q"
                            input-placeholder="Search for words or #tags"
                            input-value="${e(s.q)}"
                            target="${e(c.profile.row.bookmarkLinkTarget)}"
                            mode="${p.kind.searchMode}"
                            user="${e(s.user)}"
                            shared="${e(s.shared)}"
                            unread="${e(s.unread)}">
    </ld-search-autocomplete>
    <input type="submit" value="Search" class="d-none">
    ${_hiddenFields(s, const {'q'})}
  </form>
  <ld-dropdown class="search-options dropdown dropdown-right">
    <button type="button"
            aria-label="Search preferences"
            class="btn dropdown-toggle${hasModifiedPreferences ? ' badge' : ''}">
      <svg width="20" height="20">
        <use href="${_icon('preferences')}"></use>
      </svg>
    </button>
    <div class="menu" tabindex="0">
      <form id="search_preferences" action="" method="post">
        ${c.csrfInput}
          <div class="form-group">
            <label for="id_sort"
                   class="form-label${bold('sort')}">Sort by</label>
            ${selectField('sort', _sortChoices, s.sort, classes: 'form-select select-sm')}
          </div>
${sharedMode ? '' : '''
          <div class="form-group radio-group"
               role="radiogroup"
               aria-labelledby="search-shared-label">
            <label id="search-shared-label"
                   class="form-label${bold('shared')}">
              Shared filter
            </label>
${radios('shared', _sharedChoices, s.shared)}
          </div>
          <div class="form-group radio-group"
               role="radiogroup"
               aria-labelledby="search-unread-label">
            <label id="search-unread-label"
                   class="form-label${bold('unread')}">
              Unread filter
            </label>
${radios('unread', _unreadChoices, s.unread)}
          </div>'''}
        <div class="actions">
          <button type="submit" class="btn btn-sm btn-primary" name="apply">Apply</button>
${c.isAuthenticated ? '            <button type="submit" class="btn btn-sm" name="save">Save as default</button>' : ''}
        </div>
        ${_hiddenFields(s, editable)}
      </form>
    </div>
  </ld-dropdown>
</div>''';
}

/// `bookmarks/bulk_edit_bar.html`, minified as `{% htmlmin %}` leaves it.
String _bulkEditBar(PageContext c, ListPage p) {
  final disabled = p.kind.disabledBulkAction;
  final options = [
    if (disabled != 'bulk_archive') ('bulk_archive', 'Archive'),
    if (disabled != 'bulk_unarchive') ('bulk_unarchive', 'Unarchive'),
    ('bulk_delete', 'Delete'),
    ('bulk_tag', 'Add tags'),
    ('bulk_untag', 'Remove tags'),
    ('bulk_read', 'Mark as read'),
    ('bulk_unread', 'Mark as unread'),
    if (c.profile.row.enableSharing) ('bulk_share', 'Share'),
    if (c.profile.row.enableSharing) ('bulk_unshare', 'Unshare'),
    ('bulk_refresh', 'Refresh from website'),
  ].map((o) => '<option value="${o.$1}">${o.$2}</option>').join(' ');
  return ' <div class="bulk-edit-bar"> <label class="form-checkbox bulk-edit-checkbox all"> '
      '<input type="checkbox"> <i class="form-icon"></i> </label> '
      '<select name="bulk_action" class="form-select select-sm"> $options </select> '
      '<ld-tag-autocomplete input-name="bulk_tag_string" input-placeholder="Tag names..." '
      'variant="small"> </ld-tag-autocomplete> <button data-confirm type="submit" '
      'name="bulk_execute" class="btn btn-link btn-sm"> <span>Execute</span> </button> '
      '<label class="form-checkbox select-across d-none"> <input type="checkbox" '
      'name="bulk_select_across"> <i class="form-icon"></i> All <span class="total">'
      '${p.page.total}</span> bookmarks </label> </div> ';
}

/// `bookmarks/bookmark_list.html`.
String bookmarkList(PageContext c, ListPage p) {
  final profile = c.profile.row;
  final links = p.links;
  final String body;
  if (p.page.total == 0) {
    body = _empty(links);
  } else {
    final items = p.page.items.map((item) => _item(c, p, item)).join('\n');
    body =
        '''
  <section aria-label="Bookmark list">
    <ul class="bookmark-list${profile.permanentNotes ? ' show-notes' : ''}"
        role="list"
        tabindex="-1"
        style="--ld-bookmark-description-max-lines:${profile.bookmarkDescriptionMaxLines}"
        data-bookmarks-total="${p.page.total}">
$items
    </ul>
    <div class="bookmark-pagination${profile.stickyPagination ? ' sticky' : ''}">
${pagination(c, p.page, frame: p.paginationFrame)}
    </div>
  </section>''';
  }
  return '''
$body
<script>
  document.dispatchEvent(new CustomEvent('bookmark-list-updated'));
</script>
''';
}

String _empty(ListLinks links) {
  if (!links.queryIsValid) {
    return '''
<div class="empty mt-4">
    <p class="empty-title h5">Invalid search query</p>
    <p class="empty-subtitle">
      The search query you entered is not valid. Common reasons are unclosed parentheses or a logical operator (AND, OR,
      NOT) without operands. The error message from the parser is: "${e(links.queryError)}".
    </p>
</div>''';
  }
  return '''
<div class="empty mt-4">
    <p class="empty-title h5">You have no bookmarks yet</p>
    <p class="empty-subtitle">
      You can get started by <a href="/bookmarks/new">adding</a> bookmarks,
      <a href="/settings/general">importing</a> your existing bookmarks or configuring the
      <a href="/settings/integrations">browser extension</a> or the <a href="/settings/integrations">bookmarklet</a>.
    </p>
</div>''';
}

/// One `BookmarkItem`.
String _item(PageContext c, ListPage p, Candidate candidate) {
  final profile = c.profile.row;
  final b = candidate.row;
  final links = p.links;
  final target = e(profile.bookmarkLinkTarget);
  final isEditable = b.ownerId == c.user?.id;
  final title = b.title.isNotEmpty ? b.title : b.url;
  final tags = [...candidate.tags]..sort();
  final classes = [if (b.unread) 'unread', if (b.shared) 'shared'].join(' ');

  final tagLinks = tags
      .map((t) => '<a href="?${e(links.addTag(t))}">${e(t)}</a>')
      .join();
  final String description;
  if (profile.bookmarkDescriptionDisplay == 'inline') {
    description =
        '''
              <div class="description inline truncate">
${tags.isEmpty ? '' : '                  <span class="tags">\n                    $tagLinks\n                  </span>'}
                ${tags.isNotEmpty && b.description.isNotEmpty ? '|' : ''}
                ${b.description.isEmpty ? '' : '<span>${e(b.description)}</span>'}
              </div>''';
  } else {
    description =
        '''
              ${b.description.isEmpty ? '' : '<div class="description separate">${e(b.description)}</div>'}
${tags.isEmpty ? '' : '                <div class="tags">\n                  $tagLinks\n                </div>'}''';
  }

  final displayDate = switch (profile.bookmarkDateDisplay) {
    'relative' => humanizeRelativeDate(b.dateAdded),
    'absolute' => humanizeAbsoluteDate(b.dateAdded),
    _ => null,
  };
  final String snapshotUrl;
  final String snapshotTitle;
  if (b.latestSnapshotId case final id?) {
    snapshotUrl = '/assets/$id';
    snapshotTitle = 'View latest snapshot';
  } else {
    snapshotUrl = b.webArchiveSnapshotUrl.isNotEmpty
        ? b.webArchiveSnapshotUrl
        : webArchiveFallbackUrl(b.url, b.dateAdded);
    snapshotTitle = 'View snapshot on the Internet Archive Wayback Machine';
  }

  final date = displayDate == null
      ? ''
      : '''
                ${snapshotUrl.isEmpty ? '<span>${e(displayDate)}</span>' : '''<a href="${e(snapshotUrl)}"
                     title="$snapshotTitle"
                     target="$target"
                     rel="noopener">${e(displayDate)}</a>'''}
                ${p.isPreview ? '' : '<span>|</span>'}''';

  final showNotesButton = b.notes.isNotEmpty && !profile.permanentNotes;
  final showMarkAsRead = isEditable && b.unread;
  final showUnshare = isEditable && b.shared && profile.enableSharing;
  final extra = showNotesButton || showMarkAsRead || showUnshare
      ? '''
                  <div class="extra-actions">
                    <span class="hide-sm">|</span>
${showMarkAsRead ? '''
                      <button type="submit"
                              name="mark_as_read"
                              value="${b.id}"
                              class="btn btn-link btn-sm btn-icon"
                              data-confirm
                              data-confirm-question="Mark as read?">
                        <svg width="16" height="16">
                          <use href="${_icon('unread')}"></use>
                        </svg>
                        Unread
                      </button>''' : ''}
${showUnshare ? '''
                      <button type="submit"
                              name="unshare"
                              value="${b.id}"
                              class="btn btn-link btn-sm btn-icon"
                              data-confirm
                              data-confirm-question="Unshare?">
                        <svg width="16" height="16">
                          <use href="${_icon('share')}"></use>
                        </svg>
                        Shared
                      </button>''' : ''}
${showNotesButton ? '''
                      <button type="button" class="btn btn-link btn-sm btn-icon toggle-notes">
                        <svg width="16" height="16">
                          <use href="${_icon('note')}"></use>
                        </svg>
                        Notes
                      </button>''' : ''}
                  </div>'''
      : '';

  final String ownerActions;
  if (isEditable) {
    ownerActions = [
      if (profile.displayEditBookmarkAction)
        '                    <a href="/bookmarks/${b.id}/edit?return_url=${e(q(links.index()))}">Edit</a>',
      if (profile.displayArchiveBookmarkAction)
        b.isArchived
            ? '''
                      <button type="submit"
                              name="unarchive"
                              value="${b.id}"
                              class="btn btn-link btn-sm">Unarchive</button>'''
            : '''
                      <button type="submit"
                              name="archive"
                              value="${b.id}"
                              class="btn btn-link btn-sm">Archive</button>''',
      if (profile.displayRemoveBookmarkAction)
        '''
                    <button data-confirm
                            type="submit"
                            name="remove"
                            value="${b.id}"
                            class="btn btn-link btn-sm">Remove</button>''',
    ].join('\n');
  } else {
    final owner = p.owners[b.ownerId] ?? '';
    final byOwner = p.query.copy()..['user'] = owner;
    ownerActions =
        '''
                  <span>Shared by
                    <a href="?${e(byOwner.encode())}">${e(owner)}</a>
                  </span>''';
  }

  final favicon = b.faviconFile.isNotEmpty && profile.enableFavicons
      ? '\n                <img class="favicon" src="${static(b.faviconFile)}" alt="">'
      : '';
  final urlLine = profile.displayUrl
      ? '''
              <div class="url-path truncate">
                <a href="${e(b.url)}"
                   target="$target"
                   rel="noopener"
                   class="url-display">${e(b.url)}</a>
              </div>'''
      : '';
  final notes = b.notes.isEmpty
      ? ''
      : '''
              <div class="notes">
                <div class="markdown">${renderNotes(b.notes)}</div>
              </div>''';
  final preview = !profile.enablePreviewImages
      ? ''
      : b.previewImageFile.isNotEmpty
      ? '''
              <img class="preview-image"
                   src="${static(b.previewImageFile)}"
                   alt=""
                   loading="lazy" />'''
      : '''
              <div class="preview-image placeholder">
                <div class="img" /></div>''';

  final actions =
      '''
${profile.displayViewBookmarkAction ? '''
                  <a href="${e(links.details(b.id))}"
                     class="view-action"
                     data-turbo-action="replace"
                     data-turbo-frame="details-modal">View</a>''' : ''}
$ownerActions
$extra''';

  return '''
        <li data-bookmark-id="${b.id}"
            role="listitem"
            ${classes.isEmpty ? '' : 'class="$classes"'}>
          <div class="content">
            <div class="title">
${p.isPreview ? '' : '''
                <label class="form-checkbox bulk-edit-checkbox">
                  <input type="checkbox" name="bookmark_id" value="${b.id}">
                  <i class="form-icon"></i>
                </label>'''}$favicon
              <a href="${e(b.url)}"
                 target="$target"
                 rel="noopener">
                <span>${e(title)}</span>
              </a>
            </div>
$urlLine
$description
$notes
            <div class="actions">
$date
${p.isPreview ? '' : actions}
            </div>
          </div>
$preview
        </li>''';
}

/// `shared/pagination.html` for the list's page.
String pagination(PageContext c, Page<Object?> page, {String frame = '_top'}) {
  final base = c.path;
  final params = QueryParams.parse(c.request.requestedUri.query)
    ..remove('page')
    ..remove('details');
  String link(int number) {
    final p = params.copy()..['page'] = '$number';
    return e('$base?${p.encode()}');
  }

  final previous = page.hasPrevious
      ? '''
    <li class="page-item">
      <a href="${link(page.number - 1)}"
         tabindex="-1"
         data-turbo-frame="$frame">Previous</a>
    </li>'''
      : '''
    <li class="page-item disabled">
      <a href="#" tabindex="-1">Previous</a>
    </li>''';
  final next = page.hasNext
      ? '''
    <li class="page-item">
      <a href="${link(page.number + 1)}"
         tabindex="-1"
         data-turbo-frame="$frame">Next</a>
    </li>'''
      : '''
    <li class="page-item disabled">
      <a href="#" tabindex="-1">Next</a>
    </li>''';
  final numbers = [
    for (final n in page.window)
      n == null
          ? '''
      <li class="page-item">
        <span>...</span>
      </li>'''
          : '''
      <li class="page-item ${n == page.number ? 'active' : ''}">
        <a href="${link(n)}" data-turbo-frame="$frame">$n</a>
      </li>''',
  ].join('\n');
  return '''
<ul class="pagination">
$previous
$numbers
$next
</ul>''';
}

/// `bookmarks/bundle_section.html`.
String _bundleSection(PageContext c, ListPage p, List<BundleRow> bundles) {
  if (c.profile.row.hideBundles) return '';
  final fromSearch = p.search.q.isEmpty
      ? ''
      : '''
            <li class="menu-item">
              <a href="/bundles/new?q=${e(q(p.search.q))}"
                 class="menu-link">Create
              bundle from search</a>
            </li>''';
  final items = [
    for (final bundle in bundles)
      '''
        <li class="bundle-menu-item ${bundle.id == p.selectedBundleId ? 'selected' : ''}">
          <a href="?bundle=${bundle.id}">${e(bundle.name)}</a>
        </li>''',
  ].join('\n');
  return '''
  <section aria-labelledby="bundles-heading">
    <div class="section-header no-wrap">
      <h2 id="bundles-heading">Bundles</h2>
      <ld-dropdown class="dropdown dropdown-right ml-auto">
        <button class="btn btn-noborder dropdown-toggle" aria-label="Bundles menu">
          <svg width="20" height="20">
            <use href="${_icon('menu')}"></use>
          </svg>
        </button>
        <ul class="menu" role="list" tabindex="-1">
          <li class="menu-item">
            <a href="/bundles" class="menu-link">Manage bundles</a>
          </li>
$fromSearch
        </ul>
      </ld-dropdown>
    </div>
    <ul class="bundle-menu">
$items
    </ul>
  </section>''';
}

/// `bookmarks/user_section.html`.
String _userSection(ListPage p) {
  final users = p.users!;
  final choices = users.isEmpty
      ? const <(String, String)>[]
      : [('', 'Everyone'), for (final u in users) (u, u)];
  return '''
<section aria-labelledby="user-heading">
  <div class="section-header">
    <h2 id="user-heading">User</h2>
  </div>
  <div>
    <ld-form data-form-reset>
      <form id="user-select" action="" method="get">
        ${_hiddenFields(p.search, const {'user'})}
        <div class="form-group">
          <div class="d-flex">
            ${selectField('user', choices, p.search.user, attributes: const {'data-submit-on-change': ''}, ariaInvalid: false)}
            <noscript>
              <button type="submit" class="btn btn-link ml-2">Apply</button>
            </noscript>
          </div>
        </div>
      </form>
    </ld-form>
    <br>
  </div>
</section>''';
}

/// `bookmarks/tag_section.html` with the tag cloud.
String _tagSection(PageContext c, ListPage p) {
  final menu = c.isAuthenticated
      ? '''
      <ld-dropdown class="dropdown dropdown-right ml-auto">
        <button class="btn btn-noborder dropdown-toggle" aria-label="Tags menu">
          <svg width="20" height="20">
            <use href="${_icon('menu')}"></use>
          </svg>
        </button>
        <ul class="menu" role="list" tabindex="-1">
          <li class="menu-item">
            <a href="/tags" class="menu-link">Manage tags</a>
          </li>
        </ul>
      </ld-dropdown>'''
      : '';
  return '''
<section aria-labelledby="tags-heading">
  <div class="section-header no-wrap">
    <h2 id="tags-heading">Tags</h2>
$menu
  </div>
  <div id="tag-cloud-container">${tagCloud(p)}</div>
</section>''';
}

/// `bookmarks/tag_cloud.html`, minified as `{% htmlmin %}` leaves it.
String tagCloud(ListPage p) {
  final cloud = p.tagCloud;
  final links = p.links;
  final selected = cloud.selected.isEmpty
      ? ''
      : ' <p class="selected-tags"> ${[for (final tag in cloud.selected) '<a href="?${e(links.removeTag(tag, p.query))}" class="text-bold mr-2"><span>-${e(tag)}</span></a>'].join(' ')} </p>';
  final groups = [
    for (final group in cloud.groups)
      '<p class="group"> ${[for (final (i, tag) in group.tags.indexed)
        if (group.highlightFirstChar && i == 0) '<a href="?${e(links.addTag(tag))}" class="mr-2" data-is-tag-item>'
              '<span class="highlight-char">${e(String.fromCharCode(tag.runes.first))}</span>'
              '<span>${e(String.fromCharCodes(tag.runes.skip(1)))}</span></a>' else '<a href="?${e(links.addTag(tag))}" class="mr-2" data-is-tag-item><span>${e(tag)}</span></a>'].join(' ')} </p>',
  ].join(' ');
  return '\n <div class="tag-cloud">$selected <div class="unselected-tags"> '
      '${groups.isEmpty ? '' : '$groups '}</div> </div> \n';
}

/// `bookmarks/details/modal.html`, or the empty frame without details.
String detailsModal(PageContext c, ListPage p) {
  final d = p.details;
  if (d == null) {
    return '<turbo-frame id="details-modal" target="_top">\n</turbo-frame>';
  }
  final b = d.bookmark;
  final title = b.title.isNotEmpty ? b.title : b.url;
  final footer = d.isEditable
      ? '''
        <div class="modal-footer">
          <div class="actions">
            <div class="left-actions">
              <a class="btn btn-wide"
                 href="/bookmarks/${b.id}/edit?return_url=${e(q(p.links.details(b.id)))}">Edit</a>
            </div>
            <div class="right-actions">
              <form action="${e(p.links.action())}"
                    method="post"
                    data-turbo-action="replace">
                ${c.csrfInput}
                <input type="hidden" name="disable_turbo" value="true">
                <button data-confirm
                        class="btn btn-error btn-wide"
                        type="submit"
                        name="remove"
                        value="${b.id}">Delete</button>
              </form>
            </div>
          </div>
        </div>'''
      : '';
  return '''
<turbo-frame id="details-modal" target="_top">
  <ld-details-modal class="modal active bookmark-details"
                    data-bookmark-id="${b.id}"
                    data-close-url="${e(p.links.index())}"
                    data-turbo-frame="details-modal">
    <div class="modal-overlay" data-close-modal></div>
    <div class="modal-container" role="dialog" aria-modal="true">
${modalHeader(title)}
      <div class="modal-body">${_detailsForm(c, p, d)}</div>
$footer
    </div>
  </ld-details-modal>
</turbo-frame>''';
}

/// `shared/modal_header.html`.
String modalHeader(String title) =>
    '''
<div class="modal-header">
  <h2 class="title">${e(title)}</h2>
  <button type="button"
          class="btn btn-noborder close"
          aria-label="Close dialog"
          data-close-modal>
    <svg width="24" height="24">
      <use href="${_icon('close')}"></use>
    </svg>
  </button>
</div>''';

const _archiveIcon =
    'm76 82v4h-76l.00080851-4zm-3-6v5h-70v-5zm-62.6696277-54 .8344146.4217275.4176066 6.7436084.4176065 10.9576581v10.5383496l-.4176065 13.1364492-.0694681 8.8498268-1.1825531.3523804h-4.17367003l-1.25202116-.3523804-.48627608-8.8498268-.41840503-13.0662957v-10.5375432l.41840503-11.028618.38167482-6.7798947.87034634-.3854412zm60.0004653 0 .8353798.4217275.4168913 6.7436084.4168913 10.9576581v10.5383496l-.4168913 13.1364492-.0686832 8.8498268-1.1835879.3523804h-4.1737047l-1.2522712-.3523804-.4879704-8.8498268-.4168913-13.0662957v-10.5375432l.4168913-11.028618.3833483-6.7798947.8697215-.3854412zm-42.000632 0 .8344979.4217275.4176483 6.7436084.4176482 10.9576581v10.5383496l-.4176482 13.1364492-.0686764 8.8498268-1.1834698.3523804h-4.1740866l-1.2529447-.3523804-.4863246-8.8498268-.4168497-13.0662957v-10.5375432l.4168497-11.028618.38331-6.7798947.8688361-.3854412zm23 0 .8344979.4217275.4176483 6.7436084.4176482 10.9576581v10.5383496l-.4176482 13.1364492-.0686764 8.8498268-1.1834698.3523804h-4.1740866l-1.2521462-.3523804-.4871231-8.8498268-.4168497-13.0662957v-10.5375432l.4168497-11.028618.38331-6.7798947.8696347-.3854412zm21.6697944-9v7h-70v-7zm-35.7200748-13 36.7200748 8.4088317-1.4720205 2.5911683h-70.32799254l-2.19998696-2.10140371z';

/// `bookmarks/details/form.html`.
String _detailsForm(PageContext c, ListPage p, Details d) {
  final b = d.bookmark;
  final profile = c.profile.row;
  final target = e(profile.bookmarkLinkTarget);
  final showIcons = profile.enableFavicons && b.faviconFile.isNotEmpty;
  final archiveUrl = b.webArchiveSnapshotUrl.isNotEmpty
      ? b.webArchiveSnapshotUrl
      : webArchiveFallbackUrl(b.url, b.dateAdded);
  final snapshot = d.assets
      .where((a) => a.assetType == 'snapshot' && a.status == 'complete')
      .firstOrNull;

  String checkbox(String name, String label, bool checked) =>
      '''
            <div class="form-group">
              <label class="form-checkbox">
                <input data-submit-on-change
                       type="checkbox"
                       name="$name"
                       ${checked ? 'checked' : ''}>
                <i class="form-icon"></i> $label
              </label>
            </div>''';

  final status = d.isEditable
      ? '''
        <section class="status col-2">
          <h3>Status</h3>
          <div class="d-flex" style="gap: .8rem">
${checkbox('is_archived', 'Archived', b.isArchived)}
${checkbox('unread', 'Unread', b.unread)}
${profile.enableSharing ? checkbox('shared', 'Shared', b.shared) : ''}
          </div>
        </section>'''
      : '';
  final tags = d.tags.isEmpty
      ? ''
      : '''
        <section class="tags col-1">
          <h3 id="details-modal-tags-title">Tags</h3>
          <div>
${d.tags.map((t) => '              <a href="/bookmarks?${e(p.links.addTag(t))}">${e(t)}</a>').join('\n')}
          </div>
        </section>''';

  return '''
<ld-form>
  <form action="${e(p.links.action({'details': '${b.id}'}))}"
        method="post"
        enctype="multipart/form-data">
    ${c.csrfInput}
    <input type="hidden" name="update_state" value="${b.id}">
    <div class="weblinks">
      <a class="weblink"
         href="${e(b.url)}"
         rel="noopener"
         target="$target">
${showIcons ? '          <img class="favicon"\n               src="${static(b.faviconFile)}"\n               alt="">' : ''}
        <span>${e(b.url)}</span>
      </a>
${snapshot == null ? '' : '''
        <a class="weblink"
           href="/assets/${snapshot.id}/read"
           target="$target">
${showIcons ? '            <svg class="favicon">\n              <use href="${_icon('unread')}"></use>\n            </svg>' : ''}
          <span>Reader mode</span>
        </a>'''}
${archiveUrl.isEmpty ? '' : '''
        <a class="weblink"
           href="${e(archiveUrl)}"
           target="$target">
${showIcons ? '''            <svg class="favicon"
                 viewBox="0 0 76 86"
                 xmlns="http://www.w3.org/2000/svg">
              <path d="$_archiveIcon" fill="currentColor" fill-rule="evenodd" />
            </svg>''' : ''}
          <span>Internet Archive</span>
        </a>'''}
    </div>
${profile.enablePreviewImages && b.previewImageFile.isNotEmpty ? '''
      <div class="preview-image">
        <img src="${static(b.previewImageFile)}" alt="" />
      </div>''' : ''}
    <div class="sections grid columns-2 columns-sm-1 gap-0">
$status
      <section class="files col-2">
        <h3>Files</h3>
        <div>${_assets(c, d)}</div>
      </section>
$tags
      <section class="date-added col-1">
        <h3>Date added</h3>
        <div>
          <span>${djangoDateTime(b.dateAdded)}</span>
        </div>
      </section>
${b.description.isEmpty ? '' : '''
        <section class="description col-2">
          <h3>Description</h3>
          <div>${e(b.description)}</div>
        </section>'''}
${b.notes.isEmpty ? '' : '''
        <section class="notes col-2">
          <h3>Notes</h3>
          <div class="markdown">${renderNotes(b.notes)}</div>
        </section>'''}
    </div>
  </form>
</ld-form>
''';
}

/// `bookmarks/details/assets.html`.
String _assets(PageContext c, Details d) {
  final items = [
    for (final asset in d.assets)
      '''
        <div class="list-item" data-asset-id="${asset.id}">
          <div class="list-item-icon ${switch (asset.status) {
        'pending' => 'text-tertiary',
        'failure' => 'text-error',
        _ => 'icon-color',
      }}">${_assetIcon(asset.contentType)}</div>
          <div class="list-item-text ${switch (asset.status) {
        'pending' => 'text-tertiary',
        'failure' => 'text-error',
        _ => '',
      }}">
            <span class="truncate">
              ${e(asset.displayName)}
              ${asset.status == 'pending' ? '(queued)' : ''}
              ${asset.status == 'failure' ? '(failed)' : ''}
            </span>
            ${(asset.fileSize ?? 0) == 0 ? '' : '<span class="filesize">${fileSize(asset.fileSize!)}</span>'}
          </div>
          <div class="list-item-actions">
${asset.file.isEmpty ? '' : '''
              <a class="btn btn-link"
                 href="/assets/${asset.id}"
                 target="_blank">View</a>'''}
${d.isEditable ? '''
              <button data-confirm
                      type="submit"
                      name="remove_asset"
                      value="${asset.id}"
                      class="btn btn-link">Remove</button>''' : ''}
          </div>
        </div>''',
  ].join('\n');
  final list = d.assets.isEmpty
      ? ''
      : '''
    <div class="item-list assets">
$items
    </div>''';
  final actions = d.isEditable
      ? '''
    <div class="assets-actions">
${!d.uploadsEnabled ? '' : '''
        <ld-upload-button>
          <button id="upload-asset"
                  name="upload_asset"
                  value="${d.bookmark.id}"
                  type="submit"
                  class="btn btn-sm">Upload file</button>
          <input id="upload-asset-file"
                 name="upload_asset_file"
                 type="file"
                 class="d-hide">
        </ld-upload-button>'''}
    </div>'''
      : '';
  return '<div>\n$list\n$actions\n</div>\n';
}

String _assetIcon(String contentType) {
  const head =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
      'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round"> '
      '<path stroke="none" d="M0 0h24v24H0z" fill="none" />';
  final paths = switch (contentType) {
    'text/html' => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4',
      'M2 21v-6',
      'M5 15v6',
      'M2 18h3',
      'M20 15v6h2',
      'M13 21v-6l2 3l2 -3v6',
      'M7.5 15h3',
      'M9 15v6',
    ],
    'application/pdf' => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4',
      'M5 18h1.5a1.5 1.5 0 0 0 0 -3h-1.5v6',
      'M17 18h2',
      'M20 15h-3v6',
      'M11 15v6h1a2 2 0 0 0 2 -2v-2a2 2 0 0 0 -2 -2h-1z',
    ],
    'image/png' || 'image/jpeg' || 'image.gif' => const [
      'M15 8h.01',
      'M3 6a3 3 0 0 1 3 -3h12a3 3 0 0 1 3 3v12a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-12z',
      'M3 16l5 -5c.928 -.893 2.072 -.893 3 0l5 5',
      'M14 14l1 -1c.928 -.893 2.072 -.893 3 0l3 3',
    ],
    _ => const [
      'M14 3v4a1 1 0 0 0 1 1h4',
      'M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z',
    ],
  };
  return '$head ${paths.map((d) => '<path d="$d" />').join(' ')} </svg>';
}
