import 'package:aurora_downloader/downloader/models.dart';
import 'package:aurora_downloader/downloader/torrent_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task(String url) => DownloadTask(
      id: 't1',
      url: url,
      savePath: 'C:/tmp/out.bin',
      tempDir: 'C:/tmp/t1',
    );

void main() {
  test('magnet without native engine hard-fails (no zero-fill mock)', () async {
    final task = _task('magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567');
    final downloader = TorrentDownloader(
      task: task,
      useNativeEngine: false,
    );

    await downloader.start();

    expect(task.state, DownloadState.failed);
    expect(task.failureReason, DownloadFailure.nativeEngineUnavailable);
    expect(task.errorMessage, contains('Magnet'));
    expect(task.chunks, isEmpty);
  });

  test('.torrent without native engine hard-fails', () async {
    final task = _task('https://example.com/file.torrent');
    final downloader = TorrentDownloader(
      task: task,
      useNativeEngine: false,
    );

    await downloader.start();

    expect(task.state, DownloadState.failed);
    expect(task.failureReason, DownloadFailure.nativeEngineUnavailable);
    expect(task.errorMessage, contains('Torrent'));
  });

  test('default useNativeEngine is true', () {
    final task = _task('magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567');
    final downloader = TorrentDownloader(task: task);
    expect(downloader.useNativeEngine, isTrue);
  });
}
