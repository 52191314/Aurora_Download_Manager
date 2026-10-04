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

  group('Tier 1: Feature 1 - ResniffSuccess Tests (>=5 tests)', () {
    test('1.1: ResniffSuccess produces fresh URL and isSuccess true', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/stream.m3u8?token=${server.freshToken}',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/stream.m3u8?token=${server.validToken}',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.isSuccess, isTrue);
      expect(result.freshUrl, '${server.baseUrl}/stream.m3u8?token=${server.freshToken}');
      expect(result.isActionable, isFalse);
      expect(result.userFacingMessage, contains('Fresh media link discovered'));
    });

    test('1.2: ResniffSuccess captures high confidence score from exact path match', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/hls/v1/master.m3u8?token=${server.freshToken}',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/hls/v1/master.m3u8?token=old_token',
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.confidence, greaterThanOrEqualTo(0.8));
      expect(result.diagnosticDetails, contains('Confidence:'));
    });

    test('1.3: ResniffSuccess propagates response headers in result model', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/video.mp4?token=${server.freshToken}',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final customHeaders = {'Authorization': 'Bearer token_xyz', 'User-Agent': 'CustomUA/1.0'};
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/video.mp4?token=old_token',
        customHeaders: customHeaders,
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.headers?['Authorization'], 'Bearer token_xyz');
      expect(success.headers?['User-Agent'], 'CustomUA/1.0');
    });

    test('1.4: ResniffSuccess handles direct MP4 candidate stream refresh', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/assets/movie.mp4?sig=sig_new_789',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/assets/movie.mp4?sig=sig_old_123',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, contains('sig=sig_new_789'));
    });

    test('1.5: ResniffSuccess without mustMatchPathOf takes first non-ad stream', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/ads/banner_ad.m3u8',
        '${server.baseUrl}/content/playlist.m3u8?token=${server.freshToken}',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/watch.html');

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, contains('/content/playlist.m3u8'));
    });
  });

  group('Tier 1: Feature 2 - ResniffUnchanged Tests (>=5 tests)', () {
    test('2.1: ResniffUnchanged returns unchanged status when fresh token is identical', () async {
      final original = '${server.baseUrl}/stream.m3u8?token=${server.validToken}';
      server.htmlMediaCandidates = [original];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: original,
      );

      expect(result, isA<ResniffUnchanged>());
      expect(result.isSuccess, isFalse);
      expect(result.freshUrl, isNull);
      expect((result as ResniffUnchanged).url, original);
      expect(result.userFacingMessage, contains('Link is unchanged'));
    });

    test('2.2: ResniffUnchanged diagnostic details contain exact URL', () async {
      final url = '${server.baseUrl}/hls/vod/index.m3u8';
      server.htmlMediaCandidates = [url];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: url,
      );

      expect(result, isA<ResniffUnchanged>());
      expect(result.diagnosticDetails, contains(url));
      expect(result.isActionable, isFalse);
    });

    test('2.3: ResniffUnchanged works for direct MP4 unchanged URLs', () async {
      final url = '${server.baseUrl}/videos/clip_1080p.mp4';
      server.htmlMediaCandidates = [url];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: url,
      );

      expect(result, isA<ResniffUnchanged>());
      expect((result as ResniffUnchanged).url, url);
    });

    test('2.4: ResniffUnchanged distinguishes between identical query vs token variation', () async {
      final base = '${server.baseUrl}/media/stream.m3u8';
      server.htmlMediaCandidates = ['$base?expires=1700000000'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '$base?expires=1700000000',
      );

      expect(result, isA<ResniffUnchanged>());
    });

    test('2.5: ResniffUnchanged returns non-actionable flag', () async {
      final url = '${server.baseUrl}/dash/live.mpd';
      server.htmlMediaCandidates = [url];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: url,
      );

      expect(result, isA<ResniffUnchanged>());
      expect(result.isActionable, isFalse);
    });
  });

  group('Tier 1: Feature 3 - ResniffNoMediaFound Tests (>=5 tests)', () {
    test('3.1: ResniffNoMediaFound returned when page has 0 media elements', () async {
      server.htmlMediaCandidates = [];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/watch.html');

      expect(result, isA<ResniffNoMediaFound>());
      expect(result.isSuccess, isFalse);
      expect(result.isActionable, isTrue);
      expect(result.userFacingMessage, contains('No media streams could be located'));
    });

    test('3.2: ResniffNoMediaFound records candidates inspected count when path mismatch', () async {
      server.htmlMediaCandidates = [
        '${server.baseUrl}/other_video_1.m3u8',
        '${server.baseUrl}/unrelated_clip.mp4',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/desired/target/stream.m3u8',
      );

      expect(result, isA<ResniffNoMediaFound>());
      final notFound = result as ResniffNoMediaFound;
      expect(notFound.candidatesInspected, 2);
      expect(result.diagnosticDetails, contains('None of 2 candidates matched'));
    });

    test('3.3: ResniffNoMediaFound returns when all candidates are advertisements', () async {
      server.htmlMediaCandidates = [
        'https://googleads.g.doubleclick.net/pagead/ads/ad.m3u8',
        'https://static.trafficjunky.com/vast.xml',
      ];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/watch.html');

      expect(result, isA<ResniffNoMediaFound>());
      expect(result.diagnosticDetails, contains('ads or trackers'));
    });

    test('3.4: ResniffNoMediaFound produces honest actionable user message', () async {
      server.htmlMediaCandidates = [];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/watch.html');

      expect(result.userFacingMessage, isNot(contains('Link is still valid')));
      expect(result.userFacingMessage, isNot(contains('No update needed')));
    });

    test('3.5: ResniffNoMediaFound handles text-only article page gracefully', () async {
      server.htmlMediaCandidates = [];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/article.html');

      expect(result, isA<ResniffNoMediaFound>());
      expect(result.freshUrl, isNull);
    });
  });

  group('Tier 1: Feature 4 - ResniffChallengeDetected Tests (>=5 tests)', () {
    test('4.1: ResniffChallengeDetected identifies Cloudflare Turnstile challenge', () async {
      server.simulateTurnstileChallenge = true;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/protected.html');

      expect(result, isA<ResniffChallengeDetected>());
      final challenge = result as ResniffChallengeDetected;
      expect(challenge.challengeType, 'cloudflare_turnstile');
      expect(result.isActionable, isTrue);
      expect(result.userFacingMessage, contains('Security challenge detected'));
    });

    test('4.2: ResniffChallengeDetected identifies Google reCAPTCHA challenge', () async {
      server.simulateRecaptcha = true;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/captcha.html');

      expect(result, isA<ResniffChallengeDetected>());
      final challenge = result as ResniffChallengeDetected;
      expect(challenge.challengeType, 'recaptcha');
      expect(result.diagnosticDetails, contains('reCAPTCHA'));
    });

    test('4.3: ResniffChallengeDetected never claims link is valid or unchanged', () async {
      server.simulateTurnstileChallenge = true;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/protected.html',
        mustMatchPathOf: '${server.baseUrl}/video.m3u8',
      );

      expect(result, isA<ResniffChallengeDetected>());
      expect(result.userFacingMessage, isNot(contains('unchanged')));
      expect(result.userFacingMessage, isNot(contains('valid')));
    });

    test('4.4: ResniffChallengeDetected isActionable indicates browser fallback is needed', () async {
      server.simulateTurnstileChallenge = true;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/login.html');

      expect(result.isActionable, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('4.5: ResniffChallengeDetected reports generic WAF signatures', () {
      const customChallenge = ResniffChallengeDetected(
        challengeType: 'generic_waf',
        details: 'Imperva Incapsula blocking page detected',
      );

      expect(customChallenge.challengeType, 'generic_waf');
      expect(customChallenge.diagnosticDetails, contains('Imperva Incapsula'));
      expect(customChallenge.userFacingMessage, contains('generic_waf'));
    });
  });

  group('Tier 1: Feature 5 - ResniffPageLoadTimeout Tests (>=5 tests)', () {
    test('5.1: ResniffPageLoadTimeout triggers when response exceeds duration', () async {
      server.responseDelay = const Duration(milliseconds: 300);

      final resniffer = SimulatedHeadlessResniffer(
        timeout: const Duration(milliseconds: 50),
      );
      final result = await resniffer.resniff('${server.baseUrl}/slow_page.html');

      expect(result, isA<ResniffPageLoadTimeout>());
      expect(result.isSuccess, isFalse);
      expect(result.isActionable, isTrue);
    });

    test('5.2: ResniffPageLoadTimeout records elapsed duration in model', () async {
      server.responseDelay = const Duration(milliseconds: 200);

      final resniffer = SimulatedHeadlessResniffer(
        timeout: const Duration(milliseconds: 40),
      );
      final result = await resniffer.resniff('${server.baseUrl}/slow_page.html');

      expect(result, isA<ResniffPageLoadTimeout>());
      final timeout = result as ResniffPageLoadTimeout;
      expect(timeout.elapsed.inMilliseconds, 40);
      expect(result.userFacingMessage, contains('timed out'));
    });

    test('5.3: ResniffPageLoadTimeout diagnostic details state last known state', () async {
      server.responseDelay = const Duration(milliseconds: 200);

      final resniffer = SimulatedHeadlessResniffer(
        timeout: const Duration(milliseconds: 40),
      );
      final result = await resniffer.resniff('${server.baseUrl}/slow_page.html');

      expect(result, isA<ResniffPageLoadTimeout>());
      expect(result.diagnosticDetails, contains('network_read_timeout'));
    });

    test('5.4: ResniffPageLoadTimeout is actionable to prompt manual retry', () async {
      const timeout = ResniffPageLoadTimeout(
        elapsed: Duration(seconds: 20),
        lastState: 'dom_polling',
      );

      expect(timeout.isActionable, isTrue);
      expect(timeout.userFacingMessage, 'Page load timed out after 20 seconds.');
    });

    test('5.5: ResniffPageLoadTimeout returns null for freshUrl', () async {
      const timeout = ResniffPageLoadTimeout(elapsed: Duration(seconds: 15));
      expect(timeout.freshUrl, isNull);
      expect(timeout.isSuccess, isFalse);
    });
  });

  group('Tier 1: Feature 6 - ResniffSourceUnavailable Tests (>=5 tests)', () {
    test('6.1: ResniffSourceUnavailable categorizes HTTP 404 Not Found', () async {
      server.forcedStatusCode = 404;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/not_found.html');

      expect(result, isA<ResniffSourceUnavailable>());
      final unavailable = result as ResniffSourceUnavailable;
      expect(unavailable.statusCode, 404);
      expect(result.userFacingMessage, contains('Source page not found (404)'));
    });

    test('6.2: ResniffSourceUnavailable categorizes HTTP 410 Gone permanently', () async {
      server.forcedStatusCode = 410;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/deleted_video.html');

      expect(result, isA<ResniffSourceUnavailable>());
      final unavailable = result as ResniffSourceUnavailable;
      expect(unavailable.statusCode, 410);
      expect(result.userFacingMessage, contains('gone permanently (410)'));
    });

    test('6.3: ResniffSourceUnavailable categorizes HTTP 500 Server Error', () async {
      server.forcedStatusCode = 500;

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/server_error.html');

      expect(result, isA<ResniffSourceUnavailable>());
      final unavailable = result as ResniffSourceUnavailable;
      expect(unavailable.statusCode, 500);
      expect(result.userFacingMessage, contains('HTTP 500'));
    });

    test('6.4: ResniffSourceUnavailable categorizes DNS Host Lookup Failure', () {
      const unavailable = ResniffSourceUnavailable(
        isDnsFailure: true,
        error: 'Failed host lookup: nonexistent.domain',
      );
      expect(unavailable.isDnsFailure, isTrue);
      expect(unavailable.userFacingMessage, contains('DNS failure'));
      expect(unavailable.diagnosticDetails, contains('DNS failure: true'));
    });

    test('6.5: ResniffSourceUnavailable categorizes invalid URI scheme', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('file:///sdcard/video.mp4');

      expect(result, isA<ResniffSourceUnavailable>());
      expect(result.userFacingMessage, contains('Invalid or unsupported scheme'));
    });
  });

  group('Tier 1: Feature 7 - ResniffPlayerInteractionRequired Tests (>=5 tests)', () {
    test('7.1: ResniffPlayerInteractionRequired returns actionable result', () async {
      server.htmlMediaCandidates = ['${server.baseUrl}/hidden_stream.m3u8'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/click_to_play.html',
        simulatePlayerInteractionNeeded: true,
      );

      expect(result, isA<ResniffPlayerInteractionRequired>());
      expect(result.isActionable, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('7.2: ResniffPlayerInteractionRequired provides clear user-facing guidance', () async {
      const result = ResniffPlayerInteractionRequired(
        details: 'Custom JWPlayer play button clicked without autoplay',
      );

      expect(result.userFacingMessage, contains('Player requires direct manual interaction'));
      expect(result.diagnosticDetails, contains('JWPlayer'));
    });

    test('7.3: ResniffPlayerInteractionRequired does not provide freshUrl', () async {
      const result = ResniffPlayerInteractionRequired();
      expect(result.freshUrl, isNull);
    });

    test('7.4: ResniffPlayerInteractionRequired distinguishes from NoMediaFound', () async {
      const interaction = ResniffPlayerInteractionRequired();
      const noMedia = ResniffNoMediaFound();

      expect(interaction, isNot(isA<ResniffNoMediaFound>()));
      expect(interaction.userFacingMessage, isNot(noMedia.userFacingMessage));
    });

    test('7.5: ResniffPlayerInteractionRequired diagnostic details handle null details gracefully', () async {
      const result = ResniffPlayerInteractionRequired();
      expect(result.diagnosticDetails, contains('Click-to-play'));
    });
  });

  group('Tier 1: Feature 8 - StreamMatcher Scoring Tests (>=6 tests)', () {
    test('8.1: StreamMatcher gives exact path and domain highest score', () {
      final candidate = '${server.baseUrl}/hls/movie/master.m3u8?token=fresh_token';
      final original = '${server.baseUrl}/hls/movie/master.m3u8?token=old_token';

      final match = StreamMatcher.findBestMatch(
        candidates: [candidate],
        originalMediaUrl: original,
      );

      expect(match, isNotNull);
      expect(match!.url, candidate);
      expect(match.score, greaterThanOrEqualTo(0.9));
      expect(match.reason, contains('exact path match'));
      expect(match.reason, contains('refreshed query token'));
    });

    test('8.2: StreamMatcher filters out advertisement manifests and tracking pixels', () {
      final candidates = [
        'https://adservice.google.com/ads/vast.xml',
        'https://cdn.doubleclick.net/ad_manifest.m3u8',
        'https://analytics.example.com/pixel.gif',
        '${server.baseUrl}/content/video.mp4?token=fresh',
      ];

      final match = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: '${server.baseUrl}/content/video.mp4?token=old',
      );

      expect(match, isNotNull);
      expect(match!.url, '${server.baseUrl}/content/video.mp4?token=fresh');
      expect(StreamMatcher.isAdOrTrackingUrl(candidates[0]), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl(candidates[1]), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl(candidates[2]), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl(candidates[3]), isFalse);
    });

    test('8.3: StreamMatcher selects highest scoring candidate among multiple videos', () {
      final candidates = [
        '${server.baseUrl}/trailers/trailer_1.mp4',
        '${server.baseUrl}/episodes/season1/ep01.m3u8?token=fresh',
        '${server.baseUrl}/thumbnails/preview.mp4',
      ];

      final match = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: '${server.baseUrl}/episodes/season1/ep01.m3u8?token=expired',
      );

      expect(match, isNotNull);
      expect(match!.url, candidates[1]);
      expect(match.score, greaterThan(0.8));
    });

    test('8.4: StreamMatcher returns null when no candidate meets minimum threshold', () {
      final candidates = [
        'https://other-domain.org/different/path/video.mp4',
      ];

      final match = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: 'https://mycdn.com/target/stream.m3u8',
      );

      expect(match, isNull);
    });

    test('8.5: StreamMatcher handles subdomain matching with partial score', () {
      final candidate = 'https://sub1.video-cdn.com/stream.m3u8';
      final original = 'https://sub2.video-cdn.com/stream.m3u8';

      final match = StreamMatcher.findBestMatch(
        candidates: [candidate],
        originalMediaUrl: original,
      );

      expect(match, isNotNull);
      expect(match!.score, greaterThanOrEqualTo(0.4));
      expect(match.reason, contains('exact path match'));
    });

    test('8.6: StreamMatcher handles empty candidate list gracefully', () {
      final match = StreamMatcher.findBestMatch(
        candidates: [],
        originalMediaUrl: '${server.baseUrl}/video.mp4',
      );
      expect(match, isNull);
    });
  });

  group('Tier 1: Feature 9 - Request Headers & Session Propagation Tests (>=5 tests)', () {
    test('9.1: Headless resniff forwards custom User-Agent header', () async {
      server.requiredHeaders = {'User-Agent': 'AuroraBrowser/2.0'};
      server.htmlMediaCandidates = ['${server.baseUrl}/media.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/media.m3u8?token=old',
        customHeaders: {'User-Agent': 'AuroraBrowser/2.0'},
      );

      expect(result, isA<ResniffSuccess>());
      expect(server.requestLogs.last.headers['user-agent'], 'AuroraBrowser/2.0');
    });

    test('9.2: Headless resniff forwards Referer header for anti-hotlinking bypass', () async {
      server.requiredHeaders = {'Referer': 'https://trusted-portal.com/'};
      server.htmlMediaCandidates = ['${server.baseUrl}/media.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/media.m3u8?token=old',
        customHeaders: {'Referer': 'https://trusted-portal.com/'},
      );

      expect(result, isA<ResniffSuccess>());
      expect(server.requestLogs.last.headers['referer'], 'https://trusted-portal.com/');
    });

    test('9.3: Headless resniff forwards Authorization Bearer token header', () async {
      server.requiredHeaders = {'Authorization': 'Bearer secret_session_token_123'};
      server.htmlMediaCandidates = ['${server.baseUrl}/secure.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/secure.m3u8?token=old',
        customHeaders: {'Authorization': 'Bearer secret_session_token_123'},
      );

      expect(result, isA<ResniffSuccess>());
    });

    test('9.4: Missing required header returns ResniffSourceUnavailable with 400', () async {
      server.requiredHeaders = {'X-API-Key': 'required_api_key_456'};

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/media.m3u8',
        customHeaders: {}, // missing X-API-Key
      );

      expect(result, isA<ResniffSourceUnavailable>());
      expect((result as ResniffSourceUnavailable).statusCode, 400);
    });

    test('9.5: ResniffSuccess preserves task headers in result model for download resumption', () async {
      server.htmlMediaCandidates = ['${server.baseUrl}/stream.m3u8?token=${server.freshToken}'];

      final customHeaders = {'X-Custom-Auth': 'Token999', 'Origin': 'https://example.com'};
      final resniffer = SimulatedHeadlessResniffer(defaultHeaders: customHeaders);
      final result = await resniffer.resniff('${server.baseUrl}/watch.html');

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.headers?['X-Custom-Auth'], 'Token999');
      expect(success.headers?['Origin'], 'https://example.com');
    });
  });

  group('Tier 1: Feature 10 - Cookie Sharing & Session Parity Tests (>=5 tests)', () {
    test('10.1: Headless resniff forwards session cookies to server', () async {
      server.requiredCookie = 'session_id=aurora_session_abc123';
      server.htmlMediaCandidates = ['${server.baseUrl}/session_video.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/session_video.m3u8?token=old',
        customCookies: {'session_id': 'aurora_session_abc123'},
      );

      expect(result, isA<ResniffSuccess>());
    });

    test('10.2: Headless resniff forwards Cloudflare cf_clearance cookie', () async {
      server.requiredCookie = 'cf_clearance=cf_token_passed_456';
      server.htmlMediaCandidates = ['${server.baseUrl}/cf_video.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/cf_video.m3u8?token=old',
        customCookies: {'cf_clearance': 'cf_token_passed_456'},
      );

      expect(result, isA<ResniffSuccess>());
    });

    test('10.3: Missing required session cookie causes 403 failure in resniff', () async {
      server.requiredCookie = 'auth_token=valid_auth';

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/session_video.m3u8',
        customCookies: {}, // missing cookie
      );

      expect(result, isA<ResniffSourceUnavailable>());
      expect((result as ResniffSourceUnavailable).statusCode, 403);
    });

    test('10.4: Resniffer supports multiple concurrent cookies in Cookie header', () async {
      server.requiredCookie = 'cf_clearance';
      server.htmlMediaCandidates = ['${server.baseUrl}/stream.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/stream.m3u8?token=old',
        customCookies: {
          'session_id': '123',
          'cf_clearance': 'token_xyz',
          'user_pref': 'dark',
        },
      );

      expect(result, isA<ResniffSuccess>());
      final lastLog = server.requestLogs.last;
      expect(lastLog.headers['cookie'], contains('session_id=123'));
      expect(lastLog.headers['cookie'], contains('cf_clearance=token_xyz'));
      expect(lastLog.headers['cookie'], contains('user_pref=dark'));
    });

    test('10.5: Default cookies injected at instance initialization are preserved', () async {
      server.requiredCookie = 'persistent_login=user_777';
      server.htmlMediaCandidates = ['${server.baseUrl}/media.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer(
        defaultCookies: {'persistent_login': 'user_777'},
      );
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/media.m3u8?token=old',
      );

      expect(result, isA<ResniffSuccess>());
    });
  });

  group('Tier 1: Feature 11 - Retry Exhaustion & Auto-Budget Handlers (>=5 tests)', () {
    test('11.1: Auto-refresh succeeds within budget when entitlement allowed', () async {
      SimulatedTokenRefreshService.resetBudget('task_retry_1');
      server.htmlMediaCandidates = ['${server.baseUrl}/stream.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await SimulatedTokenRefreshService.autoRefresh(
        taskId: 'task_retry_1',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        allowed: true,
        resniffer: resniffer,
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, contains(server.freshToken!));
    });

    test('11.2: Auto-refresh fails immediately with honest reason when allowed is false (Free tier)', () async {
      SimulatedTokenRefreshService.resetBudget('task_free_tier');

      final resniffer = SimulatedHeadlessResniffer();
      final result = await SimulatedTokenRefreshService.autoRefresh(
        taskId: 'task_free_tier',
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        allowed: false,
        resniffer: resniffer,
      );

      expect(result, isA<ResniffSourceUnavailable>());
      expect(result.userFacingMessage, contains('Aurora Pro feature'));
    });

    test('11.3: Auto-refresh exhausts budget after maxAutoTries attempts', () async {
      const taskId = 'task_budget_exhaust';
      SimulatedTokenRefreshService.resetBudget(taskId);
      server.htmlMediaCandidates = ['${server.baseUrl}/stream.m3u8?token=${server.freshToken}'];
      final resniffer = SimulatedHeadlessResniffer();

      // Try 1
      final res1 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res1, isA<ResniffSuccess>());

      // Try 2
      final res2 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res2, isA<ResniffSuccess>());

      // Try 3 (Exhausted)
      final res3 = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: '${server.baseUrl}/watch.html',
        originalUrl: '${server.baseUrl}/stream.m3u8?token=old',
        allowed: true,
        resniffer: resniffer,
      );
      expect(res3, isA<ResniffSourceUnavailable>());
      expect(res3.userFacingMessage, contains('budget exhausted'));
    });

    test('11.4: Resetting auto-refresh budget permits subsequent auto tries', () async {
      const taskId = 'task_reset_test';
      SimulatedTokenRefreshService.resetBudget(taskId);
      SimulatedTokenRefreshService.recordAutoTry(taskId);
      SimulatedTokenRefreshService.recordAutoTry(taskId);
      expect(SimulatedTokenRefreshService.autoBudgetExhausted(taskId), isTrue);

      SimulatedTokenRefreshService.resetBudget(taskId);
      expect(SimulatedTokenRefreshService.autoBudgetExhausted(taskId), isFalse);
    });

    test('11.5: Missing sourcePageUrl in autoRefresh returns honest NoMediaFound', () async {
      const taskId = 'task_no_source_page';
      SimulatedTokenRefreshService.resetBudget(taskId);
      final resniffer = SimulatedHeadlessResniffer();

      final result = await SimulatedTokenRefreshService.autoRefresh(
        taskId: taskId,
        sourcePageUrl: null,
        originalUrl: 'http://cdn.example.com/video.m3u8',
        allowed: true,
        resniffer: resniffer,
      );

      expect(result, isA<ResniffNoMediaFound>());
      expect(result.diagnosticDetails, contains('no valid sourcePageUrl'));
    });
  });

  group('Tier 1: Feature 12 - Donor Stream Updating & ResniffSession Tests (>=5 tests)', () {
    test('12.1: ResniffSession correctly matches fresh candidate stream', () {
      final session = ResniffSession(
        taskId: 'task_001',
        taskName: 'Big Buck Bunny',
        originalUrl: '${server.baseUrl}/videos/bunny.m3u8?token=old_token',
        sourcePageUrl: '${server.baseUrl}/watch.html',
      );

      final freshCandidate = '${server.baseUrl}/videos/bunny.m3u8?token=fresh_token_123';
      final unrelatedCandidate = '${server.baseUrl}/trailers/trailer.m3u8';

      expect(session.matchesCandidate(freshCandidate), isTrue);
      expect(session.matchesCandidate(unrelatedCandidate), isFalse);
    });

    test('12.2: updateTaskFromDonor updates task URL and preserves task ID', () async {
      final tmp = await Directory.systemTemp.createTemp('resniff_donor_test');
      final task = DownloadTask(
        id: 'donor_task_123',
        url: '${server.baseUrl}/stream.m3u8?token=old',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp_donor',
        state: DownloadState.failed,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      final donor = DownloadTask(
        id: 'donor_proxy',
        url: '${server.baseUrl}/stream.m3u8?token=fresh_abc',
        savePath: task.savePath,
        tempDir: task.tempDir,
        headers: {'Authorization': 'Bearer fresh_donor_token'},
      );

      await queue.updateTaskFromDonor(task.id, donor);

      final updated = queue.getTask(task.id);
      expect(updated, isNotNull);
      expect(updated!.url, '${server.baseUrl}/stream.m3u8?token=fresh_abc');
      expect(updated.headers?['Authorization'], 'Bearer fresh_donor_token');
      expect(updated.state, isNot(DownloadState.failed));

      await queue.dispose();
      await tmp.delete(recursive: true);
    });

    test('12.3: updateTaskFromDonor resets error messages and failure reason', () async {
      final tmp = await Directory.systemTemp.createTemp('resniff_err_reset');
      final task = DownloadTask(
        id: 'task_failed_err',
        url: '${server.baseUrl}/stream.m3u8?token=old',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp_err',
        state: DownloadState.failed,
        errorMessage: 'HTTP 403 Forbidden',
        failureReason: DownloadFailure.hlsTokenExpired,
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      final donor = DownloadTask(
        id: 'donor_reset',
        url: '${server.baseUrl}/stream.m3u8?token=fresh_reset',
        savePath: task.savePath,
        tempDir: task.tempDir,
      );

      await queue.updateTaskFromDonor(task.id, donor);

      final updated = queue.getTask(task.id);
      expect(updated!.errorMessage, isNull);
      expect(updated.failureReason, isNull);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });

    test('12.4: updateTaskFromDonor copies browser bridges from donor task', () async {
      final tmp = await Directory.systemTemp.createTemp('resniff_bridge_test');
      final task = DownloadTask(
        id: 'task_bridge',
        url: '${server.baseUrl}/stream.m3u8',
        savePath: '${tmp.path}/video.mp4',
        tempDir: '${tmp.path}/temp_bridge',
      );

      final queue = DownloadQueue(autoRetry: false);
      queue.addTask(task);

      var bridgeInvoked = false;
      final donor = DownloadTask(
        id: 'donor_with_bridge',
        url: '${server.baseUrl}/stream.m3u8?fresh=1',
        savePath: task.savePath,
        tempDir: task.tempDir,
        fetchViaWebView: (url, {headers}) async {
          bridgeInvoked = true;
          return 'mock_body';
        },
      );

      await queue.updateTaskFromDonor(task.id, donor);

      final updated = queue.getTask(task.id);
      expect(updated!.hasBrowserBridges, isTrue);
      expect(updated.fetchViaWebView, isNotNull);

      await updated.fetchViaWebView!('http://example.com');
      expect(bridgeInvoked, isTrue);

      await queue.dispose();
      await tmp.delete(recursive: true);
    });

    test('12.5: ResniffSession stores createdAt timestamp and task metadata', () {
      final now = DateTime.now();
      final session = ResniffSession(
        taskId: 'task_meta_999',
        taskName: 'Season Finale',
        originalUrl: 'http://cdn.tv/stream.m3u8',
        sourcePageUrl: 'http://tv.com/watch/999',
        createdAt: now,
      );

      expect(session.taskId, 'task_meta_999');
      expect(session.taskName, 'Season Finale');
      expect(session.originalUrl, 'http://cdn.tv/stream.m3u8');
      expect(session.sourcePageUrl, 'http://tv.com/watch/999');
      expect(session.createdAt, now);
    });
  });
}
