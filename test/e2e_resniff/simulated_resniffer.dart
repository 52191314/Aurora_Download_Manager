import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'resniff_test_contracts.dart';

/// Simulated Headless Page Resniffer for opaque-box E2E testing without
/// platform-dependent WebView binary requirements.
class SimulatedHeadlessResniffer {
  final http.Client _client;
  final Duration timeout;
  final Map<String, String> defaultCookies;
  final Map<String, String> defaultHeaders;

  SimulatedHeadlessResniffer({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.defaultCookies = const {},
    this.defaultHeaders = const {},
  }) : _client = client ?? http.Client();

  /// Performs headless resniffing against [sourcePageUrl] with optional [mustMatchPathOf].
  Future<ResniffResult> resniff(
    String sourcePageUrl, {
    String? mustMatchPathOf,
    Map<String, String>? customHeaders,
    Map<String, String>? customCookies,
    bool simulatePlayerInteractionNeeded = false,
  }) async {
    if (!sourcePageUrl.startsWith('http://') &&
        !sourcePageUrl.startsWith('https://')) {
      return const ResniffSourceUnavailable(
        error: 'Invalid or unsupported scheme',
      );
    }

    final headers = <String, String>{
      ...defaultHeaders,
      ...?customHeaders,
    };

    final cookies = <String, String>{
      ...defaultCookies,
      ...?customCookies,
    };

    if (cookies.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] =
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    try {
      final uri = Uri.parse(sourcePageUrl);
      final response = await _client.get(uri, headers: headers).timeout(timeout);

      // HTTP Error Handling
      if (response.statusCode >= 400) {
        return ResniffSourceUnavailable(
          statusCode: response.statusCode,
          error: response.body,
        );
      }

      final body = response.body;

      // 1. Detect WAF / Security Challenges
      if (body.contains('cf-turnstile') ||
          body.contains('cloudflare-turnstile') ||
          body.contains('Just a moment...') ||
          body.contains('challenge-platform')) {
        return const ResniffChallengeDetected(
          challengeType: 'cloudflare_turnstile',
          details: 'Cloudflare Turnstile challenge page intercepted',
        );
      }
      if (body.contains('g-recaptcha') || body.contains('recaptcha')) {
        return const ResniffChallengeDetected(
          challengeType: 'recaptcha',
          details: 'Google reCAPTCHA challenge intercepted',
        );
      }

      // 2. Check Click-to-Play interaction requirement
      if (simulatePlayerInteractionNeeded) {
        return const ResniffPlayerInteractionRequired(
          details: 'Video player requires user play gesture',
        );
      }

      // 3. Extract Candidates from DOM & Scripts
      final candidates = _extractCandidates(body, sourcePageUrl);
      if (candidates.isEmpty) {
        return const ResniffNoMediaFound(
          details: 'No video/source/script media URLs detected in DOM',
          candidatesInspected: 0,
        );
      }

      // 4. Match Candidates with StreamMatcher
      if (mustMatchPathOf != null) {
        final match = StreamMatcher.findBestMatch(
          candidates: candidates,
          originalMediaUrl: mustMatchPathOf,
          sourcePageUrl: sourcePageUrl,
        );

        if (match == null) {
          return ResniffNoMediaFound(
            details: 'None of ${candidates.length} candidates matched original stream path',
            candidatesInspected: candidates.length,
          );
        }

        if (match.url == mustMatchPathOf) {
          return ResniffUnchanged(match.url);
        }

        return ResniffSuccess(
          match.url,
          confidence: match.score,
          headers: headers,
        );
      } else {
        // Without mustMatchPathOf, filter ads and take best candidate
        final validCandidates =
            candidates.where((c) => !StreamMatcher.isAdOrTrackingUrl(c)).toList();
        if (validCandidates.isEmpty) {
          return const ResniffNoMediaFound(
            details: 'All extracted candidates were identified as ads or trackers',
            candidatesInspected: 0,
          );
        }
        return ResniffSuccess(
          validCandidates.first,
          confidence: 0.95,
          headers: headers,
        );
      }
    } on TimeoutException {
      return ResniffPageLoadTimeout(
        elapsed: timeout,
        lastState: 'network_read_timeout',
      );
    } on http.ClientException catch (e) {
      final isDns = e.message.contains('Failed host lookup') ||
          e.message.contains('11001') ||
          e.message.contains('No such host') ||
          e.message.contains('not known');
      return ResniffSourceUnavailable(
        error: e.message,
        isDnsFailure: isDns,
      );
    } on SocketException catch (e) {
      final isDns = e.osError?.errorCode == 11001 ||
          e.message.contains('Failed host lookup') ||
          e.message.contains('No such host');
      return ResniffSourceUnavailable(
        error: e.message,
        isDnsFailure: isDns,
      );
    } catch (e) {
      final msg = e.toString();
      final isDns = msg.contains('Failed host lookup') ||
          msg.contains('11001') ||
          msg.contains('No such host');
      return ResniffSourceUnavailable(
        error: msg,
        isDnsFailure: isDns,
      );
    }
  }

  List<String> _extractCandidates(String html, String pageUrl) {
    final results = <String>{};

    // Regex for src="url" in <source> and <video>
    final srcRegex = RegExp(r'''(?:src|source)=["']([^"']+\.(?:m3u8|mpd|mp4)[^"']*)["']''', caseSensitive: false);
    for (final match in srcRegex.allMatches(html)) {
      final url = match.group(1);
      if (url != null) results.add(_resolveUrl(url, pageUrl));
    }

    // Regex for direct script matches
    final scriptRegex = RegExp(r'''https?://[^\s"'<>]+\.(?:m3u8|mpd|mp4)(?:\?[^\s"'<>]*)?''', caseSensitive: false);
    for (final match in scriptRegex.allMatches(html)) {
      final url = match.group(0);
      if (url != null) results.add(url);
    }

    return results.toList();
  }

  String _resolveUrl(String relativeOrAbsolute, String pageUrl) {
    try {
      final base = Uri.parse(pageUrl);
      return base.resolve(relativeOrAbsolute).toString();
    } catch (_) {
      return relativeOrAbsolute;
    }
  }
}

/// Simulated Token Refresh Coordinator that manages auto-budget limits and gating.
class SimulatedTokenRefreshService {
  static const int maxAutoTries = 2;
  static final Map<String, int> _autoTried = {};

  static bool autoBudgetExhausted(String taskId) =>
      (_autoTried[taskId] ?? 0) >= maxAutoTries;

  static void recordAutoTry(String taskId) {
    _autoTried[taskId] = (_autoTried[taskId] ?? 0) + 1;
  }

  static void resetBudget(String taskId) {
    _autoTried.remove(taskId);
  }

  static Future<ResniffResult> autoRefresh({
    required String taskId,
    required String? sourcePageUrl,
    required String originalUrl,
    required bool allowed,
    required SimulatedHeadlessResniffer resniffer,
  }) async {
    if (!allowed) {
      return const ResniffSourceUnavailable(
        error: 'Automatic link repair is an Aurora Pro feature.',
      );
    }
    if (autoBudgetExhausted(taskId)) {
      return const ResniffSourceUnavailable(
        error: 'Automatic retry budget exhausted (2 tries reached).',
      );
    }
    recordAutoTry(taskId);

    if (sourcePageUrl == null || !sourcePageUrl.startsWith('http')) {
      return const ResniffNoMediaFound(
        details: 'Task has no valid sourcePageUrl',
      );
    }

    return resniffer.resniff(
      sourcePageUrl,
      mustMatchPathOf: originalUrl,
    );
  }
}
