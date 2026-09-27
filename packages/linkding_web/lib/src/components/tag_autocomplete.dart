import 'dart:async';
import 'dart:js_interop';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:web/web.dart' as web;

import '../dom.dart';
import '../element.dart';
import '../input.dart';
import '../position.dart';
import '../tag_cache.dart';

/// `<ld-tag-autocomplete>`: the tags field of the bookmark, bundle and
/// bulk-edit forms, completing the word at the caret from the user's tags.
final class TagAutocomplete extends RenderedElement {
  TagAutocomplete(super.host);

  static const observed = [
    'input-id',
    'input-name',
    'input-value',
    'input-class',
    'input-placeholder',
    'input-aria-describedby',
    'variant',
  ];

  var _isFocus = false;
  var _isOpen = false;
  var _suggestions = <Tag>[];
  var _selectedIndex = 0;

  web.HTMLInputElement? _input;
  web.HTMLElement? _container;
  web.HTMLElement? _inputBox;
  web.HTMLElement? _menu;
  String? _committedValue;
  PositionController? _position;

  @override
  void attributeChanged(String name, String? oldValue, String? newValue) {
    if (_input != null) _update();
  }

  @override
  void render() {
    host.innerHTML =
        '''
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
    '''
            .toJS;
    _container = host.querySelector('.form-autocomplete') as web.HTMLElement;
    _inputBox =
        host.querySelector('.form-autocomplete-input') as web.HTMLElement;
    _menu = host.querySelector('.menu') as web.HTMLElement;
    final input = host.querySelector('input')! as web.HTMLInputElement;
    _input = input;
    Listener(input, 'input', (event) => _onInput(event));
    Listener(input, 'keydown', _onKeyDown);
    Listener(input, 'focus', (_) {
      _isFocus = true;
      _update();
    });
    Listener(input, 'blur', (_) {
      _isFocus = false;
      _close();
    });
    _update();
  }

  @override
  void firstUpdated() {
    _position = PositionController(
      anchor: _input!,
      overlay: _menu!,
      autoWidth: true,
      placement: 'bottom-start',
    );
  }

  @override
  void disconnected() {
    super.disconnected();
    _close();
  }

  /// Sets [name] to [value], or removes it for an empty value (Lit's
  /// `nothing`).
  static void _setOrRemove(web.Element element, String name, String value) {
    if (value.isEmpty) {
      element.removeAttribute(name);
    } else {
      element.setAttribute(name, value);
    }
  }

  void _update() {
    final input = _input;
    if (input == null) return;
    _container!.className =
        'form-autocomplete ${attribute('variant') == 'small' ? 'small' : ''}';
    _inputBox!.className =
        'form-autocomplete-input form-input ${_isFocus ? 'is-focused' : ''}';
    _setOrRemove(input, 'id', attribute('input-id'));
    _setOrRemove(input, 'name', attribute('input-name'));
    final placeholder = attribute('input-placeholder');
    input
      ..setAttribute('placeholder', placeholder.isEmpty ? ' ' : placeholder)
      ..setAttribute('class', 'form-input ${attribute('input-class')}');
    _setOrRemove(
      input,
      'aria-describedby',
      attribute('input-aria-describedby'),
    );
    final value = attribute('input-value');
    if (value != _committedValue) {
      _committedValue = value;
      input.value = value;
    }

    final menu = _menu!
      ..className = 'menu ${_isOpen && _suggestions.isNotEmpty ? 'open' : ''}';
    final items = [
      for (final (i, tag) in _suggestions.indexed)
        '''
              <li
                class="menu-item ${_selectedIndex == i ? 'selected' : ''}"
              >
                <a
                  href="#"
                >
                  ${escapeHtml(tag.name)}
                </a>
              </li>
            ''',
    ];
    // The template's own text and comment around the items.
    menu.innerHTML =
        '\n          <!-- menu list items -->\n          ${items.join()}\n        '
            .toJS;
    final links = queryAll(menu, 'a');
    for (var i = 0; i < links.length; i++) {
      final tag = _suggestions[i];
      Listener(links[i], 'mousedown', (event) {
        event.preventDefault();
        _complete(tag);
      });
    }
  }

  Future<void> _onInput(web.Event event) async {
    final input = event.target as web.HTMLInputElement;
    _input = input;
    final tags = await tagCache.getTags();
    final word = currentWord(input).toLowerCase();
    _suggestions = word.isEmpty
        ? []
        : [
            for (final tag in tags)
              if (tag.name.toLowerCase().startsWith(word)) tag,
          ];
    if (word.isNotEmpty && _suggestions.isNotEmpty) {
      _open();
    } else {
      _close();
    }
  }

  void _onKeyDown(web.Event event) {
    final key = (event as web.KeyboardEvent).keyCode;
    if (_isOpen && (key == 13 || key == 9)) {
      _complete(_suggestions[_selectedIndex]);
      event.preventDefault();
    }
    if (key == 27) {
      _close();
      event.preventDefault();
    }
    if (key == 38) {
      _updateSelection(-1);
      event.preventDefault();
    }
    if (key == 40) {
      _updateSelection(1);
      event.preventDefault();
    }
  }

  void _open() {
    _isOpen = true;
    _selectedIndex = 0;
    _position?.enable();
    _update();
  }

  void _close() {
    _isOpen = false;
    _suggestions = [];
    _selectedIndex = 0;
    _position?.disable();
    _update();
  }

  void _complete(Tag suggestion) {
    final input = _input!;
    final bounds = currentWordBounds(input);
    final value = input.value;
    input.value =
        '${value.substring(0, bounds.start)}${suggestion.name} '
        '${value.substring(bounds.end)}';
    // For the forms that watch the field, such as the bundle preview.
    host.dispatchEvent(
      web.CustomEvent('input', web.CustomEventInit(bubbles: true)),
    );
    _close();
  }

  void _updateSelection(int direction) {
    final length = _suggestions.length;
    var next = _selectedIndex + direction;
    if (next < 0) next = length > 0 ? length - 1 : 0;
    if (next >= length) next = 0;
    _selectedIndex = next;
    _update();

    // Keep the selected item in view.
    Timer(Duration.zero, () {
      final selected = _menu?.querySelector('li.selected');
      selected?.scrollIntoView(web.ScrollIntoViewOptions(block: 'center'));
    });
  }
}
