import 'dart:convert';

import 'package:dust_server/server.dart';

import '../config.dart';
import '../db/assets_repo.dart';
import '../db/rows.dart';
import '../services/assets.dart';
import '../services/errors.dart';
import 'access.dart';
import 'context.dart';

/// linkding's `views/assets.py`: a bookmark's file, and a snapshot in
/// reader mode, for anyone who may see the bookmark.
final class AssetViews {
  AssetViews(this.web);

  final Web web;

  /// `/assets/<id>`: the file itself, unzipped, shown in the browser.
  Future<Response> view(Request request) async {
    final c = await web.context(request);
    final asset = await _readable(c, request);
    final content = asset == null ? null : await web.assets.read(asset);
    if (asset == null || content == null) return notFoundPage();
    return Response(
      200,
      body: content,
      headers: {
        'content-type': asset.contentType,
        'content-disposition':
            'inline; filename="${AssetService.downloadName(asset)}"',
        'content-security-policy': _policy(asset.contentType),
      },
    );
  }

  /// `/assets/<id>/read`: a snapshot through Readability.js.
  Future<Response> read(Request request) async {
    final c = await web.context(request);
    final asset = await _readable(c, request);
    final content = asset == null ? null : await web.assets.read(asset);
    if (asset == null || content == null) return notFoundPage();
    return c.html(
      _readerPage(c, utf8.decode(content)),
      headers: {'content-security-policy': 'sandbox allow-scripts'},
    );
  }

  /// `access.asset_read`.
  Future<AssetRow?> _readable(PageContext c, Request request) async {
    final id = int.tryParse(await request.path<String>('id'));
    if (id == null || id > 2147483647) return null;
    final db = web.database.connection;
    final asset = (await AssetsRepo(db).byId(id)).orThrow;
    if (asset == null) return null;
    final bookmark = await readableBookmark(db, c, asset.bookmarkId);
    return bookmark == null ? null : asset;
  }

  static String _policy(String contentType) {
    if (contentType.startsWith('video/')) {
      return "default-src 'none'; media-src 'self';";
    }
    if (contentType == 'application/pdf') {
      return "default-src 'none'; object-src 'self';";
    }
    return 'sandbox allow-scripts';
  }

  /// `bookmarks/read.html`. The content goes in unescaped, inside a
  /// `<template>` that the sandboxed page hands to Readability.
  String _readerPage(PageContext c, String content) {
    final profile = c.profile.row;
    final version = '?v=$linkdingVersion';
    final theme = switch (profile.theme) {
      'light' =>
        '''
      <link href="${static('theme-light.css')}$version"
            rel="stylesheet"
            type="text/css" />
      <meta name="theme-color" content="#5856e0">''',
      'dark' =>
        '''
      <link href="${static('theme-dark.css')}$version"
            rel="stylesheet"
            type="text/css" />
      <meta name="theme-color" content="#161822">''',
      _ =>
        '''
      <link href="${static('theme-dark.css')}$version"
            rel="stylesheet"
            type="text/css"
            media="(prefers-color-scheme: dark)" />
      <link href="${static('theme-light.css')}$version"
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
    // The page is sandboxed, so a request for the custom CSS would carry no
    // credentials: the CSS is embedded as a data URL instead.
    final customCss = profile.customCss.isEmpty
        ? ''
        : '''
      <link href="data:text/css;charset=utf-8;base64,${base64.encode(utf8.encode(profile.customCss))}"
            rel="stylesheet"
            type="text/css" />''';
    return '''
<!DOCTYPE html>
<html lang="en" class="reader-mode">
  <head>
    <meta charset="UTF-8">
    <title>Reader view</title>
    <meta name="viewport"
          content="width=device-width, initial-scale=1.0, minimal-ui">
$theme$customCss
  </head>
  <body>
    <template id="content">$content</template>
    <script src="${static('vendor/Readability.js')}"
            type="application/javascript"></script>
    <script type="application/javascript">$_readerScript</script>
  </body>
</html>
''';
  }
}

/// linkding's reader-mode script, verbatim.
const _readerScript = r'''
      function estimateReadingTime(charCount, wordsPerMinute) {
        const avgWordLength = 5;
        const totalWords = charCount / avgWordLength;
        return Math.ceil(totalWords / wordsPerMinute);
      }

      function postProcess(articleContent) {
        articleContent.querySelectorAll('table').forEach(table => {
          table.classList.add('table');
        });
      }

      function makeReadable() {
        const content = document.getElementById('content');
        const contentHtml = content.innerHTML;
        const dom = new DOMParser().parseFromString(contentHtml, 'text/html');
        const article = new Readability(dom).parse();

        document.title = article.title;

        const container = document.createElement('div');
        container.classList.add('container');

        const articleTitle = document.createElement('h1');
        articleTitle.textContent = article.title;
        container.append(articleTitle);

        const byline = [article.byline, article.siteName].filter(Boolean);
        if (byline.length > 0) {
          const articleByline = document.createElement('p');
          articleByline.textContent = byline.join(' | ');
          articleByline.classList.add('byline');
          container.append(articleByline);
        }

        if (article.length) {
          const minTime = estimateReadingTime(article.length, 225);
          const maxTime = estimateReadingTime(article.length, 175);

          const articleReadingTime = document.createElement('p');
          articleReadingTime.textContent = `${minTime}-${maxTime} minutes`;
          articleReadingTime.classList.add('reading-time');
          container.append(articleReadingTime);
        }

        const divider = document.createElement('hr');
        container.append(divider);

        const articleContent = document.createElement('div');
        articleContent.innerHTML = article.content;
        postProcess(articleContent);
        container.append(articleContent);

        content.replaceWith(container);
      }
      makeReadable();
    ''';
