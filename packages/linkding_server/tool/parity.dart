/// Sends the same requests to a real linkding and to this clone and
/// compares what comes back.
///
///     dart run tool/parity.dart http://localhost:9090=<token> \
///         http://localhost:9091=<token>
///
/// Both servers must start from an empty database with one user, so ids line
/// up; `tool/parity.sh` at the repository root prepares that. Each step's
/// status, key headers and JSON body are compared after normalizing only
/// what must differ: timestamps taken "now", the host in absolute URLs, and
/// Python's wording inside JSON parse errors. HTML bodies are compared by
/// content type only.
///
/// One difference is known and not reported: Dart's `HttpServer` gives a
/// `204 No Content` a `content-type: text/plain` default, which `dust_server`
/// offers no way to switch off. linkding sends none.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

final class Step {
  const Step(
    this.name,
    this.method,
    this.path, {
    this.json,
    this.form,
    this.raw,
    this.contentType,
    this.auth = Auth.token,
  }) : sql = null;

  /// Runs [sql] on each server's own database; both use linkding's schema,
  /// so one statement changes the same thing in each.
  const Step.sql(this.name, this.sql)
    : method = 'SQL',
      path = '',
      json = null,
      form = null,
      raw = null,
      contentType = null,
      auth = Auth.none;

  final String name;
  final String method;
  final String path;
  final Object? json;
  final Map<String, Object>? form;
  final String? raw;
  final String? contentType;
  final Auth auth;
  final String? sql;
}

enum Auth { token, bearer, none, badToken, emptyToken }

const _post = 'POST';
const _get = 'GET';
const _put = 'PUT';
const _patch = 'PATCH';
const _delete = 'DELETE';

const _noScrape = '?disable_scraping';
const _pages = 'http://localhost:9099';

