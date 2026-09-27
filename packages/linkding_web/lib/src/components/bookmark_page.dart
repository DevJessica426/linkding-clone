import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';

/// `<ld-bookmark-page>`: tooltips for cut-off titles, the notes toggles,
/// and bulk editing, set up again whenever the list is replaced (the list
/// announces itself with `bookmark-list-updated`).
final class BookmarkPage extends HeadlessElement {
  BookmarkPage(super.host);

  Listener? _listUpdated;
  final _notesToggles = <Listener>[];
  final _bulkEditListeners = <Listener>[];

  web.HTMLInputElement? _allCheckbox;
  var _bookmarkCheckboxes = <web.HTMLInputElement>[];
  web.HTMLElement? _selectAcross;
  web.HTMLButtonElement? _executeButton;

  @override
  void init() {
    _update();
    _listUpdated = Listener(
      web.document,
      'bookmark-list-updated',
      (_) => _update(),
    );
  }

  @override
  void disconnected() => _listUpdated?.cancel();

  void _update() {
    final items = queryAll(host, 'ul.bookmark-list > li');
    _updateTooltips(items);
    _updateNotesToggles(items);
    _updateBulkEdit();
  }

  /// A title that does not fit gets its full text as a tooltip.
  void _updateTooltips(List<web.HTMLElement> items) {
    for (final item in items) {
      final anchor = item.querySelector('.title > a')! as web.HTMLElement;
      final span = anchor.querySelector('span')! as web.HTMLElement;
      if (span.offsetWidth > anchor.offsetWidth) {
        anchor.setAttribute('data-tooltip', span.textContent ?? '');
      } else {
        anchor.removeAttribute('data-tooltip');
      }
    }
  }

  void _updateNotesToggles(List<web.HTMLElement> items) {
    for (final listener in _notesToggles) {
      listener.cancel();
    }
    _notesToggles.clear();
    for (final item in items) {
      final toggle = item.querySelector('.toggle-notes');
      if (toggle == null) continue;
      _notesToggles.add(
        Listener(toggle, 'click', (event) {
          event
            ..preventDefault()
            ..stopPropagation();
          (event.target as web.Element)
              .closest('li')
              ?.classList
              .toggle('show-notes');
        }),
      );
    }
  }

  void _updateBulkEdit() {
    if (host.hasAttribute('no-bulk-edit')) return;

    for (final listener in _bulkEditListeners) {
      listener.cancel();
    }
    _bulkEditListeners.clear();

    final activeToggle = host.querySelector('.bulk-edit-active-toggle')!;
    final actionSelect =
        host.querySelector("select[name='bulk_action']")!
            as web.HTMLSelectElement;
    final allCheckbox =
        host.querySelector('.bulk-edit-checkbox.all input')!
            as web.HTMLInputElement;
    _allCheckbox = allCheckbox;
    _bookmarkCheckboxes = [
      for (final input in queryAll(host, '.bulk-edit-checkbox:not(.all) input'))
        input as web.HTMLInputElement,
    ];
    final selectAcross =
        host.querySelector('label.select-across')! as web.HTMLElement;
    _selectAcross = selectAcross;
    _executeButton =
        host.querySelector("button[name='bulk_execute']")!
            as web.HTMLButtonElement;

    _bulkEditListeners
      ..add(
        Listener(activeToggle, 'click', (_) => host.classList.toggle('active')),
      )
      ..add(
        Listener(actionSelect, 'change', (_) {
          host.setAttribute('data-bulk-action', actionSelect.value);
        }),
      )
      ..add(Listener(allCheckbox, 'change', (_) => _onToggleAll()));
    for (final checkbox in _bookmarkCheckboxes) {
      _bulkEditListeners.add(
        Listener(checkbox, 'change', (_) => _onToggleBookmark()),
      );
    }

    allCheckbox.checked = false;
    for (final checkbox in _bookmarkCheckboxes) {
      checkbox.checked = false;
    }
    _updateSelectAcross(false);
    _updateExecuteButton();

    final total =
        host
            .querySelector('[data-bookmarks-total]')
            ?.getAttribute('data-bookmarks-total') ??
        '';
    selectAcross.querySelector('span.total')!.textContent = total.isEmpty
        ? '0'
        : total;
  }

  void _onToggleAll() {
    final allChecked = _allCheckbox!.checked;
    for (final checkbox in _bookmarkCheckboxes) {
      checkbox.checked = allChecked;
    }
    _updateSelectAcross(allChecked);
    _updateExecuteButton();
  }

  void _onToggleBookmark() {
    final allChecked = _bookmarkCheckboxes.every((c) => c.checked);
    _allCheckbox!.checked = allChecked;
    _updateSelectAcross(allChecked);
    _updateExecuteButton();
  }

  void _updateSelectAcross(bool allChecked) {
    final selectAcross = _selectAcross!;
    if (allChecked) {
      selectAcross.classList.remove('d-none');
    } else {
      selectAcross.classList.add('d-none');
      (selectAcross.querySelector('input')! as web.HTMLInputElement).checked =
          false;
    }
  }

  void _updateExecuteButton() {
    _executeButton!.disabled = !_bookmarkCheckboxes.any((c) => c.checked);
  }
}
