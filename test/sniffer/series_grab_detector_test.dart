import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/series_grab_detector.dart';

void main() {
  group('parseEpisodeLink', () {
    test('parses S01E02', () {
      final e = parseEpisodeLink('Show S01E02 1080p', 'https://x/s01e02');
      expect(e, isNotNull);
      expect(e!.season, 1);
      expect(e.episodeNumber, 2);
      expect(e.order, 1002);
    });

    test('parses EP01', () {
      final e = parseEpisodeLink('EP 01', 'https://x/ep01');
      expect(e, isNotNull);
      expect(e!.episodeNumber, 1);
      expect(e.order, 1);
    });

    test('parses CJK 第N集', () {
      final e = parseEpisodeLink('第12集', 'https://x/12');
      expect(e, isNotNull);
      expect(e!.episodeNumber, 12);
    });

    test('returns null for unrelated text', () {
      expect(parseEpisodeLink('Homepage', 'https://x/'), isNull);
    });
  });

  group('detectEpisodeLinks', () {
    test('sorts by episode order', () {
      final links = detectEpisodeLinks([
        {'url': 'https://x/e3', 'text': 'EP03'},
        {'url': 'https://x/e1', 'text': 'EP01'},
        {'url': 'https://x/e2', 'text': 'EP02'},
      ]);
      expect(links.map((e) => e.episodeNumber).toList(), [1, 2, 3]);
    });

    test('drops non-episode anchors', () {
      final links = detectEpisodeLinks([
        {'url': 'https://x/about', 'text': 'About'},
        {'url': 'https://x/e1', 'text': 'E01'},
      ]);
      expect(links.length, 1);
      expect(links.first.episodeNumber, 1);
    });
  });
}
