import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'dom.dart';

/// linkding's keyboard shortcuts, outside form fields: arrow keys move
/// between bookmarks, `e` shows every note, `s` goes to the search box and
/// `n` to a new bookmark.
void initShortcuts() {
  Listener(web.document, 'keydown', (event) {
    if (isInputTarget(event)) return;
    final key = (event as web.KeyboardEvent).key;

    if (key == 'ArrowUp' || key == 'ArrowDown') {
      event.preventDefault();
      final items = queryAll(web.document, 'ul.bookmark-list > li');
      final path = event.composedPath().toDart;
      final current = items.where(path.contains).firstOrNull;
      final web.Element? next;
      if (current != null) {
        next = key == 'ArrowUp'
            ? current.previousElementSibling
            : current.nextElementSibling;
      } else {
        next = items.firstOrNull;
      }
      (next?.querySelector('a') as web.HTMLElement?)?.focus();
    }

    if (key == 'e') {
      web.document
          .querySelector('.bookmark-list')
          ?.classList
          .toggle('show-notes');
    }

    if (key == 's') {
      final search = web.document.querySelector(
        'input[type="search"]',
      ) as web.HTMLElement?;
      if (search != null) {
        search.focus();
        event.preventDefault();
      }
    }

    if (key == 'n') web.window.location.assign('/bookmarks/new');
  });
}
