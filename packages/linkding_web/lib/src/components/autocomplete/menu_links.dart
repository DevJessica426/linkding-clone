import 'dart:async';

import 'package:web/web.dart' as web;

import '../../dom.dart';

/// Picking an item of an autocomplete menu with the mouse. It listens to
/// `mousedown`, not `click`, and prevents its default, so the input keeps
/// its focus and the menu is not closed by the blur first.
void bindMenuLinks<T>(
  web.HTMLElement menu,
  List<T> items,
  void Function(T item) onPick,
) {
  final links = queryAll(menu, 'a');
  for (var i = 0; i < links.length; i++) {
    final item = items[i];
    Listener(links[i], 'mousedown', (event) {
      event.preventDefault();
      onPick(item);
    });
  }
}

/// Keeps the selected item in view, once the menu has been drawn again.
void scrollSelectedIntoView(web.HTMLElement? menu) {
  Timer(Duration.zero, () {
    final selected = menu?.querySelector('li.selected');
    selected?.scrollIntoView(web.ScrollIntoViewOptions(block: 'center'));
  });
}

/// The events of an autocomplete's field: what is typed, the keys, and
/// focus, which opens nothing but is what closes the menu on blur.
void bindAutocompleteInput(
  web.HTMLInputElement input, {
  required void Function(web.Event event) onInput,
  required void Function(web.Event event) onKeyDown,
  required void Function() onFocus,
  required void Function() onBlur,
}) {
  Listener(input, 'input', onInput);
  Listener(input, 'keydown', onKeyDown);
  Listener(input, 'focus', (_) => onFocus());
  Listener(input, 'blur', (_) => onBlur());
}
