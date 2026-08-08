import 'package:aurora_downloader/sniffer/sniffer_formatters.dart';
import 'package:aurora_downloader/sniffer/sniffer_url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ua profiles', () {
    test('uaForProfile returns known profiles', () {
      expect(uaForProfile('mobile'), contains('Android'));
      expect(uaForProfile('desktop_chrome'), contains('Windows'));
      expect(uaForProfile('unknown-key'), snifferMobileUserAgent);
    });
  });

  group('normalizeHeadersForUrl surrit', () {
    test('adds Origin and fixes missav.com referer', () {
      final headers = <String, String>{
        'Referer': 'https://missav.com/dm1/foo',
      };
      normalizeHeadersForUrl(
        headers,
        'https://surrit.com/playlist.m3u8',
      );
      expect(headers['Referer'], contains('missav.ws'));
      expect(headers['Origin'], 'https://missav.ws');
    });

    test('keeps surrit referer when already set', () {
      final headers = <String, String>{
        'Referer': 'https://surrit.com/embed/xyz',
      };
      normalizeHeadersForUrl(
        headers,
        'https://surrit.com/seg.ts',
      );
      expect(headers['Referer'], 'https://surrit.com/embed/xyz');
      expect(headers['Origin'], 'https://surrit.com');
    });
  });

  group('formatters', () {
    test('formatByteSize and durationLabel', () {
      expect(formatByteSize(0), 'Unknown');
      expect(formatByteSize(1536), contains('KB'));
      expect(durationLabel(const Duration(minutes: 1, seconds: 5)), '01:05');
      expect(titleForUrl('https://example.com/a'), 'example.com');
      expect(cleanTitle('  Hello  ', null), 'Hello');
    });
  });
}
