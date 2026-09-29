import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../element.dart';
import '../input.dart';
import '../position.dart';
import '../tag_cache.dart';
import 'autocomplete/menu_keys.dart';
import 'autocomplete/menu_links.dart';
import 'autocomplete/search_markup.dart';
import 'autocomplete/search_suggestions.dart';
import 'autocomplete/suggestion.dart';

/// `<ld-search-autocomplete>`: the search box of the bookmark lists, with
/// a menu of matching tags (after `#`), recent searches and bookmarks.
final class SearchAutocomplete extends RenderedElement {
  SearchAutocomplete(super.host);

  static const observed = [
    'input-name',
    'input-placeholder',
    'input-value',
    'mode',
    'user',
    'shared',
    'unread',
    'target',
  ];

  String? _inputValue;
  var _isFocus = false;
  var _isOpen = false;
  var _suggestions = SuggestionSet();
  int? _selectedIndex;

  web.HTMLInputElement? _input;
  web.HTMLElement? _inputBox;
  web.HTMLElement? _menu;
  String? _committedValue;
  PositionController? _position;
  final _history = SearchHistory();
  late final _debouncedLoad = debounce(_loadSuggestions);

  String get inputValue => _inputValue ?? attribute('input-value');

  @override
  void attributeChanged(String name, String? oldValue, String? newValue) {
    if (name == 'input-value') _inputValue = newValue ?? '';
    if (_input != null) _update();
  }

  @override
  void render() {
    host.innerHTML = searchAutocompleteTemplate.toJS;
    final input = _input = host.querySelector('input') as web.HTMLInputElement;
    _inputBox =
        host.querySelector('.form-autocomplete-input') as web.HTMLElement;
    _menu = host.querySelector('.menu') as web.HTMLElement;
    bindAutocompleteInput(
      input,
      onInput: (_) {
        _inputValue = input.value;
        _debouncedLoad();
      },
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
    host.style.setProperty('--menu-max-height', '400px');
    // The search of the page being shown becomes a recent search.
    _history.pushCurrent();
    _position = PositionController.menu(_input!, _menu!);
    _update();
  }

  @override
  void disconnected() {
    super.disconnected();
    _close();
  }

  /// Lit's re-render: bindings that changed are written again.
  void _update() {
    final input = _input;
    if (input == null) return;
    _inputBox!.className =
        'form-autocomplete-input form-input ${_isFocus ? 'is-focused' : ''}';
    input
      ..setAttribute('name', attribute('input-name'))
      ..setAttribute('placeholder', attribute('input-placeholder'));
    if (inputValue != _committedValue) {
      _committedValue = inputValue;
      input.value = inputValue;
    }
    final menu = _menu!..className = 'menu ${_isOpen ? 'open' : ''}';
    final markup = searchMenuMarkup(_suggestions, _selectedIndex);
    menu.innerHTML = markup.html.toJS;
    bindMenuLinks(menu, markup.items, _complete);
  }

  void _onKeyDown(web.Event event) {
    switch (menuKey(event)) {
      case MenuKey.accept when _isOpen && _selectedIndex != null:
        final chosen = _suggestions.all.elementAtOrNull(_selectedIndex!);
        if (chosen != null) _complete(chosen);
      case MenuKey.close:
        _close();
      case MenuKey.previous:
        _updateSelection(-1);
      case MenuKey.next:
        if (_isOpen) {
          _updateSelection(1);
        } else {
          _loadSuggestions();
        }
      case _:
        return;
    }
    event.preventDefault();
  }

  void _open() {
    _isOpen = true;
    _position?.enable();
    _update();
  }

  void _close() {
    _isOpen = false;
    _suggestions = SuggestionSet();
    _selectedIndex = null;
    _position?.disable();
    _update();
  }

  Future<void> _loadSuggestions() async {
    _suggestions = await loadSearchSuggestions(
      input: _input!,
      inputValue: inputValue,
      mode: attribute('mode'),
      user: host.getAttribute('user'),
      shared: host.getAttribute('shared'),
      unread: host.getAttribute('unread'),
      history: _history,
    );
    _suggestions.all.isNotEmpty ? _open() : _close();
  }

  void _complete(Suggestion suggestion) {
    switch (suggestion.type) {
      case 'search':
        _inputValue = suggestion.value;
      case 'bookmark':
        final target = attribute('target');
        web.window.open(suggestion.url!, target.isEmpty ? '_blank' : target);
      case 'tag':
        replaceCurrentWord(_input!, '#${suggestion.tagName} ');
    }
    _close();
  }

  void _updateSelection(int direction) {
    final length = _suggestions.all.length;
    if (length == 0) return;
    _selectedIndex = nextSelection(_selectedIndex, direction, length);
    _update();
  }
}
