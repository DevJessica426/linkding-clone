import '../config.dart';
import '../db/rows.dart';
import 'context.dart';
import 'html.dart';

/// linkding's `shared/layout.html` with `shared/head.html` and the
/// navigation menu, line for line.
String layout(
  PageContext c, {
  required String title,
  required String content,
  String overlays = '',
  String? rssFeedUrl,
}) {
  return '''
<!DOCTYPE html>
<html lang="en" data-api-base-url="/api/">
${head(c, title: title, rssFeedUrl: rssFeedUrl)}
  <body>
    <header class="container">
${_toasts(c)}      <div class="d-flex justify-between">
        <a href="/" class="app-link d-flex align-center">
          <img class="app-logo" src="${static('logo.png')}" alt="Application logo">
          <span class="app-name">LINKDING</span>
        </a>
        <nav>
${c.isAuthenticated ? _navMenu(c) : '            <a href="/login/" class="btn btn-link">Login</a>'}
        </nav>
      </div>
    </header>
    <div class="content container">
$content
    </div>
    <div class="modals">
$overlays
    </div>
  </body>
</html>
''';
}

/// `shared/head.html`.
String head(PageContext c, {required String title, String? rssFeedUrl}) {
  final theme = c.profile.row.theme;
  final themeLinks = switch (theme) {
    'light' =>
      '''
    <link href="${static('theme-light.css')}?v=$linkdingVersion"
          rel="stylesheet"
          type="text/css" />
    <meta name="theme-color" content="#5856e0">''',
    'dark' =>
      '''
    <link href="${static('theme-dark.css')}?v=$linkdingVersion"
          rel="stylesheet"
          type="text/css" />
    <meta name="theme-color" content="#161822">''',
    _ =>
      '''
    <link href="${static('theme-dark.css')}?v=$linkdingVersion"
          rel="stylesheet"
          type="text/css"
          media="(prefers-color-scheme: dark)" />
    <link href="${static('theme-light.css')}?v=$linkdingVersion"
          rel="stylesheet"
          type="text/css"
          media="(prefers-color-scheme: light)" />
    <meta name="theme-color"
          media="(prefers-color-scheme: dark)"
          content="#161822">
    <meta name="theme-color"
          media="(prefers-color-scheme: light)"
          content="#5856e0">''',
  };
  final profile = c.profile.row;
  final customCss = profile.customCss.isNotEmpty
      ? '\n  <link href="/custom_css?hash=${e(profile.customCssHash)}"\n'
            '        rel="stylesheet"\n        type="text/css" />'
      : '';
  final prefetch = c.settings.enableLinkPrefetch
      ? ''
      : '\n  <meta name="turbo-prefetch" content="false">';
  final rss = rssFeedUrl == null
      ? ''
      : '\n  <link rel="alternate" type="application/rss+xml" href="${e(rssFeedUrl)}" />';

  return '''
<head>
  <meta charset="UTF-8">
  <link rel="icon" href="${static('favicon.ico')}" sizes="48x48">
  <link rel="icon"
        href="${static('favicon.svg')}"
        sizes="any"
        type="image/svg+xml">
  <link rel="apple-touch-icon"
        sizes="180x180"
        href="${static('apple-touch-icon.png')}">
  <link rel="mask-icon"
        href="${static('safari-pinned-tab.svg')}"
        color="#5856e0">
  <link rel="manifest" href="/manifest.json">
  <link rel="search"
        type="application/opensearchdescription+xml"
        title="Linkding"
        href="/opensearch.xml" />
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="viewport"
        content="width=device-width, initial-scale=1.0, minimal-ui">
  <meta name="description" content="Self-hosted bookmark service">
  <meta name="robots" content="index,follow">
  <meta name="author" content="Sascha Ißbrücker">
  <title>${e(title)}</title>
$themeLinks$customCss
  <meta name="turbo-cache-control" content="no-preview">$prefetch$rss
  <script src="${static('bundle.js')}?v=$linkdingVersion"></script>
</head>''';
}

