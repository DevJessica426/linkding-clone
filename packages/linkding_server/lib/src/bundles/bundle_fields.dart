import '../db/rows/rows.dart';
import '../pages/support/cleaning.dart';

/// A bundle form's fields: what to show, and the values it saves.
final class BundleFields {
  BundleFields({
    required this.rawName,
    required this.rawSearch,
    required this.rawAnyTags,
    required this.rawAllTags,
    required this.rawExcludedTags,
    required this.filterUnread,
    required this.filterShared,
    required this.shownUnread,
    required this.shownShared,
  });

  /// An unsubmitted form: the bundle's values, or for a new bundle the
  /// defaults and what `?q=` suggested.
  factory BundleFields.initial(
    BundleRow? bundle,
    Map<String, String> initial,
  ) => BundleFields(
    rawName: bundle?.name ?? '',
    rawSearch: bundle?.search ?? initial['search'] ?? '',
    rawAnyTags: bundle?.anyTags ?? '',
    rawAllTags: bundle?.allTags ?? initial['all_tags'] ?? '',
    rawExcludedTags: bundle?.excludedTags ?? '',
    filterUnread: bundle?.filterUnread ?? 'off',
    filterShared: bundle?.filterShared ?? 'off',
    // A new model form has no initial values, so no option is chosen.
    shownUnread: bundle?.filterUnread,
    shownShared: bundle?.filterShared,
  );

  /// Submitted values. A filter left out keeps the bundle's value (the
  /// model's default for a new one); one sent empty is saved empty, as
  /// Django's `construct_instance` does for a field with a default.
  factory BundleFields.fromData(Map<String, String> data, BundleRow? bundle) =>
      BundleFields(
        rawName: data['name'] ?? '',
        rawSearch: data['search'] ?? '',
        rawAnyTags: data['any_tags'] ?? '',
        rawAllTags: data['all_tags'] ?? '',
        rawExcludedTags: data['excluded_tags'] ?? '',
        filterUnread: data['filter_unread'] ?? bundle?.filterUnread ?? 'off',
        filterShared: data['filter_shared'] ?? bundle?.filterShared ?? 'off',
        shownUnread: data['filter_unread'],
        shownShared: data['filter_shared'],
      );

  final String rawName;
  final String rawSearch;
  final String rawAnyTags;
  final String rawAllTags;
  final String rawExcludedTags;
  final String filterUnread;
  final String filterShared;

  /// The option each filter shows as chosen: what was sent, or the saved
  /// value, and none for a new bundle.
  final String? shownUnread;
  final String? shownShared;

  String get name => rawName.trim();
  String get search => rawSearch.trim();
  String get anyTags => rawAnyTags.trim();
  String get allTags => rawAllTags.trim();
  String get excludedTags => rawExcludedTags.trim();

  /// `BookmarkBundleForm` and the model's limits.
  Map<String, List<String>> validate() {
    List<String> choice(String value) =>
        value.isEmpty || const {'off', 'yes', 'no'}.contains(value)
        ? const []
        : [
            'Select a valid choice. $value is not one of the available '
                'choices.',
          ];
    return {
      'name': cleanChar(rawName, required: true, maxLength: 256).errors,
      'search': cleanChar(rawSearch, maxLength: 256).errors,
      'any_tags': cleanChar(rawAnyTags, maxLength: 1024).errors,
      'all_tags': cleanChar(rawAllTags, maxLength: 1024).errors,
      'excluded_tags': cleanChar(rawExcludedTags, maxLength: 1024).errors,
      'filter_unread': choice(filterUnread),
      'filter_shared': choice(filterShared),
    };
  }

  /// An unsaved bundle holding these values, for the preview.
  BundleRow toBundle(int ownerId) {
    final now = DateTime.now().toUtc();
    return BundleRow(
      id: 0,
      name: 'Preview Bundle',
      search: search,
      anyTags: anyTags,
      allTags: allTags,
      excludedTags: excludedTags,
      filterUnread: filterUnread,
      filterShared: filterShared,
      order: 0,
      dateCreated: now,
      dateModified: now,
      ownerId: ownerId,
    );
  }
}
