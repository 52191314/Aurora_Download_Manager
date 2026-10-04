import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/resniff_result.dart';

void main() {
  group('ResniffResult Adversarial & Exhaustive Round-Trip Suite', () {
    test('All 7 ResniffResult variants round-trip through JSON perfectly', () {
      final List<ResniffResult> allVariants = [
        // 1. ResniffSuccess variations
        const ResniffSuccess(
          'https://cdn.example.com/hls/master.m3u8?token=xyz123&exp=1700000000',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Adversarial/1.0)',
            'Cookie': 'session=abc; cf_clearance=def456',
            'X-Custom-Header': 'test_val:123',
            'Referer': 'https://source.example.com/watch?v=999',
          },
          confidence: 0.9876,
        ),
        const ResniffSuccess(
          'https://edge01.stream.org/video.mp4',
          confidence: 0.0,
        ),
        const ResniffSuccess(
          'https://cdn.unicode-test.org/hls/🎬_영상_stream.m3u8',
          headers: {},
          confidence: 1.0,
        ),

        // 2. ResniffUnchanged variations
        const ResniffUnchanged('https://cdn.example.com/static/file.mp4'),
        const ResniffUnchanged('http://192.168.1.100:8080/live/feed.ts'),

        // 3. ResniffNoMediaFound variations
        const ResniffNoMediaFound(),
        const ResniffNoMediaFound(candidatesInspected: 150),
        const ResniffNoMediaFound(
          details: 'Inspected 12 <video> tags and 45 network requests, zero media found.',
          candidatesInspected: 57,
        ),

        // 4. ResniffChallengeDetected variations
        const ResniffChallengeDetected(challengeType: 'cloudflare_turnstile'),
        const ResniffChallengeDetected(challengeType: 'cloudflare'),
        const ResniffChallengeDetected(challengeType: 'recaptcha_v2'),
        const ResniffChallengeDetected(challengeType: 'recaptcha_v3'),
        const ResniffChallengeDetected(challengeType: 'hcaptcha'),
        const ResniffChallengeDetected(
          challengeType: 'custom_datadome',
          details: 'DataDome captcha challenge intercepted at #dd-modal',
        ),

        // 5. ResniffPageLoadTimeout variations
        const ResniffPageLoadTimeout(),
        const ResniffPageLoadTimeout(
          elapsed: Duration(milliseconds: 35420),
          lastState: 'evaluating_player_ready_state',
        ),
        const ResniffPageLoadTimeout(
          elapsed: Duration.zero,
          lastState: 'initial_navigation',
        ),

        // 6. ResniffSourceUnavailable variations
        const ResniffSourceUnavailable(statusCode: 404, error: 'Page Not Found'),
        const ResniffSourceUnavailable(statusCode: 410, error: 'Resource Gone'),
        const ResniffSourceUnavailable(statusCode: 500, error: 'Internal Server Error'),
        const ResniffSourceUnavailable(statusCode: 503, error: 'Backend Unreachable'),
        const ResniffSourceUnavailable(isDnsFailure: true, error: 'NXDOMAIN'),
        const ResniffSourceUnavailable(error: 'Connection refused (ERR_CONNECTION_REFUSED)'),

        // 7. ResniffPlayerInteractionRequired variations
        const ResniffPlayerInteractionRequired(),
        const ResniffPlayerInteractionRequired(
          details: 'Click-to-play overlay with custom SVG play icon (.vjs-big-play-button)',
        ),
      ];

      for (final original in allVariants) {
        final jsonMap = original.toJson();
        final jsonStr = original.toString(); // jsonEncode(toJson())
        
        // Verify toString is valid json
        final parsedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(parsedMap, equals(jsonMap));

        // Verify deserialization matches original
        final deserialized = ResniffResult.fromJson(jsonMap);
        expect(deserialized.runtimeType, equals(original.runtimeType));
        expect(deserialized, equals(original));
        expect(deserialized.hashCode, equals(original.hashCode));
        expect(deserialized.isSuccess, equals(original.isSuccess));
        expect(deserialized.freshUrl, equals(original.freshUrl));
        expect(deserialized.isActionable, equals(original.isActionable));
        expect(deserialized.userFacingMessage, equals(original.userFacingMessage));
        expect(deserialized.diagnosticDetails, equals(original.diagnosticDetails));
      }
    });

    test('ResniffResult.fromJson handles corrupted, partial, or anomalous payloads safely', () {
      // 1. Missing type
      final noType = ResniffResult.fromJson({});
      expect(noType, isA<ResniffNoMediaFound>());
      expect((noType as ResniffNoMediaFound).details, contains('Unrecognized result type'));

      // 2. Null type
      final nullType = ResniffResult.fromJson({'type': null});
      expect(nullType, isA<ResniffNoMediaFound>());

      // 3. Success with string confidence or missing fields
      final stringConf = ResniffResult.fromJson({
        'type': 'success',
        'url': 'https://cdn.example.com/video.mp4',
        'confidence': 0.85,
        'headers': {'int_val': 12345, 'bool_val': true},
      });
      expect(stringConf, isA<ResniffSuccess>());
      final success = stringConf as ResniffSuccess;
      expect(success.headers!['int_val'], '12345');
      expect(success.headers!['bool_val'], 'true');

      // 4. SourceUnavailable with string status or nulls
      final sourceUnavail = ResniffResult.fromJson({
        'type': 'source_unavailable',
        'statusCode': 404,
        'isDnsFailure': null,
      });
      expect(sourceUnavail, isA<ResniffSourceUnavailable>());
      expect((sourceUnavail as ResniffSourceUnavailable).statusCode, 404);
      expect(sourceUnavail.isDnsFailure, isFalse);

      // 5. PageLoadTimeout with unexpected elapsed types
      final timeoutObj = ResniffResult.fromJson({
        'type': 'page_load_timeout',
        'elapsedMs': 12345.67,
      });
      expect(timeoutObj, isA<ResniffPageLoadTimeout>());
      expect((timeoutObj as ResniffPageLoadTimeout).elapsed.inMilliseconds, 12345);
    });

    test('ResniffResult diagnostic messages and user-facing messages are honest and informative', () {
      // Unchanged does not claim success
      const unchanged = ResniffUnchanged('https://example.com/video.mp4');
      expect(unchanged.isSuccess, isFalse);
      expect(unchanged.freshUrl, isNull);
      expect(unchanged.userFacingMessage, isNot(contains('Refreshed')));
      expect(unchanged.userFacingMessage, contains('unchanged'));

      // NoMediaFound does not say success
      const noMedia = ResniffNoMediaFound(candidatesInspected: 4);
      expect(noMedia.isSuccess, isFalse);
      expect(noMedia.userFacingMessage, contains('No matching media stream'));
      expect(noMedia.isActionable, isTrue);

      // ChallengeDetected informs user actionable action
      const challenge = ResniffChallengeDetected(challengeType: 'cloudflare_turnstile');
      expect(challenge.isActionable, isTrue);
      expect(challenge.userFacingMessage, contains('Cloudflare verification required'));

      // DNS failure
      const dnsFail = ResniffSourceUnavailable(isDnsFailure: true);
      expect(dnsFail.userFacingMessage, contains('DNS failure'));
    });
  });
}
