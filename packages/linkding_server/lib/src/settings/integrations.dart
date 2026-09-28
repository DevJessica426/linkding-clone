import 'package:dust_server/server.dart';

import '../auth/sessions.dart' show newTokenKey;
import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/users_repo.dart';
import '../pages/render.dart';
import '../pages/session_data.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';

/// `/settings/integrations`: the browser extension and bookmarklet, the API
/// tokens (a new one's key shown once), and the feed URLs.
Future<Response> settingsIntegrations(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final user = visitor.signedIn;
  final users = UsersRepo((await request.state<LinkdingDatabase>()).connection);
  final session = await SessionData.of(request);
  final newKey = await session.pop('api_token_key');
  final newName = await session.pop('api_token_name');
  final message = (await session.takeMessages())
      .where((m) => m.extraTags == 'api_success_message')
      .firstOrNull
      ?.message;
  var feedKey = (await users.feedToken(user.id)).orThrow;
  if (feedKey == null) {
    (await users.insertFeedToken(
      newTokenKey(),
      DateTime.now().toUtc(),
      user.id,
    )).orThrow;
    feedKey = (await users.feedToken(user.id)).orThrow!;
  }
  final tokens = (await users.apiTokens(user.id)).orThrow;
  return renderPage(
    await request.state<TemplateEngine>(),
    visitor,
    title: 'Integrations - Linkding',
    template: 'settings/integrations',
    values: {
      'applicationUrl': '${visitor.baseUrl}/bookmarks/new',
      'feedKey': feedKey,
      'hasMessage': message != null,
      'message': message ?? '',
      'hasNewToken': newKey != null && newName != null,
      'newKey': newKey ?? '',
      'hasTokens': tokens.isNotEmpty,
      'tokens': [
        for (final t in tokens)
          {'id': t.id, 'name': t.name, 'created': _tokenDate(t.created)},
      ],
    },
  );
}

/// `/settings/integrations/create-api-token`: the dialog, and creating the
/// token, whose key the integrations page shows once.
Future<Response> createApiToken(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  if (request.method != 'POST') {
    final engine = await request.state<TemplateEngine>();
    return htmlResponse(
      engine.render('settings/create-token', {
        ...commonValues(visitor),
        'title': 'Create API Token',
      }),
    );
  }
  final form = await request.extract(const PostedForm());
  var name = (form['name'] ?? '').trim();
  if (name.isEmpty) name = 'API Token';
  final db = (await request.state<LinkdingDatabase>()).connection;
  final token = (await UsersRepo(db).insertApiToken(
    newTokenKey(),
    name,
    DateTime.now().toUtc(),
    visitor.signedIn.id,
  )).orThrow;
  final session = await SessionData.of(request);
  await session.set('api_token_key', token.key);
  await session.set('api_token_name', token.name);
  await session.addMessage(
    'API token "${token.name}" created successfully',
    extraTags: 'api_success_message',
  );
  return Redirect.found('/settings/integrations').intoResponse();
}

/// `/settings/integrations/delete-api-token`.
Future<Result<Response, Rejection>> deleteApiToken(Request request) async {
  if (request.method == 'POST') {
    final visitor = await request.extract(const Extension<Visitor>());
    final form = await request.extract(const PostedForm());
    final user = visitor.signedIn;
    final users = UsersRepo(
      (await request.state<LinkdingDatabase>()).connection,
    );
    final id = int.tryParse(form['token_id']?.trim() ?? '');
    final tokens = (await users.apiTokens(user.id)).orThrow;
    final token = tokens.where((t) => t.id == id).firstOrNull;
    if (token == null) {
      return const Err(Rejection.notFound('API token does not exist'));
    }
    (await users.deleteApiToken(token.id, user.id)).orThrow;
    await (await SessionData.of(request)).addMessage(
      'API token "${token.name}" has been deleted.',
      extraTags: 'api_success_message',
    );
  }
  return Ok(Redirect.found('/settings/integrations').intoResponse());
}

/// Django's `date:"M d, Y H:i"`.
String _tokenDate(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final v = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${months[v.month - 1]} ${two(v.day)}, ${v.year} '
      '${two(v.hour)}:${two(v.minute)}';
}
