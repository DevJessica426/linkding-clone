import 'markdown_escape.dart';

/// linkding's link callbacks: bleach's `nofollow`, then
/// `schemeless_urls_to_https`, which also applies to existing links unless
/// their text spells out `http://`.
void linkCallbacks(Map<String, String> attributes, String text) {
  final href = attributes['href'];
  if (href == null) return;
  if (!href.startsWith('mailto:')) {
    final rel = (attributes['rel'] ?? '')
        .split(' ')
        .where((v) => v.isNotEmpty)
        .toList();
    if (!rel.any((v) => v.toLowerCase() == 'nofollow')) rel.add('nofollow');
    attributes['rel'] = rel.join(' ');
  }
  if (!text.startsWith('http://')) {
    attributes['href'] = href.replaceFirst(RegExp('^http://'), 'https://');
  }
}

const _protocols = [
  'afs', 'aim', 'callto', 'data', 'ed2k', 'feed', 'ftp', 'gopher', 'http', //
  'https', 'irc', 'mailto', 'news', 'nntp', 'rsync', 'rtsp', 'sftp', 'ssh',
  'tag', 'telnet', 'urn', 'webcal', 'xmpp',
];

/// bleach's top-level domains, sorted as its pattern lists them.
final _tlds =
    ('ac ad ae aero af ag ai al am an ao aq ar arpa as asia at au aw '
            'ax az ba bb bd be bf bg bh bi biz bj bm bn bo br bs bt bv bw by bz '
            'ca cat cc cd cf cg ch ci ck cl cm cn co com coop cr cu cv cx cy cz '
            'de dj dk dm do dz ec edu ee eg er es et eu fi fj fk fm fo fr ga gb '
            'gd ge gf gg gh gi gl gm gn gov gp gq gr gs gt gu gw gy hk hm hn hr '
            'ht hu id ie il im in info int io iq ir is it je jm jo jobs jp ke kg '
            'kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md '
            'me mg mh mil mk ml mm mn mo mobi mp mq mr ms mt mu museum mv mw mx '
            'my mz na name nc ne net nf ng ni nl no np nr nu nz om org pa pe pf '
            'pg ph pk pl pm pn post pr pro ps pt pw py qa re ro rs ru rw sa sb sc '
            'sd se sg sh si sj sk sl sm sn so sr ss st su sv sx sy sz tc td tel '
            'tf tg th tj tk tl tm tn to tp tr travel tt tv tw tz ua ug uk us uy '
            'uz va vc ve vg vi vn vu wf ws xn xxx ye yt yu za zm zw')
        .split(' ')
      ..sort();

/// Python's Unicode `\w` and `\b`.
const _w = r'[\p{L}\p{N}_]';
const _boundary = '(?:(?<=$_w)(?!$_w)|(?<!$_w)(?=$_w))';

/// bleach's `URL_RE`.
final _urlPattern = RegExp(
  r'\(*'
  '$_boundary(?<![@.])(?:(?:${_protocols.join('|')}):/{0,3}'
  '(?:(?:$_w+:)?$_w+@)?)?'
  r'(?:[\p{L}\p{N}_-]+\.)+'
  '(?:${_tlds.join('|')})(?::[0-9]+)?(?!\\.$_w)$_boundary'
  r'(?:[/?][^\s{}|\\^`<>"]*)?',
  caseSensitive: false,
  unicode: true,
);

final _protocolPattern = RegExp(r'^[\p{L}\p{N}_-]+:/{0,3}', unicode: true);

/// bleach's `linkify` over one run of text.
String linkify(String text) {
  final out = StringBuffer();
  var end = 0;
  for (final match in _urlPattern.allMatches(text)) {
    out.write(escapeText(text.substring(end, match.start)));
    final (url, prefix, suffix) = _stripNonUrlBits(match[0]!);
    final attributes = <String, String>{
      'href': _protocolPattern.hasMatch(url) ? url : 'http://$url',
    };
    linkCallbacks(attributes, url);
    out
      ..write(escapeText(prefix))
      ..write('<a')
      ..writeAll([
        for (final MapEntry(:key, :value) in attributes.entries)
          ' $key="${escapeAttribute(value)}"',
      ])
      ..write('>${escapeText(url)}</a>')
      ..write(escapeText(suffix));
    end = match.end;
  }
  out.write(escapeText(text.substring(end)));
  return out.toString();
}

/// bleach's `strip_non_url_bits`: balanced parentheses around a URL, and a
/// closing parenthesis, comma or period after it, are not part of it.
(String, String, String) _stripNonUrlBits(String fragment) {
  var prefix = '';
  var suffix = '';
  while (fragment.isNotEmpty) {
    if (fragment.startsWith('(')) {
      prefix = '$prefix(';
      fragment = fragment.substring(1);
      if (fragment.endsWith(')')) {
        suffix = ')$suffix';
        fragment = fragment.substring(0, fragment.length - 1);
      }
      continue;
    }
    if (fragment.endsWith(')') && !fragment.contains('(')) {
      fragment = fragment.substring(0, fragment.length - 1);
      suffix = ')$suffix';
      continue;
    }
    if (fragment.endsWith(',') || fragment.endsWith('.')) {
      suffix = '${fragment[fragment.length - 1]}$suffix';
      fragment = fragment.substring(0, fragment.length - 1);
      continue;
    }
    break;
  }
  return (fragment, prefix, suffix);
}
