import 'package:linkding_server/src/api/pagination.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// DRF's page links, against the ones DRF built.
void main() {
  final fixture = loadFixture('logic');
  group('DRF pagination links', () {
    for (final [url as String, withLimit, withOffset, withoutOffset]
        in fixtureRows(fixture, 'page_links')) {
      test(url, () {
        expect(replaceQueryParam(url, 'limit', '5'), withLimit);
        expect(
          replaceQueryParam(
            replaceQueryParam(url, 'limit', '5'),
            'offset',
            '15',
          ),
          withOffset,
        );
        expect(removeQueryParam(url, 'offset'), withoutOffset);
      });
    }
  });
}
