import 'package:dust_dart/db.dart';

import '../compat/form_data.dart';
import '../db/rows.dart';
import '../db/settings_repo.dart';
import '../db/users_repo.dart';
import '../pages/cleaning.dart';
import '../pages/widgets.dart';
import '../services/errors.dart';
import 'profile_widgets.dart';

/// What `settings-global.html` reads: the global settings' widgets, for a
/// superuser.
Future<Map<String, Object?>> globalSettingsValues(
  Executor db,
  GlobalSettingsRow settings,
) async {
  final users = (await UsersRepo(db).allUsers()).orThrow;
  const narrow = {'class': 'width-25 width-sm-100'};
  return {
    'w_landing_page': selectWidget(
      'landing_page',
      const [('login', 'Login'), ('shared_bookmarks', 'Shared Bookmarks')],
      settings.landingPage,
      fieldAttributes(
        'landing_page',
        widget: const {'class': 'form-select'},
        required: true,
        requiredAttribute: false,
        hasHelp: true,
        extra: narrow,
      ),
    ),
    'w_guest_profile_user': selectWidget(
      'guest_profile_user',
      [
        ('', 'Standard profile'),
        for (final u in users) ('${u.id}', u.username),
      ],
      '${settings.guestProfileUserId ?? ''}',
      fieldAttributes(
        'guest_profile_user',
        widget: const {'class': 'form-select'},
        hasHelp: true,
        extra: narrow,
      ),
    ),
    'w_enable_link_prefetch': checkboxField(
      'enable_link_prefetch',
      settings.enableLinkPrefetch,
      'Enable prefetching links on hover',
      fieldAttributes('enable_link_prefetch', hasHelp: true),
    ),
  };
}

/// `update_global_settings`: saved when valid; the page reports it saved
/// either way, as linkding does.
Future<void> saveGlobalSettings(Executor db, FormData form) async {
  final landingPage = form['landing_page'] ?? '';
  if (!const {'login', 'shared_bookmarks'}.contains(landingPage)) return;
  final guest = form['guest_profile_user'] ?? '';
  int? guestId;
  if (guest.isNotEmpty) {
    guestId = int.tryParse(guest.trim());
    final users = (await UsersRepo(db).allUsers()).orThrow;
    if (!users.any((u) => u.id == guestId)) return;
  }
  final settings = (await SettingsRepo(db).global()).orThrow!;
  (await SettingsRepo(db).updateGlobal(
    settings.id,
    landingPage,
    guestId,
    checkboxValue(form['enable_link_prefetch']),
  )).orThrow;
}
