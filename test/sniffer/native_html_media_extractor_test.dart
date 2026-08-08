import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/native_html_media_extractor.dart';

void main() {
  group('NativeHtmlMediaExtractor HTML Parsing', () {
    test('extracts clean m3u8 URL from xchina-style HTML snippet', () {
      const html = '''
        <!DOCTYPE html>
        <html>
        <head><title>Test</title></head>
        <body>
          <script>
            var playerUrl = 'https://video.xchina.download/m3u8/6a6bc60e4d2a3/720.m3u8?expires=1785511879&md5=OrGpbve8GxvJX8c5H1LOgQ';
          </script>
        </body>
        </html>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(results, hasLength(1));
      expect(
        results.first,
        equals(
          'https://video.xchina.download/m3u8/6a6bc60e4d2a3/720.m3u8?expires=1785511879&md5=OrGpbve8GxvJX8c5H1LOgQ',
        ),
      );
    });

    test('extracts clean JSON escaped m3u8 URL', () {
      const html = r'''
        <script>
          var config = {"url":"https:\/\/video.xchina.download\/m3u8\/6a6bc60e4d2a3\/720.m3u8?expires=1785511879&md5=OrGpbve8GxvJX8c5H1LOgQ"};
        </script>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(results, hasLength(1));
      expect(
        results.first,
        equals(
          'https://video.xchina.download/m3u8/6a6bc60e4d2a3/720.m3u8?expires=1785511879&md5=OrGpbve8GxvJX8c5H1LOgQ',
        ),
      );
    });
  });
}
