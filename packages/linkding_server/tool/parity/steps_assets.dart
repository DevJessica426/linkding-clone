import 'step.dart';

/// The rest of the asset steps.
final assetSteps = <Step>[
  const Step('download', get, '/api/bookmarks/900/assets/1/download/'),
  const Step(
    'download a gzip upload',
    get,
    '/api/bookmarks/900/assets/2/download/',
  ),
  const Step(
    'download unauthenticated',
    get,
    '/api/bookmarks/900/assets/1/download/',
    auth: Auth.none,
  ),
  const Step('PUT an asset', put, '/api/bookmarks/900/assets/1/', json: {}),
  const Step(
    'singlefile without a file',
    post,
    '/api/bookmarks/singlefile/',
    form: {'url': 'https://assets.example.invalid/'},
  ),
  const Step(
    'singlefile as JSON',
    post,
    '/api/bookmarks/singlefile/',
    json: {'url': 'https://assets.example.invalid/'},
  ),
  const Step(
    'singlefile for a saved URL',
    post,
    '/api/bookmarks/singlefile/',
    form: {'url': 'https://assets.example.invalid'},
    files: [
      (
        'file',
        'page.html',
        'text/html',
        '<html><head><title>Snap</title></head><body><p>Saved page</p></body></html>',
      ),
    ],
  ),
  const Step(
    'singlefile for a new URL',
    post,
    '/api/bookmarks/singlefile/',
    form: {'url': '$pagesUrl/page.html'},
    files: [
      ('file', 'page.html', 'text/html', '<html><body>Other</body></html>'),
    ],
  ),
  const Step('singlefile by GET', get, '/api/bookmarks/singlefile/'),
  const Step('assets after a snapshot', get, '/api/bookmarks/900/assets/'),
  const Step('the new bookmark', get, '/api/bookmarks/?q=Saved+OR+page.html'),
  const Step('delete an asset', delete, '/api/bookmarks/900/assets/3/'),
  const Step('delete it again', delete, '/api/bookmarks/900/assets/3/'),
  const Step('assets after deleting', get, '/api/bookmarks/900/assets/'),
  const Step('final state', get, '/api/bookmarks/?limit=100'),
];
