import '../../compat/django.dart';
import '../../compat/form_data.dart';
import '../../pages/support/cleaning.dart';
import '../service/bookmark_service.dart';

/// linkding's `BookmarkForm`: the values to show, and once submitted, the
/// cleaned values and errors.
final class BookmarkForm {
  BookmarkForm({
    String? url,
    String? title,
    String? description,
    String? notes,
    String? tagString,
    this.autoClose,
    this.unread = false,
    this.shared = false,
    this.hasNotes = false,
  }) : rawUrl = url,
       isBound = false,
       raw = {
         'title': title,
         'description': description,
         'notes': notes,
         'tag_string': tagString,
       };

  /// A submitted form shows what was sent. A field that was not sent at
  /// all saves as empty: none of these fields has a default that Django's
  /// `construct_instance` would keep instead.
  BookmarkForm.bound(FormData data)
    : rawUrl = data['url'],
      isBound = true,
      autoClose = data['auto_close'],
      unread = checkboxValue(data['unread']),
      shared = checkboxValue(data['shared']),
      hasNotes = false,
      raw = {
        'title': data['title'],
        'description': data['description'],
        'notes': data['notes'],
        'tag_string': data['tag_string'],
      };

  final bool isBound;
  final String? rawUrl;
  final Map<String, String?> raw;
  final String? autoClose;
  final bool unread;
  final bool shared;
  bool hasNotes;

  String? url;
  final cleaned = <String, String>{};
  final errors = <String, List<String>>{
    'url': [],
    'title': [],
    'description': [],
    'notes': [],
    'tag_string': [],
  };

  bool get isValid => errors.values.every((e) => e.isEmpty);

  /// A popup opened with `?auto_close` closes itself after saving.
  bool get isAutoClose => autoClose == 'True';

  /// The tag string as `BookmarkForm.save` passes it on: the raw input with
  /// spaces turned into commas.
  String get tagString => (raw['tag_string'] ?? '').replaceAll(' ', ',');

  /// The form's field checks, then the model's.
  void validate({required bool checkUrl}) {
    final cleanUrl = cleanChar(rawUrl, required: true);
    url = cleanUrl.value;
    errors['url']!.addAll(cleanUrl.errors);
    if (cleanUrl.errors.isEmpty && checkUrl && !isValidUrl(cleanUrl.value)) {
      errors['url']!.add('Enter a valid URL.');
    }
    if (errors['url']!.isEmpty) {
      errors['url']!.addAll(cleanChar(cleanUrl.value, maxLength: 2048).errors);
    }
    for (final (name, maxLength) in const [
      ('title', 512),
      ('description', null),
      ('notes', null),
      ('tag_string', null),
    ]) {
      final field = cleanChar(raw[name], maxLength: maxLength);
      errors[name]!.addAll(field.errors);
      cleaned[name] = field.value;
    }
  }

  BookmarkDraft draft({bool isArchived = false, DateTime? dateAdded}) =>
      BookmarkDraft(
        url: url!,
        title: cleaned['title']!,
        description: cleaned['description']!,
        notes: cleaned['notes']!,
        unread: unread,
        shared: shared,
        isArchived: isArchived,
        dateAdded: dateAdded,
      );
}
