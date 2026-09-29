import '../body.dart';
import '../fields.dart';

const _filterChoices = {'off', 'yes', 'no'};

/// The bundle fields of a request body: absent ones are null.
typedef BundleInput = ({
  String? name,
  String? search,
  String? anyTags,
  String? allTags,
  String? excludedTags,
  String? filterUnread,
  String? filterShared,
  int? order,
});

/// Reads [BundleInput] from [body], checked in linkding's order.
BundleInput bundleInput(RequestBody body, {required bool partial}) {
  requireObject(body);
  final errors = FieldErrors();
  T? read<T>(String name, T Function(Object?) parse, {bool required = false}) {
    final field = fieldOf(body, name, partial: partial);
    if (!field.present) {
      if (required && !partial) {
        errors.errors[name] = ['This field is required.'];
      }
      return null;
    }
    return errors.check(name, () => parse(field.value));
  }

  String? tags(String name) =>
      read(name, (v) => text(v, allowBlank: true, maxLength: 1024));
  final result = (
    name: read('name', (v) => text(v, maxLength: 256), required: true),
    search: read('search', (v) => text(v, allowBlank: true, maxLength: 256)),
    anyTags: tags('any_tags'),
    allTags: tags('all_tags'),
    excludedTags: tags('excluded_tags'),
    filterUnread: read('filter_unread', (v) => choice(v, _filterChoices)),
    filterShared: read('filter_shared', (v) => choice(v, _filterChoices)),
    order: read('order', integer),
  );
  errors.throwIfAny();
  return result;
}
