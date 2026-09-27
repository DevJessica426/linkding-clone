import 'dart:async';

import 'package:web/web.dart' as web;

/// Calls [callback] once calls have paused for [delay]: linkding's
/// `debounce`.
void Function() debounce(
  void Function() callback, [
  Duration delay = const Duration(milliseconds: 250),
]) {
  Timer? timer;
  return () {
    timer?.cancel();
    timer = Timer(delay, () {
      timer = null;
      callback();
    });
  };
}

/// [text] cut to [maxChars] with an ellipsis. As in linkding, the check is
/// against 30 characters whatever [maxChars] is.
String clampText(String text, [int maxChars = 30]) {
  if (text.isEmpty || text.length <= 30) return text;
  return '${text.substring(0, maxChars.clamp(0, text.length))}...';
}

/// The word the caret is in (or ends), up to the caret: from the last space
/// before it.
({int start, int end}) currentWordBounds(web.HTMLInputElement input) {
  final text = input.value;
  final end = input.selectionStart ?? text.length;
  var start = end;
  while (start > 0 && text[start - 1] != ' ') {
    start--;
  }
  return (start: start, end: end);
}

String currentWord(web.HTMLInputElement input) {
  final bounds = currentWordBounds(input);
  return input.value.substring(bounds.start, bounds.end);
}
