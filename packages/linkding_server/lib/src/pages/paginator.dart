import '../web/query_params.dart';
import 'visitor.dart';

/// A page of a list as Django's `Paginator.get_page` picks it: a missing or
/// malformed number is the first page, one past the end the last.
final class Page<T> {
  Page._(this.items, this.number, this.pageCount, this.total);

  factory Page.of(List<T> all, int perPage, String? requested) {
    final pageCount = all.isEmpty ? 1 : (all.length + perPage - 1) ~/ perPage;
    var number = int.tryParse(requested ?? '') ?? 1;
    if (requested != null && int.tryParse(requested) == null) number = 1;
    if (number < 1) number = requested == null ? 1 : pageCount;
    if (number > pageCount) number = pageCount;
    final start = (number - 1) * perPage;
    return Page._(
      all.skip(start).take(perPage).toList(),
      number,
      pageCount,
      all.length,
    );
  }

  final List<T> items;
  final int number;
  final int pageCount;
  final int total;

  bool get hasPrevious => number > 1;
  bool get hasNext => number < pageCount;

  /// linkding's window of page numbers: two either side of the current one,
  /// plus the first and last, with null where pages are left out.
  List<int?> get window {
    final visible = <int>{
      for (
        var n = number - 2 < 1 ? 1 : number - 2;
        n <= (number + 2 > pageCount ? pageCount : number + 2);
        n++
      )
        n,
      1,
      pageCount,
    }.toList()..sort();
    final result = <int?>[];
    for (final n in visible) {
      if (result.isNotEmpty && result.last! < n - 1) result.add(null);
      result.add(n);
    }
    return result;
  }
}

/// What `pagination.html` reads: links to the neighbouring and nearby
/// pages of [page], keeping the query but for `page` and `details`, for the
/// Turbo [frame] the list lives in.
Map<String, Object?> paginationValues(
  Visitor visitor,
  Page<Object?> page, {
  String frame = '_top',
}) {
  final params = QueryParams.parse(visitor.request.requestedUri.query)
    ..remove('page')
    ..remove('details');
  String link(int number) {
    final p = params.copy()..['page'] = '$number';
    return '${visitor.path}?${p.encode()}';
  }

  return {
    'frame': frame,
    'hasPrevious': page.hasPrevious,
    'previous': page.hasPrevious ? link(page.number - 1) : '',
    'hasNext': page.hasNext,
    'next': page.hasNext ? link(page.number + 1) : '',
    'numbers': [
      for (final n in page.window)
        {
          'gap': n == null,
          'active': n == page.number,
          'number': n ?? 0,
          'link': n == null ? '' : link(n),
        },
    ],
  };
}
