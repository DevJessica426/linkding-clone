import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';

/// `form.requestSubmit(submitter)`.
void requestSubmit(web.Element? form, [web.HTMLElement? submitter]) {
  if (form == null) return;
  if (submitter == null) {
    form.callMethod('requestSubmit'.toJS);
  } else {
    form.callMethod('requestSubmit'.toJS, submitter);
  }
}

/// `<ld-form>`: submits on a change of a `data-submit-on-change` field,
/// or on Ctrl/Cmd+Enter with `data-submit-on-ctrl-enter`; with
/// `data-form-reset`, puts its fields back to how the page came before
/// Turbo caches it, so going back shows filters that match the URL.
final class Form extends HeadlessElement {
  Form(super.host);

  final _initialValues = <(web.HTMLInputElement, Object)>[];

  @override
  void init() {
    Listener(host, 'keydown', _onKeyDown);
    Listener(host, 'change', _onChange);
    if (host.hasAttribute('data-form-reset')) {
      for (final control in queryAll(host, 'input, select')) {
        // A select has `value` too, and is never a toggle.
        final input = control as web.HTMLInputElement;
        _initialValues.add((
          input,
          _isToggle(input) ? input.checked : input.value,
        ));
      }
    }
  }

  static bool _isToggle(web.HTMLInputElement control) =>
      control.type == 'checkbox' || control.type == 'radio';

  @override
  void disconnected() {
    if (!host.hasAttribute('data-form-reset')) return;
    for (final (control, initial) in _initialValues) {
      if (_isToggle(control)) {
        control.checked = initial as bool;
      } else {
        control.value = initial as String;
      }
    }
    _initialValues.clear();
  }

  void _onChange(web.Event event) {
    final target = event.target as web.Element;
    if (target.hasAttribute('data-submit-on-change')) {
      requestSubmit(host.querySelector('form'));
    }
  }

  void _onKeyDown(web.Event event) {
    final key = event as web.KeyboardEvent;
    if (host.hasAttribute('data-submit-on-ctrl-enter') &&
        key.key == 'Enter' &&
        (key.metaKey || key.ctrlKey)) {
      event
        ..preventDefault()
        ..stopPropagation();
      requestSubmit(host.querySelector('form'));
    }
  }
}

/// `<ld-clear-button data-for="id">`: shown while the field has a value;
/// empties it.
final class ClearButton extends HeadlessElement {
  ClearButton(super.host);

  web.HTMLInputElement? _field;

  @override
  void init() {
    final id = host.getAttribute('data-for');
    final field = web.document.getElementById(id ?? '');
    if (field == null) {
      web.console.error('Field with ID $id not found'.toJS);
      return;
    }
    _field = field as web.HTMLInputElement;
    Listener(host, 'click', (_) => _clear());
    Listener(field, 'input', (_) => _update());
    Listener(field, 'value-changed', (_) => _update());
    _update();
  }

  void _update() =>
      host.style.display = _field!.value.isNotEmpty ? 'inline' : 'none';

  void _clear() {
    _field!
      ..value = ''
      ..focus();
    _update();
  }
}

/// `<ld-upload-button>`: its submit button picks a file, and picking one
/// submits the form.
final class UploadButton extends HeadlessElement {
  UploadButton(super.host);

  @override
  void init() {
    final button =
        host.querySelector('button[type="submit"]')! as web.HTMLElement;
    final fileInput =
        host.querySelector('input[type="file"]')! as web.HTMLInputElement;
    Listener(button, 'click', (event) {
      event.preventDefault();
      fileInput.click();
    });
    Listener(fileInput, 'change', (_) {
      if ((fileInput.files?.length ?? 0) == 0) return;
      requestSubmit(host.closest('form'), button);
      // So the file is not submitted again.
      fileInput.value = '';
    });
  }
}
