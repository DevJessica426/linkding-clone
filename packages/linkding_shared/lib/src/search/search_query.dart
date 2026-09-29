/// linkding's search language: words, `"phrases"`, `#tags`, `!keywords`,
/// `and`, `or`, `not` and parentheses, with `and` implied between adjacent
/// expressions.
///
/// A port of linkding's `search_query_parser.py`, kept structurally close to
/// it so the two can be compared line by line: the same tokens, the same
/// precedence (`or` < `and` < `not`), the same leniency (an unclosed quote ends
/// at the end of the query) and the same failures.
library;

export 'legacy_query.dart';
export 'search_expressions.dart';
export 'search_parser.dart' show parseSearchQuery;
export 'search_text.dart';
export 'search_tokens.dart';
