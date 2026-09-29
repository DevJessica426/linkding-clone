import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../db/or_throw.dart';
import '../pages/session/session_data.dart';
import '../pages/support/widgets.dart';
import 'tag_dialogs.dart';
import 'tag_forms.dart';

/// `/tags/merge`: moves the bookmarks of some tags to another, then
/// deletes those tags.
Future<Response> tagMerge(Request request) async {
  final (visitor, engine, tags) = await tagContext(request);
  String dialog(FormData form, Map<String, List<String>> errors) =>
      tagDialog(engine, visitor, {
        'action': '/tags/merge',
        'target': '_top',
        'closeUrl': '/tags',
        'title': 'Merge Tags',
        'modalClass': 'modal active',
        'submit': 'Merge Tags',
        'body': engine.render('tags/merge-fields', {
          'fields': [
            for (final (name, label, help) in _mergeFields)
              _tagField(name, label, form[name], help, errors[name] ?? []),
          ],
        }),
      });
  if (request.method != 'POST') {
    return htmlResponse(dialog(const FormData({}), const {}));
  }
  final form = await request.extract(const PostedForm());
  final user = visitor.signedIn;
  final merge = await cleanMerge(tags, form, user.id);
  if (!merge.isValid) return replaceTagDialog(dialog(form, merge.errors));
  final target = merge.target!;
  (await tags.merge(user.id, target.id, [
    for (final t in merge.merged) t.id,
  ])).orThrow;
  await (await SessionData.of(request)).addMessage(
    'Successfully merged ${merge.merged.length} tags '
    '(${merge.merged.map((t) => t.name).join(', ')}) into "${target.name}".',
  );
  return Redirect.found('/tags').intoResponse();
}

const _mergeFields = [
  (
    'target_tag',
    'Target tag',
    '\n            Enter the name of the tag you want to keep. The tags '
        'entered below will be merged into this one.\n          ',
  ),
  (
    'merge_tags',
    'Tags to merge',
    '\n            Enter the names of tags to merge into the target tag, '
        'separated by spaces.\n            These tags will be deleted after '
        'merging.\n          ',
  ),
];

Map<String, Object?> _tagField(
  String name,
  String label,
  String? value,
  String help,
  List<String> errors,
) {
  final attrs = fieldAttributes(
    name,
    required: true,
    hasHelp: true,
    errors: errors,
  );
  return {
    'name': name,
    'label': label,
    'value': value ?? '',
    'describedBy': attrs['aria-describedby'],
    'hasClasses': attrs['class'] != null,
    'classes': attrs['class'] ?? '',
    'help': help,
    'errors': errorList(name, errors),
  };
}
