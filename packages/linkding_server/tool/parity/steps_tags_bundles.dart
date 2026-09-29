import 'step.dart';

/// Tags and bundles.
final tagBundleSteps = <Step>[
  // Tags.
  const Step(
    'create a tag that exists in another case',
    post,
    '/api/tags/',
    json: {'name': 'PAD'},
  ),
  const Step('create a new tag', post, '/api/tags/', json: {'name': 'fresh'}),
  const Step(
    'create a tag with spaces',
    post,
    '/api/tags/',
    json: {'name': '  has space  '},
  ),
  const Step('create a blank tag', post, '/api/tags/', json: {'name': ''}),
  const Step(
    'create a tag without name',
    post,
    '/api/tags/',
    json: <String, Object>{},
  ),
  Step('create a tag too long', post, '/api/tags/', json: {'name': 't' * 65}),
  const Step('tags list', get, '/api/tags/'),
  const Step('tags page', get, '/api/tags/?limit=3&offset=3'),
  const Step('retrieve tag', get, '/api/tags/1/'),
  const Step('retrieve missing tag', get, '/api/tags/999/'),
  const Step(
    'PUT a tag is not allowed',
    put,
    '/api/tags/1/',
    json: {'name': 'x'},
  ),
  const Step('delete a tag', delete, '/api/tags/2/'),
  const Step('its bookmark lost the tag', get, '/api/bookmarks/?q=%23b'),
  const Step('delete it again', delete, '/api/tags/2/'),

  // Bundles.
  const Step(
    'create bundle',
    post,
    '/api/bundles/',
    json: {'name': 'Evens', 'any_tags': 'even three', 'filter_unread': 'no'},
  ),
  const Step(
    'create bundle with order',
    post,
    '/api/bundles/',
    json: {'name': 'Second', 'order': 7, 'search': 'filler'},
  ),
  const Step(
    'create bundle, next order',
    post,
    '/api/bundles/',
    json: {'name': 'Third', 'all_tags': 'even', 'excluded_tags': 'three'},
  ),
  const Step(
    'invalid bundle',
    post,
    '/api/bundles/',
    json: {'name': '', 'filter_shared': 'maybe', 'order': 'x'},
  ),
  const Step(
    'bundle order as text and float',
    post,
    '/api/bundles/',
    json: {'name': 'Floaty', 'order': '4.0'},
  ),
  const Step(
    'bundle order out of range',
    post,
    '/api/bundles/',
    json: {'name': 'Huge', 'order': 99999999999},
  ),
  const Step('bundles list', get, '/api/bundles/'),
  const Step('bundle filters the list', get, '/api/bookmarks/?bundle=1'),
  const Step(
    'bundle with search and excludes',
    get,
    '/api/bookmarks/?bundle=3',
  ),
  const Step('bundle words', get, '/api/bookmarks/?bundle=2'),
  const Step(
    'PUT bundle without name',
    put,
    '/api/bundles/1/',
    json: {'search': 's'},
  ),
  const Step(
    'PATCH bundle',
    patch,
    '/api/bundles/1/',
    json: {'filter_shared': 'yes', 'order': 0},
  ),
  const Step('retrieve missing bundle', get, '/api/bundles/999/'),
  const Step('delete bundle', delete, '/api/bundles/1/'),
  const Step('bundles renumbered', get, '/api/bundles/'),
];
