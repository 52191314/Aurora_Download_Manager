import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task({
  required String url,
  DownloadFailure? reason,
  int downloadedBytes = 0,
}) {
  return DownloadTask(
    id: 't1',
    url: url,
    savePath: 'C:/tmp/out.bin',
    tempDir: 'C:/tmp/t1',
    downloadedBytes: downloadedBytes,
    failureReason: reason,
  );
}

void main() {
  const minBytes = 10 * 1024 * 1024;

  test('retries a fresh HTTP failure', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://cdn.example/file.mp4',
          reason: DownloadFailure.connectionReset,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isFalse,
    );
  });

  test('skips near-complete chunkIncomplete so retry cannot wipe 90%', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://cdn.example/file.mp4',
          reason: DownloadFailure.chunkIncomplete,
          downloadedBytes: minBytes,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
  });

  test('still retries chunkIncomplete with little progress', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://cdn.example/file.mp4',
          reason: DownloadFailure.chunkIncomplete,
          downloadedBytes: 1024,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isFalse,
    );
  });

  test('never auto-retries expired links or dead certificates', () {
    // Expired HLS link: token refresh already ran (or is Pro-gated) — a
    // queue-level retry re-fails identically and floods analytics.
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://vd687.okcdn.ru/video/index.m3u8?tkn=expired',
          reason: DownloadFailure.hlsTokenExpired,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
    // Broken site certificate: every retry fails the same way.
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://open.stealth.si/file.mp4',
          reason: DownloadFailure.certificateInvalid,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
  });

  test('never auto-retries magnets or torrent engine failures', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
          reason: DownloadFailure.torrentMetadataFailed,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://example.com/file.torrent',
          reason: DownloadFailure.speedStall,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
  });

  test('never auto-retries HLS circuit breaker', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://cdn.example/master.m3u8',
          reason: DownloadFailure.hlsCircuitBreaker,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
  });

  test('never auto-retries disk full', () {
    expect(
      DownloadQueue.shouldSkipAutoRetry(
        _task(
          url: 'https://cdn.example/file.mp4',
          reason: DownloadFailure.diskFull,
        ),
        minBytesBeforeFullRetry: minBytes,
      ),
      isTrue,
    );
  });
}
