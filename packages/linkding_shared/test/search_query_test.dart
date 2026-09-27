import 'dart:convert';
import 'dart:io';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:test/test.dart';

/// The Dart parser against linkding's own.
///
/// `fixtures/search_queries.json` is written by `tool/search_fixture.py`,
/// which runs linkding's `search_query_parser.py` over every string in its
/// parser tests plus 400 random queries. Each entry must come out the same
/// here: tokens, tree or error, the tree written back, the tags it mentions,
/// and the query with `#book` stripped, in both tag-search modes.
void main() {
  final entries = (jsonDecode(
    File('test/fixtures/search_queries.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  test('the fixture covers errors and successes', () {
    expect(entries.length, greaterThan(500));
    expect(entries.where((e) => e.containsKey('error')), isNotEmpty);
  });

  for (final entry in entries) {
    final query = entry['query']! as String;
    group(jsonEncode(query), () {
      test('tokens', () {
        final tokens = [
          for (final t in SearchQueryTokenizer(query).tokenize())
            [_tokenName(t.type), t.value, t.position],
        ];
        expect(tokens, entry['tokens']);
      });

      test('tree', () {
        if (entry['error'] case [final String message, final int position]) {
          expect(
            () => parseSearchQuery(query),
            throwsA(
              isA<SearchQueryParseError>()
                  .having((e) => e.message, 'message', message)
                  .having((e) => e.position, 'position', position),
            ),
          );
        } else {
          final parsed = parseSearchQuery(query);
          expect(_tree(parsed), entry['tree']);
          expect(expressionToString(parsed), entry['text']);
        }
      });

      test('tags and stripping', () {
        expect(extractTagNamesFromQuery(query), entry['tags_strict']);
        expect(
          extractTagNamesFromQuery(query, laxTags: true),
          entry['tags_lax'],
        );
        expect(stripTagFromQuery(query, 'book'), entry['strip_book_strict']);
        expect(
          stripTagFromQuery(query, 'book', laxTags: true),
          entry['strip_book_lax'],
        );
      });
    });
  }
}

String _tokenName(TokenType type) => switch (type) {
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

Object? _tree(SearchExpression? e) => switch (e) {
  null => null,
  TermExpression(:final term) => ['term', term],
  TagExpression(:final tag) => ['tag', tag],
  SpecialKeywordExpression(:final keyword) => ['keyword', keyword],
  AndExpression(:final left, :final right) => [
    'and',
    _tree(left),
    _tree(right),
  ],
  OrExpression(:final left, :final right) => ['or', _tree(left), _tree(right)],
  NotExpression(:final operand) => ['not', _tree(operand)],
};
