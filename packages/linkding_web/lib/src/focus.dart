import 'package:web/web.dart' as web;

import 'dom.dart';

var _keyboardActive = false;

/// Whether the visitor is using the keyboard rather than the mouse, which
/// decides whether programmatic focus shows its outline.
bool get isKeyboardActive => _keyboardActive;

/// Keeps Tab and Shift+Tab inside [element], starting at its first
/// focusable element: linkding's `FocusTrapController`.
final class FocusTrapController {
  FocusTrapController(this.element) {
    final focusable = queryAll(
      element,
      'a[href]:not([disabled]), button:not([disabled]), '
      'textarea:not([disabled]), input[type="text"]:not([disabled]), '
      'input[type="radio"]:not([disabled]), '
      'input[type="checkbox"]:not([disabled]), select:not([disabled])',
    );
    _first = focusable.firstOrNull;
    _last = focusable.lastOrNull;
    // linkding assumes there is at least one; so does the trap.
    if (_first case final first?) {
      focusElement(first, focusVisible: _keyboardActive);
    }
    _keyDown = Listener(element, 'keydown', _onKeyDown);
  }

  final web.HTMLElement element;
  web.HTMLElement? _first;
  web.HTMLElement? _last;
  late final Listener _keyDown;

  void destroy() => _keyDown.cancel();

  void _onKeyDown(web.Event event) {
    final key = event as web.KeyboardEvent;
    if (key.key != 'Tab') return;
    final active = web.document.activeElement;
    if (key.shiftKey) {
      if (active == _first) {
        event.preventDefault();
        _last?.focus();
      }
    } else if (active == _last) {
      event.preventDefault();
      _first?.focus();
    }
  }
}

var _afterPageLoadFocusTarget = <String>[];
var _firstPageLoad = true;

/// Where focus goes after the next Turbo page load, first match wins.
void setAfterPageLoadFocusTarget(List<String> targets) {
  _afterPageLoadFocusTarget = targets;
}

void _programmaticFocus(web.HTMLElement element) {
  // An element that is not focusable by default gets tabIndex -1, and no
  // outline, since `focusVisible` is not supported everywhere.
  final isFocusable = element.tabIndex >= 0;
  if (!isFocusable) {
    element.tabIndex = -1;
    element.style.setProperty('outline', 'none');
  }
  focusElement(
    element,
    focusVisible: isKeyboardActive && isFocusable,
    preventScroll: true,
  );
}

/// The listeners of linkding's `focus.js`: keyboard tracking, and after
/// each Turbo navigation focus on something a screen reader announces
/// meaningfully.
void initFocus() {
  Listener(web.window, 'keydown', (_) => _keyboardActive = true, capture: true);
  Listener(
    web.window,
    'mousedown',
    (_) => _keyboardActive = false,
    capture: true,
  );

  Listener(web.document, 'turbo:load', (_) {
    // The browser announces the first page itself.
    if (_firstPageLoad) {
      _firstPageLoad = false;
      return;
    }
    // A modal dialog handles its own focus.
    if (web.document.querySelector("[aria-modal='true']") != null) return;

    for (final target in _afterPageLoadFocusTarget) {
      final element = web.document.querySelector(target);
      if (element != null) {
        _programmaticFocus(element as web.HTMLElement);
        return;
      }
    }
    _afterPageLoadFocusTarget = [];

    // The browser handles autofocus.
    if (web.document.querySelector('[autofocus]') != null) return;

    // A toast from some action, or else the main content.
    final toast = web.document.querySelector('.toast');
    if (toast != null) {
      _programmaticFocus(toast as web.HTMLElement);
      return;
    }
    final main = web.document.querySelector('main');
    if (main != null) _programmaticFocus(main as web.HTMLElement);
  });
}
