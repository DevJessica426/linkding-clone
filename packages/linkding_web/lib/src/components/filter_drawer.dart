import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';
import '../focus.dart';
import 'modal.dart';

/// `<ld-filter-drawer-trigger>`: opens the filter drawer.
final class FilterDrawerTrigger extends HeadlessElement {
  FilterDrawerTrigger(super.host);

  @override
  void init() {
    Listener(host, 'click', (_) {
      final drawer = web.document.createElement('ld-filter-drawer');
      web.document.body!.querySelector('.modals')!.appendChild(drawer);
    });
  }
}

/// `<ld-filter-drawer>`: a drawer that borrows the side panel's contents
/// while it is open, with its headings one level down.
final class FilterDrawer extends Modal {
  FilterDrawer(super.host);

  Listener? _beforeCache;

  @override
  void connected() {
    host.classList
      ..add('modal')
      ..add('drawer');
    host.innerHTML = _template.toJS;
    _teleport();
    // Closed before Turbo caches the page, so the side panel gets its
    // contents back.
    _beforeCache = Listener(
      web.document,
      'turbo:before-cache',
      (_) => doClose(),
    );
    // A reflow first, so the slide-in transition runs.
    host.getBoundingClientRect();
    web.window.requestAnimationFrame(
      ((num _) => host.classList.add('active')).toJS,
    );
    init();
  }

  @override
  void disconnected() {
    super.disconnected();
    _teleportBack();
    _beforeCache?.cancel();
  }

  static void _mapHeading(web.Element container, String from, String to) {
    for (final heading in queryAll(container, from)) {
      final replacement = web.document.createElement(to)
        ..textContent = heading.textContent;
      heading.replaceWith(replacement);
    }
  }

  static void _moveChildren(web.Element from, web.Element to) {
    for (
      var child = from.firstElementChild;
      child != null;
      child = from.firstElementChild
    ) {
      to.append(child);
    }
  }

  void _teleport() {
    final content = host.querySelector('.modal-body')!;
    _moveChildren(web.document.querySelector('.side-panel')!, content);
    _mapHeading(content, 'h2', 'h3');
  }

  void _teleportBack() {
    final sidePanel = web.document.querySelector('.side-panel')!;
    _moveChildren(host.querySelector('.modal-body')!, sidePanel);
    _mapHeading(sidePanel, 'h3', 'h2');
  }

  @override
  void doClose() {
    super.doClose();
    final restoreFocus =
        web.document.querySelector('ld-filter-drawer-trigger') ??
        web.document.body!;
    focusElement(
      restoreFocus as web.HTMLElement,
      focusVisible: isKeyboardActive,
    );
  }
}

const _template = '''
        <div class="modal-overlay" data-close-modal></div>
        <div class="modal-container" role="dialog" aria-modal="true">
          <div class="modal-header">
            <h2>Filters</h2>
            <button
              class="btn btn-noborder close"
              aria-label="Close dialog"
              data-close-modal
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="24"
                height="24"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                fill="none"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path stroke="none" d="M0 0h24v24H0z" fill="none"></path>
                <path d="M18 6l-12 12"></path>
                <path d="M6 6l12 12"></path>
              </svg>
            </button>
          </div>
          <div class="modal-body"></div>
        </div>
      ''';
