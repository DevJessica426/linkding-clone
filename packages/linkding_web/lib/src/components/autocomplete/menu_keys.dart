import 'package:web/web.dart' as web;

/// The keys an autocomplete menu answers to.
enum MenuKey { accept, close, previous, next }

/// The menu key [event] stands for: Enter or Tab take the selected
/// suggestion, Escape closes the menu, the arrows move the selection.
MenuKey? menuKey(web.Event event) =>
    switch ((event as web.KeyboardEvent).keyCode) {
      13 || 9 => MenuKey.accept,
      27 => MenuKey.close,
      38 => MenuKey.previous,
      40 => MenuKey.next,
      _ => null,
    };

/// The index after moving [direction] steps from [current] in a menu of
/// [length] entries, wrapping round at either end. With nothing selected
/// yet, going down selects the first and going up the last.
int nextSelection(int? current, int direction, int length) {
  if (current == null) return direction > 0 ? 0 : length - 1;
  var next = current + direction;
  if (next < 0) next = length - 1;
  if (next >= length) next = 0;
  return next;
}
