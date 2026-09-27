import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';
import '../focus.dart';
import '../position.dart';

/// `<ld-dropdown>`: opens on click only (not on focus, as the CSS alone
/// would), and closes on Escape, an outside click, or focus leaving it.
final class Dropdown extends HeadlessElement {
  Dropdown(super.host);

  var _opened = false;
  web.HTMLElement? _toggle;
  Listener? _outsideClick;

  @override
  void init() {
    host.style.setProperty('--dropdown-focus-display', 'none');
    Listener(host, 'keydown', _onEscape);
    Listener(host, 'focusout', _onFocusOut);

    final toggle = host.querySelector('.dropdown-toggle')! as web.HTMLElement;
    _toggle = toggle;
    toggle.setAttribute('aria-expanded', 'false');
    Listener(toggle, 'click', (_) => _opened ? _close() : _open());
  }

  @override
  void disconnected() => _close();

  void _open() {
    _opened = true;
    host.classList.add('active');
    _toggle!.setAttribute('aria-expanded', 'true');
    _outsideClick = Listener(web.document, 'click', (event) {
      if (!host.contains(event.target as web.Node?)) _close();
    });
  }

  void _close() {
    _opened = false;
    host.classList.remove('active');
    _toggle?.setAttribute('aria-expanded', 'false');
    _outsideClick?.cancel();
    _outsideClick = null;
  }

  void _onEscape(web.Event event) {
    if ((event as web.KeyboardEvent).key == 'Escape' && _opened) {
      event.preventDefault();
      _close();
      _toggle!.focus();
    }
  }

  void _onFocusOut(web.Event event) {
    final related = (event as web.FocusEvent).relatedTarget as web.Node?;
    if (!host.contains(related)) _close();
  }
}

var _confirmId = 0;

void _removeAllConfirmDropdowns() {
  for (final dropdown in queryAll(web.document, 'ld-confirm-dropdown')) {
    behaviorOf<ConfirmDropdown>(dropdown).close();
  }
}

/// A button with `data-confirm` asks first: a click opens a confirmation
/// dropdown at the button instead of submitting. Open ones close on
/// Escape and before Turbo caches the page.
void initConfirmations() {
  Listener(web.document, 'click', (event) {
    final button = (event.target as web.Element?)?.closest(
      'button[data-confirm]',
    );
    if (button == null) return;

    _removeAllConfirmDropdowns();
    event.preventDefault();

    final dropdown =
        web.document.createElement('ld-confirm-dropdown') as web.HTMLElement;
    behaviorOf<ConfirmDropdown>(dropdown).button =
        button as web.HTMLButtonElement;
    web.document.body!.appendChild(dropdown);
  });
  Listener(
    web.document,
    'turbo:before-cache',
    (_) => _removeAllConfirmDropdowns(),
  );
  Listener(web.document, 'keydown', (event) {
    if ((event as web.KeyboardEvent).key == 'Escape') {
      _removeAllConfirmDropdowns();
    }
  });
}

/// `<ld-confirm-dropdown>`: the question, Cancel and Confirm, placed
/// under the button; Confirm submits the button's form with the button.
final class ConfirmDropdown extends ElementBehavior {
  ConfirmDropdown(super.host);

  late web.HTMLButtonElement button;
  final _id = 'confirm-${_confirmId++}';
  var _rendered = false;
  PositionController? _position;
  FocusTrapController? _focusTrap;

  @override
  void connected() {
    if (_rendered) return;
    _rendered = true;
    // Lit renders on the next microtask.
    scheduleMicrotask(() {
      _render();
      _firstUpdated();
    });
  }

  void _render() {
    final question = button.getAttribute('data-confirm-question') ?? '';
    host.innerHTML =
        """
      <div
        class="menu with-arrow"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="$_id"
      >
        <span id="$_id" style="font-weight: bold;">
          ${escapeHtml(question.isEmpty ? 'Are you sure?' : question)}
        </span>
        <button type="button" class="btn">Cancel</button>
        <button type="submit" class="btn btn-error">
          Confirm
        </button>
        <div class="menu-arrow"></div>
      </div>
    """
            .toJS;
    final buttons = queryAll(host, 'button');
    Listener(buttons[0], 'click', (_) => close());
    Listener(buttons[1], 'click', (_) => _confirm());
  }

  void _firstUpdated() {
    host.classList
      ..add('dropdown')
      ..add('confirm-dropdown')
      ..add('active');
    final menu = host.querySelector('.menu')! as web.HTMLElement;
    _position = PositionController(
      anchor: button,
      overlay: menu,
      arrow: host.querySelector('.menu-arrow') as web.HTMLElement?,
      offset: 12,
    )..enable();
    _focusTrap = FocusTrapController(menu);
  }

  void _confirm() {
    button.closest('form')?.callMethod('requestSubmit'.toJS, button);
    close();
  }

  void close() {
    _position?.disable();
    _focusTrap?.destroy();
    host.remove();
    focusElement(button, focusVisible: isKeyboardActive);
  }
}
