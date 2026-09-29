import 'step.dart';

/// The profile, sharing, archiving and deleting, reading pages, and auto-tagging rules.
final profilePageSteps = <Step>[
  // Profile, sharing, archiving, deleting.
  const Step('profile', get, '/api/user/profile/'),
  const Step(
    'shared list without credentials',
    get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step(
    'shared list with a wrong token',
    get,
    '/api/bookmarks/shared/',
    auth: Auth.badToken,
  ),
  const Step('shared list signed in', get, '/api/bookmarks/shared/'),
  const Step(
    'shared list of an unknown user',
    get,
    '/api/bookmarks/shared/?user=nobody',
  ),
  const Step('archive', post, '/api/bookmarks/2/archive/'),
  const Step('archive with GET', get, '/api/bookmarks/2/archive/'),
  const Step('archived list now', get, '/api/bookmarks/archived/'),
  const Step('unarchive', post, '/api/bookmarks/2/unarchive/'),
  const Step('archive a missing bookmark', post, '/api/bookmarks/999/archive/'),
  const Step('delete', delete, '/api/bookmarks/2/'),
  const Step('delete again', delete, '/api/bookmarks/2/'),

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
      get,
      '/api/bookmarks/check/?url=${Uri.encodeComponent('$pagesUrl/$page')}',
    ),
  Step(
    'check a blocked internal address',
    get,
    '/api/bookmarks/check/?url=${Uri.encodeComponent('http://127.0.0.1:9099/page.html')}',
  ),
  const Step(
    'create fills title and description from the page',
    post,
    '/api/bookmarks/',
    json: {'url': '$pagesUrl/page.html'},
  ),
  const Step(
    'create keeps a given title, fills the description',
    post,
    '/api/bookmarks/',
    json: {'url': '$pagesUrl/og.html', 'title': 'Mine'},
  ),
  const Step(
    'create from a page with unicode',
    post,
    '/api/bookmarks/',
    json: {'url': '$pagesUrl/unicode.html', 'description': 'given'},
  ),
  const Step(
    'create from a blocked address',
    post,
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
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fx.example.invalid%2F',
  ),
  const Step(
    'check with a path rule',
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Ffiller.example.invalid%2F2%2Fmore',
  ),
  const Step(
    'check with a query rule',
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fexample.org%2F%3Flang%3Den%26x%3D1',
  ),
  const Step(
    'create gets automatic tags',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://auto.example.invalid/',
      'tag_names': ['Auto', 'mine'],
    },
  ),
  const Step(
    'PATCH applies rules too',
    patch,
    '/api/bookmarks/9/',
    json: {'title': 'Filler 5 again'},
  ),
  const Step.sql('a rule that breaks every rule', r'''
UPDATE bookmarks_userprofile SET auto_tagging_rules = E'example.invalid auto\n.co.uk broken\n'
'''),
  const Step(
    'check with a broken rule',
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fx.example.invalid%2F',
  ),
  const Step(
    'create with a broken rule',
    post,
    '/api/bookmarks/$noScrape',
    json: {'url': 'https://broken-rule.example.invalid/'},
  ),
  const Step.sql(
    'clear rules',
    "UPDATE bookmarks_userprofile SET auto_tagging_rules = ''",
  ),
];
