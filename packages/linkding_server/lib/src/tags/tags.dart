/// linkding's tags page and its dialogs.
library;

import 'package:dust_server/server.dart';

import '../pages/sign_in.dart';
import 'tag_dialogs.dart';
import 'tag_list.dart';
import 'tag_merge.dart';

Router tagRoutes() => Router()
  ..routeLayer(fromExtractor(const RequireSignIn()))
  ..route('/tags', any(tagIndex))
  ..route('/tags/new', any(tagCreate))
  ..route('/tags/{id|[0-9]+}/edit', any(tagEdit))
  ..route('/tags/merge', any(tagMerge));
