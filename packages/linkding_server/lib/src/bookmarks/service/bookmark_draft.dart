/// The fields of a bookmark someone is saving, before it has an id.
final class BookmarkDraft {
  BookmarkDraft({
    required this.url,
    this.title = '',
    this.description = '',
    this.notes = '',
    this.isArchived = false,
    this.unread = false,
    this.shared = false,
    this.dateAdded,
    this.dateModified,
  });

  String url;
  String title;
  String description;
  String notes;
  bool isArchived;
  bool unread;
  bool shared;
  DateTime? dateAdded;
  DateTime? dateModified;
}
