import 'step.dart';

/// Authentication, the API root, and creating bookmarks with every kind of rejected body.
final createSteps = <Step>[
  // Authentication and the API root.
  const Step('no credentials', get, '/api/bookmarks/', auth: Auth.none),
  const Step('wrong token', get, '/api/bookmarks/', auth: Auth.badToken),
  const Step(
    'empty token header',
    get,
    '/api/bookmarks/',
    auth: Auth.emptyToken,
  ),
  const Step('bearer token', get, '/api/bookmarks/', auth: Auth.bearer),
  const Step('api root', get, '/api/'),
  const Step('health', get, '/health', auth: Auth.none),
  const Step(
    'unauthenticated PATCH on a list is 401 before 405',
    patch,
    '/api/bookmarks/',
    auth: Auth.none,
  ),
  const Step('PATCH on a list', patch, '/api/bookmarks/'),
  const Step('missing slash redirects', get, '/api/bookmarks'),
  const Step('unknown API path', get, '/api/nope/'),

  // Creating, and every kind of rejected body.
  const Step(
    'create with tags in mixed case',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://a.example.invalid/a',
      'title': 'A',
      'tag_names': ['b', 'A', 'a'],
    },
  ),
  const Step(
    'create from a form',
    post,
    '/api/bookmarks/$noScrape',
    form: {
      'url': 'https://form.example.invalid',
      'title': 'Form',
      'tag_names': 'x',
    },
  ),
  const Step(
    'create from a form, scraping an unreachable page',
    post,
    '/api/bookmarks/',
    form: {'url': 'https://unreachable.example.invalid/page'},
  ),
  const Step(
    'text/plain body',
    post,
    '/api/bookmarks/$noScrape',
    raw: 'hello',
    contentType: 'text/plain',
  ),
  const Step(
    'malformed JSON',
    post,
    '/api/bookmarks/$noScrape',
    raw: '{bad',
    contentType: 'application/json',
  ),
  const Step(
    'JSON list instead of object',
    post,
    '/api/bookmarks/$noScrape',
    json: [1],
  ),
  const Step(
    'JSON null body',
    post,
    '/api/bookmarks/$noScrape',
    raw: 'null',
    contentType: 'application/json',
  ),
  const Step('no body at all', post, '/api/bookmarks/$noScrape'),
  const Step(
    'wrong types everywhere',
    post,
    '/api/bookmarks/$noScrape',
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
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': '',
      'tag_names': ['ok', ''],
    },
  ),
  const Step(
    'whitespace url',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': '   '},
  ),
  const Step(
    'invalid urls',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': 'ftp:/nope'},
  ),
  const Step(
    'javascript url',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': 'javascript:alert(1)'},
  ),
  Step(
    'title too long',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': 'https://long.example.invalid', 'title': 'x' * 513},
  ),
  Step(
    'url too long and invalid',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': 'https://example.invalid/${'x' * 2100}'},
  ),
  const Step(
    'bad dates',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://dates.example.invalid',
      'date_added': 'yesterday',
      'date_modified': 5,
    },
  ),
  const Step(
    'tags with commas and spaces, truthy strings, a date',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://tags.example.invalid',
      'tag_names': ['a,b', 'two words', ' pad '],
      'unread': 'yes',
      'shared': 1,
      'date_added': '2020-01-02',
    },
  ),
];
