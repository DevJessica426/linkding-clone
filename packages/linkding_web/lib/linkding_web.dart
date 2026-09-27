/// The interactive parts of the linkding pages, in Dart: the `ld-*`
/// custom elements, confirmations and keyboard shortcuts that linkding
/// writes in JavaScript. Turbo and Floating UI, the libraries linkding
/// builds on, are bundled with it as they are.
library;

import 'src/components/bookmark_page.dart';
import 'src/components/controls.dart';
import 'src/components/dropdown.dart';
import 'src/components/filter_drawer.dart';
import 'src/components/modal.dart';
import 'src/components/search_autocomplete.dart';
import 'src/components/tag_autocomplete.dart';
import 'src/element.dart';
import 'src/focus.dart';
import 'src/shortcuts.dart';

/// Defines the elements and registers the page-wide listeners, in the
/// order linkding's `index.js` imports its modules.
void start() {
  initElementSupport();
  initFocus();
  defineElement('ld-bookmark-page', BookmarkPage.new);
  defineElement('ld-clear-button', ClearButton.new);
  initConfirmations();
  defineElement('ld-confirm-dropdown', ConfirmDropdown.new);
  defineElement('ld-details-modal', DetailsModal.new);
  defineElement('ld-dropdown', Dropdown.new);
  defineElement('ld-filter-drawer-trigger', FilterDrawerTrigger.new);
  defineElement('ld-filter-drawer', FilterDrawer.new);
  defineElement('ld-form', Form.new);
  defineElement('ld-modal', Modal.new);
  defineElement(
    'ld-search-autocomplete',
    SearchAutocomplete.new,
    observedAttributes: SearchAutocomplete.observed,
  );
  defineElement(
    'ld-tag-autocomplete',
    TagAutocomplete.new,
    observedAttributes: TagAutocomplete.observed,
  );
  defineElement('ld-upload-button', UploadButton.new);
  initShortcuts();
}
