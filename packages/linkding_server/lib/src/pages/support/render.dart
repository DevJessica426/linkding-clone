import 'package:dust_server/server.dart';

import '../../config.dart';
import 'html.dart' show q;
import '../session/visitor.dart';

/// What every template can use: the CSRF token, produced only when a
/// template renders it, as Django's `{% csrf_token %}` produces it.
Map<String, Object?> commonValues(Visitor visitor) => {
  'csrfToken': (Object _) => visitor.csrfToken,
  'version': linkdingVersion,
};

/// linkding's `shared/layout.html` around [template]: the head, the toasts,
/// the navigation, the page, and the page's overlays (modals).
Response renderPage(
  TemplateEngine engine,
  Visitor visitor, {
  required String title,
  required String template,
  Map<String, Object?> values = const {},
  String overlays = '',
  String? rssFeedUrl,
  int status = 200,
  Map<String, Object> headers = const {},
}) {
  final common = commonValues(visitor);
  final content = engine.render(template, {...common, ...values});
  return render(engine, 'layout', {
    ...layoutValues(visitor, title: title, rssFeedUrl: rssFeedUrl),
    'content': content,
    'overlays': overlays,
  }, status: status).change(headers: headers);
}

/// `shared/top_frame.html`: a document holding only [frame], for a Turbo
/// frame request that also moves the page's address.
Response renderTopFrame(
  TemplateEngine engine,
  Visitor visitor, {
  required String title,
  required String frame,
  String? rssFeedUrl,
}) => render(engine, 'top-frame', {
  ...layoutValues(visitor, title: title, rssFeedUrl: rssFeedUrl),
  'frame': frame,
});

/// The values `layout`, `head`, `nav` and `toasts` read.
Map<String, Object?> layoutValues(
  Visitor visitor, {
  required String title,
  String? rssFeedUrl,
}) {
  final profile = visitor.profile.row;
  return {
    ...commonValues(visitor),
    'title': title,
    'themeLight': profile.theme == 'light',
    'themeDark': profile.theme == 'dark',
    'themeAuto': profile.theme != 'light' && profile.theme != 'dark',
    'hasCustomCss': profile.customCss.isNotEmpty,
    'customCssHash': profile.customCssHash,
    'noPrefetch': !visitor.settings.enableLinkPrefetch,
    'hasRss': rssFeedUrl != null,
    'rssFeedUrl': rssFeedUrl ?? '',
    'signedIn': visitor.isAuthenticated,
    'sharing': profile.enableSharing,
    'hasToasts': visitor.toasts.isNotEmpty,
    'toasts': [
      for (final toast in visitor.toasts)
        {'id': toast.id, 'message': toast.message},
    ],
    'returnUrl': q(visitor.path),
  };
}