/// The API surface, in an order where later steps build on earlier ones.
final steps = <Step>[
  // Authentication and the API root.
  const Step('no credentials', _get, '/api/bookmarks/', auth: Auth.none),
  const Step('wrong token', _get, '/api/bookmarks/', auth: Auth.badToken),
  const Step(
    'empty token header',
    _get,
    '/api/bookmarks/',
    auth: Auth.emptyToken,
  ),
  const Step('bearer token', _get, '/api/bookmarks/', auth: Auth.bearer),
  const Step('api root', _get, '/api/'),
  const Step('health', _get, '/health', auth: Auth.none),
  const Step(
    'unauthenticated PATCH on a list is 401 before 405',
    _patch,
    '/api/bookmarks/',
    auth: Auth.none,
  ),
  const Step('PATCH on a list', _patch, '/api/bookmarks/'),
  const Step('missing slash redirects', _get, '/api/bookmarks'),
  const Step('unknown API path', _get, '/api/nope/'),

  // Creating, and every kind of rejected body.
  const Step(
    'create with tags in mixed case',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://a.example.invalid/a',
      'title': 'A',
      'tag_names': ['b', 'A', 'a'],
    },
  ),
  const Step(
    'create from a form',
    _post,
    '/api/bookmarks/$_noScrape',
    form: {
      'url': 'https://form.example.invalid',
      'title': 'Form',
      'tag_names': 'x',
    },
  ),
  const Step(
    'create from a form, scraping an unreachable page',
    _post,
    '/api/bookmarks/',
    form: {'url': 'https://unreachable.example.invalid/page'},
  ),
  const Step(
    'text/plain body',
    _post,
    '/api/bookmarks/$_noScrape',
    raw: 'hello',
    contentType: 'text/plain',
  ),
  const Step(
    'malformed JSON',
    _post,
    '/api/bookmarks/$_noScrape',
    raw: '{bad',
    contentType: 'application/json',
  ),
  const Step(
    'JSON list instead of object',
    _post,
    '/api/bookmarks/$_noScrape',
    json: [1],
  ),
  const Step(
    'JSON null body',
    _post,
    '/api/bookmarks/$_noScrape',
    raw: 'null',
    contentType: 'application/json',
  ),
  const Step('no body at all', _post, '/api/bookmarks/$_noScrape'),
  const Step(
    'wrong types everywhere',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 123,
      'title': true,
      'unread': 'maybe',
      'tag_names': 'a,b',
      'notes': null,
    },
  ),
  const Step(
    'blank url and blank tag',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': '',
      'tag_names': ['ok', ''],
    },
  ),
  const Step(
    'whitespace url',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': '   '},
  ),
  const Step(
    'invalid urls',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': 'ftp:/nope'},
  ),
  const Step(
    'javascript url',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': 'javascript:alert(1)'},
  ),
  Step(
    'title too long',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': 'https://long.example.invalid', 'title': 'x' * 513},
  ),
  Step(
    'url too long and invalid',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': 'https://example.invalid/${'x' * 2100}'},
  ),
  const Step(
    'bad dates',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://dates.example.invalid',
      'date_added': 'yesterday',
      'date_modified': 5,
    },
  ),
  const Step(
    'tags with commas and spaces, truthy strings, a date',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://tags.example.invalid',
      'tag_names': ['a,b', 'two words', ' pad '],
      'unread': 'yes',
      'shared': 1,
      'date_added': '2020-01-02',
    },
  ),
  const Step(
    'title and notes are trimmed',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': '  https://trim.example.invalid/  ',
      'title': '  Trim me  ',
      'notes': ' n ',
      'description': 7,
      'is_archived': 'off',
    },
  ),
  const Step(
    'saving a known URL again updates that bookmark',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://A.EXAMPLE.invalid/a/',
      'title': 'Merged',
      'notes': 'n',
      'is_archived': true,
    },
  ),
  const Step(
    'an archived bookmark straight away',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://archived.example.invalid',
      'title': 'Zebra',
      'is_archived': true,
    },
  ),
  const Step(
    'explicit dates',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://old.example.invalid',
      'title': 'old',
      'date_added': '2019-05-06T07:08:09.123456+02:00',
      'date_modified': '2019-05-06T07:08:09Z',
    },
  ),

  // Reading one bookmark.
  const Step('retrieve', _get, '/api/bookmarks/1/'),
  const Step('retrieve a missing id', _get, '/api/bookmarks/999/'),
  const Step('retrieve a non-numeric id', _get, '/api/bookmarks/abc/'),
  const Step('retrieve a huge id', _get, '/api/bookmarks/99999999999/'),
  const Step('retrieve a negative id', _get, '/api/bookmarks/-1/'),

  // Updating.
  const Step(
    'PUT without url',
    _put,
    '/api/bookmarks/1/',
    json: {'title': 'x'},
  ),
  const Step(
    'PUT keeps what it does not send',
    _put,
    '/api/bookmarks/1/',
    json: {'url': 'https://a.example.invalid/a', 'title': 'Put'},
  ),
  const Step(
    'PATCH tags only',
    _patch,
    '/api/bookmarks/1/',
    json: {
      'tag_names': ['z', 'Y'],
    },
  ),
  const Step(
    'PATCH booleans and date_added',
    _patch,
    '/api/bookmarks/1/',
    json: {
      'unread': true,
      'shared': 'false',
      'date_added': '2021-02-03T04:05:06Z',
    },
  ),
  const Step(
    'PATCH into a duplicate URL',
    _patch,
    '/api/bookmarks/1/',
    json: {'url': 'https://tags.example.invalid'},
  ),
  const Step(
    'PATCH a missing bookmark',
    _patch,
    '/api/bookmarks/999/',
    json: {'title': 'x'},
  ),
  const Step(
    'PATCH with bad JSON on a missing bookmark is 404 first',
    _patch,
    '/api/bookmarks/999/',
    raw: '{bad',
    contentType: 'application/json',
  ),
  Step(
    'PATCH with invalid fields',
    _patch,
    '/api/bookmarks/1/',
    json: {'title': 'x' * 600, 'unread': 'nope'},
  ),

  // Checking a URL.
  const Step('check without a url', _get, '/api/bookmarks/check/'),
  const Step(
    'check a saved url, normalized',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fa.example.invalid%2Fa%2F',
  ),
  const Step(
    'check an unsaved url',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fnew.example.invalid%2F',
  ),

  // A few more bookmarks for lists.
  for (var i = 1; i <= 6; i++)
    Step(
      'filler $i',
      _post,
      '/api/bookmarks/$_noScrape',
      json: {
        'url': 'https://filler.example.invalid/$i',
        'title': 'Filler ${7 - i} history',
        'description': i.isEven ? 'rome and more' : 'athens',
        'tag_names': [if (i.isEven) 'even', if (i % 3 == 0) 'three'],
        'unread': i == 2,
      },
    ),

  // Lists, paging and search.
  const Step('list', _get, '/api/bookmarks/'),
  const Step('page 2 of 2-per-page', _get, '/api/bookmarks/?limit=2&offset=2'),
  const Step('first page links', _get, '/api/bookmarks/?limit=3'),
  const Step(
    'previous link back to offset-less',
    _get,
    '/api/bookmarks/?limit=3&offset=2&q=history',
  ),
  const Step(
    'zero and negative paging',
    _get,
    '/api/bookmarks/?limit=0&offset=-3',
  ),
  const Step('garbage paging', _get, '/api/bookmarks/?limit=abc&offset=x'),
  const Step('offset past the end', _get, '/api/bookmarks/?limit=2&offset=50'),
  const Step(
    'extra params are kept in links',
    _get,
    '/api/bookmarks/?limit=1&zeta=1&alpha=2&q=a+b',
  ),
  const Step('archived list', _get, '/api/bookmarks/archived/'),
  for (final q in [
    '%23pad',
    '%23PAD',
    'history',
    'HISTORY',
    'rome',
    'rome%20athens',
    'rome%20or%20athens',
    'not%20rome',
    '%23even%20%23three',
    '%23even%20or%20%23three',
    'not%20%23even',
    '!untagged',
    '!unread',
    '!unread%20or%20%23three',
    'not%20!untagged',
    '!foo',
    'rome%20or%20!foo',
    'not%20!foo',
    '(a',
    'a)',
    '%22filler%206%22',
    '%22Filler%206%20history%22',
    'example.invalid',
    'filler.example.invalid%2F3',
    '%25',
    '_',
    'and',
    '%22and%22',
    '%23',
    'z%20and%20not%20y',
    '(%23even%20or%20%23three)%20and%20not%20athens',
  ])
    Step('search q=$q', _get, '/api/bookmarks/?q=$q'),
  for (final sort in [
    'title_asc',
    'title_desc',
    'added_asc',
    'added_desc',
    'modified_asc',
    'modified_desc',
    'bogus',
  ])
    Step('sort $sort', _get, '/api/bookmarks/?sort=$sort'),
  for (final filter in [
    'unread=yes',
    'unread=no',
    'unread=maybe',
    'shared=yes',
    'shared=no',
    'modified_since=garbage',
    'modified_since=2020-01-01',
    'added_since=2020-01-01T00:00:00Z',
    'added_since=2019-12-31',
    'added_since=2100-01-01',
    'bundle=999',
  ])
    Step('filter $filter', _get, '/api/bookmarks/?$filter'),

  // Tags.
  const Step(
    'create a tag that exists in another case',
    _post,
    '/api/tags/',
    json: {'name': 'PAD'},
  ),
  const Step('create a new tag', _post, '/api/tags/', json: {'name': 'fresh'}),
  const Step(
    'create a tag with spaces',
    _post,
    '/api/tags/',
    json: {'name': '  has space  '},
  ),
  const Step('create a blank tag', _post, '/api/tags/', json: {'name': ''}),
  const Step(
    'create a tag without name',
    _post,
    '/api/tags/',
    json: <String, Object>{},
  ),
  Step('create a tag too long', _post, '/api/tags/', json: {'name': 't' * 65}),
  const Step('tags list', _get, '/api/tags/'),
  const Step('tags page', _get, '/api/tags/?limit=3&offset=3'),
  const Step('retrieve tag', _get, '/api/tags/1/'),
  const Step('retrieve missing tag', _get, '/api/tags/999/'),
  const Step(
    'PUT a tag is not allowed',
    _put,
    '/api/tags/1/',
    json: {'name': 'x'},
  ),
  const Step('delete a tag', _delete, '/api/tags/2/'),
  const Step('its bookmark lost the tag', _get, '/api/bookmarks/?q=%23b'),
  const Step('delete it again', _delete, '/api/tags/2/'),

  // Bundles.
  const Step(
    'create bundle',
    _post,
    '/api/bundles/',
    json: {'name': 'Evens', 'any_tags': 'even three', 'filter_unread': 'no'},
  ),
  const Step(
    'create bundle with order',
    _post,
    '/api/bundles/',
    json: {'name': 'Second', 'order': 7, 'search': 'filler'},
  ),
  const Step(
    'create bundle, next order',
    _post,
    '/api/bundles/',
    json: {'name': 'Third', 'all_tags': 'even', 'excluded_tags': 'three'},
  ),
  const Step(
    'invalid bundle',
    _post,
    '/api/bundles/',
    json: {'name': '', 'filter_shared': 'maybe', 'order': 'x'},
  ),
  const Step(
    'bundle order as text and float',
    _post,
    '/api/bundles/',
    json: {'name': 'Floaty', 'order': '4.0'},
  ),
  const Step(
    'bundle order out of range',
    _post,
    '/api/bundles/',
    json: {'name': 'Huge', 'order': 99999999999},
  ),
  const Step('bundles list', _get, '/api/bundles/'),
  const Step('bundle filters the list', _get, '/api/bookmarks/?bundle=1'),
  const Step(
    'bundle with search and excludes',
    _get,
    '/api/bookmarks/?bundle=3',
  ),
  const Step('bundle words', _get, '/api/bookmarks/?bundle=2'),
  const Step(
    'PUT bundle without name',
    _put,
    '/api/bundles/1/',
    json: {'search': 's'},
  ),
  const Step(
    'PATCH bundle',
    _patch,
    '/api/bundles/1/',
    json: {'filter_shared': 'yes', 'order': 0},
  ),
  const Step('retrieve missing bundle', _get, '/api/bundles/999/'),
  const Step('delete bundle', _delete, '/api/bundles/1/'),
  const Step('bundles renumbered', _get, '/api/bundles/'),

  // Profile, sharing, archiving, deleting.
  const Step('profile', _get, '/api/user/profile/'),
  const Step(
    'shared list without credentials',
    _get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step(
    'shared list with a wrong token',
    _get,
    '/api/bookmarks/shared/',
    auth: Auth.badToken,
  ),
  const Step('shared list signed in', _get, '/api/bookmarks/shared/'),
  const Step(
    'shared list of an unknown user',
    _get,
    '/api/bookmarks/shared/?user=nobody',
  ),
  const Step('archive', _post, '/api/bookmarks/2/archive/'),
  const Step('archive with GET', _get, '/api/bookmarks/2/archive/'),
  const Step('archived list now', _get, '/api/bookmarks/archived/'),
  const Step('unarchive', _post, '/api/bookmarks/2/unarchive/'),
  const Step(
    'archive a missing bookmark',
    _post,
    '/api/bookmarks/999/archive/',
  ),
  const Step('delete', _delete, '/api/bookmarks/2/'),
  const Step('delete again', _delete, '/api/bookmarks/2/'),

  // Reading pages: a local site, which both servers may reach because
  // LD_ALLOWED_INTERNAL_HOSTS=localhost; 127.0.0.1 stays blocked.
  for (final page in [
    'page.html',
    'og.html',
    'title-only.html',
    'meta-without-content.html',
    'empty-title.html',
    'unicode.html',
    'missing.html',
  ])
    Step(
      'check reads $page',
      _get,
      '/api/bookmarks/check/?url=${Uri.encodeComponent('$_pages/$page')}',
    ),
  Step(
    'check a blocked internal address',
    _get,
    '/api/bookmarks/check/?url=${Uri.encodeComponent('http://127.0.0.1:9099/page.html')}',
  ),
  const Step(
    'create fills title and description from the page',
    _post,
    '/api/bookmarks/',
    json: {'url': '$_pages/page.html'},
  ),
  const Step(
    'create keeps a given title, fills the description',
    _post,
    '/api/bookmarks/',
    json: {'url': '$_pages/og.html', 'title': 'Mine'},
  ),
  const Step(
    'create from a page with unicode',
    _post,
    '/api/bookmarks/',
    json: {'url': '$_pages/unicode.html', 'description': 'given'},
  ),
  const Step(
    'create from a blocked address',
    _post,
    '/api/bookmarks/',
    json: {'url': 'http://127.0.0.1:9099/title-only.html'},
  ),

  // Auto-tagging rules.
  const Step.sql('set auto-tagging rules', r'''
UPDATE bookmarks_userprofile SET auto_tagging_rules =
E'# a comment\nexample.invalid auto\nfiller.example.invalid/2 two second  # trailing\nlocalhost:9099 local\nexample.org/?lang=en english\n'
'''),
  const Step(
    'check applies rules',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fx.example.invalid%2F',
  ),
  const Step(
    'check with a path rule',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Ffiller.example.invalid%2F2%2Fmore',
  ),
  const Step(
    'check with a query rule',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fexample.org%2F%3Flang%3Den%26x%3D1',
  ),
  const Step(
    'create gets automatic tags',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {
      'url': 'https://auto.example.invalid/',
      'tag_names': ['Auto', 'mine'],
    },
  ),
  const Step(
    'PATCH applies rules too',
    _patch,
    '/api/bookmarks/9/',
    json: {'title': 'Filler 5 again'},
  ),
  const Step.sql('a rule that breaks every rule', r'''
UPDATE bookmarks_userprofile SET auto_tagging_rules = E'example.invalid auto\n.co.uk broken\n'
'''),
  const Step(
    'check with a broken rule',
    _get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fx.example.invalid%2F',
  ),
  const Step(
    'create with a broken rule',
    _post,
    '/api/bookmarks/$_noScrape',
    json: {'url': 'https://broken-rule.example.invalid/'},
  ),
  const Step.sql(
    'clear rules',
    "UPDATE bookmarks_userprofile SET auto_tagging_rules = ''",
  ),

  // Lax tag search and legacy search.
  const Step.sql(
    'lax tag search',
    "UPDATE bookmarks_userprofile SET tag_search = 'lax'",
  ),
  for (final q in [
    'even',
    'EVEN',
    'three',
    'not%20even',
    'auto%20or%20three',
    '%23even',
  ])
    Step('lax q=$q', _get, '/api/bookmarks/?q=$q'),
  const Step('profile shows lax', _get, '/api/user/profile/'),
  const Step.sql(
    'legacy search',
    'UPDATE bookmarks_userprofile SET legacy_search = true',
  ),
  for (final q in [
    'rome%20or%20athens',
    'even',
    '%23even%20!unread',
    '!untagged',
    'not',
    '(rome',
  ])
    Step('legacy q=$q', _get, '/api/bookmarks/?q=$q'),
  const Step.sql(
    'back to strict, new search',
    "UPDATE bookmarks_userprofile SET tag_search = 'strict', legacy_search = false",
  ),

  // Sharing.
  const Step(
    'share one more',
    _patch,
    '/api/bookmarks/5/',
    json: {'shared': true},
  ),
  const Step(
    'shared list before sharing is enabled',
    _get,
    '/api/bookmarks/shared/',
  ),
  const Step.sql(
    'enable sharing',
    'UPDATE bookmarks_userprofile SET enable_sharing = true',
  ),
  const Step('shared list signed in', _get, '/api/bookmarks/shared/'),
  const Step(
    'shared list anonymous, not public',
    _get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step.sql(
    'enable public sharing',
    'UPDATE bookmarks_userprofile SET enable_public_sharing = true',
  ),
  const Step(
    'shared list anonymous, public',
    _get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step(
    'shared list of admin',
    _get,
    '/api/bookmarks/shared/?user=admin',
    auth: Auth.none,
  ),
  const Step(
    'shared list searched',
    _get,
    '/api/bookmarks/shared/?q=%23pad',
    auth: Auth.none,
  ),
  const Step(
    'shared list filtered',
    _get,
    '/api/bookmarks/shared/?unread=yes&limit=1',
  ),
  const Step('profile shows sharing', _get, '/api/user/profile/'),
  const Step('HEAD a list', 'HEAD', '/api/bookmarks/'),
  const Step('final state', _get, '/api/bookmarks/?limit=100'),
];

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: parity.dart <base>=<token>=<database url> '
      '<base>=<token>=<database url>',
    );
    exit(2);
  }
  final [reference, clone] = [for (final arg in args) arg.split('=')];
  final left = await _run(reference[0], reference[1], reference[2]);
  final right = await _run(clone[0], clone[1], clone[2]);

  var failures = 0;
  for (var i = 0; i < steps.length; i++) {
    final a = const JsonEncoder.withIndent('  ').convert(left[i]);
    final b = const JsonEncoder.withIndent('  ').convert(right[i]);
    if (a == b) continue;
    failures++;
    stdout
      ..writeln('✗ ${steps[i].method} ${steps[i].path} — ${steps[i].name}')
      ..writeln('  linkding: ${jsonEncode(left[i])}')
      ..writeln('  clone:    ${jsonEncode(right[i])}');
  }
  stdout.writeln(
    '\n${steps.length - failures} of ${steps.length} requests answered the same'
    '${failures == 0 ? '' : '; $failures differ'}.',
  );
  exitCode = failures == 0 ? 0 : 1;
}

