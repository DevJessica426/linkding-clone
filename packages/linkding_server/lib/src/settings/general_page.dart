import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../core/profile.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../pages/render.dart';
import '../pages/session_data.dart';
import '../pages/visitor.dart';
import 'global_settings.dart';
import 'profile_form.dart';
import 'profile_save.dart';
import 'profile_widgets.dart';
import 'version_info.dart';

/// `/settings` and `/settings/general`.
Future<Response> settingsGeneral(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final messages = await (await SessionData.of(request)).takeMessages();
  return _page(request, visitor, messages, ProfileForm.of(visitor.profile.row));
}

/// `/settings/update`: the profile, the global settings, or one of the
/// maintenance buttons.
Future<Result<Response, Rejection>> settingsUpdate(Request request) async {
  final back = Ok<Response, Rejection>(
    Redirect.found('/settings/general').intoResponse(),
  );
  if (request.method != 'POST') return back;
  final visitor = await request.extract(const Extension<Visitor>());
  final form = await request.extract(const PostedForm());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final session = await SessionData.of(request);
  Future<void> say(String message) =>
      session.addMessage(message, extraTags: 'settings_success_message');

  if (form.has('update_profile')) {
    final profile = ProfileForm.bound(form);
    if (profile.isValid) {
      await profile.save(db, visitor.signedIn.id);
      await say('Profile updated');
      return back;
    }
    // Django's form has already written the valid fields into the
    // request's profile (unsaved), and the page is drawn with it.
    final shown = visitor.withProfile(
      Profile(profile.applyTo(visitor.profile.row)),
    );
    final messages = [
      ...await session.takeMessages(),
      const MessageRow(
        level: 'error',
        message: 'Profile update failed, check the form below for errors',
        extraTags: 'settings_error_message',
      ),
    ];
    return Ok(await _page(request, shown, messages, profile, status: 422));
  }
  if (form.has('update_global_settings')) {
    if (!visitor.signedIn.isSuperuser) {
      return const Err(Rejection.forbidden('superusers only'));
    }
    await saveGlobalSettings(db, form);
    await say('Global settings updated');
  }
  if (form.has('refresh_favicons')) {
    // Favicons are not loaded by this server; like linkding without the
    // feature, nothing is scheduled.
    await say('Scheduled favicon update. This may take a while...');
  }
  if (form.has('create_missing_html_snapshots')) {
    await say('No missing snapshots found.');
  }
  return back;
}

Future<Response> _page(
  Request request,
  Visitor visitor,
  List<MessageRow> messages,
  ProfileForm form, {
  int status = 200,
}) async {
  String? tagged(String tag) =>
      messages.where((m) => m.extraTags == tag).firstOrNull?.message;
  final success = tagged('settings_success_message');
  final error = tagged('settings_error_message');
  final superuser = visitor.signedIn.isSuperuser;
  final db = (await request.state<LinkdingDatabase>()).connection;
  return renderPage(
    await request.state<TemplateEngine>(),
    visitor,
    title: 'Settings - Linkding',
    template: 'settings/general',
    status: status,
    values: {
      'hasSuccess': success != null,
      'success': success ?? '',
      'hasError': error != null,
      'error': error ?? '',
      ...profileWidgetValues(form, visitor.profile.row),
      'isSuperuser': superuser,
      if (superuser) ...await globalSettingsValues(db, visitor.settings),
      'about': await versionInfo(),
    },
  );
}
