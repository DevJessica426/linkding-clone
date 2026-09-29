import 'package:linkding_shared/linkding_shared.dart';

import '../../core/profile.dart';
import '../../pages/support/query_params.dart';
import 'list_kind.dart';

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
