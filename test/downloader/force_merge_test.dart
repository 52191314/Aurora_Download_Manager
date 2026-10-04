import 'dart:io';
import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('force_merge_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('aurora_downloader/public_downloads'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'remuxTsToMp4') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          final destPath = args['destPath'] as String;
          // Simulate successful remux by creating the destination file
          await File(destPath).writeAsString('mock mp4 content');
          return {'success': true, 'error': null};
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('aurora_downloader/public_downloads'),
      null,
    );
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('HLS TS task with .m3u8 savePath is merged, remuxed, and assigned .mp4 extension', () async {
    final queue = DownloadQueue();
    final taskId = 'hls_ts_task';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    // Create mock TS segment files
    await File('${taskTemp.path}/segment_000000.ts').writeAsBytes([0x47, 0x01, 0x02, 0x03]);
    await File('${taskTemp.path}/segment_000001.ts').writeAsBytes([0x47, 0x04, 0x05, 0x06]);

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/video/master.m3u8',
      savePath: '${tempDir.path}/my_video.m3u8',
      tempDir: taskTemp.path,
      state: DownloadState.failed,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isTrue);

    final updated = queue.getTask(taskId);
    expect(updated, isNotNull);
    expect(updated!.state, DownloadState.completed);
    expect(updated.savePath, '${tempDir.path}/my_video.mp4');
    expect(await File('${tempDir.path}/my_video.mp4').exists(), isTrue);
    expect(await File('${tempDir.path}/my_video.ts').exists(), isFalse);
    expect(await File('${tempDir.path}/my_video.m3u8').exists(), isFalse);

    await queue.dispose();
  });

  test('HLS TS task with .ts savePath is remuxed to .mp4', () async {
    final queue = DownloadQueue();
    final taskId = 'hls_ts_direct_path';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    await File('${taskTemp.path}/segment_000000.ts').writeAsBytes([0x47, 0x01, 0x02, 0x03]);

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/video/master.m3u8',
      savePath: '${tempDir.path}/direct_video.ts',
      tempDir: taskTemp.path,
      state: DownloadState.paused,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isTrue);

    final updated = queue.getTask(taskId);
    expect(updated!.state, DownloadState.completed);
    expect(updated.savePath, '${tempDir.path}/direct_video.mp4');
    expect(await File('${tempDir.path}/direct_video.mp4').exists(), isTrue);

    await queue.dispose();
  });

  test('HLS fMP4 task with .m3u8 savePath is merged directly to .mp4 without .m3u8 extension', () async {
    final queue = DownloadQueue();
    final taskId = 'hls_fmp4_task';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    // fMP4 segments (m4s)
    await File('${taskTemp.path}/segment_000000.mp4').writeAsBytes([0x00, 0x00, 0x00, 0x20]);
    await File('${taskTemp.path}/segment_000001.m4s').writeAsBytes([0x00, 0x00, 0x00, 0x40]);

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/video/manifest.m3u8',
      savePath: '${tempDir.path}/fmp4_stream.m3u8',
      tempDir: taskTemp.path,
      state: DownloadState.failed,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isTrue);

    final updated = queue.getTask(taskId);
    expect(updated!.state, DownloadState.completed);
    expect(updated.savePath, '${tempDir.path}/fmp4_stream.mp4');
    expect(await File('${tempDir.path}/fmp4_stream.mp4').exists(), isTrue);
    expect(await File('${tempDir.path}/fmp4_stream.m3u8').exists(), isFalse);

    await queue.dispose();
  });

  test('Direct TS chunk download is merged and remuxed to .mp4', () async {
    final queue = DownloadQueue();
    final taskId = 'direct_ts_chunks';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    await File('${taskTemp.path}/part_0').writeAsBytes([0x47, 0x10, 0x20, 0x30]);
    await File('${taskTemp.path}/part_1').writeAsBytes([0x47, 0x40, 0x50, 0x60]);

    final List<DownloadChunk> chunks = [
      DownloadChunk(index: 0, start: 0, end: 3),
      DownloadChunk(index: 1, start: 4, end: 7),
    ];

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/raw_stream.ts',
      savePath: '${tempDir.path}/raw_stream.ts',
      tempDir: taskTemp.path,
      chunks: chunks,
      state: DownloadState.failed,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isTrue);

    final updated = queue.getTask(taskId);
    expect(updated!.state, DownloadState.completed);
    expect(updated.savePath, '${tempDir.path}/raw_stream.mp4');
    expect(await File('${tempDir.path}/raw_stream.mp4').exists(), isTrue);

    await queue.dispose();
  });

  test('TS task retains .ts fallback if native remux fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('aurora_downloader/public_downloads'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'remuxTsToMp4') {
          return {'success': false, 'error': 'Unsupported audio track'};
        }
        return null;
      },
    );

    final queue = DownloadQueue();
    final taskId = 'hls_remux_fail';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    await File('${taskTemp.path}/segment_000000.ts').writeAsBytes([0x47, 0x01, 0x02]);

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/video/master.m3u8',
      savePath: '${tempDir.path}/fallback_video.m3u8',
      tempDir: taskTemp.path,
      state: DownloadState.failed,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isTrue);

    final updated = queue.getTask(taskId);
    expect(updated!.state, DownloadState.completed);
    expect(updated.savePath, '${tempDir.path}/fallback_video.ts');
    expect(await File('${tempDir.path}/fallback_video.ts').exists(), isTrue);
    expect(updated.errorMessage, contains("Couldn't convert to .mp4"));

    await queue.dispose();
  });

  test('Force merge with no chunks fails cleanly with mergeFailed', () async {
    final queue = DownloadQueue();
    final taskId = 'empty_task';
    final taskTemp = Directory('${tempDir.path}/temp_$taskId');
    await taskTemp.create(recursive: true);

    final task = DownloadTask(
      id: taskId,
      url: 'https://example.com/video/master.m3u8',
      savePath: '${tempDir.path}/empty.m3u8',
      tempDir: taskTemp.path,
      state: DownloadState.failed,
    );

    queue.addTask(task);

    final success = await queue.forceMergeTask(taskId);
    expect(success, isFalse);

    final updated = queue.getTask(taskId);
    expect(updated!.state, DownloadState.failed);
    expect(updated.failureReason, DownloadFailure.mergeFailed);

    await queue.dispose();
  });
}
