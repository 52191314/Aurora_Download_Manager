import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/resniff_result.dart';

void main() {
  group('ResniffResult Sealed Class Hierarchy Tests', () {
    test('ResniffSuccess properties, getters, serialization, and equality', () {
      const headers = {'Referer': 'https://example.com/', 'Authorization': 'Bearer 123'};
      const result = ResniffSuccess(
        'https://cdn.example.com/live/stream.m3u8?token=xyz',
        headers: headers,
        confidence: 0.95,
      );

      expect(result.isSuccess, isTrue);
      expect(result.freshUrl, 'https://cdn.example.com/live/stream.m3u8?token=xyz');
      expect(result.isActionable, isFalse);
      expect(result.confidence, 0.95);
      expect(result.headers, headers);
      expect(result.userFacingMessage, contains('Refreshed stream URL found successfully'));
      expect(result.diagnosticDetails, contains('confidence: 95.0%'));
      expect(result.diagnosticDetails, contains('2 headers'));

      // Serialization round-trip
      final json = result.toJson();
      expect(json['type'], 'success');
      expect(json['url'], 'https://cdn.example.com/live/stream.m3u8?token=xyz');
      expect(json['confidence'], 0.95);
      expect(json['headers'], headers);

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffSuccess>());
      expect(deserialized, equals(result));
      expect(deserialized.hashCode, equals(result.hashCode));

      // Equality checks
      const sameResult = ResniffSuccess(
        'https://cdn.example.com/live/stream.m3u8?token=xyz',
        headers: {'Referer': 'https://example.com/', 'Authorization': 'Bearer 123'},
        confidence: 0.95,
      );
      expect(result, equals(sameResult));

      const diffResult = ResniffSuccess(
        'https://cdn.example.com/live/other.m3u8',
        confidence: 0.8,
      );
      expect(result == diffResult, isFalse);
    });

    test('ResniffUnchanged properties, getters, serialization, and equality', () {
      const result = ResniffUnchanged('https://cdn.example.com/video.mp4');

      expect(result.isSuccess, isFalse);
      expect(result.freshUrl, isNull);
      expect(result.isActionable, isFalse);
      expect(result.url, 'https://cdn.example.com/video.mp4');
      expect(result.userFacingMessage, contains('still active and unchanged'));
      expect(result.diagnosticDetails, 'Unchanged: https://cdn.example.com/video.mp4');

      // Serialization round-trip
      final json = result.toJson();
      expect(json['type'], 'unchanged');
      expect(json['url'], 'https://cdn.example.com/video.mp4');

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffUnchanged>());
      expect(deserialized, equals(result));
      expect(deserialized.hashCode, equals(result.hashCode));
    });

    test('ResniffNoMediaFound handles default and custom details', () {
      const result1 = ResniffNoMediaFound(candidatesInspected: 5);
      expect(result1.isSuccess, isFalse);
      expect(result1.freshUrl, isNull);
      expect(result1.isActionable, isTrue);
      expect(result1.candidatesInspected, 5);
      expect(result1.userFacingMessage, contains('after inspecting 5 candidates'));
      expect(result1.diagnosticDetails, contains('candidatesInspected=5'));

      const result2 = ResniffNoMediaFound(details: 'Custom DOM scan failure');
      expect(result2.userFacingMessage, 'Custom DOM scan failure');
      expect(result2.diagnosticDetails, contains('details=Custom DOM scan failure'));

      const defaultEmpty = ResniffNoMediaFound();
      expect(defaultEmpty.userFacingMessage, 'No media stream detected on the source page.');

      // Serialization round-trip
      final json = result1.toJson();
      expect(json['type'], 'no_media_found');
      expect(json['candidatesInspected'], 5);

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffNoMediaFound>());
      expect(deserialized, equals(result1));
    });

    test('ResniffChallengeDetected handles Cloudflare, Recaptcha, and custom WAFs', () {
      const cfResult = ResniffChallengeDetected(
        challengeType: 'cloudflare_turnstile',
        details: null,
      );
      expect(cfResult.isActionable, isTrue);
      expect(cfResult.challengeType, 'cloudflare_turnstile');
      expect(cfResult.userFacingMessage, contains('Cloudflare verification required'));
      expect(cfResult.diagnosticDetails, contains('challengeType=cloudflare_turnstile'));

      const recaptchaResult = ResniffChallengeDetected(
        challengeType: 'recaptcha_v3',
      );
      expect(recaptchaResult.userFacingMessage, contains('reCAPTCHA required'));

      const hcaptchaResult = ResniffChallengeDetected(
        challengeType: 'hcaptcha',
      );
      expect(hcaptchaResult.userFacingMessage, contains('hCaptcha required'));

      const customResult = ResniffChallengeDetected(
        challengeType: 'akamai_botman',
        details: 'Custom Akamai interstitial challenge',
      );
      expect(customResult.userFacingMessage, 'Custom Akamai interstitial challenge');

      // Serialization round-trip
      final json = cfResult.toJson();
      expect(json['type'], 'challenge_detected');
      expect(json['challengeType'], 'cloudflare_turnstile');

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffChallengeDetected>());
      expect(deserialized, equals(cfResult));
    });

    test('ResniffPageLoadTimeout records duration and last known state', () {
      const result = ResniffPageLoadTimeout(
        elapsed: Duration(seconds: 15),
        lastState: 'dom_polling_active',
      );

      expect(result.isActionable, isTrue);
      expect(result.elapsed, const Duration(seconds: 15));
      expect(result.lastState, 'dom_polling_active');
      expect(result.userFacingMessage, contains('timed out after 15s (state: dom_polling_active)'));
      expect(result.diagnosticDetails, contains('elapsed=15000ms, lastState=dom_polling_active'));

      // Serialization round-trip
      final json = result.toJson();
      expect(json['type'], 'page_load_timeout');
      expect(json['elapsedMs'], 15000);
      expect(json['lastState'], 'dom_polling_active');

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffPageLoadTimeout>());
      expect(deserialized, equals(result));
    });

    test('ResniffSourceUnavailable handles 404, 410, DNS, and generic errors', () {
      const notFoundResult = ResniffSourceUnavailable(
        statusCode: 404,
        error: 'Not Found',
      );
      expect(notFoundResult.isActionable, isTrue);
      expect(notFoundResult.statusCode, 404);
      expect(notFoundResult.isDnsFailure, isFalse);
      expect(notFoundResult.userFacingMessage, contains('HTTP 404'));
      expect(notFoundResult.diagnosticDetails, contains('HTTP 404 (Not Found)'));

      const goneResult = ResniffSourceUnavailable(statusCode: 410);
      expect(goneResult.userFacingMessage, contains('HTTP 410'));

      const dnsResult = ResniffSourceUnavailable(isDnsFailure: true);
      expect(dnsResult.isDnsFailure, isTrue);
      expect(dnsResult.userFacingMessage, contains('DNS failure'));
      expect(dnsResult.diagnosticDetails, contains('DNS failure'));

      const serverError = ResniffSourceUnavailable(
        statusCode: 503,
        error: 'Service Unavailable',
      );
      expect(serverError.userFacingMessage, contains('HTTP 503: Service Unavailable'));

      // Serialization round-trip
      final json = notFoundResult.toJson();
      expect(json['type'], 'source_unavailable');
      expect(json['statusCode'], 404);

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffSourceUnavailable>());
      expect(deserialized, equals(notFoundResult));
    });

    test('ResniffPlayerInteractionRequired formats message and serialization', () {
      const defaultResult = ResniffPlayerInteractionRequired();
      expect(defaultResult.isActionable, isTrue);
      expect(defaultResult.userFacingMessage, contains('Player requires manual interaction'));
      expect(defaultResult.diagnosticDetails, 'PlayerInteractionRequired');

      const customResult = ResniffPlayerInteractionRequired(
        details: 'Age verification modal blocking autoplay',
      );
      expect(customResult.userFacingMessage, 'Age verification modal blocking autoplay');
      expect(customResult.diagnosticDetails, contains('Age verification modal blocking autoplay'));

      // Serialization round-trip
      final json = customResult.toJson();
      expect(json['type'], 'player_interaction_required');
      expect(json['details'], 'Age verification modal blocking autoplay');

      final deserialized = ResniffResult.fromJson(json);
      expect(deserialized, isA<ResniffPlayerInteractionRequired>());
      expect(deserialized, equals(customResult));
    });

    test('Exhaustive pattern matching covers all variants without default branch', () {
      final List<ResniffResult> results = [
        const ResniffSuccess('https://cdn.example.com/video.m3u8'),
        const ResniffUnchanged('https://cdn.example.com/video.m3u8'),
        const ResniffNoMediaFound(candidatesInspected: 3),
        const ResniffChallengeDetected(challengeType: 'cloudflare_turnstile'),
        const ResniffPageLoadTimeout(elapsed: Duration(seconds: 10)),
        const ResniffSourceUnavailable(statusCode: 404),
        const ResniffPlayerInteractionRequired(details: 'Click required'),
      ];

      for (final res in results) {
        final category = switch (res) {
          ResniffSuccess() => 'success',
          ResniffUnchanged() => 'unchanged',
          ResniffNoMediaFound() => 'no_media_found',
          ResniffChallengeDetected() => 'challenge_detected',
          ResniffPageLoadTimeout() => 'page_load_timeout',
          ResniffSourceUnavailable() => 'source_unavailable',
          ResniffPlayerInteractionRequired() => 'player_interaction_required',
        };
        expect(category, isNotEmpty);
      }
    });

    test('ResniffResult.fromJson handles unrecognized type gracefully', () {
      final fallback = ResniffResult.fromJson({'type': 'invalid_unknown_type'});
      expect(fallback, isA<ResniffNoMediaFound>());
      expect((fallback as ResniffNoMediaFound).details, contains('Unrecognized result type'));
    });
  });
}
