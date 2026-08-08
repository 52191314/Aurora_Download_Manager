// Regression: torrent engine tasks must not be treated like HTTP splitter
// tasks. The engine manages its own save dir, so:
//  1. auto-classification must NOT rewrite task.savePath (it made
//     uniquePath append a " (1)" collision suffix once the engine's dir
//     existed, and publishing then failed with
//     "Couldn't publish — completed file not found");
//  2. force merge must be refused (there are never per-chunk files in
//     tempDir to merge — the engine writes pieces straight to its save dir).
import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _magnet =
    'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567';

void main() {
  // The native engine is unavailable in unit tests, so the magnet task
  // hard-fails asynchronously; let that settle before asserting on state.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('auto-classification leaves torrent savePath untouched', () async {
    final queue = DownloadQueue();
    final task = DownloadTask(
      id: 't1',
      url: _magnet,
      savePath: 'C:/completed/downloaded_file',
      tempDir: 'C:/tmp/t1',
    );

    queue.addTask(task);

    // No category folder ("Other/...") and no " (1)" suffix injected.
    expect(task.savePath, 'C:/completed/downloaded_file');
    await settle();
    await queue.dispose();
  });

  test('forceMergeTask refuses native torrent tasks with a clear message',
      () async {
    final queue = DownloadQueue();
    final task = DownloadTask(
      id: 't2',
      url: 'https://example.com/movie.torrent',
      savePath: 'C:/completed/movie',
      tempDir: 'C:/tmp/t2',
    );

    queue.addTask(task);
    await settle();

    final ok = await queue.forceMergeTask('t2');
    expect(ok, isFalse);

    // Read the live task from the queue (the async engine failure may have
    // replaced the instance we constructed).
    final live = queue.allTasks.firstWhere((t) => t.id == 't2');
    expect(live.errorMessage, contains('resume or redownload'));
    expect(live.failureReason, DownloadFailure.mergeFailed);
    await queue.dispose();
  });
}
