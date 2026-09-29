import '../pages/visitor.dart';
import '../pages/widgets.dart';
import 'bookmark_form.dart';

const _text = {'class': 'form-input', 'autocomplete': 'off'};
const _textarea = {'cols': '40', 'rows': '10', 'class': 'form-input'};

/// What `bookmarks/form` reads: the form's widgets as Django renders them.
Map<String, Object?> formValues(
  Visitor visitor,
  BookmarkForm form, {
  required String heading,
  required String action,
  required String returnUrl,
  required int bookmarkId,
}) {
  final profile = visitor.profile.row;
  final errors = form.errors;
  return {
    'heading': heading,
    'action': action,
    'returnUrl': returnUrl,
    'bookmarkId': bookmarkId,
    'autoClose': hiddenInput('auto_close', form.autoClose),
    'urlInput': inputField(
      'text',
      'url',
      form.rawUrl,
      fieldAttributes(
        'url',
        widget: _text,
        required: true,
        errors: errors['url']!,
        extra: const {'autofocus': true},
      ),
    ),
    'urlErrors': errorList('url', errors['url']!),
    'tagString': form.raw['tag_string'] ?? '',
    'tagDescribedBy': fieldAttributes(
      'tag_string',
      hasHelp: true,
    )['aria-describedby'],
    'titleInput': inputField(
      'text',
      'title',
      form.raw['title'],
      fieldAttributes(
        'title',
        widget: {..._text, 'maxlength': '512'},
        errors: errors['title']!,
      ),
    ),
    'descriptionInput': textareaField(
      'description',
      form.raw['description'],
      fieldAttributes(
        'description',
        widget: _textarea,
        errors: errors['description']!,
        extra: const {'rows': '3'},
      ),
    ),
    'hasNotes': form.hasNotes,
    'notesInput': textareaField(
      'notes',
      form.raw['notes'],
      fieldAttributes(
        'notes',
        widget: _textarea,
        hasHelp: true,
        errors: errors['notes']!,
        extra: const {'rows': '8'},
      ),
    ),
    'unreadInput': _checkbox('unread', form.unread, 'Mark as unread'),
    'sharing': profile.enableSharing,
    'sharedInput': _checkbox('shared', form.shared, 'Share'),
    'sharedHelp': profile.enablePublicSharing
        ? 'Share this bookmark with other registered users and anonymous '
              'users.'
        : 'Share this bookmark with other registered users.',
    'isAutoClose': form.isAutoClose,
  };
}

String _checkbox(String name, bool checked, String label) =>
    checkboxField(name, checked, label, fieldAttributes(name, hasHelp: true));
