import 'package:aurora_downloader/sniffer/headless_resniffer.dart';
import 'package:aurora_downloader/sniffer/resniff_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeadlessPageResniffer — Candidate Evaluation & Scoring Integration', () {
    const sourcePage = 'https://tube.example.com/watch/video-12345';
    const staleMedia = 'https://cdn.stream.example.com/hls/token_111/master.m3u8';

    test('returns ResniffNoMediaFound when candidates list is empty', () {
      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: [],
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffNoMediaFound>());
      final noMedia = result as ResniffNoMediaFound;
      expect(noMedia.candidatesInspected, 0);
      expect(noMedia.isActionable, isTrue);
      expect(noMedia.userFacingMessage, contains('No candidate media URLs found'));
    });

    test('returns ResniffNoMediaFound when all candidates are ads or tracking URLs', () {
      final candidates = [
        'https://googleads.g.doubleclick.net/pagead/ads?client=ca-pub-123',
        'https://static.trafficjunky.com/ads/vast_preroll.m3u8',
        'https://cdn.stream.example.com/telemetry/ping.m3u8?session=abc',
        'https://analytics.google.com/collect?v=2&tid=G-123',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffNoMediaFound>());
      final noMedia = result as ResniffNoMediaFound;
      expect(noMedia.candidatesInspected, 4);
      expect(noMedia.details, contains('ads or tracking manifests'));
    });

    test('returns ResniffUnchanged when candidate is identical to originalMediaUrl', () {
      final candidates = [
        'https://static.trafficjunky.com/preroll.m3u8',
        staleMedia,
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffUnchanged>());
      final unchanged = result as ResniffUnchanged;
      expect(unchanged.url, staleMedia);
      expect(unchanged.isSuccess, isFalse);
      expect(unchanged.userFacingMessage, contains('still active and unchanged'));
    });

    test('returns ResniffSuccess when candidate is refreshed token with same host and path', () {
      const freshMedia = 'https://cdn.stream.example.com/hls/token_111/master.m3u8?token=fresh_999&exp=1800000000';
      final candidates = [
        'https://googleads.g.doubleclick.net/vast.m3u8',
        freshMedia,
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.url, freshMedia);
      expect(success.isSuccess, isTrue);
      expect(success.confidence, closeTo(0.99, 0.01));
      expect(success.userFacingMessage, contains('found successfully'));
    });

    test('returns ResniffSuccess when candidate has rotated subpath token', () {
      const freshRotated = 'https://cdn.stream.example.com/hls/token_222_rotated_hash/master.m3u8';
      final candidates = [
        'https://other.domain.com/unrelated/preview.mp4',
        freshRotated,
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.url, freshRotated);
      expect(success.confidence, greaterThanOrEqualTo(0.5));
    });

    test('returns ResniffNoMediaFound when candidates exist but none match originalMediaUrl', () {
      final candidates = [
        'https://othercdn.com/different_movie/sample.mp4',
        'https://thirdparty.org/random/clip.mp3',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: staleMedia,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffNoMediaFound>());
      final noMedia = result as ResniffNoMediaFound;
      expect(noMedia.candidatesInspected, 2);
      expect(noMedia.details, contains('none matched the original media stream'));
    });

    test('returns ResniffSuccess with first candidate when originalMediaUrl is null (general discovery)', () {
      final candidates = [
        'https://googleads.g.doubleclick.net/vast.m3u8',
        'https://cdn.stream.example.com/hls/master.m3u8',
        'https://cdn.stream.example.com/hls/720p.m3u8',
      ];

      final result = HeadlessPageResniffer.evaluateCandidates(
        candidates: candidates,
        originalMediaUrl: null,
        sourcePageUrl: sourcePage,
      );

      expect(result, isA<ResniffSuccess>());
      final success = result as ResniffSuccess;
      expect(success.url, 'https://cdn.stream.example.com/hls/master.m3u8');
      expect(success.confidence, 1.0);
    });
  });

  group('HeadlessPageResniffer — Security Challenge Detection Parser', () {
    test('parses Cloudflare Turnstile challenge element result', () {
      const json = '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare Turnstile challenge element detected (#challenge-stage)"}';
      final challenge = HeadlessPageResniffer.parseChallengeDetectionResult(json);

      expect(challenge, isNotNull);
      expect(challenge!.challengeType, 'cloudflare_turnstile');
      expect(challenge.details, contains('#challenge-stage'));
      expect(challenge.isActionable, isTrue);
      expect(challenge.userFacingMessage, contains('#challenge-stage'));
    });

    test('parses Cloudflare title challenge detection result', () {
      const json = '{"detected":true,"type":"cloudflare_turnstile","details":"Cloudflare challenge page title detected: \\"Just a moment...\\""}';
      final challenge = HeadlessPageResniffer.parseChallengeDetectionResult(json);

      expect(challenge, isNotNull);
      expect(challenge!.challengeType, 'cloudflare_turnstile');
      expect(challenge.details, contains('Just a moment...'));
    });

    test('parses reCAPTCHA challenge result', () {
      const json = '{"detected":true,"type":"recaptcha","details":"reCAPTCHA challenge element detected (.g-recaptcha)"}';
      final challenge = HeadlessPageResniffer.parseChallengeDetectionResult(json);

      expect(challenge, isNotNull);
      expect(challenge!.challengeType, 'recaptcha');
      expect(challenge.details, contains('.g-recaptcha'));
    });

    test('parses hCaptcha challenge result', () {
      const json = '{"detected":true,"type":"hcaptcha","details":"hCaptcha challenge element detected (.h-captcha)"}';
      final challenge = HeadlessPageResniffer.parseChallengeDetectionResult(json);

      expect(challenge, isNotNull);
      expect(challenge!.challengeType, 'hcaptcha');
      expect(challenge.details, contains('.h-captcha'));
    });

    test('parses generic WAF challenge result', () {
      const json = '{"detected":true,"type":"generic_waf","details":"WAF challenge element detected (#ddos-guard)"}';
      final challenge = HeadlessPageResniffer.parseChallengeDetectionResult(json);

      expect(challenge, isNotNull);
      expect(challenge!.challengeType, 'generic_waf');
      expect(challenge.details, contains('#ddos-guard'));
    });

    test('returns null when detected is false or JSON is empty', () {
      expect(HeadlessPageResniffer.parseChallengeDetectionResult('{"detected":false}'), isNull);
      expect(HeadlessPageResniffer.parseChallengeDetectionResult(''), isNull);
      expect(HeadlessPageResniffer.parseChallengeDetectionResult(null), isNull);
      expect(HeadlessPageResniffer.parseChallengeDetectionResult('invalid-json'), isNull);
    });
  });

  group('HeadlessPageResniffer — Player Status Parser', () {
    test('parses paused player requiring interaction', () {
      const json = '{"hasPlayer":true,"isPlaying":false,"details":"Found 1 video element(s) in paused or unplayed state."}';
      final status = HeadlessPageResniffer.parsePlayerStatusResult(json);

      expect(status.hasPlayer, isTrue);
      expect(status.isPlaying, isFalse);
      expect(status.details, contains('paused or unplayed state'));
    });

    test('parses actively playing player', () {
      const json = '{"hasPlayer":true,"isPlaying":true,"details":""}';
      final status = HeadlessPageResniffer.parsePlayerStatusResult(json);

      expect(status.hasPlayer, isTrue);
      expect(status.isPlaying, isTrue);
    });

    test('parses overlay play button requiring user gesture', () {
      const json = '{"hasPlayer":true,"isPlaying":false,"details":"Play button overlay detected requiring user gesture."}';
      final status = HeadlessPageResniffer.parsePlayerStatusResult(json);

      expect(status.hasPlayer, isTrue);
      expect(status.isPlaying, isFalse);
      expect(status.details, contains('Play button overlay'));
    });

    test('parses empty or invalid player status gracefully', () {
      final status = HeadlessPageResniffer.parsePlayerStatusResult('{}');
      expect(status.hasPlayer, isFalse);
      expect(status.isPlaying, isFalse);

      final statusNull = HeadlessPageResniffer.parsePlayerStatusResult(null);
      expect(statusNull.hasPlayer, isFalse);
      expect(statusNull.isPlaying, isFalse);
    });
  });

  group('HeadlessPageResniffer — Candidates JSON Parser', () {
    test('parses valid JSON array of URLs', () {
      const json = '["https://cdn.example.com/master.m3u8", "https://cdn.example.com/720p.m3u8"]';
      final candidates = HeadlessPageResniffer.parseCandidatesJson(json);

      expect(candidates.length, 2);
      expect(candidates[0], 'https://cdn.example.com/master.m3u8');
      expect(candidates[1], 'https://cdn.example.com/720p.m3u8');
    });

    test('parses empty or malformed JSON array', () {
      expect(HeadlessPageResniffer.parseCandidatesJson('[]'), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson(null), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson('not-json'), isEmpty);
      expect(HeadlessPageResniffer.parseCandidatesJson('{"url": "test"}'), isEmpty);
    });
  });

  group('HeadlessPageResniffer — pollUntilFound Timing Utility', () {
    test('returns immediately on first probe when non-empty list is returned', () async {
      int probeCount = 0;
      bool wakeCalled = false;

      final result = await pollUntilFound(
        () async {
          probeCount++;
          return ['https://cdn.example.com/stream.m3u8'];
        },
        timeout: const Duration(seconds: 2),
        interval: const Duration(milliseconds: 50),
        wakeUp: () async {
          wakeCalled = true;
        },
      );

      expect(result, ['https://cdn.example.com/stream.m3u8']);
      expect(probeCount, 1);
      expect(wakeCalled, isFalse);
    });

    test('invokes wakeUp once after first empty probe and returns on subsequent probe', () async {
      int probeCount = 0;
      int wakeCount = 0;

      final result = await pollUntilFound(
        () async {
          probeCount++;
          if (probeCount >= 3) {
            return ['https://cdn.example.com/delayed.m3u8'];
          }
          return null;
        },
        timeout: const Duration(seconds: 2),
        interval: const Duration(milliseconds: 30),
        wakeUp: () async {
          wakeCount++;
        },
      );

      expect(result, ['https://cdn.example.com/delayed.m3u8']);
      expect(probeCount, 3);
      expect(wakeCount, 1); // Only invoked once
    });

    test('returns null when timeout elapses with no matching streams', () async {
      int wakeCount = 0;

      final result = await pollUntilFound(
        () async => null,
        timeout: const Duration(milliseconds: 120),
        interval: const Duration(milliseconds: 30),
        wakeUp: () async {
          wakeCount++;
        },
      );

      expect(result, isNull);
      expect(wakeCount, 1);
    });
  });

  group('HeadlessPageResniffer — Instance Lifecycle & Validation', () {
    test('returns ResniffNoMediaFound when resniffer is disposed', () async {
      final resniffer = HeadlessPageResniffer();
      await resniffer.dispose();

      final result = await resniffer.resniff('https://example.com/video');
      expect(result, isA<ResniffNoMediaFound>());
      expect((result as ResniffNoMediaFound).details, contains('disposed'));

      final allResult = await resniffer.resniffAll('https://example.com/video');
      expect(allResult, isEmpty);
    });

    test('returns ResniffSourceUnavailable when sourcePageUrl has invalid scheme', () async {
      final resniffer = HeadlessPageResniffer();
      final result = await resniffer.resniff('ftp://invalid.com/file');

      expect(result, isA<ResniffSourceUnavailable>());
      final unavail = result as ResniffSourceUnavailable;
      expect(unavail.error, contains('Invalid source URL'));
    });

    test('resniffAll returns empty list for invalid URL', () async {
      final resniffer = HeadlessPageResniffer();
      final result = await resniffer.resniffAll('ftp://invalid.com/file');
      expect(result, isEmpty);
    });
  });
}