/// `shared/top_frame.html`: a page holding only [frame], for a Turbo frame
/// request that also changes the address of the page.
String topFrame(
  PageContext c, {
  required String title,
  required String frame,
  String? rssFeedUrl,
}) =>
    '''
<html lang="en">
${head(c, title: title, rssFeedUrl: rssFeedUrl)}
  <body>
    $frame
  </body>
</html>
''';

String _toasts(PageContext c) {
  if (c.toasts.isEmpty) return '';
  final items = c.toasts
      .map(
        (t) =>
            '''
              <div class="toast d-flex">
                ${e(t.message)}
                <button type="submit"
                        name="toast"
                        value="${t.id}"
                        class="btn btn-clear"></button>
              </div>''',
      )
      .join('\n');
  return '''
        <div class="message-list">
          <form action="/toasts/acknowledge?return_url=${q(c.path)}"
                method="post">
            ${c.csrfInput}
$items
          </form>
        </div>
''';
}

/// `shared/nav_menu.html`, minified as linkding's `{% htmlmin %}` does.
String _navMenu(PageContext c) {
  final sharing = c.profile.row.enableSharing;
  final icons = '${static('icons.svg')}?v=$linkdingVersion';
  final logout =
      '<form class="d-inline" action="/logout/" method="post" data-turbo="false"> '
      '${c.csrfInput} <button type="submit" class="btn btn-link">Logout</button> </form>';
  final logoutMenu =
      '<form class="d-inline" action="/logout/" method="post" data-turbo="false"> '
      '${c.csrfInput} <button type="submit" class="btn btn-link menu-link">Logout</button> </form>';
  String item(String href, String label) =>
      '<li class="menu-item"> <a href="$href" class="menu-link">$label</a> </li>';
  return [
    ' <div class="hide-md">',
    '<a href="/bookmarks/new" class="btn btn-primary mr-2">Add bookmark</a>',
    '<ld-dropdown class="dropdown">',
    '<button class="btn btn-link dropdown-toggle" tabindex="0">Bookmarks</button>',
    '<ul class="menu" role="list" tabindex="-1">',
    item('/bookmarks', 'Active'),
    item('/bookmarks/archived', 'Archived'),
    if (sharing) item('/bookmarks/shared', 'Shared'),
    item('/bookmarks?unread=yes', 'Unread'),
    item('/bookmarks?q=!untagged', 'Untagged'),
    '</ul> </ld-dropdown>',
    '<ld-dropdown class="dropdown">',
    '<button class="btn btn-link dropdown-toggle" tabindex="0">Settings</button>',
    '<ul class="menu" role="list" tabindex="-1">',
    item('/settings/general', 'General'),
    item('/settings/integrations', 'Integrations'),
    '</ul> </ld-dropdown>',
    logout,
    '</div>',
    '<div class="show-md">',
    '<a href="/bookmarks/new" aria-label="Add bookmark" class="btn btn-primary">',
    '<svg width="24" height="24"> <use href="$icons#plus"></use> </svg> </a>',
    '<ld-dropdown class="dropdown dropdown-right">',
    '<button class="btn btn-link dropdown-toggle" aria-label="Navigation menu" tabindex="0">',
    '<svg width="24" height="24"> <use href="$icons#menu"></use> </svg> </button>',
    '<!-- menu component --> <ul class="menu" role="list" tabindex="-1">',
    item('/bookmarks', 'Bookmarks'),
    item('/bookmarks/archived', 'Archived bookmarks'),
    if (sharing) item('/bookmarks/shared', 'Shared bookmarks'),
    item('/bookmarks?unread=yes', 'Unread'),
    item('/bookmarks?q=!untagged', 'Untagged'),
    '<div class="divider"></div>',
    item('/settings/general', 'Settings'),
    item('/settings/integrations', 'Integrations'),
    '<div class="divider"></div>',
    '<li class="menu-item"> $logoutMenu </li>',
    '</ul> </ld-dropdown> </div> ',
  ].join(' ');
}

/// `shared/messages.html`.
String messageList(List<MessageRow> messages) => messages.isEmpty
    ? ''
    : '''
  <div class="message-list">
    ${messages.map((m) => '<div class="toast toast-${e(m.tags)}" role="alert">${e(m.message)}</div>').join()}
  </div>''';
