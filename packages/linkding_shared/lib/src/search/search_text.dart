import 'search_expressions.dart';
import 'search_parser.dart';

bool _needsParentheses(SearchExpression expression, Type parent) {
  if (expression is OrExpression && parent == AndExpression) return true;
  return (expression is AndExpression || expression is OrExpression) &&
      parent == NotExpression;
}

String _toText(SearchExpression expression, [Type? parent]) {
  switch (expression) {
    case TermExpression(:final term):
      if (term.contains(' ') ||
          ['(', ')', '"', "'"].any((c) => term.contains(c))) {
        final escaped = term.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        return '"$escaped"';
      }
      return term;
    case TagExpression(:final tag):
      return '#$tag';
    case SpecialKeywordExpression(:final keyword):
      return '!$keyword';
    case NotExpression(:final operand):
      final inner = _toText(operand);
      return operand is AndExpression || operand is OrExpression
          ? 'not ($inner)'
          : 'not $inner';
    case AndExpression(:final left, :final right):
      var leftText = _toText(left);
      var rightText = _toText(right);
      if (_needsParentheses(left, AndExpression)) leftText = '($leftText)';
      if (_needsParentheses(right, AndExpression)) rightText = '($rightText)';
      final text = '$leftText $rightText';
      return parent != null && _needsParentheses(expression, parent)
          ? '($text)'
          : text;
    case OrExpression(:final left, :final right):
      final text = '${_toText(left)} or ${_toText(right)}';
      return parent != null && _needsParentheses(expression, parent)
          ? '($text)'
          : text;
  }
}

/// Writes [expression] back as a query string.
String expressionToString(SearchExpression? expression) =>
    expression == null ? '' : _toText(expression);

SearchExpression? _stripTag(
  SearchExpression? expression,
  String tag,
  bool lax,
) {
  final lower = tag.toLowerCase();
  switch (expression) {
    case null:
      return null;
    case TagExpression(tag: final name):
      return name.toLowerCase() == lower ? null : expression;
    case TermExpression(:final term):
      return lax && term.toLowerCase() == lower ? null : expression;
    case SpecialKeywordExpression():
      return expression;
    case NotExpression(:final operand):
      final kept = _stripTag(operand, tag, lax);
      return kept == null ? null : NotExpression(kept);
    case AndExpression(:final left, :final right):
      final l = _stripTag(left, tag, lax);
      final r = _stripTag(right, tag, lax);
      if (l == null) return r;
      if (r == null) return l;
      return AndExpression(l, r);
    case OrExpression(:final left, :final right):
      final l = _stripTag(left, tag, lax);
      final r = _stripTag(right, tag, lax);
      if (l == null) return r;
      if (r == null) return l;
      return OrExpression(l, r);
  }
}

/// [query] without every mention of [tag]; what clicking a selected tag in
/// the sidebar navigates to. An unparseable query comes back unchanged.
String stripTagFromQuery(String query, String tag, {bool laxTags = false}) {
  final SearchExpression? parsed;
  try {
    parsed = parseSearchQuery(query);
  } on SearchQueryParseError {
    return query;
  }
  if (parsed == null) return '';
  return expressionToString(_stripTag(parsed, tag, laxTags));
}

List<String> _tagNames(SearchExpression? expression, bool lax) =>
    switch (expression) {
      null => const [],
      TagExpression(:final tag) => [tag],
      TermExpression(:final term) => lax ? [term] : const [],
      SpecialKeywordExpression() => const [],
      NotExpression(:final operand) => _tagNames(operand, lax),
      AndExpression(:final left, :final right) ||
      OrExpression(
        :final left,
        :final right,
      ) => [..._tagNames(left, lax), ..._tagNames(right, lax)],
    };

/// The tags [query] mentions, lower-cased, de-duplicated and sorted. In lax
/// mode a plain word counts as a tag too.
List<String> extractTagNamesFromQuery(String query, {bool laxTags = false}) {
  final SearchExpression? parsed;
  try {
    parsed = parseSearchQuery(query);
  } on SearchQueryParseError {
    return const [];
  }
  final seen = <String>{};
  final names = [
    for (final name in _tagNames(parsed, laxTags))
      if (seen.add(name.toLowerCase())) name.toLowerCase(),
  ];
  return names..sort();
}
