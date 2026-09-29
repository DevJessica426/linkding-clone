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
