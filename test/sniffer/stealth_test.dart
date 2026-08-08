import 'package:aurora_downloader/sniffer/stealth_metadata_channel.dart';
import 'package:aurora_downloader/sniffer/sniffer_url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Stealth Metadata Extraction', () {
    test('extracts major and full Chrome version correctly', () {
      const sampleUa =
          'Mozilla/5.0 (Linux; Android 14; Pixel 7 Build/UQ1A.240105.004; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36';

      final major = StealthMetadataChannel.extractChromeVersion(sampleUa);
      final full = StealthMetadataChannel.extractFullChromeVersion(sampleUa);

      expect(major, '131');
      expect(full, '131.0.6778.135');
    });

    test('returns null for missing user agent', () {
      expect(StealthMetadataChannel.extractChromeVersion(null), isNull);
      expect(StealthMetadataChannel.extractFullChromeVersion(null), isNull);
    });

    test('stripWebViewUaMarkers removes WebView tags while preserving Chrome version', () {
      const sampleUa =
          'Mozilla/5.0 (Linux; Android 14; Pixel 7 Build/UQ1A.240105.004; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36';

      final cleaned = stripWebViewUaMarkers(sampleUa);

      expect(cleaned, isNot(contains('wv')));
      expect(cleaned, isNot(contains('Version/4.0')));
      expect(cleaned, contains('Chrome/131.0.6778.135'));
    });
  });
}
