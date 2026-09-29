import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import '../db/repos/users_repo.dart';
import '../pages/support/render.dart';
import '../pages/session/visitor.dart';
import '../pages/support/widgets.dart';
import 'password_validation.dart';
import 'passwords.dart';
import 'sessions.dart';

/// `/change-password/`: Django's `PasswordChangeView` with linkding's
/// error list, answering a failed change with 422 for Turbo.
Future<Response> changePassword(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final engine = await request.state<TemplateEngine>();
  if (request.method != 'POST') return _page(engine, visitor, const {});

  final form = await request.extract(const PostedForm());
  final user = visitor.signedIn;
  final users = UsersRepo((await request.state<LinkdingDatabase>()).connection);
  final hasher = await request.state<PasswordHasher>();
  final errors = await _clean(
    form,
    user,
    users,
    hasher,
    await request.state<PasswordValidator>(),
  );
  if (errors.values.any((e) => e.isNotEmpty)) {
    return _page(engine, visitor, errors, status: 422);
  }
  final password = await hasher.hash(form['new_password1']!);
  (await users.setPassword(user.id, password)).orThrow;
  final session = await (await request.state<Sessions>())
      .keepAfterPasswordChange(request, user.id);
  return Redirect.found('/password-change-done/')
      .intoResponse()
      .change(headers: {'set-cookie': ?session});
}

/// `/password-change-done/`.
Future<Response> passwordChangeDone(Request request) async => renderPage(
  await request.state<TemplateEngine>(),
  await request.extract(const Extension<Visitor>()),
  title: 'Password changed - Linkding',
  template: 'accounts/password-changed',
);

/// `PasswordChangeForm.is_valid`: every field's errors, in field order.
Future<Map<String, List<String>>> _clean(
  FormData form,
  UserRow user,
  UsersRepo users,
  PasswordHasher hasher,
  PasswordValidator validator,
) async {
  final errors = <String, List<String>>{
    for (final (name, _, _) in _fields) name: [],
  };
  // `CharField(strip=False)` for each field, in order.
  final cleaned = <String, String>{};
  for (final MapEntry(key: name, value: fieldErrors) in errors.entries) {
    final value = form[name] ?? '';
    if (value.isEmpty) {
      fieldErrors.add('This field is required.');
    } else if (value.contains('\x00')) {
      fieldErrors.add('Null characters are not allowed.');
    } else {
      cleaned[name] = value;
    }
  }
  // `clean_old_password`; a correct password in an outdated hash is stored
  // again, as Django's `check_password` does.
  if (cleaned['old_password'] case final old?) {
    if (await hasher.verify(old, user.password)) {
      if (hasher.mustUpdate(user.password)) {
        (await users.setPassword(user.id, await hasher.hash(old))).orThrow;
      }
    } else {
      errors['old_password']!.add(
        'Your old password was entered incorrectly. Please enter it again.',
      );
    }
  }
  // `SetPasswordForm.clean`: the two must match, and the second must pass
  // the password validators.
  final first = cleaned['new_password1'];
  final second = cleaned['new_password2'];
  if (first != null && second != null && first != second) {
    errors['new_password2']!.add('The two password fields didn’t match.');
  } else if (second != null) {
    errors['new_password2']!.addAll(validator.validate(second, user));
  }
  return errors;
}

/// The form's fields: name, label, and the widget's own attributes.
const _fields = [
  (
    'old_password',
    'Old password',
    {'autocomplete': 'current-password', 'autofocus': true},
  ),
  ('new_password1', 'New password', {'autocomplete': 'new-password'}),
  ('new_password2', 'Confirm new password', {'autocomplete': 'new-password'}),
];

Response _page(
  TemplateEngine engine,
  Visitor visitor,
  Map<String, List<String>> errors, {
  int status = 200,
}) => renderPage(
  engine,
  visitor,
  title: 'Change password - Linkding',
  template: 'accounts/password-change',
  status: status,
  values: {
    'fields': [
      for (final (name, label, widget) in _fields)
        {
          'name': name,
          'label': label,
          'widget': inputField(
            'password',
            name,
            null,
            fieldAttributes(
              name,
              widget: widget,
              required: true,
              // Django's help texts: the validators' rules, and "enter the
              // same password"; none for the old password.
              djangoHelpText: name != 'old_password',
              errors: errors[name] ?? const [],
              extra: const {'class': 'form-input'},
            ),
          ),
          'errors': errorList(name, errors[name] ?? const []),
        },
    ],
  },
);
