import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/sniffer/browser_library.dart';
import 'package:aurora_downloader/sniffer/library_transfer.dart';
import 'package:aurora_downloader/sniffer/models/sniffed_media.dart';
import 'package:aurora_downloader/sniffer/playback_quality.dart';
import 'package:aurora_downloader/sniffer/sheets/library_transfer_sheets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyImport imports favorites', () async {
    BrowserLibrary? saved;
    final queue = DownloadQueue();
    final library = BrowserLibrary.empty();

    final summary = await LibraryTransfer.applyImport(
      decoded: {
        'favorites': [
          {
            'id': 'f1',
            'title': 'Example',
            'url': 'https://example.com',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
        'folders': [],
      },
      options: const LibraryImportOptions(favorites: true),
      library: library,
      downloadQueue: queue,
      baseDir: r'C:\tmp\base',
      baseTemp: r'C:\tmp\temp',
      saveLibrary: (lib) async {
        saved = lib;
      },
    );

    expect(summary.favoritesCount, 1);
    expect(saved?.favorites.length, 1);
    expect(saved?.favorites.first.url, 'https://example.com');
    expect(summary.snackMessage(), contains('1 favorites'));
  });

  test('sortQualityMedia orders by height desc', () {
    SniffedMedia m(String url, int h) => SniffedMedia(
          url: url,
          name: url,
          type: MediaType.video,
          sniffedAt: DateTime.now(),
          height: h,
        );
    final sorted = sortQualityMedia([m('a', 480), m('b', 1080), m('c', 720)]);
    expect(sorted.map((e) => e.height).toList(), [1080, 720, 480]);
  });

  test('pickStartQuality prefers matching url', () {
    final a = SniffedMedia(
      url: 'https://x/a.m3u8',
      name: 'a',
      type: MediaType.playlist,
      sniffedAt: DateTime.now(),
      height: 720,
    );
    final b = SniffedMedia(
      url: 'https://x/b.m3u8',
      name: 'b',
      type: MediaType.playlist,
      sniffedAt: DateTime.now(),
      height: 1080,
    );
    expect(pickStartQuality(a, [b, a]).url, a.url);
  });
}
