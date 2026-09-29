/// The pages around linkding's pages: the landing redirect, the web app
/// manifest, OpenSearch, custom CSS, and dismissing toasts.
library;

import 'package:dust_server/server.dart';

import '../pages/session/sign_in.dart';
import 'landing.dart';
import 'manifest.dart';
import 'site_files.dart';
import 'toasts.dart';

export 'manifest.dart' show pythonJson;

Router siteRoutes() => Router()
  ..route('/', any(root))
  ..route('/manifest.json', any(manifest))
  ..route('/custom_css', any(customCss))
  ..route('/opensearch.xml', any(opensearch))
  ..merge(
    Router()
      ..routeLayer(fromExtractor(const RequireSignIn()))
      ..route('/toasts/acknowledge', any(acknowledgeToast)),
  );
