import 'step.dart';

/// The rest of the rejected bodies, reading one bookmark, and updating.
final updateSteps = <Step>[
  const Step(
    'title and notes are trimmed',
    post,
    '/api/bookmarks/$noScrape',
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
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://A.EXAMPLE.invalid/a/',
      'title': 'Merged',
      'notes': 'n',
      'is_archived': true,
    },
  ),
  const Step(
    'an archived bookmark straight away',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://archived.example.invalid',
      'title': 'Zebra',
      'is_archived': true,
    },
  ),
  const Step(
    'explicit dates',
    post,
    '/api/bookmarks/$noScrape',
    json: {
      'url': 'https://old.example.invalid',
      'title': 'old',
      'date_added': '2019-05-06T07:08:09.123456+02:00',
      'date_modified': '2019-05-06T07:08:09Z',
    },
  ),

  // Reading one bookmark.
  const Step('retrieve', get, '/api/bookmarks/1/'),
  const Step('retrieve a missing id', get, '/api/bookmarks/999/'),
  const Step('retrieve a non-numeric id', get, '/api/bookmarks/abc/'),
  const Step('retrieve a huge id', get, '/api/bookmarks/99999999999/'),
  const Step('retrieve a negative id', get, '/api/bookmarks/-1/'),

  // Updating.
  const Step('PUT without url', put, '/api/bookmarks/1/', json: {'title': 'x'}),
  const Step(
    'PUT keeps what it does not send',
    put,
    '/api/bookmarks/1/',
    json: {'url': 'https://a.example.invalid/a', 'title': 'Put'},
  ),
  const Step(
    'PATCH tags only',
    patch,
    '/api/bookmarks/1/',
    json: {
      'tag_names': ['z', 'Y'],
    },
  ),
  const Step(
    'PATCH booleans and date_added',
    patch,
    '/api/bookmarks/1/',
    json: {
      'unread': true,
      'shared': 'false',
      'date_added': '2021-02-03T04:05:06Z',
    },
  ),
  const Step(
    'PATCH into a duplicate URL',
    patch,
    '/api/bookmarks/1/',
    json: {'url': 'https://tags.example.invalid'},
  ),
  const Step(
    'PATCH a missing bookmark',
    patch,
    '/api/bookmarks/999/',
    json: {'title': 'x'},
  ),
  const Step(
    'PATCH with bad JSON on a missing bookmark is 404 first',
    patch,
    '/api/bookmarks/999/',
    raw: '{bad',
    contentType: 'application/json',
  ),
  Step(
    'PATCH with invalid fields',
    patch,
    '/api/bookmarks/1/',
    json: {'title': 'x' * 600, 'unread': 'nope'},
  ),
];
