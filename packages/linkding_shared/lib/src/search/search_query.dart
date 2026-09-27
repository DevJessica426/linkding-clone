/// linkding's search language: words, `"phrases"`, `#tags`, `!keywords`,
/// `and`, `or`, `not` and parentheses, with `and` implied between adjacent
/// expressions.
///
/// A port of linkding's `search_query_parser.py`, kept structurally close to
/// it so the two can be compared line by line: the same tokens, the same
/// precedence (`or` < `and` < `not`), the same leniency (an unclosed quote ends
/// at the end of the query) and the same failures.
library;

enum TokenType { term, tag, specialKeyword, and, or, not, lparen, rparen, eof }

final class Token {
  const Token(this.type, this.value, this.position);

  final TokenType type;
  final String value;
  final int position;

  @override
  String toString() => 'Token($type, $value, $position)';
}

final _whitespace = RegExp(r'\s');

bool _isSpace(String char) => _whitespace.hasMatch(char);

/// Splits a query into tokens.
final class SearchQueryTokenizer {
  SearchQueryTokenizer(String query) : _query = query.trim() {
    _current = _query.isEmpty ? null : _query[0];
  }

  final String _query;
  int _position = 0;
  String? _current;

  void _advance() {
    _position++;
    _current = _position >= _query.length ? null : _query[_position];
  }

  void _skipWhitespace() {
    while (_current != null && _isSpace(_current!)) {
      _advance();
    }
  }

  String _readWhile(String stopChars) {
    final buffer = StringBuffer();
    while (_current != null &&
        !_isSpace(_current!) &&
        !stopChars.contains(_current!)) {
      buffer.write(_current);
      _advance();
    }
    return buffer.toString();
  }

  String _readQuoted(String quote) {
    final buffer = StringBuffer();
    _advance(); // the opening quote
    while (_current != null && _current != quote) {
      if (_current == r'\') {
        _advance();
        final escaped = _current;
        if (escaped != null) {
          buffer.write(switch (escaped) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            _ => escaped, // \\, the quote itself, and anything else as-is
          });
          _advance();
        }
      } else {
        buffer.write(_current);
        _advance();
      }
    }
    // An unclosed quote ends with the query, rather than failing.
    if (_current == quote) _advance();
    return buffer.toString();
  }

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (_current != null) {
      _skipWhitespace();
      final char = _current;
      if (char == null) break;
      final start = _position;

      if (char == '(') {
        tokens.add(Token(TokenType.lparen, '(', start));
        _advance();
      } else if (char == ')') {
        tokens.add(Token(TokenType.rparen, ')', start));
        _advance();
      } else if (char == '"' || char == "'") {
        tokens.add(Token(TokenType.term, _readQuoted(char), start));
      } else if (char == '#') {
        _advance();
        final tag = _readWhile('()"\'');
        if (tag.isNotEmpty) tokens.add(Token(TokenType.tag, tag, start));
      } else if (char == '!') {
        _advance();
        final keyword = _readWhile('()"\'');
        if (keyword.isNotEmpty) {
          tokens.add(Token(TokenType.specialKeyword, keyword, start));
        }
      } else {
        final term = _readWhile('()"\'#!');
        tokens.add(switch (term.toLowerCase()) {
          'and' => Token(TokenType.and, term, start),
          'or' => Token(TokenType.or, term, start),
          'not' => Token(TokenType.not, term, start),
          _ => Token(TokenType.term, term, start),
        });
      }
    }
    tokens.add(Token(TokenType.eof, '', _query.length));
    return tokens;
  }
}

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

String _typeName(TokenType type) => switch (type) {
  TokenType.term => 'TERM',
  TokenType.tag => 'TAG',
  TokenType.specialKeyword => 'SPECIAL_KEYWORD',
  TokenType.and => 'AND',
  TokenType.or => 'OR',
  TokenType.not => 'NOT',
  TokenType.lparen => 'LPAREN',
  TokenType.rparen => 'RPAREN',
  TokenType.eof => 'EOF',
};

final class _Parser {
  _Parser(this._tokens)
    : _current = _tokens.isEmpty
          ? const Token(TokenType.eof, '', 0)
          : _tokens.first;

  final List<Token> _tokens;
  int _position = 0;
  Token _current;

  void _advance() {
    if (_position < _tokens.length - 1) {
      _position++;
      _current = _tokens[_position];
    }
  }

  void _consume(TokenType expected) {
    if (_current.type != expected) {
      throw SearchQueryParseError(
        'Expected ${_typeName(expected)}, got ${_typeName(_current.type)}',
        _current.position,
      );
    }
    _advance();
  }

  SearchExpression? parse() {
    if (_tokens.isEmpty ||
        (_tokens.length == 1 && _tokens.first.type == TokenType.eof)) {
      return null;
    }
    final expression = _or();
    if (_current.type != TokenType.eof) {
      throw SearchQueryParseError(
        'Unexpected token ${_typeName(_current.type)}',
        _current.position,
      );
    }
    return expression;
  }

  SearchExpression _or() {
    var left = _and();
    while (_current.type == TokenType.or) {
      _advance();
      left = OrExpression(left, _and());
    }
    return left;
  }

  static const _implicitAnd = {
    TokenType.term,
    TokenType.tag,
    TokenType.specialKeyword,
    TokenType.lparen,
    TokenType.not,
  };

  SearchExpression _and() {
    var left = _not();
    while (_current.type == TokenType.and ||
        _implicitAnd.contains(_current.type)) {
      if (_current.type == TokenType.and) _advance();
      left = AndExpression(left, _not());
    }
    return left;
  }

  SearchExpression _not() {
    if (_current.type == TokenType.not) {
      _advance();
      return NotExpression(_not());
    }
    return _primary();
  }

  SearchExpression _primary() {
    final token = _current;
    switch (token.type) {
      case TokenType.term:
        _advance();
        return TermExpression(token.value);
      case TokenType.tag:
        _advance();
        return TagExpression(token.value);
      case TokenType.specialKeyword:
        _advance();
        return SpecialKeywordExpression(token.value);
      case TokenType.lparen:
        _advance();
        final inner = _or();
        _consume(TokenType.rparen);
        return inner;
      default:
        throw SearchQueryParseError(
          'Unexpected token ${_typeName(token.type)}',
          token.position,
        );
    }
  }
}

/// Parses [query], or returns null for an empty one.
///
/// Throws [SearchQueryParseError] when it cannot be parsed.
SearchExpression? parseSearchQuery(String? query) {
  if (query == null || query.trim().isEmpty) return null;
  return _Parser(SearchQueryTokenizer(query).tokenize()).parse();
}

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

/// The query as legacy search reads it: space-separated words, `#tags`, and
/// the two `!` commands, all combined with `and`. Bundles still use it.
final class LegacyQuery {
  const LegacyQuery({
    required this.searchTerms,
    required this.tagNames,
    required this.untagged,
    required this.unread,
  });

  factory LegacyQuery.parse(String? query) {
    final words = (query ?? '')
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    final tags = <String, String>{};
    for (final word in words.where((w) => w.startsWith('#'))) {
      tags[word.substring(1).toLowerCase()] = word.substring(1);
    }
    return LegacyQuery(
      searchTerms: [
        for (final word in words)
          if (!word.startsWith('#') && !word.startsWith('!')) word,
      ],
      tagNames: tags.values.toList(),
      untagged: words.contains('!untagged'),
      unread: words.contains('!unread'),
    );
  }

  final List<String> searchTerms;
  final List<String> tagNames;
  final bool untagged;
  final bool unread;
}
