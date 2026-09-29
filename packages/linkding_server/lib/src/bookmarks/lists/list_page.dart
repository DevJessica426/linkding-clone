import '../../db/rows/rows.dart';
import '../../pages/support/paginator.dart';
import '../../pages/support/query_params.dart';
import '../../search/search.dart';
import 'list_kind.dart';
import 'list_links.dart';
import 'tag_cloud.dart';

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
