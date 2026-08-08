import 'dart:convert';

import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/premium/automation/automation_api_service.dart';
import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  // NOTE: no TestWidgetsFlutterBinding here — its fake HttpClient returns
  // 400 for every request, which would break these real-socket tests.

  group('AutomationApiService.buildEnqueueSavePath', () {
    // p.join emits platform separators (backslash on Windows); normalize so
    // assertions are platform-independent.
    String norm(String path) => path.replaceAll('\\', '/');

    test('uses the completed dir, never a /tmp placeholder', () {
      final path = norm(AutomationApiService.buildEnqueueSavePath(
        url: 'https://example.com/media/video-720p.mp4',
        completedDir: '/sdcard/Aurora/completed',
      ));
      expect(path, startsWith('/sdcard/Aurora/completed/'));
      expect(path, isNot(contains('/tmp')));
      expect(path, endsWith('.mp4'));
      expect(path, contains('video-720p'));
    });

    test('derives filename from the URL path when no label', () {
      final path = norm(AutomationApiService.buildEnqueueSavePath(
        url: 'https://cdn.example.com/clips/clip-42.mp4',
        completedDir: '/data/app/completed',
      ));
      expect(path, '/data/app/completed/clip-42.mp4');
    });

    test('uses label when provided', () {
      final path = norm(AutomationApiService.buildEnqueueSavePath(
        url: 'https://example.com/watch?id=9',
        label: 'My Custom Episode',
        completedDir: '/data/app/completed',
      ));
      expect(path, contains('My Custom Episode'));
      expect(path, isNot(contains('watch')));
    });

    test('appends a collision suffix for reserved paths', () {
      final path = norm(AutomationApiService.buildEnqueueSavePath(
        url: 'https://example.com/clip.mp4',
        completedDir: '/data/app/completed',
        reservedPaths: ['/data/app/completed/clip.mp4'],
      ));
      expect(path, '/data/app/completed/clip (1).mp4');
    });
  });

  group('AutomationApiService HTTP server', () {
    late AutomationApiService service;
    late ProEntitlement entitlement;
    late int port;
    late String token;

    Future<http.Response> call(
      String method,
      String path, {
      String? body,
      bool auth = true,
    }) {
      final uri = Uri.parse('http://127.0.0.1:$port$path');
      final headers = <String, String>{
        if (auth) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(uri, headers: headers, body: body);
        default:
          throw ArgumentError(method);
      }
    }

    setUp(() async {
      entitlement = ProEntitlement()..setDebugTier(EntitlementTier.ultra);
      service = AutomationApiService(
        proEntitlement: entitlement,
        completedDirProvider: () async => '/data/app/completed',
        tempDirProvider: () async => '/data/app/temp',
      );
      token = await service.start(bindPort: 0);
      port = service.port;
    });

    tearDown(() async {
      await service.stop();
    });

    test('rejects unauthenticated requests with 401', () async {
      final res = await call('GET', '/v1/status', auth: false);
      expect(res.statusCode, 401);
    });

    test('status returns tier JSON with a valid token', () async {
      final res = await call('GET', '/v1/status');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['tier'], 'ultra');
      expect(body['isUltra'], isTrue);
      expect(body['apiVersion'], '1.0');
    });

    test('unknown route returns 404', () async {
      final res = await call('GET', '/v1/nope');
      expect(res.statusCode, 404);
    });

    test('oversized body is rejected with 413', () async {
      final big = '{"url": "${'a' * (70 * 1024)}"}';
      final res = await call('POST', '/v1/tasks', body: big);
      expect(res.statusCode, 413);
    });

    test('malformed JSON returns 400', () async {
      final res = await call('POST', '/v1/tasks', body: 'not-json');
      expect(res.statusCode, 400);
    });

    test('missing url field returns 400', () async {
      final res = await call('POST', '/v1/tasks', body: '{"label":"x"}');
      expect(res.statusCode, 400);
    });

    test('enqueue without a queue returns 503, not a fake 201', () async {
      final res = await call(
        'POST',
        '/v1/tasks',
        body: '{"url":"https://example.com/x.mp4"}',
      );
      expect(res.statusCode, 503);
    });

    test('rate limit kicks in after many rapid requests', () async {
      var limited = false;
      for (var i = 0; i < 70; i++) {
        final res = await call('GET', '/v1/status');
        if (res.statusCode == 429) {
          limited = true;
          break;
        }
      }
      expect(limited, isTrue);
    });
  });

  group('AutomationApiService gating', () {
    test('refuses to start below Ultra', () async {
      final free = ProEntitlement()..setDebugTier(EntitlementTier.free);
      final svc = AutomationApiService(proEntitlement: free);
      expect(svc.isAllowed, isFalse);
      expect(svc.start(), throwsStateError);
    });

    test('enqueue with a real queue lands under the completed dir', () async {
      final entitlement = ProEntitlement()
        ..setDebugTier(EntitlementTier.ultra);
      final queue = DownloadQueue();
      final svc = AutomationApiService(
        proEntitlement: entitlement,
        downloadQueue: queue,
        completedDirProvider: () async => '/data/app/completed',
        tempDirProvider: () async => '/data/app/temp',
      );
      final token = await svc.start(bindPort: 0);

      // Connection-refused host: the task fails fast instead of hitting the
      // network; we only assert the enqueue path + save path.
      final res = await http.post(
        Uri.parse('http://127.0.0.1:${svc.port}/v1/tasks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"url":"http://127.0.0.1:1/never-downloaded.mp4"}',
      );
      expect(res.statusCode, 201);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['status'], 'queued');
      expect(body['savePath'], contains('/data/app/completed'));
      expect(body['savePath'], isNot(contains('/tmp')));

      expect(queue.allTasks, hasLength(1));
      expect(queue.allTasks.first.url, 'http://127.0.0.1:1/never-downloaded.mp4');

      // Duplicate enqueue is reported honestly as 409.
      final dup = await http.post(
        Uri.parse('http://127.0.0.1:${svc.port}/v1/tasks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"url":"http://127.0.0.1:1/never-downloaded.mp4"}',
      );
      expect(dup.statusCode, 409);

      await svc.stop();
      await queue.dispose();
    });
  });
}
