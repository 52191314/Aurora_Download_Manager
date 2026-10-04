import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/downloader/downloader.dart';

void main() {
  group('getEffectiveChunksForAttempt', () {
    test('keeps full chunks on first attempt', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 8), 8);
    });

    test('halves on first retry', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(1, 8), 4);
    });

    test('quarters on second retry', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 8), 2);
    });

    test('falls back to one chunk on third retry', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(3, 8), 1);
      expect(DownloadQueue.getEffectiveChunksForAttempt(9, 32), 1);
    });

    test('never goes below 1', () {
      expect(DownloadQueue.getEffectiveChunksForAttempt(0, 1), 1);
      expect(DownloadQueue.getEffectiveChunksForAttempt(2, 1), 1);
    });
  });
}
