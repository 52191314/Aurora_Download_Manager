// Regression: a 403/401 response during a chunk download must fail the task
// with a clean error, NOT crash with "Bad state: Stream has already been
// listened to" (the pre-fix behavior — the 403 branch broke out of the retry
// loop without nulling `response`, so the consumed stream was re-listened at
// the status checks below).
import 'dart:io';

import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String url;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      if (request.method == 'HEAD') {
        request.response.statusCode = 200;
        request.response.headers.set('content-length', '100000');
        request.response.headers.set('accept-ranges', 'bytes');
        request.response.close();
        return;
      }
      // Any real GET (range probe or chunk download) is forbidden.
      request.response.statusCode = 403;
      request.response.write('Forbidden');
      request.response.close();
    });
    url = 'http://127.0.0.1:${server.port}/file.mp4';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('403 chunk response fails cleanly, no stream double-listen', () async {
    final tmp = await Directory.systemTemp.createTemp('hermes-403');
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: id,
      url: url,
      savePath: '${tmp.path}/blocked.mp4',
      tempDir: '${tmp.path}/temp_$id',
    );

    final queue = DownloadQueue(autoRetry: true, retryLimit: 2);
    queue.addTask(task);

    String? finalError;
    DownloadState? finalState;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final t = queue.getTask(id);
      if (t == null) break;
      if (t.state == DownloadState.completed ||
          t.state == DownloadState.failed) {
        finalState = t.state;
        finalError = t.errorMessage;
        break;
      }
    }

    expect(finalState, DownloadState.failed);
    expect(finalError, isNotNull);
    expect(finalError, isNot(contains('already been listened')));

    await queue.dispose();
    await tmp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
