import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'dom.dart';

/// The Dart side of one custom element: created for an element the first
/// time the browser connects it (or when code asks for it earlier), and
/// told about each connection, disconnection and observed attribute
/// change.
abstract class ElementBehavior {
  ElementBehavior(this.host);

  final web.HTMLElement host;

  void connected() {}

  void disconnected() {}

  void attributeChanged(String name, String? oldValue, String? newValue) {}
}

typedef BehaviorFactory = ElementBehavior Function(web.HTMLElement host);

final _factories = <String, BehaviorFactory>{};

@JS('ldDefineElement')
external void _defineElement(
  String name,
  JSFunction connected,
  JSFunction disconnected,
  JSArray<JSString> observedAttributes,
  JSFunction attributeChanged,
);

/// `customElements.define(name, ...)` with the element's behaviour in Dart.
void defineElement(
  String name,
  BehaviorFactory create, {
  List<String> observedAttributes = const [],
}) {
  _factories[name] = create;
  _defineElement(
    name,
    ((web.HTMLElement host) => behaviorOf(host).connected()).toJS,
    ((web.HTMLElement host) => behaviorOf(host).disconnected()).toJS,
    [for (final a in observedAttributes) a.toJS].toJS,
    ((
      web.HTMLElement host,
      String name,
      String? oldValue,
      String? newValue,
    ) => behaviorOf(host).attributeChanged(name, oldValue, newValue)).toJS,
  );
}

const _behaviorKey = '__ldBehavior';

/// The behaviour of [host], created on first use.
T behaviorOf<T extends ElementBehavior>(web.HTMLElement host) {
  final existing = host[_behaviorKey];
  if (existing != null) {
    return (existing as JSBoxedDartObject).toDart as T;
  }
  final behavior = _factories[host.localName]!(host);
  host[_behaviorKey] = behavior.toJSBox;
  return behavior as T;
}

/// The behaviour of [element] if it is one of these custom elements.
ElementBehavior? existingBehaviorOf(web.Element element) {
  final existing = element[_behaviorKey];
  return existing == null
      ? null
      : (existing as JSBoxedDartObject).toDart as ElementBehavior;
}

/// linkding's `HeadlessElement`: wraps server-rendered DOM, set up once
/// its children exist. On a fresh page load `connectedCallback` fires
/// before the children are parsed, so setup waits for `turbo:load`.
abstract class HeadlessElement extends ElementBehavior {
  HeadlessElement(super.host);

  var _initialized = false;

  @override
  void connected() {
    if (_initialized) return;
    _initialized = true;
    if (web.document.readyState == 'loading') {
      Listener(web.document, 'turbo:load', (_) => init(), once: true);
    } else {
      init();
    }
  }

  void init();
}

var _isTopFrameVisit = false;

/// linkding's `TurboLitElement`: renders its own content into the light
/// DOM, which is emptied before Turbo caches the page (restoring the
/// cached copy renders it again), and which Turbo's morphing leaves alone.
abstract class RenderedElement extends ElementBehavior {
  RenderedElement(super.host);

  var _firstRendered = false;
  Listener? _beforeCache;

  @override
  void connected() {
    _beforeCache = Listener(web.document, 'turbo:before-cache', (_) {
      // A frame visit that targets the top frame keeps the contents.
      if (!_isTopFrameVisit) host.innerHTML = ''.toJS;
    });
    if (!_firstRendered) {
      _firstRendered = true;
      // Lit renders on the next microtask, with the attributes as they are
      // then.
      scheduleMicrotask(() {
        render();
        firstUpdated();
      });
    }
  }

  @override
  void disconnected() {
    _beforeCache?.cancel();
    _beforeCache = null;
  }

  /// Builds the element's content.
  void render();

  void firstUpdated() {}

  /// An attribute as a string property: empty when missing.
  String attribute(String name) => host.getAttribute(name) ?? '';
}

/// The listeners `element.js` registers once for the whole page.
void initElementSupport() {
  Listener(web.document, 'turbo:visit', (event) {
    final url = ((event as web.CustomEvent).detail as JSObject)['url']
        .dartify();
    _isTopFrameVisit =
        web.document.querySelector('turbo-frame[src="$url"][target="_top"]') !=
        null;
  });
  Listener(web.document, 'turbo:render', (_) => _isTopFrameVisit = false);
  Listener(web.document, 'turbo:before-morph-element', (event) {
    // Morphing would remove what these elements rendered themselves.
    final parent = (event.target as web.Element?)?.parentElement;
    if (parent != null && existingBehaviorOf(parent) is RenderedElement) {
      event.preventDefault();
    }
  });
}