Future<List<Object?>> _run(String base, String token, String database) async {
  final client = http.Client();
  final results = <Object?>[];
  for (final step in steps) {
    if (step.sql case final sql?) {
      final result = await Process.run('psql', [
        database,
        '-v',
        'ON_ERROR_STOP=1',
        '-qc',
        sql,
      ]);
      results.add(result.exitCode == 0 ? 'ok' : 'failed: ${result.stderr}');
      continue;
    }
    final request = http.Request(step.method, Uri.parse('$base${step.path}'))
      ..followRedirects = false;
    switch (step.auth) {
      case Auth.token:
        request.headers['authorization'] = 'Token $token';
      case Auth.bearer:
        request.headers['authorization'] = 'Bearer $token';
      case Auth.badToken:
        request.headers['authorization'] = 'Token nope';
      case Auth.emptyToken:
        request.headers['authorization'] = 'Token';
      case Auth.none:
        break;
    }
    if (step.json != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(step.json);
    } else if (step.form != null) {
      request.bodyFields = {
        for (final e in step.form!.entries) e.key: '${e.value}',
      };
    } else if (step.raw != null) {
      request.headers['content-type'] = step.contentType!;
      request.body = step.raw!;
    }
    final response = await http.Response.fromStream(await client.send(request));
    results.add(_normalize(base, response));
  }
  client.close();
  return results;
}

