import 'dart:async';
import 'dart:js_interop';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:web/web.dart' as web;

import '../element.dart';
import '../input.dart';
import '../position.dart';
import '../tag_cache.dart';
import 'autocomplete/menu_keys.dart';
import 'autocomplete/menu_links.dart';
import 'autocomplete/tag_markup.dart';

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
    host.innerHTML = tagAutocompleteTemplate.toJS;
    _container = host.querySelector('.form-autocomplete') as web.HTMLElement;
    _inputBox =
        host.querySelector('.form-autocomplete-input') as web.HTMLElement;
    _menu = host.querySelector('.menu') as web.HTMLElement;
    final input = host.querySelector('input')! as web.HTMLInputElement;
    _input = input;
    bindAutocompleteInput(
      input,
      onInput: _onInput,
      onKeyDown: _onKeyDown,
      onFocus: () {
        _isFocus = true;
        _update();
      },
      onBlur: () {
        _isFocus = false;
        _close();
      },
    );
    _update();
  }

  @override
  void firstUpdated() {
    _position = PositionController.menu(_input!, _menu!);
  }

  @override
  void disconnected() {
    super.disconnected();
    _close();
  }

  void _update() {
    final input = _input;
    if (input == null) return;
    _container!.className =
        'form-autocomplete ${attribute('variant') == 'small' ? 'small' : ''}';
    _inputBox!.className =
        'form-autocomplete-input form-input ${_isFocus ? 'is-focused' : ''}';
    syncTagInput(input, attribute);
    final value = attribute('input-value');
    if (value != _committedValue) {
      _committedValue = value;
      input.value = value;
    }

    final menu = _menu!
      ..className = 'menu ${_isOpen && _suggestions.isNotEmpty ? 'open' : ''}';
    // The template's own text and comment around the items.
    menu.innerHTML = tagMenuMarkup(_suggestions, _selectedIndex).toJS;
    bindMenuLinks(menu, _suggestions, _complete);
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
    switch (menuKey(event)) {
      case MenuKey.accept when _isOpen:
        _complete(_suggestions[_selectedIndex]);
      case MenuKey.close:
        _close();
      case MenuKey.previous:
        _updateSelection(-1);
      case MenuKey.next:
        _updateSelection(1);
      case _:
        return;
    }
    event.preventDefault();
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
    replaceCurrentWord(_input!, '${suggestion.name} ');
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
    scrollSelectedIntoView(_menu);
  }
}
