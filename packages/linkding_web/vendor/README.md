The libraries linkding 1.47.0 bundles into its `bundle.js`, as published:

| File | Package | License |
| --- | --- | --- |
| `turbo.es2017-umd.js` | `@hotwired/turbo` 8.0.21 | MIT, `LICENSE-turbo.txt` |
| `floating-ui.core.umd.min.js` | `@floating-ui/core` 1.7.3 | MIT, `LICENSE-floating-ui.txt` |
| `floating-ui.dom.umd.min.js` | `@floating-ui/dom` 1.7.4 | MIT, `LICENSE-floating-ui.txt` |

`tool/build_web.sh` puts them in front of the compiled Dart code. linkding's
third dependency, Lit, is not needed: the Dart components build their own
DOM.
