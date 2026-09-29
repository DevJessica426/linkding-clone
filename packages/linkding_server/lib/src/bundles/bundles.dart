/// linkding's bundles: saved searches listed beside the bookmarks, with
/// an editor that previews what a bundle matches.
library;

import 'package:dust_server/server.dart';

import '../pages/sign_in.dart';
import 'bundle_editor.dart';
import 'bundle_list.dart';
import 'bundle_preview.dart';

Router bundleRoutes() => Router()
  ..routeLayer(fromExtractor(const RequireSignIn()))
  ..route('/bundles', any(bundleIndex))
  ..route('/bundles/action', any(bundleAction))
  ..route('/bundles/new', any(newBundle))
  ..route('/bundles/{id|[0-9]+}/edit', any(editBundle))
  ..route('/bundles/preview', any(previewBundle));
