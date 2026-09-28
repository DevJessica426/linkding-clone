import 'package:dust_server/server.dart';

/// The media type of a Turbo Stream response.
const turboStreamType = 'text/vnd.turbo-stream.html';

/// linkding's `turbo.update`: [content] as the new inside of [target].
String turboUpdate(String target, String content, {String method = ''}) =>
    '<turbo-stream action="update"${method.isEmpty ? '' : ' method="$method"'} '
    'target="$target"><template>$content</template></turbo-stream>';

/// linkding's `turbo.replace`: [content] in place of [target].
String turboReplace(String target, String content, {String method = ''}) =>
    '<turbo-stream action="replace"${method.isEmpty ? '' : ' method="$method"'} '
    'target="$target"><template>$content</template></turbo-stream>';

/// linkding's `turbo.stream`: several stream elements in one response.
Response turboStream(List<String> streams) =>
    Response.ok(streams.join('\n'), headers: {'content-type': turboStreamType});
