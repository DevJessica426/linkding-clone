/// What the queries select, one type per shape, over linkding's own tables.
/// `dust build` writes each file's row mapping; `dust db build` checks every
/// column against these fields.
library;

export 'bookmark_rows.dart';
export 'bundle_row.dart';
export 'profile_row.dart';
export 'settings_rows.dart';
export 'tag_rows.dart';
export 'user_rows.dart';
