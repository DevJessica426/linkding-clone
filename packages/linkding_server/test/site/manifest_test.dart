import 'package:linkding_server/src/site/manifest.dart';
import 'package:test/test.dart';

/// The manifest's JSON as Python's `json.dumps` writes it.
void main() {
  test("json.dumps's default separators", () {
    expect(
      pythonJson({
        'a': [1, 'b'],
        'c': {'d': true, 'e': null},
      }),
      '{"a": [1, "b"], "c": {"d": true, "e": null}}',
    );
  });
}