Map<String, Object?> _normalize(String base, http.Response response) {
  final type = response.statusCode == 204
      ? null
      : response.headers['content-type']?.split(';').first;
  Object? body;
  if (type == 'application/json' && response.body.isNotEmpty) {
    body = _clean(jsonDecode(response.body), base);
  } else if (response.body.isNotEmpty) {
    body = '<$type>';
  }
  final location = response.headers['location'];
  return {
    'status': response.statusCode,
    'content-type': ?type,
    if (location != null) 'location': location.replaceAll(base, '<base>'),
    'allow': ?response.headers['allow'],
    'www-authenticate': ?response.headers['www-authenticate'],
    'body': ?body,
  };
}

final _timestamp = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{6})?Z$');
final _archiveStamp = RegExp(r'https://web\.archive\.org/web/(\d{14})/');

Object? _clean(Object? value, String base, [String? key]) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key as String: _clean(e.value, base, e.key as String),
    };
  }
  if (value is List) {
    final cleaned = [for (final item in value) _clean(item, base)];
    if (key == 'auto_tags') cleaned.sort((a, b) => '$a'.compareTo('$b'));
    return cleaned;
  }
  if (value is String) {
    if (key == 'detail' && value.startsWith('JSON parse error - ')) {
      return 'JSON parse error - <python message>';
    }
    if (_timestamp.hasMatch(value)) {
      final at = DateTime.parse(value);
      if (DateTime.now().toUtc().difference(at).inHours.abs() < 24) {
        return '<now>';
      }
    }
    final stamp = _archiveStamp.firstMatch(value);
    if (stamp != null && stamp[1]!.startsWith(_today())) {
      return value.replaceFirst(stamp[1]!, '<now>');
    }
    return value.replaceAll(base, '<base>');
  }
  return value;
}

String _today() {
  final now = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}
