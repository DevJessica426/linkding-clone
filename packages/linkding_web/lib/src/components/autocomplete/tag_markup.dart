import 'package:linkding_shared/linkding_shared.dart';
import 'package:web/web.dart' as web;

import '../../dom.dart';

/// The skeleton `<ld-tag-autocomplete>` renders into its host.
const tagAutocompleteTemplate = '''
      <div class="form-autocomplete ">
        <!-- autocomplete input container -->
        <div
          class="form-autocomplete-input form-input "
        >
          <!-- autocomplete real input box -->
          <input
            type="text"
            autocomplete="off"
            autocapitalize="off"
          />
        </div>

        <!-- autocomplete suggestion list -->
        <ul
          class="menu "
        >
          <!-- menu list items -->
        </ul>
      </div>
    ''';

/// The menu's content: the template's own comment around one item per
/// suggestion, [selected] marked.
String tagMenuMarkup(List<Tag> suggestions, int selected) {
  final items = [
    for (final (i, tag) in suggestions.indexed)
      '''
              <li
                class="menu-item ${selected == i ? 'selected' : ''}"
              >
                <a
                  href="#"
                >
                  ${escapeHtml(tag.name)}
                </a>
              </li>
            ''',
  ];
  return '\n          <!-- menu list items -->\n          ${items.join()}\n        ';
}

/// Sets [name] to [value], or removes it for an empty value (Lit's
/// `nothing`).
void setOrRemove(web.Element element, String name, String value) {
  if (value.isEmpty) {
    element.removeAttribute(name);
  } else {
    element.setAttribute(name, value);
  }
}

/// The attributes of the field itself that follow the host's own.
void syncTagInput(
  web.HTMLInputElement input,
  String Function(String name) attribute,
) {
  setOrRemove(input, 'id', attribute('input-id'));
  setOrRemove(input, 'name', attribute('input-name'));
  final placeholder = attribute('input-placeholder');
  input
    ..setAttribute('placeholder', placeholder.isEmpty ? ' ' : placeholder)
    ..setAttribute('class', 'form-input ${attribute('input-class')}');
  setOrRemove(input, 'aria-describedby', attribute('input-aria-describedby'));
}
