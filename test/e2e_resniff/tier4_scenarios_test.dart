import 'dart:io';
import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart' hide ResniffSession;
import 'package:flutter_test/flutter_test.dart' hide StreamMatcher;

import 'mock_resniff_server.dart';
import 'resniff_test_contracts.dart';
import 'simulated_resniffer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late MockResniffServer server;

  setUp(() async {
    server = MockResniffServer();
    await server.start();
  });

  tearDown(() async {
    await server.dispose();
  });

  group('Tier 4: Scenario S1 - HLS 403 Auto-Revival & Continuous Segment Resumption', () {
    test('S1: Full workflow from 403 token expiry to auto-resniff, playlist refresh, and queue resume', () async {
      final tmp = await Directory.systemTemp.createTemp('s1_hls_revival');
      final taskId = 's1_hls_task';

      // 1. Initial task in downloading state
      final task = DownloadTask(
        id: taskId,
        url: '${server.baseUrl}/master.m3u8?token=expired_tok_001',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        savePath: '${tmp.path}/movie.mp4',
        tempDir: '${tmp.path}/temp_s1',
        completedParts: 14,
        totalParts: 50,
        state: DownloadState.downloading,
      );

      final queue = DownloadQueue(autoRetry: true, retryLimit: 3);
      queue.addTask(task);

      // 2. Server updates source page with fresh token
      server.htmlMediaCandidates = [
        '${server.baseUrl}/master.m3u8?token=${server.freshToken}',
      ];

      // 3. 403 trigger simulates token expiration handler
      final resniffer = SimulatedHeadlessResniffer();
      final resniffResult = await SimulatedTokenRefreshService.autoRefresh(
        taskId: task.id,
        sourcePageUrl: task.sourcePageUrl,
        originalUrl: task.url,
        allowed: true,
        resniffer: resniffer,
      );

      expect(resniffResult, isA<ResniffSuccess>());
      final freshMediaUrl = (resniffResult as ResniffSuccess).url;

      // 4. Update task from donor with fresh URL
      final donor = DownloadTask(
        id: 'donor_$taskId',
        url: freshMediaUrl,
        savePath: task.savePath,
        tempDir: task.tempDir,
      );

      await queue.updateTaskFromDonor(taskId, donor, wipeOnUrlChange: false);

      // 5. Verification: Task is active with fresh token, progress preserved, error cleared
      final updatedTask = queue.getTask(taskId);
      expect(updatedTask, isNotNull);
      expect(updatedTask!.url, contains(server.freshToken!));
      expect(updatedTask.completedParts, 14);
      expect(updatedTask.totalParts, 50);
      expect(updatedTask.errorMessage, isNull);
      expect(updatedTask.failureReason, isNull);
      expect(updatedTask.state, isNot(DownloadState.failed));

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 4: Scenario S2 - WAF Turnstile Challenge -> Browser Tab Fallback Recovery', () {
    test('S2: Headless Turnstile detection transitions to interactive tab and donor reattachment', () async {
      final tmp = await Directory.systemTemp.createTemp('s2_waf_fallback');
      final taskId = 's2_waf_task';

      // 1. Task fails due to Cloudflare challenge
      final task = DownloadTask(
        id: taskId,
        url: '${server.baseUrl}/secure/stream.m3u8?token=old',
        sourcePageUrl: '${server.baseUrl}/cloudflare_video.html',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp_s2',
        state: DownloadState.failed,
        errorMessage: 'HTTP 403 Forbidden: Cloudflare challenge required',
        failureReason: DownloadFailure.httpForbidden,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      // 2. Headless resniff encounters Turnstile
      server.simulateTurnstileChallenge = true;
      final resniffer = SimulatedHeadlessResniffer();
      final resniffResult = await resniffer.resniff(
        task.sourcePageUrl!,
        mustMatchPathOf: task.url,
      );

      expect(resniffResult, isA<ResniffChallengeDetected>());
      expect(resniffResult.isActionable, isTrue);

      // 3. UI enters primed resniff mode
      queue.resniffPendingTaskId = taskId;
      final session = ResniffSession(
        taskId: taskId,
        taskName: 'Protected Video',
        originalUrl: task.url,
        sourcePageUrl: task.sourcePageUrl!,
      );

      // 4. User solves challenge in interactive browser; sniffer captures stream with cf_clearance
      final capturedMediaUrl = '${server.baseUrl}/secure/stream.m3u8?token=${server.freshToken}&cf_clearance=valid_cf_clearance_123';
      expect(session.matchesCandidate(capturedMediaUrl), isTrue);

      final donor = DownloadTask(
        id: 'browser_captured_donor',
        url: capturedMediaUrl,
        savePath: task.savePath,
        tempDir: task.tempDir,
        headers: {'Cookie': 'cf_clearance=valid_cf_clearance_123'},
      );

      // 5. Update task from interactive donor
      await queue.updateTaskFromDonor(taskId, donor);

      final revived = queue.getTask(taskId);
      expect(revived!.url, capturedMediaUrl);
      expect(revived.headers?['Cookie'], contains('cf_clearance'));
      expect(revived.errorMessage, isNull);
      expect(revived.failureReason, isNull);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 4: Scenario S3 - Direct MP4 CDN Token Expiry & Byte Offset Resume', () {
    test('S3: MP4 multi-chunk task updates expired CDN link and preserves downloaded chunks', () async {
      final tmp = await Directory.systemTemp.createTemp('s3_mp4_resume');
      final taskId = 's3_mp4_task';

      // 1. Task with 2 completed chunks and 2 remaining chunks
      final chunks = [
        DownloadChunk(index: 0, start: 0, end: 10000, bytesDownloaded: 10001, isCompleted: true),
        DownloadChunk(index: 1, start: 10001, end: 20000, bytesDownloaded: 10000, isCompleted: true),
        DownloadChunk(index: 2, start: 20001, end: 30000, bytesDownloaded: 0, isCompleted: false),
        DownloadChunk(index: 3, start: 30001, end: 40000, bytesDownloaded: 0, isCompleted: false),
      ];

      final task = DownloadTask(
        id: taskId,
        url: '${server.baseUrl}/downloads/movie.mp4?sig=expired_sig_111',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        savePath: '${tmp.path}/movie.mp4',
        tempDir: '${tmp.path}/temp_s3',
        totalBytes: 40001,
        downloadedBytes: 20001,
        chunks: chunks,
        state: DownloadState.failed,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      // 2. Server provides refreshed signed URL
      server.htmlMediaCandidates = [
        '${server.baseUrl}/downloads/movie.mp4?sig=fresh_sig_999',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        task.sourcePageUrl!,
        mustMatchPathOf: task.url,
      );

      expect(result, isA<ResniffSuccess>());
      final freshUrl = (result as ResniffSuccess).url;

      // 3. Update task with fresh signature without wiping completed byte chunks
      final donor = DownloadTask(
        id: 'donor_$taskId',
        url: freshUrl,
        savePath: task.savePath,
        tempDir: task.tempDir,
      );

      await queue.updateTaskFromDonor(taskId, donor, wipeOnUrlChange: false);

      final revived = queue.getTask(taskId);
      expect(revived!.url, contains('sig=fresh_sig_999'));
      expect(revived.chunks.where((c) => c.isCompleted).length, 2);
      expect(revived.progressPercent, 50);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 4: Scenario S4 - Dead Link (HTTP 410) Honest Diagnostic & Prevention of False Success', () {
    test('S4: Deleted media source produces clear 410 error and never claims link is valid', () async {
      server.forcedStatusCode = 410;
      final resniffer = SimulatedHeadlessResniffer();

      final result = await resniffer.resniff(
        '${server.baseUrl}/deleted_video.html',
        mustMatchPathOf: '${server.baseUrl}/stream.m3u8',
      );

      expect(result, isA<ResniffSourceUnavailable>());
      final unavailable = result as ResniffSourceUnavailable;
      expect(unavailable.statusCode, 410);
      expect(unavailable.userFacingMessage, contains('gone permanently (410)'));
      expect(unavailable.userFacingMessage, isNot(contains('Link is still valid')));
      expect(unavailable.userFacingMessage, isNot(contains('No update needed')));
    });
  });

  group('Tier 4: Scenario S5 - Click-to-Play Video Stream Wake Gestures & Queue Injection', () {
    test('S5: Interactive player wake gesture triggers media manifest injection and revives task', () async {
      final tmp = await Directory.systemTemp.createTemp('s5_click_to_play');
      final taskId = 's5_wake_task';

      final task = DownloadTask(
        id: taskId,
        url: '${server.baseUrl}/hls/stream.m3u8?token=old',
        sourcePageUrl: '${server.baseUrl}/interactive_player.html',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp_s5',
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      // Page with manifest discovered after wake gesture
      server.htmlMediaCandidates = ['${server.baseUrl}/hls/stream.m3u8?token=${server.freshToken}'];
      final resniffer = SimulatedHeadlessResniffer();

      final result = await resniffer.resniff(
        task.sourcePageUrl!,
        mustMatchPathOf: task.url,
      );

      expect(result, isA<ResniffSuccess>());
      final freshUrl = (result as ResniffSuccess).url;

      final donor = DownloadTask(
        id: 'donor_wake',
        url: freshUrl,
        savePath: task.savePath,
        tempDir: task.tempDir,
      );

      await queue.updateTaskFromDonor(taskId, donor);

      final updated = queue.getTask(taskId);
      expect(updated!.url, contains(server.freshToken!));

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 4: Scenario S6 - Queue Donor Interception Lifecycle from Browser Sniffer', () {
    test('S6: Primed tab intercepts refreshed stream and updates waiting task without user confusion', () async {
      final tmp = await Directory.systemTemp.createTemp('s6_donor_interception');
      final taskId = 's6_waiting_task';

      final task = DownloadTask(
        id: taskId,
        url: '${server.baseUrl}/video/720p.m3u8?token=old',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        savePath: '${tmp.path}/video_720p.mp4',
        tempDir: '${tmp.path}/temp_s6',
        state: DownloadState.failed,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);
      queue.resniffPendingTaskId = taskId;

      // Resniff callback handler
      queue.onResniffDuplicate = (targetId, intercepted) async {
        await queue.updateTaskFromDonor(targetId, intercepted);
      };

      // Sniffer in browser captures updated stream with new token and audio track
      final sniffedTask = DownloadTask(
        id: 'sniffed_in_tab',
        url: '${server.baseUrl}/video/720p.m3u8?token=${server.freshToken}',
        savePath: '${tmp.path}/video_720p.mp4',
        tempDir: '${tmp.path}/temp_sniffed',
        headers: {'User-Agent': 'CustomBrowserUA'},
      );

      queue.addTask(sniffedTask);

      final activeTask = queue.getTask(taskId);
      expect(activeTask!.url, contains(server.freshToken!));
      expect(activeTask.headers?['User-Agent'], 'CustomBrowserUA');
      expect(queue.allTasks.length, 1);
      expect(activeTask.errorMessage, isNull);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });
}
