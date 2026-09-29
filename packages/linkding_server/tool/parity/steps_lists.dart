import 'step.dart';

/// Checking a URL, a few more bookmarks, and lists with paging and search.
final listSteps = <Step>[
  // Checking a URL.
  const Step('check without a url', get, '/api/bookmarks/check/'),
  const Step(
    'check a saved url, normalized',
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fa.example.invalid%2Fa%2F',
  ),
  const Step(
    'check an unsaved url',
    get,
    '/api/bookmarks/check/?url=https%3A%2F%2Fnew.example.invalid%2F',
  ),

  // A few more bookmarks for lists.
  for (var i = 1; i <= 6; i++)
    Step(
      'filler $i',
      post,
      '/api/bookmarks/$noScrape',
      json: {
        'url': 'https://filler.example.invalid/$i',
        'title': 'Filler ${7 - i} history',
        'description': i.isEven ? 'rome and more' : 'athens',
        'tag_names': [if (i.isEven) 'even', if (i % 3 == 0) 'three'],
        'unread': i == 2,
      },
    ),

  // Lists, paging and search.
  const Step('list', get, '/api/bookmarks/'),
  const Step('page 2 of 2-per-page', get, '/api/bookmarks/?limit=2&offset=2'),
  const Step('first page links', get, '/api/bookmarks/?limit=3'),
  const Step(
    'previous link back to offset-less',
    get,
    '/api/bookmarks/?limit=3&offset=2&q=history',
  ),
  const Step(
    'zero and negative paging',
    get,
    '/api/bookmarks/?limit=0&offset=-3',
  ),
  const Step('garbage paging', get, '/api/bookmarks/?limit=abc&offset=x'),
  const Step('offset past the end', get, '/api/bookmarks/?limit=2&offset=50'),
  const Step(
    'extra params are kept in links',
    get,
    '/api/bookmarks/?limit=1&zeta=1&alpha=2&q=a+b',
  ),
  const Step('archived list', get, '/api/bookmarks/archived/'),
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
    Step('search q=$q', get, '/api/bookmarks/?q=$q'),
  for (final sort in [
    'title_asc',
    'title_desc',
    'added_asc',
    'added_desc',
    'modified_asc',
    'modified_desc',
    'bogus',
  ])
    Step('sort $sort', get, '/api/bookmarks/?sort=$sort'),
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
    Step('filter $filter', get, '/api/bookmarks/?$filter'),
];
