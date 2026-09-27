// Custom elements whose behaviour is written in Dart. An element class has
// to be a JavaScript class extending HTMLElement, so this is the one piece
// of hand-written JavaScript: each class hands its lifecycle callbacks to
// the Dart functions registered for its name (see lib/src/element.dart).
(function () {
  window.ldDefineElement = function (
    name,
    connected,
    disconnected,
    observedAttributes,
    attributeChanged,
  ) {
    customElements.define(
      name,
      class extends HTMLElement {
        static get observedAttributes() {
          return observedAttributes;
        }

        connectedCallback() {
          connected(this);
        }

        disconnectedCallback() {
          disconnected(this);
        }

        attributeChangedCallback(attribute, oldValue, newValue) {
          attributeChanged(this, attribute, oldValue, newValue);
        }
      },
    );
  };
})();
