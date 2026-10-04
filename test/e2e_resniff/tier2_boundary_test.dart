import 'dart:io';
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

  group('Tier 2: Boundary 1 - Empty Inputs & Malformed URLs', () {
    test('B1.1: Empty sourcePageUrl returns ResniffSourceUnavailable', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('');

      expect(result, isA<ResniffSourceUnavailable>());
      expect(result.userFacingMessage, contains('Invalid or unsupported scheme'));
    });

    test('B1.2: Malformed URL without scheme returns ResniffSourceUnavailable', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('example.com/video/watch.html');

      expect(result, isA<ResniffSourceUnavailable>());
    });

    test('B1.3: blob: scheme returns ResniffSourceUnavailable', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('blob:http://example.com/uuid-1234');

      expect(result, isA<ResniffSourceUnavailable>());
    });

    test('B1.4: javascript: pseudo-scheme returns ResniffSourceUnavailable', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('javascript:void(0)');

      expect(result, isA<ResniffSourceUnavailable>());
    });

    test('B1.5: data: base64 URI returns ResniffSourceUnavailable', () async {
      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('data:text/html;base64,PGh0bWw+PC9odG1sPg==');

      expect(result, isA<ResniffSourceUnavailable>());
    });
  });

  group('Tier 2: Boundary 2 - Special Characters & Unicode Tokens', () {
    test('B2.1: URL with special symbols in token query parameters is parsed cleanly', () async {
      const specialToken = 'sig=abc!@#*()_+-={}|[]:;,.?&auth=xyz~`';
      final mediaUrl = '${server.baseUrl}/stream.m3u8?$specialToken';
      server.htmlMediaCandidates = [mediaUrl];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/stream.m3u8?sig=old_token',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, mediaUrl);
    });

    test('B2.2: URL with percent-encoded spaces and UTF-8 characters is preserved', () async {
      final mediaUrl = '${server.baseUrl}/media/video%20name%20%E6%B8%AC%E8%A9%A6.mp4?token=utf8_ok';
      server.htmlMediaCandidates = [mediaUrl];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/media/video%20name%20%E6%B8%AC%E8%A9%A6.mp4?token=old',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, mediaUrl);
    });

    test('B2.3: StreamMatcher handles URL-encoded path segments correctly', () {
      final candidate = 'http://cdn.net/hls/my%20clip/master.m3u8?token=new';
      final original = 'http://cdn.net/hls/my%20clip/master.m3u8?token=old';

      final match = StreamMatcher.findBestMatch(
        candidates: [candidate],
        originalMediaUrl: original,
      );

      expect(match, isNotNull);
      expect(match!.url, candidate);
      expect(match.score, greaterThanOrEqualTo(0.9));
    });
  });

  group('Tier 2: Boundary 3 - Dynamic Query Parameters & Port Numbers & IPv6', () {
    test('B3.1: Complex multi-key query token parameters are preserved', () async {
      final mediaUrl = '${server.baseUrl}/hls/live.m3u8?hls=1&jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9&sig=XYZ%3D%3D&exp=1799999999';
      server.htmlMediaCandidates = [mediaUrl];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff(
        '${server.baseUrl}/watch.html',
        mustMatchPathOf: '${server.baseUrl}/hls/live.m3u8?hls=1&jwt=old_jwt&sig=OLD&exp=1600000000',
      );

      expect(result, isA<ResniffSuccess>());
      expect(result.freshUrl, mediaUrl);
    });

    test('B3.2: Non-standard high port numbers are supported', () {
      final candidate = 'http://127.0.0.1:65534/video.mp4?token=fresh';
      final original = 'http://127.0.0.1:65534/video.mp4?token=old';

      final match = StreamMatcher.findBestMatch(
        candidates: [candidate],
        originalMediaUrl: original,
      );

      expect(match, isNotNull);
      expect(match!.url, candidate);
    });

    test('B3.3: IPv6 loopback addresses are matched by StreamMatcher', () {
      final candidate = 'http://[::1]:8080/vod/stream.m3u8?token=new';
      final original = 'http://[::1]:8080/vod/stream.m3u8?token=old';

      final match = StreamMatcher.findBestMatch(
        candidates: [candidate],
        originalMediaUrl: original,
      );

      expect(match, isNotNull);
      expect(match!.url, candidate);
      expect(match.score, greaterThanOrEqualTo(0.9));
    });
  });

  group('Tier 2: Boundary 4 - HTTP Status Codes Matrix (400, 401, 403, 404, 410, 429, 500, 502, 503, 504)', () {
    for (final status in [400, 401, 403, 404, 410, 429, 500, 502, 503, 504]) {
      test('B4.status_$status: HTTP $status produces structured ResniffSourceUnavailable', () async {
        server.forcedStatusCode = status;

        final resniffer = SimulatedHeadlessResniffer();
        final result = await resniffer.resniff('${server.baseUrl}/status_$status.html');

        expect(result, isA<ResniffSourceUnavailable>());
        final unavailable = result as ResniffSourceUnavailable;
        expect(unavailable.statusCode, status);
        expect(result.isActionable, isTrue);
        expect(result.isSuccess, isFalse);
      });
    }
  });

  group('Tier 2: Boundary 5 - Timeout Thresholds & Zero Delays', () {
    test('B5.1: Ultra-short timeout (1ms) triggers ResniffPageLoadTimeout reliably', () async {
      server.responseDelay = const Duration(milliseconds: 100);

      final resniffer = SimulatedHeadlessResniffer(
        timeout: const Duration(milliseconds: 1),
      );
      final result = await resniffer.resniff('${server.baseUrl}/slow.html');

      expect(result, isA<ResniffPageLoadTimeout>());
      expect(result.isActionable, isTrue);
    });

    test('B5.2: Immediate response with zero delay completes successfully', () async {
      server.responseDelay = Duration.zero;
      server.htmlMediaCandidates = ['${server.baseUrl}/instant.m3u8?token=${server.freshToken}'];

      final resniffer = SimulatedHeadlessResniffer();
      final result = await resniffer.resniff('${server.baseUrl}/fast.html');

      expect(result, isA<ResniffSuccess>());
    });
  });

  group('Tier 2: Boundary 6 - Ad & Tracking Manifest Pattern Filtering', () {
    final adTestCases = [
      'https://pagead2.googlesyndication.com/pagead/ads?client=ca-pub-123',
      'https://securepubads.g.doubleclick.net/gampad/ads?iu=/12345/ad.m3u8',
      'https://ads.server.net/vast.xml',
      'https://video.popads.net/vpaid/ad.js',
      'https://cdn.trafficjunky.com/campaign/ad.m3u8',
      'https://a.exoclick.com/ads/video.mp4',
      'https://tracking.analytics.com/pixel.gif',
      'https://telemetry.site.com/ping.m3u8',
      'https://site.com/media/ping/beacon.mp4',
    ];

    for (final adUrl in adTestCases) {
      test('B6.filter_ad: isAdOrTrackingUrl flags "$adUrl"', () {
        expect(StreamMatcher.isAdOrTrackingUrl(adUrl), isTrue);
      });
    }

    test('B6.ad_filtering_preserves_legitimate_media', () {
      const legitimateUrl = 'https://cdn.site.com/videos/media_production_1080p.m3u8?token=valid';
      expect(StreamMatcher.isAdOrTrackingUrl(legitimateUrl), isFalse);
    });
  });

  group('Tier 2: Boundary 7 - High Candidate Volume Stress (100+ candidates)', () {
    test('B7.1: StreamMatcher efficiently selects best match from 150 candidates', () {
      final candidates = <String>[];
      for (var i = 0; i < 150; i++) {
        if (i % 3 == 0) {
          candidates.add('https://adserver.com/ads/banner_$i.m3u8');
        } else if (i == 77) {
          candidates.add('${server.baseUrl}/target/movie.m3u8?token=fresh_77');
        } else {
          candidates.add('${server.baseUrl}/other_videos/video_$i.mp4');
        }
      }

      final match = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: '${server.baseUrl}/target/movie.m3u8?token=old_00',
      );

      expect(match, isNotNull);
      expect(match!.url, '${server.baseUrl}/target/movie.m3u8?token=fresh_77');
      expect(match.score, greaterThanOrEqualTo(0.9));
    });
  });

  group('Tier 2: Boundary 8 - Result Model Null Safety & Defaults', () {
    test('B8.1: ResniffNoMediaFound default constructor values', () {
      const res = ResniffNoMediaFound();
      expect(res.candidatesInspected, 0);
      expect(res.details, isNull);
      expect(res.diagnosticDetails, 'Inspected 0 candidate(s).');
      expect(res.isSuccess, isFalse);
      expect(res.isActionable, isTrue);
      expect(res.freshUrl, isNull);
    });

    test('B8.2: ResniffPageLoadTimeout default constructor values', () {
      const res = ResniffPageLoadTimeout();
      expect(res.elapsed, const Duration(seconds: 20));
      expect(res.lastState, isNull);
      expect(res.diagnosticDetails, contains('Last known state: loading'));
    });

    test('B8.3: ResniffSourceUnavailable without arguments defaults safely', () {
      const res = ResniffSourceUnavailable();
      expect(res.statusCode, isNull);
      expect(res.error, isNull);
      expect(res.isDnsFailure, isFalse);
      expect(res.userFacingMessage, 'Source page could not be accessed.');
    });
  });
}
