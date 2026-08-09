// Regression (2026-08-09, 2da14d9): the per-task progress notifier must fire
// when a live tick changes the values the queue card renders.
//
// Pre-fix: `_emitTask`'s no-op guard compared `notifier.value` fields against
// the emitted task's fields — but the queue and engines mutate the SAME
// DownloadTask instance in place, so prev and task were the same object and
// every comparison was "unchanged". The ValueNotifier never fired, freezing
// the queue card's progress bar / speed / status at their initial values
// until the task object was replaced at completion.
import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('per-task notifier fires on in-place progress mutation (P1b)',
      () async {
    final queue = DownloadQueue();
    final task = DownloadTask(
      id: 't1',
      url: 'https://example.com/video.mp4',
      savePath: '/tmp/video.mp4',
      tempDir: '/tmp/temp_t1',
      state: DownloadState.downloading,
      totalBytes: 1000,
    );

    // First emit lazily creates the notifier (no notification yet).
    queue.emitTask(task);
    final notifier = queue.taskNotifierFor('t1');
    expect(notifier, isNotNull, reason: 'notifier is created on first emit');

    var fires = 0;
    notifier!.addListener(() => fires++);

    // Live tick: the engine mutates the SAME instance in place…
    task.downloadedBytes = 400;
    task.speed = 2000;
    queue.emitTask(task);
    expect(fires, 1,
        reason: 'rendered fields changed — the notifier must fire');
    expect(notifier.value.downloadedBytes, 400);
    expect(notifier.value.speed, 2000);

    // Every emit fires — even a no-op tick — so the card tracks every
    // speed tick (the live section is cheap to rebuild; the top-left
    // header already updates per tick).
    queue.emitTask(task);
    expect(fires, 2, reason: 'no-op ticks fire too (unconditional push)');

    // Another real change fires again.
    task.downloadedBytes = 900;
    task.statusMessage = 'merging';
    queue.emitTask(task);
    expect(fires, 3, reason: 'status change must fire the notifier');
    expect(notifier.value.statusMessage, 'merging');

    await queue.dispose();
  });
}
