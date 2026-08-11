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

  group('protocol-relative media URLs', () {
    test('extracts protocol-relative direct URL and resolves to https', () {
      const html = '''
        <html><body>
          <video src="//cdn.example.com/clips/1200.mp4"></video>
        </body></html>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(results, ['https://cdn.example.com/clips/1200.mp4']);
    });

    test('extracts protocol-relative m3u8 with query', () {
      const html = '''
        <script>var u = "//hls.example.com/live/720.m3u8?token=abc123";</script>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(
        results,
        ['https://hls.example.com/live/720.m3u8?token=abc123'],
      );
    });

    test('extracts protocol-relative JSON-escaped URL', () {
      const html = r'''
        <script>
          var config = {"url":"\/\/cdn.example.com\/clips\/1200.m3u8"};
        </script>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(results, ['https://cdn.example.com/clips/1200.m3u8']);
    });

    test('extracts escaped absolute URL with protocol-relative form unchanged', () {
      const html = r'''
        <script>
          var config = {"url":"https:\/\/cdn.example.com\/clips\/1200.mp4"};
        </script>
      ''';

      final results = NativeHtmlMediaExtractor.parseHtmlForMedia(html);
      expect(results, ['https://cdn.example.com/clips/1200.mp4']);
    });
  });
}
