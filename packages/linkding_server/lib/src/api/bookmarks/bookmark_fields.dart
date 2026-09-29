import '../body.dart';
import '../fields.dart';

/// The bookmark fields of a request body, checked in linkding's order.
/// Absent fields are null.
typedef BookmarkFields = ({
  String? url,
  String? title,
  String? description,
  String? notes,
  bool? isArchived,
  bool? unread,
  bool? shared,
  List<String>? tagNames,
  DateTime? dateAdded,
  DateTime? dateModified,
});

/// Reads [BookmarkFields] from [body]; a full update ([partial] false)
/// needs a URL. [checkUrl] is off with `LD_DISABLE_URL_VALIDATION`.
BookmarkFields bookmarkFields(
  RequestBody body, {
  required bool partial,
  required bool checkUrl,
}) {
  requireObject(body);
  final errors = FieldErrors();
  T? read<T>(
    String name,
    T Function(Object?) parse, {
    bool required = false,
    bool checkbox = false,
    bool list = false,
    bool blankIsAbsent = false,
  }) {
    final field = fieldOf(
      body,
      name,
      partial: partial,
      checkbox: checkbox,
      list: list,
    );
    if (!field.present) {
      if (required && !partial) {
        errors.errors[name] = ['This field is required.'];
      }
      return null;
    }
    if (blankIsAbsent && body.isForm && field.value == '') return null;
    return errors.check(name, () => parse(field.value));
  }

  final validator = validUrl(disabled: !checkUrl);
  final url = read(
    'url',
    (v) => text(v, maxLength: 2048, validators: [validator]),
    required: true,
  );
  final title = read('title', (v) => text(v, allowBlank: true, maxLength: 512));
  final description = read('description', (v) => text(v, allowBlank: true));
  final notes = read('notes', (v) => text(v, allowBlank: true));
  final isArchived = read('is_archived', boolean, checkbox: true);
  final unread = read('unread', boolean, checkbox: true);
  final shared = read('shared', boolean, checkbox: true);
  final tagNames = read('tag_names', stringList, list: true);
  final dateAdded = read('date_added', dateTime, blankIsAbsent: true);
  final dateModified = read('date_modified', dateTime, blankIsAbsent: true);
  errors.throwIfAny();
  return (
    url: url,
    title: title,
    description: description,
    notes: notes,
    isArchived: isArchived,
    unread: unread,
    shared: shared,
    tagNames: tagNames,
    dateAdded: dateAdded,
    dateModified: dateModified,
  );
}
