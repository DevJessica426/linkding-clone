/// linkding's settings pages: preferences, integrations, import and export.
library;

import 'package:dust_server/server.dart';

import '../pages/session/sign_in.dart';
import 'general_page.dart';
import 'import_export.dart';
import 'integrations.dart';

Router settingsRoutes() => Router()
  ..routeLayer(fromExtractor(const RequireSignIn()))
  ..route('/settings', any(settingsGeneral))
  ..route('/settings/general', any(settingsGeneral))
  ..route('/settings/update', any(settingsUpdate))
  ..route('/settings/integrations', any(settingsIntegrations))
  ..route('/settings/integrations/create-api-token', any(createApiToken))
  ..route('/settings/integrations/delete-api-token', any(deleteApiToken))
  ..route('/settings/import', any(importBookmarks))
  ..route('/settings/export', any(exportBookmarks));
