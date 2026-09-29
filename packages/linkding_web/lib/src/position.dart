import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The parts of Floating UI (bundled as the `FloatingUIDOM` global) that
/// linkding uses.
@JS('FloatingUIDOM')
external JSObject get _floatingUi;

JSObject _middleware(String name, [JSAny? options]) =>
    _floatingUi.callMethod<JSObject>(name.toJS, options);

/// Places an overlay (a menu) at an anchor and keeps it there while either
/// moves: linkding's `PositionController`.
final class PositionController {
  PositionController({
    required this.anchor,
    required this.overlay,
    this.arrow,
    this.placement = 'bottom',
    this.offset,
    this.autoWidth = false,
  });

  /// The dropdown of an autocomplete: as wide as its field, below it.
  PositionController.menu(this.anchor, this.overlay)
    : arrow = null,
      placement = 'bottom-start',
      offset = null,
      autoWidth = true;

  final web.HTMLElement anchor;
  final web.HTMLElement overlay;
  final web.HTMLElement? arrow;
  final String placement;
  final num? offset;
  final bool autoWidth;
  JSFunction? _cleanup;

  void enable() {
    _cleanup ??= _floatingUi.callMethod<JSFunction>(
      'autoUpdate'.toJS,
      anchor,
      overlay,
      updatePosition.toJS,
    );
  }

  void disable() {
    _cleanup?.callAsFunction();
    _cleanup = null;
  }

  void updatePosition() {
    final middleware = <JSObject>[_middleware('flip'), _middleware('shift')];
    if (arrow case final arrow?) {
      middleware.add(_middleware('arrow', JSObject()..['element'] = arrow));
    }
    if (offset case final offset? when offset != 0) {
      middleware.add(_middleware('offset', offset.toJS));
    }
    final options = JSObject()
      ..['placement'] = placement.toJS
      ..['strategy'] = 'fixed'.toJS
      ..['middleware'] = middleware.toJS;
    _floatingUi
        .callMethod<JSPromise<JSObject>>(
          'computePosition'.toJS,
          anchor,
          overlay,
          options,
        )
        .toDart
        .then((result) {
          final x = (result['x'] as JSNumber).toDartDouble;
          final y = (result['y'] as JSNumber).toDartDouble;
          overlay.style
            ..left = '${_px(x)}px'
            ..top = '${_px(y)}px';
          overlay.classList
            ..remove('top-aligned')
            ..remove('bottom-aligned')
            ..add('${(result['placement'] as JSString).toDart}-aligned');

          if (arrow case final arrow?) {
            final data =
                (result['middlewareData'] as JSObject)['arrow'] as JSObject;
            final ax = data['x'] as JSNumber?;
            final ay = data['y'] as JSNumber?;
            arrow.style
              ..left = ax == null ? '' : '${_px(ax.toDartDouble)}px'
              ..top = ay == null ? '' : '${_px(ay.toDartDouble)}px';
          }
        });

    if (autoWidth) overlay.style.width = '${anchor.offsetWidth}px';
  }
}

/// A number as JavaScript writes it in a template string: no `.0` for a
/// whole number.
String _px(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';
