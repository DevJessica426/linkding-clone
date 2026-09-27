import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';
import '../focus.dart';

/// `<ld-modal>`: closes on its close buttons and Escape with a fade-out,
/// locks page scrolling while open, traps focus, and visits its close URL
/// once gone.
class Modal extends HeadlessElement {
  Modal(super.host);

  FocusTrapController? _focusTrap;

  @override
  void init() {
    for (final button in queryAll(host, '[data-close-modal]')) {
      Listener(button, 'click', onClose);
    }
    Listener(host, 'keydown', _onKeyDown);
    web.document.body!.classList.add('scroll-lock');
    _focusTrap = FocusTrapController(
      host.querySelector('.modal-container')! as web.HTMLElement,
    );
  }

  @override
  void disconnected() {
    web.document.body!.classList.remove('scroll-lock');
    _focusTrap?.destroy();
  }

  void _onKeyDown(web.Event event) {
    if (isInputTarget(event)) return;
    if ((event as web.KeyboardEvent).key == 'Escape') onClose(event);
  }

  void onClose(web.Event event) {
    event.preventDefault();
    host.classList.add('closing');
    // Only the first animation to end counts, as in linkding.
    Listener(host, 'animationend', (event) {
      if ((event as web.AnimationEvent).animationName == 'fade-out') {
        doClose();
      }
    }, once: true);
  }

  void doClose() {
    host.remove();
    host.dispatchEvent(web.CustomEvent('modal:close'));

    final closeUrl = host.getAttribute('data-close-url') ?? '';
    if (closeUrl.isNotEmpty) {
      final action = host.getAttribute('data-turbo-action') ?? '';
      final frame = host.getAttribute('data-turbo-frame') ?? '';
      turboVisit(
        closeUrl,
        action: action.isEmpty ? 'replace' : action,
        frame: frame.isEmpty ? null : frame,
      );
    }
  }
}

/// `<ld-details-modal>`: after closing, focus returns to the bookmark's
/// "View" link.
final class DetailsModal extends Modal {
  DetailsModal(super.host);

  @override
  void doClose() {
    super.doClose();
    final bookmarkId = host.getAttribute('data-bookmark-id');
    setAfterPageLoadFocusTarget([
      "ul.bookmark-list li[data-bookmark-id='$bookmarkId'] a.view-action",
    ]);
  }
}
