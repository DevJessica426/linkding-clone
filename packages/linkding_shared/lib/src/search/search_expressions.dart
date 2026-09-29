/// A parsed query.
sealed class SearchExpression {
  const SearchExpression();
}

/// A word or phrase, matched in title, description, notes and URL.
final class TermExpression extends SearchExpression {
  const TermExpression(this.term);
  final String term;

  @override
  bool operator ==(Object other) =>
      other is TermExpression && other.term == term;
  @override
  int get hashCode => term.hashCode;
  @override
  String toString() => 'Term($term)';
}

/// `#name`: the bookmark carries that tag, ignoring case.
final class TagExpression extends SearchExpression {
  const TagExpression(this.tag);
  final String tag;

  @override
  bool operator ==(Object other) => other is TagExpression && other.tag == tag;
  @override
  int get hashCode => tag.hashCode;
  @override
  String toString() => 'Tag($tag)';
}

/// `!unread` or `!untagged`. Anything else matches every bookmark.
final class SpecialKeywordExpression extends SearchExpression {
  const SpecialKeywordExpression(this.keyword);
  final String keyword;

  @override
  bool operator ==(Object other) =>
      other is SpecialKeywordExpression && other.keyword == keyword;
  @override
  int get hashCode => keyword.hashCode;
  @override
  String toString() => 'Keyword($keyword)';
}

final class AndExpression extends SearchExpression {
  const AndExpression(this.left, this.right);
  final SearchExpression left;
  final SearchExpression right;

  @override
  bool operator ==(Object other) =>
      other is AndExpression && other.left == left && other.right == right;
  @override
  int get hashCode => Object.hash('and', left, right);
  @override
  String toString() => 'And($left, $right)';
}

final class OrExpression extends SearchExpression {
  const OrExpression(this.left, this.right);
  final SearchExpression left;
  final SearchExpression right;

  @override
  bool operator ==(Object other) =>
      other is OrExpression && other.left == left && other.right == right;
  @override
  int get hashCode => Object.hash('or', left, right);
  @override
  String toString() => 'Or($left, $right)';
}

final class NotExpression extends SearchExpression {
  const NotExpression(this.operand);
  final SearchExpression operand;

  @override
  bool operator ==(Object other) =>
      other is NotExpression && other.operand == operand;
  @override
  int get hashCode => Object.hash('not', operand);
  @override
  String toString() => 'Not($operand)';
}

/// A query that cannot be parsed, such as `(a` or `a and`. linkding answers
/// it with no results rather than an error.
final class SearchQueryParseError implements Exception {
  const SearchQueryParseError(this.message, this.position);
  final String message;
  final int position;

  @override
  String toString() => '$message at position $position';
}
