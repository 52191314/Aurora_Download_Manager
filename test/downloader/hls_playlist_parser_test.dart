import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/downloader/hls_playlist_parser.dart';

void main() {
  group('HlsPlaylistParser Hardening Tests', () {
    test('parses standard HLS playlist', () {
      const body = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:10
#EXTINF:10.0,
segment1.ts
#EXTINF:5.0,
segment2.ts''';

      final playlist = HlsPlaylistParser.parse(body, Uri.parse('https://example.com/playlist.m3u8'));
      expect(playlist.segments.length, equals(2));
      expect(playlist.mediaSequence, equals(10));
      expect(playlist.segments.first.durationSeconds, equals(10.0));
    });

    test('handles malformed tags without RangeError crash', () {
      const body = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE
#EXTINF
segment1.ts
#EXT-X-BYTERANGE
segment2.ts''';

      final playlist = HlsPlaylistParser.parse(body, Uri.parse('https://example.com/playlist.m3u8'));
      expect(playlist.segments.length, equals(2));
      expect(playlist.mediaSequence, equals(0));
    });
  });
}
