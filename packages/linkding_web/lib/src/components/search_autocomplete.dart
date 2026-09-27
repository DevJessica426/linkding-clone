import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../api.dart';
import '../dom.dart';
import '../element.dart';
import '../input.dart';
import '../position.dart';
import '../tag_cache.dart';

/// One entry of the search menu.
final class _Suggestion {
  _Suggestion.tag(this.index, this.tagName)
    : type = 'tag',
      label = '#$tagName',
      value = null,
      url = null;

  _Suggestion.search(this.index, String this.value)
    : type = 'search',
      label = value,
      tagName = null,
      url = null;

  _Suggestion.bookmark(this.index, this.label, String this.url)
    : type = 'bookmark',
      tagName = null,
      value = null;

  final String type;
  final int index;
  final String label;
  final String? tagName;
  final String? value;
  final String? url;
}

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
  var _tags = <_Suggestion>[];
  var _recentSearches = <_Suggestion>[];
  var _bookmarks = <_Suggestion>[];
  var _total = <_Suggestion>[];
  int? _selectedIndex;

  web.HTMLInputElement? _input;
  web.HTMLElement? _inputBox;
  web.HTMLElement? _menu;
  String? _committedValue;
  PositionController? _position;
  final _history = SearchHistory();
  late final _debouncedLoad = debounce(_loadSuggestions);

  String get inputValue => _inputValue ?? attribute('input-value');

  String? _optional(String name) => host.getAttribute(name);

  @override
  void attributeChanged(String name, String? oldValue, String? newValue) {
    if (name == 'input-value') _inputValue = newValue ?? '';
    if (_input != null) _update();
  }

  @override
  void render() {
    host.innerHTML =
        '''
      <div class="form-autocomplete">
        <div
          class="form-autocomplete-input form-input "
        >
          <input
            type="search"
            class="form-input"
            autocomplete="off"
          />
        </div>

        <ul class="menu ">
        </ul>
      </div>
    '''
            .toJS;
    final input = host.querySelector('input')! as web.HTMLInputElement;
    _input = input;
    _inputBox =
        host.querySelector('.form-autocomplete-input') as web.HTMLElement;
    _menu = host.querySelector('.menu') as web.HTMLElement;
    Listener(input, 'input', (event) {
      _inputValue = input.value;
      _debouncedLoad();
    });
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
    host.style.setProperty('--menu-max-height', '400px');
    // The search of the page being shown becomes a recent search.
    _history.pushCurrent();
    _updateSuggestions();
    _position = PositionController(
      anchor: _input!,
      overlay: _menu!,
      autoWidth: true,
      placement: 'bottom-start',
    );
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
    final sections = [
      _section(_tags, 'Tags'),
      _section(_recentSearches, 'Recent Searches'),
      _section(_bookmarks, 'Bookmarks'),
    ];
    // The template's own text around the three sections, as Lit keeps it.
    menu.innerHTML =
        '\n          ${sections.map((s) => s.html).join('\n          ')}\n        '
            .toJS;
    final suggestions = [for (final s in sections) ...s.items];
    final links = queryAll(menu, 'a');
    for (var i = 0; i < links.length; i++) {
      final suggestion = suggestions[i];
      Listener(links[i], 'mousedown', (event) {
        event.preventDefault();
        _complete(suggestion);
      });
    }
  }

  /// linkding's `renderSuggestions`: a heading, then one link per
  /// suggestion; nothing for no suggestions.
  ({String html, List<_Suggestion> items}) _section(
    List<_Suggestion> items,
    String title,
  ) {
    if (items.isEmpty) return (html: '', items: const []);
    final entries = [
      for (final s in items)
        '''
          <li
            class="menu-item ${_selectedIndex == s.index ? 'selected' : ''}"
          >
            <a
              href="#"
            >
              ${escapeHtml(s.label)}
            </a>
          </li>
        ''',
    ];
    return (
      html:
          '\n      <li class="menu-item group-item">${escapeHtml(title)}</li>\n'
          '      ${entries.join()}\n    ',
      items: items,
    );
  }

  void _onKeyDown(web.Event event) {
    final key = (event as web.KeyboardEvent).keyCode;
    // Enter or Tab takes the selected suggestion.
    if (_isOpen && _selectedIndex != null && (key == 13 || key == 9)) {
      final index = _selectedIndex!;
      if (index < _total.length) _complete(_total[index]);
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
      if (!_isOpen) {
        _loadSuggestions();
      } else {
        _updateSelection(1);
      }
      event.preventDefault();
    }
  }

  void _open() {
    _isOpen = true;
    _position?.enable();
    _update();
  }

  void _close() {
    _isOpen = false;
    _updateSuggestions();
    _selectedIndex = null;
    _position?.disable();
    _update();
  }

  Future<void> _loadSuggestions() async {
    var index = 0;

    // Tags, after a `#`.
    final tags = await tagCache.getTags();
    var tagSuggestions = <_Suggestion>[];
    final word = currentWord(_input!);
    if (word.length > 1 && word.startsWith('#')) {
      final search = word.substring(1).toLowerCase();
      tagSuggestions = [
        for (final tag
            in tags
                .where((t) => t.name.toLowerCase().startsWith(search))
                .take(5))
          _Suggestion.tag(index++, tag.name),
      ];
    }

    final recentSearches = [
      for (final value in _history.recentSearches(inputValue, 5))
        _Suggestion.search(index++, value),
    ];

    // Bookmarks, from three characters on.
    var bookmarks = <_Suggestion>[];
    if (inputValue.length >= 3) {
      final mode = attribute('mode');
      final found = await api.listBookmarks(
        {
          'user': _optional('user'),
          'shared': _optional('shared'),
          'unread': _optional('unread'),
          'q': inputValue,
        },
        limit: 5,
        path: mode.isEmpty ? '' : '/$mode',
      );
      bookmarks = [
        for (final bookmark in found)
          _Suggestion.bookmark(
            index++,
            clampText(
              bookmark.title.isNotEmpty ? bookmark.title : bookmark.url,
              60,
            ),
            bookmark.url,
          ),
      ];
    }

    _updateSuggestions(recentSearches, bookmarks, tagSuggestions);
    if (_total.isNotEmpty) {
      _open();
    } else {
      _close();
    }
  }

  void _updateSuggestions([
    List<_Suggestion> recentSearches = const [],
    List<_Suggestion> bookmarks = const [],
    List<_Suggestion> tags = const [],
  ]) {
    _recentSearches = recentSearches;
    _bookmarks = bookmarks;
    _tags = tags;
    _total = [...tags, ...recentSearches, ...bookmarks];
  }

  void _complete(_Suggestion suggestion) {
    switch (suggestion.type) {
      case 'search':
        _inputValue = suggestion.value;
        _close();
      case 'bookmark':
        final target = attribute('target');
        web.window.open(suggestion.url!, target.isEmpty ? '_blank' : target);
        _close();
      case 'tag':
        final input = _input!;
        final bounds = currentWordBounds(input);
        final value = input.value;
        input.value =
            '${value.substring(0, bounds.start)}#${suggestion.tagName} '
            '${value.substring(bounds.end)}';
        _close();
    }
  }

  void _updateSelection(int direction) {
    final length = _total.length;
    if (length == 0) return;
    final selected = _selectedIndex;
    if (selected == null) {
      _selectedIndex = direction > 0 ? 0 : length - 1;
    } else {
      var next = selected + direction;
      if (next < 0) next = length - 1;
      if (next >= length) next = 0;
      _selectedIndex = next;
    }
    _update();
  }
}
