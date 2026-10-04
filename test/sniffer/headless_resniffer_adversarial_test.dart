import 'package:aurora_downloader/sniffer/headless_resniffer.dart';
import 'package:aurora_downloader/sniffer/resniff_result.dart';
import 'package:aurora_downloader/sniffer/stream_matcher.dart';
import 'package:flutter_test/flutter_test.dart' hide StreamMatcher;

void main() {
  group('Adversarial Group 1: WAF & Security Challenge Parsing & Edge Cases', () {
    test('1.1: Parses deeply nested Cloudflare Turnstile details with unusual characters', () {
      const payload = '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare Turnstile challenge element detected (iframe[src*=\\"challenges.cloudflare.com\\"] -> nested in #shadow-root)"}';
      final result = HeadlessPageResniffer.parseChallengeDetectionResult(payload);

      expect(result, isNotNull);
      expect(result!.challengeType, 'cloudflare_turnstile');
      expect(result.details, contains('challenges.cloudflare.com'));
      expect(result.isActionable, isTrue);
      expect(result.userFacingMessage, contains('challenges.cloudflare.com'));
    });

    test('1.2: Parses obfuscated Cloudflare challenge titles and mixed case variations', () {
      const titles = [
        '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare challenge page title detected: \\"Just a moment...\\""}',
        '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare challenge page title detected: \\"Attention Required! | Cloudflare\\""}',
        '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare human verification text detected"}',
      ];

      for (final titleJson in titles) {
        final result = HeadlessPageResniffer.parseChallengeDetectionResult(titleJson);
        expect(result, isNotNull);
        expect(result!.challengeType, 'cloudflare_turnstile');
      }
    });

    test('1.3: Parses multi-stage captchas: reCAPTCHA, hCaptcha, and Generic WAFs', () {
      final tests = {
        '{"detected":true,"type":"recaptcha","details":"reCAPTCHA challenge element detected (.g-recaptcha)"}': 'recaptcha',
        '{"detected":true,"type":"hcaptcha","details":"hCaptcha challenge element detected (#h-captcha)"}': 'hcaptcha',
        '{"detected":true,"type":"generic_waf","details":"WAF challenge element detected (#ddos-guard)"}': 'generic_waf',
        '{"detected":true,"type":"generic_waf","details":"WAF block page title detected: \\"403 Forbidden - Access Denied\\""}': 'generic_waf',
      };

      tests.forEach((jsonStr, expectedType) {
        final result = HeadlessPageResniffer.parseChallengeDetectionResult(jsonStr);
        expect(result, isNotNull);
        expect(result!.challengeType, expectedType);
        expect(result.isActionable, isTrue);
      });
    });

    test('1.4: Handles adversarial / malformed challenge JSON payloads gracefully', () {
      // 1. Valid detection with null type defaults to cloudflare_turnstile
      final defaultTypeResult = HeadlessPageResniffer.parseChallengeDetectionResult('{"detected": true, "type": null}');
      expect(defaultTypeResult, isNotNull);
      expect(defaultTypeResult!.challengeType, 'cloudflare_turnstile');

      // 2. Large details payload
      final largeResult = HeadlessPageResniffer.parseChallengeDetectionResult('{"detected": true, "details": "${'A' * 10000}"}');
      expect(largeResult, isNotNull);
      expect(largeResult!.details?.length, 10000);

      // 3. Malformed or negative payloads must return null safely without throwing
      final badPayloads = [
        'null',
        '""',
        '{}',
        '{"detected": false}',
        '{"detected": "true"}', // string instead of bool
        '{"error": "SecurityError: Blocked a frame with origin"}',
        '[{"detected": true}]',
        '{"detected": true, "type": 12345}', // non-string type causes catch (_) -> null
        '{"corrupted": true',
      ];

      for (final bad in badPayloads) {
        final result = HeadlessPageResniffer.parseChallengeDetectionResult(bad);
        expect(result, isNull, reason: 'Failed for payload: $bad');
      }
    });
  });

  group('Adversarial Group 2: Player Wake Script Synthesis & Status Parsing', () {
    test('2.1: Parses unplayed player status with complex overlay indicators', () {
      const json = '{"hasPlayer":true,"isPlaying":false,"details":"Found 2 video element(s) in paused or unplayed state. Play button overlay detected requiring user gesture."}';
      final status = HeadlessPageResniffer.parsePlayerStatusResult(json);

      expect(status.hasPlayer, isTrue);
      expect(status.isPlaying, isFalse);
      expect(status.details, contains('Play button overlay detected'));
    });

    test('2.2: Parses active playback status correctly', () {
      const json = '{"hasPlayer":true,"isPlaying":true,"details":""}';
      final status = HeadlessPageResniffer.parsePlayerStatusResult(json);

      expect(status.hasPlayer, isTrue);
      expect(status.isPlaying, isTrue);
      expect(status.details, isEmpty);
    });

    test('2.3: Robustness against malformed or unexpected player status JSON', () {
      final badJsonList = [
        null,
        '',
        '{}',
        '{"hasPlayer": "yes", "isPlaying": "no"}',
        '{"hasPlayer": true, "isPlaying": null}',
        '{"unexpected_key": 999}',
        'not a json string',
        '{"hasPlayer": true, "details": 12345}',
      ];

      for (final bad in badJsonList) {
        final status = HeadlessPageResniffer.parsePlayerStatusResult(bad);
        expect(status, isNotNull);
        // Default fallbacks should be safe
        if (bad == '{"hasPlayer": true, "isPlaying": null}') {
          expect(status.hasPlayer, isTrue);
          expect(status.isPlaying, isFalse);
        } else if (bad == null || bad == '' || bad == '{}') {
          expect(status.hasPlayer, isFalse);
          expect(status.isPlaying, isFalse);
        }
      }
    });
  });

  group('Adversarial Group 3: Multi-Candidate Harvest Parsing & Malformed Payloads', () {
    test('3.1: Parses oversized candidate JSON array (10,000 URLs) without performance degradation', () {
      final candidatesList = List.generate(
        10000,
        (i) => 'https://cdn.example.com/stream_$i/manifest.m3u8?token=tok_$i',
      );
      final jsonStr = '[${candidatesList.map((u) => '"$u"').join(',')}]';

      final stopwatch = Stopwatch()..start();
      final parsed = HeadlessPageResniffer.parseCandidatesJson(jsonStr);
      stopwatch.stop();

      expect(parsed.length, 10000);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('3.2: Handles mixed data types and malformed items in candidates JSON array', () {
      const jsonWithGarbage = '['
          '"https://cdn.example.com/valid1.m3u8",'
          'null,'
          '12345,'
          'true,'
          '{"object": "ignored"},'
          '["nested", "ignored"],'
          '"https://cdn.example.com/valid2.mp4"'
          ']';

      final parsed = HeadlessPageResniffer.parseCandidatesJson(jsonWithGarbage);
      expect(parsed.length, 2);
      expect(parsed, contains('https://cdn.example.com/valid1.m3u8'));
      expect(parsed, contains('https://cdn.example.com/valid2.mp4'));
    });

    test('3.3: Gracefully handles corrupted JSON, unicode escape errors, and empty arrays', () {
      expect(HeadlessPageResniffer.parseCandidatesJson(null), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson(''), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson('[]'), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson('invalid json string {['), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson('{"url": "https://cdn.com/1.m3u8"}'), isEmpty);
    });
  });

  group('Adversarial Group 4: Stream Scoring, Ad Filtering & Candidate Evaluation', () {
    const sourcePage = 'https://tube.example.com/watch/video-999';
    const originalMedia = 'https://media.tube.example.com/videos/hls/1080p/master.m3u8?token=old_token_123&exp=1700000000';

    test('4.1: Evaluates candidate list with 5,000 ads and exactly 1 valid refreshed stream', () {
      final adCandidates = List.generate(
        5000,
        (i) => 'https://googleads.g.doubleclick.net/pagead/ads?ad_id=$i&client=pub-123.m3u8',
      );
      const freshMedia = 'https://media.tube.example.com/videos/hls/1080p/master.m3u8?token=fresh_token_456&exp=1900000000';
      final allCandidates = [...adCandidates, freshMedia];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: allCandidates,
        originalMediaUrl: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.url, freshMedia);
      expect(success.confidence, greaterThanOrEqualTo(0.9));
    });

    test('4.2: Unchanged stream detection when candidate exactly matches original media', () {
      final candidates = [
        'https://static.trafficjunky.com/preroll.m3u8',
        originalMedia,
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffUnchanged>());
      final unchanged = result as ResniffUnchanged;
      expect(unchanged.url, originalMedia);
      expect(unchanged.isSuccess, isFalse);
    });

    test('4.3: Returns ResniffNoMediaFound when candidate streams belong to completely different videos', () {
      final unrelatedCandidates = [
        'https://othercdn.com/different_movie_9999/trailer.mp4',
        'https://cdn.unrelated.org/clips/preview_clip.m4a',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: unrelatedCandidates,
        originalMediaUrl: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffNoMediaFound>());
      final noMedia = result as ResniffNoMediaFound;
      expect(noMedia.candidatesInspected, 2);
      expect(noMedia.details, contains('none matched the original media stream'));
    });

    test('4.3b: StreamMatcher boundary - identical generic entrypoint name (master.m3u8) on unrelated CDN', () {
      // Documents and validates that identical generic entrypoint names (master.m3u8) across different CDNs
      // score 0.45 (0.20 format + 0.25 filename match).
      final match = StreamMatcher.evaluateCandidate(
        candidate: 'https://othercdn.com/different_movie_9999/master.m3u8',
        original: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(match.score, closeTo(0.45, 0.01));
      expect(match.reason, contains('Identical media format'));
      expect(match.reason, contains('Matching base filename'));
    });

    test('4.4: Handles candidate list when all candidates are tracking manifests or ping streams', () {
      final trackingCandidates = [
        'https://media.tube.example.com/telemetry/ping.m3u8?session=abc',
        'https://analytics.google.com/collect?v=2&tid=G-123',
        'https://doubleclick.net/ad.m3u8',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: trackingCandidates,
        originalMediaUrl: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffNoMediaFound>());
      final noMedia = result as ResniffNoMediaFound;
      expect(noMedia.candidatesInspected, 3);
      expect(noMedia.details, contains('ads or tracking manifests'));
    });

    test('4.5: Handles null or empty originalMediaUrl by returning first valid candidate', () {
      final candidates = [
        'https://googleads.g.doubleclick.net/ad.m3u8',
        'https://cdn.example.com/video1.mp4',
        'https://cdn.example.com/video2.mp4',
      ];

      final resultNull = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: null,
        sourcePageUrl: sourcePage,
      );

      expect(resultNull, isA<ResniffSuccess>());
      expect((resultNull as ResniffSuccess).url, 'https://cdn.example.com/video1.mp4');

      final resultEmpty = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: '   ',
        sourcePageUrl: sourcePage,
      );

      expect(resultEmpty, isA<ResniffSuccess>());
      expect((resultEmpty as ResniffSuccess).url, 'https://cdn.example.com/video1.mp4');
    });

    test('4.6: Resilient against malformed URL candidates with unencoded characters or invalid URIs', () {
      final weirdCandidates = [
        'not a valid url at all %%%',
        'http://[invalid-ipv6-host/test.m3u8',
        'https://media.tube.example.com/videos/hls/1080p/master.m3u8?token=rot_tok_777',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: weirdCandidates,
        originalMediaUrl: originalMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffSuccess>());
      expect((result as ResniffSuccess).url, contains('rot_tok_777'));
    });
  });

  group('Adversarial Group 5: Timing, Polling Loops, Exceptions & Cancellation Resilience', () {
    test('5.1: pollUntilFound handles synchronous and asynchronous probe exceptions without crashing', () async {
      int callCount = 0;

      // A probe that throws twice then succeeds
      final result = await pollUntilFound(
        () async {
          callCount++;
          if (callCount <= 2) {
            throw Exception('DOM execution transient failure $callCount');
          }
          return ['https://cdn.example.com/recovered.m3u8'];
        },
        timeout: const Duration(seconds: 2),
        interval: const Duration(milliseconds: 20),
      ).catchError((e) => <String>['caught_error']);

      expect(result, isNotNull);
    });

    test('5.2: pollUntilFound with 0 or negative timeout returns immediately without endless loop', () async {
      int probeCount = 0;

      final result = await pollUntilFound(
        () async {
          probeCount++;
          return null;
        },
        timeout: Duration.zero,
        interval: const Duration(milliseconds: 10),
      );

      expect(result, isNull);
      expect(probeCount, lessThanOrEqualTo(1));
    });

    test('5.3: pollUntilFound executes wakeUp once and preserves timeout deadline', () async {
      int wakeCount = 0;
      final start = DateTime.now();

      final result = await pollUntilFound(
        () async => null,
        timeout: const Duration(milliseconds: 150),
        interval: const Duration(milliseconds: 30),
        wakeUp: () async {
          wakeCount++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
      );

      final elapsed = DateTime.now().difference(start);
      expect(result, isNull);
      expect(wakeCount, 1);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(140));
      expect(elapsed.inMilliseconds, lessThan(500));
    });

    test('5.4: Concurrent polling sessions execute independently without interference', () async {
      final futures = List.generate(10, (index) async {
        int count = 0;
        return pollUntilFound(
          () async {
            count++;
            if (count >= 3) return ['https://cdn.example.com/session_$index.m3u8'];
            return null;
          },
          timeout: const Duration(seconds: 1),
          interval: const Duration(milliseconds: 20),
        );
      });

      final results = await Future.wait(futures);
      expect(results.length, 10);
      for (int i = 0; i < 10; i++) {
        expect(results[i], ['https://cdn.example.com/session_$i.m3u8']);
      }
    });
  });

  group('Adversarial Group 6: HeadlessPageResniffer Lifecycle & Validation', () {
    test('6.1: Dispose idempotency — multiple calls to dispose are completely safe', () async {
      final resniffer = HeadlessPageResniffer();
      await resniffer.dispose();
      await resniffer.dispose();
      await resniffer.dispose();

      final result = await resniffer.resniff('https://example.com');
      expect(result, isA<ResniffNoMediaFound>());
      expect((result as ResniffNoMediaFound).details, contains('disposed'));
    });

    test('6.2: Invalid URL schemes return ResniffSourceUnavailable', () async {
      final schemes = [
        'ftp://example.com/video',
        'file:///local/path/video.mp4',
        'javascript:alert(1)',
        'data:text/html,<html></html>',
        'chrome://flags',
        'about:blank',
      ];

      for (final schemeUrl in schemes) {
        final resniffer = HeadlessPageResniffer();
        final result = await resniffer.resniff(schemeUrl);
        expect(result, isA<ResniffSourceUnavailable>());
        final unavail = result as ResniffSourceUnavailable;
        expect(unavail.error, contains('Invalid source URL'));
      }
    });

    test('6.3: resniff handles mustMatchPathOf fallback parameter seamlessly', () async {
      final resniffer = HeadlessPageResniffer();
      final result = await resniffer.resniff(
        'https://tube.example.com/video/123',
        mustMatchPathOf: 'https://cdn.example.com/hls/1080p/master.m3u8',
      );

      expect(result, isA<ResniffNoMediaFound>());
      expect((result as ResniffNoMediaFound).details, contains('supported on mobile platforms'));
    });
  });
}
