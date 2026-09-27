import 'dart:convert';
import 'dart:typed_data';

import 'package:dust_server/server.dart';
import 'package:linkding_server/src/compat/form_data.dart';
import 'package:test/test.dart';

/// Form bodies as the web pages post them.
void main() {
  Request post(String contentType, String body) => Request(
    'POST',
    Uri.parse('http://localhost/bookmarks/action'),
    headers: {'content-type': contentType},
    body: Stream.value(Uint8List.fromList(utf8.encode(body))),
  );

  test('urlencoded, every value of a repeated key', () async {
    final form = await readFormData(
      post(
        'application/x-www-form-urlencoded',
        'bookmark_id=1&bookmark_id=2&q=a+b&empty=',
      ),
    );
    expect(form.list('bookmark_id'), ['1', '2']);
    expect(form['q'], 'a b');
    expect(form['empty'], '');
    expect(form.has('missing'), isFalse);
  });

  test('multipart from a request body stream, with a file', () async {
    const boundary = 'b0undary';
    final body = [
      '--$boundary\r\nContent-Disposition: form-data; name="upload_asset"',
      '\r\n\r\n900\r\n',
      '--$boundary\r\nContent-Disposition: form-data; name="upload_asset_file";',
      ' filename="C:\\\\docs\\\\notes.md"\r\n',
      'Content-Type: Text/Markdown; charset=utf-8\r\n\r\n# Notes\r\n',
      '--$boundary--\r\n',
    ].join();
    final form = await readFormData(
      post('multipart/form-data; boundary=$boundary', body),
    );
    expect(form['upload_asset'], '900');
    final file = form.files['upload_asset_file']!;
    expect(file.name, 'notes.md');
    expect(file.contentType, 'text/markdown');
    expect(utf8.decode(file.bytes), '# Notes');
  });
}
