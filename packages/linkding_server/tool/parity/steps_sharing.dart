import 'step.dart';

/// Lax tag search, legacy search, sharing, and the first asset steps.
final sharingSteps = <Step>[
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
    Step('lax q=$q', get, '/api/bookmarks/?q=$q'),
  const Step('profile shows lax', get, '/api/user/profile/'),
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
    Step('legacy q=$q', get, '/api/bookmarks/?q=$q'),
  const Step.sql(
    'back to strict, new search',
    "UPDATE bookmarks_userprofile SET tag_search = 'strict', legacy_search = false",
  ),

  // Sharing.
  const Step(
    'share one more',
    patch,
    '/api/bookmarks/5/',
    json: {'shared': true},
  ),
  const Step(
    'shared list before sharing is enabled',
    get,
    '/api/bookmarks/shared/',
  ),
  const Step.sql(
    'enable sharing',
    'UPDATE bookmarks_userprofile SET enable_sharing = true',
  ),
  const Step('shared list signed in', get, '/api/bookmarks/shared/'),
  const Step(
    'shared list anonymous, not public',
    get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step.sql(
    'enable public sharing',
    'UPDATE bookmarks_userprofile SET enable_public_sharing = true',
  ),
  const Step(
    'shared list anonymous, public',
    get,
    '/api/bookmarks/shared/',
    auth: Auth.none,
  ),
  const Step(
    'shared list of admin',
    get,
    '/api/bookmarks/shared/?user=admin',
    auth: Auth.none,
  ),
  const Step(
    'shared list searched',
    get,
    '/api/bookmarks/shared/?q=%23pad',
    auth: Auth.none,
  ),
  const Step(
    'shared list filtered',
    get,
    '/api/bookmarks/shared/?unread=yes&limit=1',
  ),
  const Step('profile shows sharing', get, '/api/user/profile/'),
  const Step('HEAD a list', 'HEAD', '/api/bookmarks/'),

  // Assets, on a bookmark with a known id.
  const Step.sql('a bookmark for assets', r'''
INSERT INTO bookmarks_bookmark (id, url, url_normalized, title, description,
  notes, web_archive_snapshot_url, favicon_file, preview_image_file, unread,
  is_archived, shared, date_added, date_modified, owner_id)
SELECT 900, 'https://assets.example.invalid/', 'https://assets.example.invalid',
  'Assets', '', '', '', '', '', false, false, false,
  '2026-01-02T03:04:05Z', '2026-01-02T03:04:05Z', id
FROM auth_user WHERE username = 'admin'
'''),
  const Step('no assets yet', get, '/api/bookmarks/900/assets/'),
  Step(
    'upload a text file',
    post,
    '/api/bookmarks/900/assets/upload/',
    files: [('file', 'notes.txt', 'text/plain', 'hello asset\n' * 40)],
  ),
  const Step(
    'upload a gzip file as it is',
    post,
    '/api/bookmarks/900/assets/upload/',
    files: [('file', 'dir/archive.tar.gz', 'application/gzip', 'not really')],
  ),
  const Step(
    'upload a name without extension',
    post,
    '/api/bookmarks/900/assets/upload/',
    files: [('file', 'README', 'text/markdown', '# Readme')],
  ),
  const Step(
    'upload with no file',
    post,
    '/api/bookmarks/900/assets/upload/',
    json: {'file': 'x'},
  ),
  const Step(
    'upload with a form but no file',
    post,
    '/api/bookmarks/900/assets/upload/',
    form: {'file': 'x'},
  ),
  const Step(
    'upload to a missing bookmark',
    post,
    '/api/bookmarks/999999/assets/upload/',
    files: [('file', 'a.txt', 'text/plain', 'a')],
  ),
  const Step('upload by GET', get, '/api/bookmarks/900/assets/upload/'),
  const Step('list assets', get, '/api/bookmarks/900/assets/'),
  const Step(
    'list assets paged',
    get,
    '/api/bookmarks/900/assets/?limit=1&offset=1',
  ),
  const Step(
    'list assets of a missing bookmark',
    get,
    '/api/bookmarks/999999/assets/',
  ),
  const Step('list without slash', get, '/api/bookmarks/900/assets'),
  const Step('one asset', get, '/api/bookmarks/900/assets/1/'),
  const Step('a missing asset', get, '/api/bookmarks/900/assets/99/'),
  const Step('a malformed asset id', get, '/api/bookmarks/900/assets/abc/'),
  const Step('an asset of another bookmark', get, '/api/bookmarks/1/assets/1/'),
];
