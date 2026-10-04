import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/torrent_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Adaptive Retry Chunk Count Calculation', () {
    test('standard 8 chunks: reduces to 4, 2, then 1 on 3rd attempt', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 8), equals(8));
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 8), equals(4));
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 8), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 8), equals(1));
      expect(DownloadQueue.getEffectiveChunksForAttempt(4, 8), equals(1));
    });

    test('16 chunks: reduces to 8, 4, then 1 on 3rd attempt', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 16), equals(16));
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 16), equals(8));
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 16), equals(4));
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 16), equals(1));
    });

    test('4 chunks: reduces to 2, 2, then 1 on 3rd attempt', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 4), equals(4));
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 4), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 4), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 4), equals(1));
    });

    test('2 chunks: stays 2, 2, then 1 on 3rd attempt', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 2), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 2), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 2), equals(2));
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 2), equals(1));
    });

    test('1 chunk: always 1', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 1), equals(1));
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 1), equals(1));
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 1), equals(1));
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 1), equals(1));
    });
  });

  group('Torrent Engine Pre-Check', () {
    test('isNativeEngineAvailable and checkNativeEngineAvailability methods exist and return safely', () async {
      // In unit test environment without native libtorrent, it returns false / error string
      final available = await TorrentDownloader.isNativeEngineAvailable();
      expect(available, isA<bool>());

      final reason = await TorrentDownloader.checkNativeEngineAvailability();
      if (!available) {
        expect(reason, isNotNull);
        expect(reason, contains('BitTorrent engine'));
      } else {
        expect(reason, isNull);
      }
    });
  });
}
