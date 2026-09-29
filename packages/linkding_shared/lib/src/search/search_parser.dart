import 'search_expressions.dart';
import 'search_tokens.dart';

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
