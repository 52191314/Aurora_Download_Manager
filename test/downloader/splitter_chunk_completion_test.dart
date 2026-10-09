// Regression: direct downloads failing as "Download interrupted: not all
// chunks completed" (DownloadFailure.chunkIncomplete) even though every chunk
// request had succeeded, and the retries that followed failing the same way.
//
// The chunk paths below used to return without marking the chunk complete and
// without raising an error:
//   - the native (OkHttp) path for a download of unknown length,
//   - the native path when the body ended short of the chunk,
//   - the Dart path when the server closed the body early but cleanly.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_downloader/downloader/download_splitter.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:aurora_downloader/platform/native_download_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _nativeChannel = MethodChannel('aurora_downloader/native_download');

Uint8List _payload(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + 7) % 251));

/// Parses `bytes=a-b` / `bytes=a-` into an inclusive (start, end) pair.
(int, int)? _parseRange(String? header, int total) {
  if (header == null || header.isEmpty) return null;
  final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header);
  if (m == null) return null;
  final start = int.parse(m.group(1)!);
  final end = m.group(2)!.isEmpty ? total - 1 : int.parse(m.group(2)!);
  return (start, end);
}

http.StreamedResponse _partial(Uint8List data, int start, int end) {
  return http.StreamedResponse(
    Stream.value(data.sublist(start, end + 1)),
    206,
    contentLength: end - start + 1,
    headers: {'content-range': 'bytes $start-$end/${data.length}'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;
  late DownloadTask task;
  DownloadSplitter? splitter;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('splitter_completion');
    task = DownloadTask(
      id: 'chunk_completion',
      url: 'https://cdn.example.com/file.bin',
      savePath: '${tempDir.path}/file.bin',
      tempDir: '${tempDir.path}/temp',
    );
  });

  tearDown(() async {
    NativeDownloadClient.debugAssumeAndroid = false;
    messenger.setMockMethodCallHandler(_nativeChannel, null);
    await splitter?.dispose();
    splitter = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Stands in for the Kotlin NativeDownloadEngine: appends on 206,
  /// overwrites otherwise, exactly as the real one does.
  void mockNativeEngine(
    FutureOr<(int status, List<int> body)> Function(String rangeHeader) serve,
  ) {
    NativeDownloadClient.debugAssumeAndroid = true;
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      if (call.method != 'downloadChunk') return true;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final (status, body) = await serve(args['rangeHeader'] as String);
      final file = File(args['filePath'] as String);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        body,
        mode: status == 206 ? FileMode.append : FileMode.write,
        flush: true,
      );
      return <String, dynamic>{
        'statusCode': status,
        'bytesWritten': body.length,
        'downloadId': args['downloadId'],
      };
    });
  }

  test('unknown-length download completes on the native path', () async {
    final data = _payload(120000);
    final nativeRanges = <String>[];
    mockNativeEngine((rangeHeader) {
      nativeRanges.add(rangeHeader);
      return (200, data);
    });

    // No Content-Length anywhere, so the size stays unknown and the task
    // gets a single open-ended chunk.
    var dartBodyRequests = 0;
    final client = MockClient.streaming((request, _) async {
      if (request.method == 'HEAD' || request.headers['Range'] == 'bytes=0-0') {
        return http.StreamedResponse(const Stream.empty(), 200);
      }
      dartBodyRequests++;
      return http.StreamedResponse(const Stream.empty(), 500);
    });

    splitter = DownloadSplitter(task: task, client: client, numChunks: 8);
    await splitter!.start();

    expect(task.state, DownloadState.completed);
    expect(task.failureReason, isNull);
    expect(await File(task.savePath).readAsBytes(), data);
    expect(nativeRanges, ['']);
    expect(dartBodyRequests, 0, reason: 'the native result must be accepted');
  });

  test('a short native body is resumed from the bytes on disk', () async {
    final data = _payload(300000);
    var shortServed = false;
    mockNativeEngine((rangeHeader) {
      final (start, end) = _parseRange(rangeHeader, data.length)!;
      if (start == 0 && !shortServed) {
        shortServed = true;
        return (206, data.sublist(0, 1000));
      }
      return (206, data.sublist(start, end + 1));
    });

    final dartRanges = <String>[];
    final client = MockClient.streaming((request, _) async {
      if (request.method == 'HEAD') {
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {
            'content-length': '${data.length}',
            'accept-ranges': 'bytes',
          },
        );
      }
      final header = request.headers['Range']!;
      dartRanges.add(header);
      final (start, end) = _parseRange(header, data.length)!;
      return _partial(data, start, end);
    });

    splitter = DownloadSplitter(task: task, client: client, numChunks: 2);
    await splitter!.start();

    expect(task.state, DownloadState.completed);
    expect(await File(task.savePath).readAsBytes(), data);
    // Resumed after the 1000 bytes the native attempt wrote — not from the
    // start of the chunk, which would duplicate them.
    expect(dartRanges, ['bytes=1000-149999']);
  });

  test('a body the server ends early is reconnected and resumed', () async {
    final data = _payload(300000);
    var shortServed = false;
    final ranges = <String>[];
    final client = MockClient.streaming((request, _) async {
      if (request.method == 'HEAD') {
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {
            'content-length': '${data.length}',
            'accept-ranges': 'bytes',
          },
        );
      }
      final header = request.headers['Range']!;
      ranges.add(header);
      final (start, end) = _parseRange(header, data.length)!;
      if (start == 0 && !shortServed) {
        shortServed = true;
        // Clean end of stream halfway through the chunk: no error raised.
        return http.StreamedResponse(
          Stream.value(data.sublist(0, 75000)),
          206,
          headers: {'content-range': 'bytes $start-$end/${data.length}'},
        );
      }
      return _partial(data, start, end);
    });

    splitter = DownloadSplitter(task: task, client: client, numChunks: 2);
    await splitter!.start();

    expect(task.state, DownloadState.completed);
    expect(await File(task.savePath).readAsBytes(), data);
    expect(ranges, contains('bytes=75000-149999'));
  });

  test('single-connection reconnect restarts the file when the server '
      'cannot resume', () async {
    final data = _payload(150000);
    var bodyRequests = 0;
    String? reconnectRange;
    final client = MockClient.streaming((request, _) async {
      if (request.method == 'HEAD') {
        // Size is known, but the server does not advertise range support.
        return http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'content-length': '${data.length}'},
        );
      }
      if (request.headers['Range'] == 'bytes=0-0') {
        // Range probe answered with the whole file: no range support.
        return http.StreamedResponse(
          Stream.value(data),
          200,
          contentLength: data.length,
          headers: {'content-length': '${data.length}'},
        );
      }
      bodyRequests++;
      if (bodyRequests == 1) {
        Stream<List<int>> dropped() async* {
          yield data.sublist(0, 50000);
          throw const SocketException('Connection reset by peer');
        }

        return http.StreamedResponse(dropped(), 200);
      }
      reconnectRange = request.headers['Range'];
      return http.StreamedResponse(Stream.value(data), 200);
    });

    splitter = DownloadSplitter(task: task, client: client, numChunks: 1);
    await splitter!.start();

    expect(task.state, DownloadState.completed);
    expect(reconnectRange, 'bytes=50000-');
    // The 200 answer carries the whole file again; appending it after the
    // 50000 bytes already written would corrupt the result.
    expect(await File(task.savePath).readAsBytes(), data);
  });
}
