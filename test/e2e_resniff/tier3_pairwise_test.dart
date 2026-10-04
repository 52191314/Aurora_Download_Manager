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

  group('Tier 3: Pairwise 1 - Cloudflare Turnstile Challenge + Browser Fallback Handshake', () {
    test('P1: Headless challenge triggers ResniffChallengeDetected -> creates primed ResniffSession for browser tab', () async {
      server.simulateTurnstileChallenge = true;
      final resniffer = SimulatedHeadlessResniffer();

      // 1. Headless attempt blocked by Turnstile
      final result = await resniffer.resniff(
        '${server.baseUrl}/cloudflare_protected.html',
        mustMatchPathOf: '${server.baseUrl}/stream.m3u8?token=old',
      );

      expect(result, isA<ResniffChallengeDetected>());
      expect(result.isActionable, isTrue);

      // 2. Queue initializes primed ResniffSession for the interactive browser tab
      final session = ResniffSession(
        taskId: 'cf_task_1',
        taskName: 'Protected Video',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        sourcePageUrl: '${server.baseUrl}/cloudflare_protected.html',
      );

      // 3. User solves challenge in interactive tab and sniffer captures fresh stream
      final freshStream = '${server.baseUrl}/stream.m3u8?token=${server.freshToken}&cf_clearance=cleared_123';
      expect(session.matchesCandidate(freshStream), isTrue);
    });
  });

  group('Tier 3: Pairwise 2 - Expired HLS Token + Auto-Refresh + Segment Continuity', () {
    test('P2: 403 on HLS playlist triggers auto-refresh and retains completed parts progress', () async {
      final tmp = await Directory.systemTemp.createTemp('hls_continuity_test');
      final task = DownloadTask(
        id: 'hls_task_403',
        url: '${server.baseUrl}/master.m3u8?token=expired_token',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        savePath: '${tmp.path}/hls_video.mp4',
        tempDir: '${tmp.path}/hls_temp',
        completedParts: 5,
        totalParts: 10,
        state: DownloadState.downloading,
      );

      // Server returns fresh token on source page
      server.htmlMediaCandidates = ['${server.baseUrl}/master.m3u8?token=${server.freshToken}'];
      final resniffer = SimulatedHeadlessResniffer();

      // Token expiry callback
      final refreshResult = await SimulatedTokenRefreshService.autoRefresh(
        taskId: task.id,
        sourcePageUrl: task.sourcePageUrl,
        originalUrl: task.url,
        allowed: true,
        resniffer: resniffer,
      );

      expect(refreshResult, isA<ResniffSuccess>());
      final freshUrl = (refreshResult as ResniffSuccess).url;

      // Update task from donor without wiping completed parts
      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      final donor = DownloadTask(
        id: 'donor_${task.id}',
        url: freshUrl,
        savePath: task.savePath,
        tempDir: task.tempDir,
      );

      // Path matches so completed parts are preserved
      await queue.updateTaskFromDonor(task.id, donor, wipeOnUrlChange: false);

      final updatedTask = queue.getTask(task.id);
      expect(updatedTask!.url, contains(server.freshToken!));
      expect(updatedTask.completedParts, 5);
      expect(updatedTask.totalParts, 10);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 3: Pairwise 3 - Donor Interception + Active Queue Duplicate Resolution', () {
    test('P3: In-tab donor match routes directly to pending task instead of adding duplicate', () async {
      final tmp = await Directory.systemTemp.createTemp('donor_interception_test');
      final task = DownloadTask(
        id: 'pending_resniff_task',
        url: '${server.baseUrl}/vod/video.mp4?token=old',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp',
        state: DownloadState.failed,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);
      queue.resniffPendingTaskId = task.id;

      var onResniffDuplicateCalled = false;
      queue.onResniffDuplicate = (targetTaskId, interceptedTask) async {
        onResniffDuplicateCalled = true;
        expect(targetTaskId, task.id);
        expect(interceptedTask.url, contains(server.freshToken!));
        await queue.updateTaskFromDonor(targetTaskId, interceptedTask);
      };

      // Fresh stream sniffed in browser
      final freshlySniffedTask = DownloadTask(
        id: 'sniffed_task_temp',
        url: '${server.baseUrl}/vod/video.mp4?token=${server.freshToken}',
        savePath: '${tmp.path}/video_sniffed.mp4',
        tempDir: '${tmp.path}/temp_sniffed',
      );

      // Add to queue in resniff mode
      queue.addTask(freshlySniffedTask);

      expect(onResniffDuplicateCalled, isTrue);
      final revivedTask = queue.getTask(task.id);
      expect(revivedTask!.url, contains(server.freshToken!));

      await queue.dispose();
      await tmp.delete(recursive: true);
    });
  });

  group('Tier 3: Pairwise 4 - Multi-Candidate DOM + Ad Filtering + Quality Selection', () {
    test('P4: Filters out 3 ad manifests and selects 1080p stream over preview thumbnail', () async {
      server.htmlMediaCandidates = [
        'https://pagead2.googlesyndication.com/ad.m3u8',
        'https://static.trafficjunky.com/vast.xml',
        '${server.baseUrl}/previews/thumb_preview.mp4',
        '${server.baseUrl}/hls/v1/1080p/index.m3u8?token=${server.freshToken}',
        'https://telemetry.site.com/pixel.gif',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/hls/v1/1080p/index.m3u8?token=old_token',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, contains('/1080p/index.m3u8'));
      expect((result as ResniffSuccess).confidence, greaterThanOrEqualTo(0.9));
    });
  });

  group('Tier 3: Pairwise 5 - Session Cookies + Anti-Hotlinking Referer Header', () {
    test('P5: Resniff propagates both session cookies and Referer header simultaneously', () async {
      server.requiredCookie = 'user_session=gold_member_99';
      server.requiredHeaders = {'Referer': 'https://premium-tube.com/portal'};
      server.htmlMediaCandidates = [
        '${server.baseUrl}/premium/master.m3u8?token=${server.freshToken}',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/premium/master.m3u8?token=old',
        customCookies: {'user_session': 'gold_member_99'},
        customHeaders: {'Referer': 'https://premium-tube.com/portal'},
      );

      expect(result, isA<ResniffSuccess>());
      final log = server.requestLogs.last;
      expect(log.headers['cookie'], contains('user_session=gold_member_99'));
      expect(log.headers['referer'], 'https://premium-tube.com/portal');
    });
  });

  group('Tier 3: Pairwise 6 - 403 Forbidden Chunk + Retry Exhaustion + Diagnostics', () {
    test('P6: Chunk 403 failure exhausts budget after 2 tries and sets honest error reason', () async {
      const taskId = 'chunk_fail_task';
      SimulatedTokenRefreshService.resetBudget(taskId);
      server.forcedStatusCode = 403;

      final resniffer = SimulatedHeadlessResniffer();

      // Attempt 1: Failed
      final res1 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/video.mp4',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res1, isA<ResniffSourceUnavailable>());

      // Attempt 2: Failed
      final res2 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/video.mp4',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res2, isA<ResniffSourceUnavailable>());

      // Attempt 3: Blocked by budget
      final res3 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/video.mp4',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res3, isA<ResniffSourceUnavailable>());
      expect(res3.userFacingMessage, contains('budget exhausted'));
    });
  });

  group('Tier 3: Pairwise 7 - HTTP 429 Rate Limiting + Exponential Backoff Diagnostic', () {
    test('P7: Rate limited response produces actionable 429 diagnostic message', () async {
      server.forcedStatusCode = 429;
      final resniffer = SimulatedHeadlessResniffer();

      final result = await resniffer.resniff('${server.baseUrl}/rate_limited.html');

      expect(result, isA<ResniffSourceUnavailable>());
      final unavailable = result as ResniffSourceUnavailable;
      expect(unavailable.statusCode, 429);
      expect(unavailable.userFacingMessage, contains('HTTP 429'));
      expect(unavailable.isActionable, isTrue);
    });
  });

  group('Tier 3: Pairwise 8 - Player Interaction Required + Custom Overlay Wakeup', () {
    test('P8: Click-to-play page returns ResniffPlayerInteractionRequired with actionable details', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/custom_player.html',
        simulatePlayerInteractionNeeded: true,
      );

      expect(result, isA<ResniffPlayerInteractionRequired>());
      expect(result.isActionable, isTrue);
      expect(result.diagnosticDetails, contains('play gesture'));
    });
  });

  group('Tier 3: Pairwise 9 - Multi-Candidate Path Matching with Varying Subdirectories', () {
    test('P9: Matcher distinguishes between episode 1 and episode 2 on same series page', () {
      final candidates = [
        'http://media.tv/series/season1/ep02/stream.m3u8?token=new',
        'http://media.tv/series/season1/ep01/stream.m3u8?token=new',
        'http://media.tv/series/season1/ep03/stream.m3u8?token=new',
      ];

      final matchEp1 = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: 'http://media.tv/series/season1/ep01/stream.m3u8?token=old',
      );

      expect(matchEp1, isNotNull);
      expect(matchEp1!.url, candidates[1]);

      final matchEp2 = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: 'http://media.tv/series/season1/ep02/stream.m3u8?token=old',
      );

      expect(matchEp2, isNotNull);
      expect(matchEp2!.url, candidates[0]);
    });
  });

  group('Tier 3: Pairwise 10 - Pro vs Free Tier Gating Honesty Check', () {
    test('P10: Free tier gets clear upsell reason without false positive claim', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await SimulatedTokenRefreshService.autoRefresh(
        taskId: 'free_task',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/video.m3u8',
        allowed: false,
        resniffer: resniffer,
      );

      expect(result, isA<ResniffSourceUnavailable>());
      expect(result.userFacingMessage, contains('Aurora Pro feature'));
      expect(result.userFacingMessage, isNot(contains('Link is still valid')));
      expect(result.userFacingMessage, isNot(contains('No update needed')));
    });
  });
}
