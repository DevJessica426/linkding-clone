import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// An event listener that can be removed again, as the components'
/// `addEventListener` / `removeEventListener` pairs do.
final class Listener {
  Listener(
    this.target,
    this.type,
    void Function(web.Event event) handler, {
    bool capture = false,
    bool once = false,
  }) : _capture = capture {
    _function = handler.toJS;
    target.addEventListener(
      type,
      _function,
      web.AddEventListenerOptions(capture: capture, once: once),
    );
  }

  final web.EventTarget target;
  final String type;
  final bool _capture;
  late final JSFunction _function;

  void cancel() => target.removeEventListener(
    type,
    _function,
    web.EventListenerOptions(capture: _capture),
  );
}

/// `element.focus({focusVisible, preventScroll})`; `focusVisible` is not in
/// the typed bindings yet.
void focusElement(
  web.HTMLElement element, {
  bool? focusVisible,
  bool? preventScroll,
}) {
  final options = JSObject();
  if (focusVisible != null) options['focusVisible'] = focusVisible.toJS;
  if (preventScroll != null) options['preventScroll'] = preventScroll.toJS;
  element.callMethod('focus'.toJS, options);
}

/// The elements matching [selectors] under [root] (an element or the
/// document), as a list.
List<web.HTMLElement> queryAll(JSObject root, String selectors) {
  final nodes = root.callMethod<web.NodeList>(
    'querySelectorAll'.toJS,
    selectors.toJS,
  );
  return [
    for (var i = 0; i < nodes.length; i++) nodes.item(i)! as web.HTMLElement,
  ];
}

/// Whether an event came from a form field, where the page's own keyboard
/// shortcuts stay out of the way.
bool isInputTarget(web.Event event) {
  final name = (event.target as web.Node?)?.nodeName;
  return name == 'INPUT' || name == 'SELECT' || name == 'TEXTAREA';
}

/// `Turbo.visit(url, {action, frame})`.
@JS('Turbo.visit')
external void _turboVisit(String url, JSObject options);

void turboVisit(String url, {String action = 'advance', String? frame}) {
  final options = JSObject()..['action'] = action.toJS;
  if (frame != null) options['frame'] = frame.toJS;
  _turboVisit(url, options);
}

/// `String.prototype.localeCompare` with the browser's default collation,
/// as linkding sorts tag names.
@JS('Intl.Collator')
extension type _Collator._(JSObject _) implements JSObject {
  external factory _Collator();

  external int compare(String a, String b);
}

final _collator = _Collator();

int localeCompare(String a, String b) => _collator.compare(a, b);

/// [text] for an HTML template, escaped so that it reads as itself, as
/// Lit's text bindings do.
String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
