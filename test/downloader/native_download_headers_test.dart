import 'package:aurora_downloader/platform/native_download_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NativeDownloadClient.headerValue', () {
    test('matches Cookie regardless of case', () {
      expect(
        NativeDownloadClient.headerValue(
          {'cookie': 'a=1'},
          'Cookie',
        ),
        'a=1',
      );
      expect(
        NativeDownloadClient.headerValue(
          {'Cookie': 'session=xyz'},
          'cookie',
        ),
        'session=xyz',
      );
    });

    test('ignores empty values', () {
      expect(
        NativeDownloadClient.headerValue({'Cookie': ''}, 'Cookie'),
        isNull,
      );
      expect(NativeDownloadClient.headerValue({}, 'Cookie'), isNull);
      expect(NativeDownloadClient.headerValue(null, 'Cookie'), isNull);
    });
  });

  group('NativeDownloadClient.cookieHeaderFrom', () {
    test('explicit cookie wins', () {
      expect(
        NativeDownloadClient.cookieHeaderFrom(
          explicit: 'live=1',
          headers: {'Cookie': 'stale=1'},
          providerCookies: {'Cookie': 'jar=1'},
        ),
        'live=1',
      );
    });

    test('live jar Cookie key wins over task headers', () {
      expect(
        NativeDownloadClient.cookieHeaderFrom(
          headers: {'Cookie': 'stale=1'},
          providerCookies: {'Cookie': 'cf_clearance=abc'},
        ),
        'cf_clearance=abc',
      );
    });

    test('flattens name=value jar maps', () {
      expect(
        NativeDownloadClient.cookieHeaderFrom(
          providerCookies: {'cf_clearance': 'abc', 'session': '1'},
        ),
        'cf_clearance=abc; session=1',
      );
    });

    test('falls back to task headers', () {
      expect(
        NativeDownloadClient.cookieHeaderFrom(
          headers: {'Cookie': 'from-enqueue=1'},
        ),
        'from-enqueue=1',
      );
    });
  });
}
