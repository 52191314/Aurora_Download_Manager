import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'resniff_result.dart';
import 'stream_matcher.dart';


/// JavaScript for detecting Cloudflare Turnstile, Cloudflare Challenge, reCAPTCHA,
/// hCaptcha, or generic WAF verification pages in the DOM.
const String _kChallengeDetectionJs = r'''
(() => {
  try {
    const title = (document.title || '').toLowerCase();
    const bodyText = (document.body ? document.body.innerText || document.body.textContent || '' : '').toLowerCase();

    // 1. Cloudflare Turnstile / Challenge
    const cfSelectors = [
      '#challenge-stage',
      '#cf-turnstile-wrapper',
      '#cf-challenge-running',
      '.cf-turnstile',
      '#challenge-form',
      '.cf-browser-verification',
      '#cf-wrapper',
      'iframe[src*="challenges.cloudflare.com"]',
      'iframe[src*="turnstile"]',
      '#turnstile-wrapper'
    ];
    for (const sel of cfSelectors) {
      const el = document.querySelector(sel);
      if (el) {
        return JSON.stringify({
          detected: true,
          type: 'cloudflare_turnstile',
          details: 'Cloudflare Turnstile challenge element detected (' + sel + ')'
        });
      }
    }
    if (title.includes('just a moment...') ||
        title.includes('attention required! | cloudflare') ||
        (title.includes('cloudflare') && title.includes('moment'))) {
      return JSON.stringify({
        detected: true,
        type: 'cloudflare_turnstile',
        details: 'Cloudflare challenge page title detected: "' + document.title + '"'
      });
    }
    if (bodyText.includes('verify you are human') && (bodyText.includes('cloudflare') || document.querySelector('#challenge-running'))) {
      return JSON.stringify({
        detected: true,
        type: 'cloudflare_turnstile',
        details: 'Cloudflare human verification text detected'
      });
    }

    // 2. reCAPTCHA
    const recaptchaSelectors = [
      '.g-recaptcha',
      '#g-recaptcha',
      'iframe[src*="google.com/recaptcha"]',
      'iframe[src*="recaptcha"]',
      '#recaptcha',
      '.recaptcha'
    ];
    for (const sel of recaptchaSelectors) {
      if (document.querySelector(sel)) {
        return JSON.stringify({
          detected: true,
          type: 'recaptcha',
          details: 'reCAPTCHA challenge element detected (' + sel + ')'
        });
      }
    }

    // 3. hCaptcha
    const hcaptchaSelectors = [
      '.h-captcha',
      '#h-captcha',
      'iframe[src*="hcaptcha.com"]',
      'iframe[src*="hcaptcha"]'
    ];
    for (const sel of hcaptchaSelectors) {
      if (document.querySelector(sel)) {
        return JSON.stringify({
          detected: true,
          type: 'hcaptcha',
          details: 'hCaptcha challenge element detected (' + sel + ')'
        });
      }
    }

    // 4. Generic WAF / Bot Block
    const wafSelectors = [
      '#ddos-guard',
      '.ddos-guard',
      '#waf-block',
      '.waf-block',
      '#waf-challenge'
    ];
    for (const sel of wafSelectors) {
      if (document.querySelector(sel)) {
        return JSON.stringify({
          detected: true,
          type: 'generic_waf',
          details: 'WAF challenge element detected (' + sel + ')'
        });
      }
    }
    if (title.includes('access denied') ||
        title.includes('403 forbidden') ||
        title.includes('ddos-guard') ||
        title.includes('security check')) {
      return JSON.stringify({
        detected: true,
        type: 'generic_waf',
        details: 'WAF block page title detected: "' + document.title + '"'
      });
    }
  } catch (e) {
    return JSON.stringify({ detected: false, error: e.toString() });
  }
  return JSON.stringify({ detected: false });
})();
''';

/// JavaScript that inspects the DOM and Performance API for all candidate media URLs.
const String _kMultiMediaCandidatesJs = r'''
(() => {
  try {
    const out = new Set();
    const mediaExtRegex = /\.(m3u8|mpd|mp4|m4s|webm|ts|mkv)(?!\w)/i;

    function addUrl(u) {
      if (!u || typeof u !== 'string') return;
      let clean = u.trim().replace(/\\\/|\/\\/g, '/');
      if (clean.indexOf('//') === 0) clean = 'https:' + clean;
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        if (clean.indexOf('ping.m3u8') === -1 && clean.indexOf('/ping') === -1) {
          out.add(clean);
        }
      }
    }

    function scanDom(root) {
      if (!root || !root.querySelectorAll) return;

      // 1. Source tags
      const sources = root.querySelectorAll('source[src], source[data-src]');
      for (const s of sources) {
        addUrl(s.src || s.getAttribute('src') || s.getAttribute('data-src'));
      }

      // 2. Video / Audio tags
      const medias = root.querySelectorAll('video, audio');
      for (const m of medias) {
        addUrl(m.currentSrc);
        addUrl(m.src);
        addUrl(m.getAttribute('src'));
        addUrl(m.getAttribute('data-src'));
      }

      // 3. Meta tags
      const metas = root.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"], meta[property="twitter:player:stream"], meta[itemprop="contentURL"]');
      for (const mt of metas) {
        addUrl(mt.content || mt.getAttribute('content'));
      }

      // 4. Inline Scripts
      const scripts = root.querySelectorAll('script');
      for (const sc of scripts) {
        const text = sc.textContent || '';
        if (text.length > 500000) continue; // skip massive bundles
        const re = /(?:https?:)?\\?\/\\?\/[^"'`\s<>]+?\.(?:m3u8|mpd|mp4|m4s|webm|ts|mkv)(?!\w)[^"'`\s<>]*/gi;
        let match;
        while ((match = re.exec(text)) !== null) {
          addUrl(match[0]);
        }
      }
    }

    // Scan main document
    scanDom(document);

    // Scan accessible iframes
    const iframes = document.querySelectorAll('iframe');
    for (const f of iframes) {
      try {
        const fr = f.contentDocument;
        if (fr) scanDom(fr);
      } catch (_) {}
    }

    // 5. Global Player JS objects
    try {
      if (window.videojs && typeof window.videojs.getAllPlayers === 'function') {
        const players = window.videojs.getAllPlayers();
        for (const p of players) {
          if (p && typeof p.currentSrc === 'function') addUrl(p.currentSrc());
          if (p && typeof p.src === 'function') addUrl(p.src());
        }
      }
    } catch (_) {}

    try {
      if (window.jwplayer && typeof window.jwplayer === 'function') {
        const jw = window.jwplayer();
        if (jw) {
          if (typeof jw.getPlaylist === 'function') {
            const pl = jw.getPlaylist();
            if (Array.isArray(pl)) {
              for (const item of pl) {
                if (item.file) addUrl(item.file);
                if (Array.isArray(item.sources)) {
                  for (const src of item.sources) {
                    if (src && src.file) addUrl(src.file);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      if (window.player) {
        if (typeof window.player.src === 'string') addUrl(window.player.src);
        if (window.player.options && window.player.options.url) addUrl(window.player.options.url);
      }
      if (window.playerInstance && typeof window.playerInstance.src === 'string') {
        addUrl(window.playerInstance.src);
      }
      if (window.hls && typeof window.hls.url === 'string') {
        addUrl(window.hls.url);
      }
      if (window.dp && window.dp.video && window.dp.video.src) {
        addUrl(window.dp.video.src);
      }
    } catch (_) {}

    // 6. Performance resource entries
    try {
      const entries = performance.getEntriesByType('resource');
      for (const e of entries) {
        const u = e.name;
        if (u && mediaExtRegex.test(u)) {
          addUrl(u);
        } else if (e.initiatorType === 'media' || e.initiatorType === 'video' || e.initiatorType === 'audio') {
          addUrl(u);
        }
      }
    } catch (_) {}

    return JSON.stringify(Array.from(out));
  } catch (err) {
    return '[]';
  }
})();
''';

/// JavaScript to check if an unplayed player or overlay button is present on the page.
const String _kPlayerStatusCheckJs = r'''
(() => {
  try {
    const videos = document.querySelectorAll('video, audio');
    let hasPlayer = false;
    let isPlaying = false;
    let details = '';

    if (videos.length > 0) {
      hasPlayer = true;
      for (const v of videos) {
        if (!v.paused && !v.ended && v.readyState > 2) {
          isPlaying = true;
        }
      }
      if (!isPlaying) {
        details = 'Found ' + videos.length + ' video element(s) in paused or unplayed state.';
      }
    }

    const playerWrappers = document.querySelectorAll('.video-js, .plyr, .jwplayer, .dplayer, [class*="player-container"], [class*="video-player"]');
    if (playerWrappers.length > 0) {
      hasPlayer = true;
      if (!details) {
        details = 'Embedded video player container detected on page.';
      }
    }

    const playButtons = document.querySelectorAll('.vjs-big-play-button, .plyr__control--overlaid, .jw-display-icon-container, [class*="play-button" i], [aria-label*="Play" i]');
    if (playButtons.length > 0) {
      hasPlayer = true;
      if (!details) {
        details = 'Play button overlay detected requiring user gesture.';
      }
    }

    return JSON.stringify({
      hasPlayer: hasPlayer,
      isPlaying: isPlaying,
      details: details
    });
  } catch (e) {
    return JSON.stringify({ hasPlayer: false, isPlaying: false, details: '' });
  }
})();
''';

/// JavaScript for executing robust player wake gestures.
const String _kWakePlayerJs = r'''
(() => {
  try {
    // 1. Mute and trigger play on all video/audio elements
    const medias = document.querySelectorAll('video, audio');
    for (const m of medias) {
      try {
        m.muted = true;
        m.playsInline = true;
        m.setAttribute('playsinline', '');
        m.setAttribute('webkit-playsinline', '');
        m.setAttribute('autoplay', '');
        const p = m.play();
        if (p && typeof p.catch === 'function') {
          p.catch(() => {});
        }
      } catch (_) {}
    }

    // 2. Click play buttons and dispatch pointer/mouse/touch events
    const playSelectors = [
      '.vjs-big-play-button',
      '.plyr__control--overlaid',
      '.jw-preview',
      '.jw-display-icon-container',
      '.jw-overlay',
      '[class*="play-button" i]',
      '[class*="play_button" i]',
      '[class*="playBtn" i]',
      '[class*="play-btn" i]',
      '.play-btn',
      '.big-play-button',
      '.vjs-play-control',
      '.mejs__overlay-play',
      '[aria-label*="Play" i]',
      '[title*="Play" i]'
    ];

    function dispatchInteractiveEvents(el) {
      if (!el) return;
      try {
        el.click();
      } catch (_) {}
      try {
        if (window.PointerEvent) {
          el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: 'touch' }));
          el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, cancelable: true, pointerType: 'touch' }));
        }
      } catch (_) {}
      try {
        el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      } catch (_) {}
      try {
        if (window.TouchEvent) {
          el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, cancelable: true }));
          el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, cancelable: true }));
        }
      } catch (_) {}
    }

    for (const sel of playSelectors) {
      const btns = document.querySelectorAll(sel);
      for (const btn of btns) {
        dispatchInteractiveEvents(btn);
      }
    }

    // 3. Click closest player wrappers
    for (const m of medias) {
      const wrap = m.closest('[class*=player i], [id*=player i]');
      if (wrap) {
        dispatchInteractiveEvents(wrap);
      }
    }

    return true;
  } catch (_) {
    return false;
  }
})();
''';

/// Polls [probe] every [interval] until it returns a non-empty list or
/// [timeout] elapses. [wakeUp] runs once, right after the first empty probe
/// (players that need a play gesture), and its completion does not reset the
/// deadline.
///
/// Extracted as a top-level utility so the timing logic is unit-testable
/// without a WebView.
Future<List<String>?> pollUntilFound(
  Future<List<String>?> Function() probe, {
  Duration timeout = const Duration(seconds: 12),
  Duration interval = const Duration(seconds: 1),
  Future<void> Function()? wakeUp,
}) async {
  final deadline = DateTime.now().add(timeout);
  var woke = false;
  while (DateTime.now().isBefore(deadline)) {
    final result = await probe();
    if (result != null && result.isNotEmpty) return result;
    if (!woke && wakeUp != null) {
      woke = true;
      await wakeUp();
    }
    await Future<void>.delayed(interval);
  }
  return null;
}

/// A high-fidelity headless page resniffer that navigates to a source page in a
/// headless WebView, sharing session cookies and DOM storage with the main
/// browser, querying the rendered DOM and network performance entries for fresh
/// media stream URLs, and categorizing outcomes into strongly-typed [ResniffResult]s.
class HeadlessPageResniffer {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  bool _isDisposed = false;

  static const Duration _defaultTimeout = Duration(seconds: 20);
  static const Duration _jsGracePeriod = Duration(seconds: 3);
  static const Duration _resourcePollDelay = Duration(seconds: 1);

  /// Loads [sourcePageUrl] in a headless WebView sharing session cookies and
  /// persistent storage with interactive tabs (`incognito: false`), waits for the
  /// page to render, queries the DOM and performance entries for candidate media URLs,
  /// and evaluates them against [originalMediaUrl] using [StreamMatcher].
  ///
  /// Returns a strongly-typed [ResniffResult] indicating success, unchanged link,
  /// challenge block, timeout, dead link (HTTP 404/410/DNS), or missing media.
  Future<ResniffResult> resniff(
    String sourcePageUrl, {
    String? originalMediaUrl,
    String? mustMatchPathOf,
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    final effectiveOriginalUrl = originalMediaUrl ?? mustMatchPathOf;
    if (_isDisposed) {
      return const ResniffNoMediaFound(details: 'Resniffer is disposed.');
    }
    if (!sourcePageUrl.startsWith('http://') && !sourcePageUrl.startsWith('https://')) {
      return ResniffSourceUnavailable(
        error: 'Invalid source URL: $sourcePageUrl',
      );
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ResniffNoMediaFound(
        details: 'Headless WebView is only supported on mobile platforms (Android/iOS).',
      );
    }

    final loadCompleter = Completer<bool>();
    ResniffSourceUnavailable? earlyHttpError;
    String lastState = 'initializing';
    final startTime = DateTime.now();

    try {
      _headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(sourcePageUrl),
          headers: headers,
        ),
        initialSettings: InAppWebViewSettings(
          incognito: false,
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          cacheEnabled: true,
          cacheMode: CacheMode.LOAD_DEFAULT,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          useOnLoadResource: false,
          useShouldInterceptRequest: true,
        ),
        onLoadStart: (controller, url) {
          lastState = 'loading_page';
        },
        onLoadStop: (controller, url) {
          lastState = 'page_loaded';
          if (!loadCompleter.isCompleted) {
            loadCompleter.complete(true);
          }
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          if (request.isForMainFrame == true) {
            final code = errorResponse.statusCode;
            if (code != null && code >= 400) {
              earlyHttpError = ResniffSourceUnavailable(
                statusCode: code,
                error: errorResponse.reasonPhrase ?? 'HTTP $code Error',
              );
              if (!loadCompleter.isCompleted) {
                loadCompleter.complete(false);
              }
            }
          }
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true) {
            final desc = error.description.toLowerCase();
            final isDns = error.type == WebResourceErrorType.HOST_LOOKUP ||
                desc.contains('name_not_resolved') ||
                desc.contains('host_lookup') ||
                desc.contains('err_name_not_resolved');
            earlyHttpError = ResniffSourceUnavailable(
              statusCode: null,
              error: error.description,
              isDnsFailure: isDns,
            );
            if (!loadCompleter.isCompleted) {
              loadCompleter.complete(false);
            }
          }
        },
      );

      await _headless!.run();
      _controller = _headless!.webViewController;
      if (_controller == null) {
        return const ResniffNoMediaFound(details: 'WebViewController failed to initialize.');
      }

      // Calculate remaining timeout for initial page load
      final elapsedSoFar = DateTime.now().difference(startTime);
      final pageLoadTimeout = timeout > elapsedSoFar
          ? timeout - elapsedSoFar
          : const Duration(seconds: 5);

      final ok = await loadCompleter.future.timeout(
        pageLoadTimeout,
        onTimeout: () => false,
      );

      if (_isDisposed) {
        return const ResniffNoMediaFound(details: 'Resniffer disposed during page load.');
      }

      if (!ok) {
        if (earlyHttpError != null) {
          return earlyHttpError!;
        }
        return ResniffPageLoadTimeout(
          elapsed: DateTime.now().difference(startTime),
          lastState: lastState,
        );
      }

      // 1. Check WAF / Cloudflare challenge immediately after load
      lastState = 'checking_security_challenge';
      final initialChallenge = await _checkSecurityChallenge();
      if (initialChallenge != null) {
        return initialChallenge;
      }

      // 2. Give JS time to execute and initialize player
      lastState = 'js_initialization';
      await Future<void>.delayed(_jsGracePeriod);
      if (_isDisposed) {
        return const ResniffNoMediaFound(details: 'Resniffer disposed during JS init.');
      }

      // 3. Re-check challenge in case JS rendered it
      final postJsChallenge = await _checkSecurityChallenge();
      if (postJsChallenge != null) {
        return postJsChallenge;
      }

      // 4. Multi-candidate DOM & performance polling loop
      lastState = 'polling_media_candidates';
      final remainingTimeout = timeout - DateTime.now().difference(startTime);
      final pollDuration = remainingTimeout > const Duration(seconds: 2)
          ? remainingTimeout
          : const Duration(seconds: 5);

      final discoveredCandidates = <String>{};

      final pollResult = await pollUntilFound(
        () async {
          final candidates = await _queryCandidatesFromDom();
          if (candidates.isNotEmpty) {
            discoveredCandidates.addAll(candidates);
            final matchResult = evaluateCandidates(
              candidates: candidates,
              originalMediaUrl: effectiveOriginalUrl,
              sourcePageUrl: sourcePageUrl,
            );
            if (matchResult is ResniffSuccess || matchResult is ResniffUnchanged) {
              return [matchResult.freshUrl ?? (matchResult as ResniffUnchanged).url];
            }
          }
          return null;
        },
        timeout: pollDuration,
        interval: _resourcePollDelay,
        wakeUp: _isDisposed ? null : _wakePlayer,
      );

      if (pollResult != null && pollResult.isNotEmpty) {
        return evaluateCandidates(
          candidates: discoveredCandidates.toList(),
          originalMediaUrl: effectiveOriginalUrl,
          sourcePageUrl: sourcePageUrl,
        );
      }

      // 5. Check if security challenge appeared late
      final lateChallenge = await _checkSecurityChallenge();
      if (lateChallenge != null) {
        return lateChallenge;
      }

      // 6. Check if unplayed player is present requiring user interaction
      final playerStatus = await _checkPlayerStatus();
      if (playerStatus.hasPlayer && !playerStatus.isPlaying) {
        return ResniffPlayerInteractionRequired(
          details: playerStatus.details.isNotEmpty
              ? playerStatus.details
              : 'Player detected but playback has not started. Manual interaction required.',
        );
      }

      // 7. Return candidates evaluation (NoMediaFound with candidates count)
      return evaluateCandidates(
        candidates: discoveredCandidates.toList(),
        originalMediaUrl: effectiveOriginalUrl,
        sourcePageUrl: sourcePageUrl,
      );
    } on TimeoutException {
      return ResniffPageLoadTimeout(
        elapsed: DateTime.now().difference(startTime),
        lastState: lastState,
      );
    } catch (e) {
      return ResniffSourceUnavailable(
        error: 'Headless resniff failed: $e',
      );
    } finally {
      await dispose();
    }
  }

  /// Evaluates [candidates] against [originalMediaUrl] and returns the appropriate
  /// [ResniffResult] variant.
  @visibleForTesting
  static ResniffResult evaluateCandidates({
    required List<String> candidates,
    required String? originalMediaUrl,
    required String sourcePageUrl,
  }) {
    if (candidates.isEmpty) {
      return const ResniffNoMediaFound(
        candidatesInspected: 0,
        details: 'No candidate media URLs found in DOM or network resources.',
      );
    }

    final validCandidates = candidates
        .where((c) => !StreamMatcher.isAdOrTrackingUrl(c))
        .toList();

    if (validCandidates.isEmpty) {
      return ResniffNoMediaFound(
        candidatesInspected: candidates.length,
        details: 'All ${candidates.length} discovered candidates were identified as ads or tracking manifests.',
      );
    }

    if (originalMediaUrl != null && originalMediaUrl.trim().isNotEmpty) {
      final bestMatch = StreamMatcher.findBestMatch(
        candidates: validCandidates,
        originalMediaUrl: originalMediaUrl.trim(),
        sourcePageUrl: sourcePageUrl,
      );

      if (bestMatch != null) {
        if (bestMatch.url == originalMediaUrl.trim()) {
          return ResniffUnchanged(bestMatch.url);
        }
        return ResniffSuccess(
          bestMatch.url,
          confidence: bestMatch.score,
        );
      }

      return ResniffNoMediaFound(
        candidatesInspected: candidates.length,
        details: 'Discovered ${candidates.length} candidate(s), but none matched the original media stream with sufficient confidence.',
      );
    }

    // No originalMediaUrl provided: return the first valid candidate
    return ResniffSuccess(
      validCandidates.first,
      confidence: 1.0,
    );
  }

  /// Parses challenge detection JSON result.
  @visibleForTesting
  static ResniffChallengeDetected? parseChallengeDetectionResult(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty || jsonString == '{}') return null;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic> && decoded['detected'] == true) {
        final type = decoded['type'] as String? ?? 'cloudflare_turnstile';
        final details = decoded['details'] as String?;
        return ResniffChallengeDetected(
          challengeType: type,
          details: details,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Parses player status JSON result.
  @visibleForTesting
  static ({bool hasPlayer, bool isPlaying, String details}) parsePlayerStatusResult(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty || jsonString == '{}') {
      return (hasPlayer: false, isPlaying: false, details: '');
    }
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return (
          hasPlayer: decoded['hasPlayer'] == true,
          isPlaying: decoded['isPlaying'] == true,
          details: decoded['details'] as String? ?? '',
        );
      }
    } catch (_) {}
    return (hasPlayer: false, isPlaying: false, details: '');
  }

  /// Parses media candidates JSON string array.
  @visibleForTesting
  static List<String> parseCandidatesJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty || jsonString == '[]') {
      return const [];
    }
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Checks for security / WAF challenges via DOM JavaScript evaluation.
  Future<ResniffChallengeDetected?> _checkSecurityChallenge() async {
    final ctrl = _controller;
    if (ctrl == null) return null;
    try {
      final result = await ctrl.evaluateJavascript(source: _kChallengeDetectionJs);
      if (result is String) {
        return parseChallengeDetectionResult(result);
      }
    } catch (_) {}
    return null;
  }

  /// Queries all candidate media URLs from the DOM, players, and performance entries.
  Future<List<String>> _queryCandidatesFromDom() async {
    final ctrl = _controller;
    if (ctrl == null) return const [];
    try {
      final result = await ctrl.evaluateJavascript(source: _kMultiMediaCandidatesJs);
      if (result is String) {
        return parseCandidatesJson(result);
      }
    } catch (_) {}
    return const [];
  }

  /// Checks player status (video element state, overlay buttons) to see if manual
  /// interaction is required.
  Future<({bool hasPlayer, bool isPlaying, String details})> _checkPlayerStatus() async {
    final ctrl = _controller;
    if (ctrl == null) return (hasPlayer: false, isPlaying: false, details: '');
    try {
      final result = await ctrl.evaluateJavascript(source: _kPlayerStatusCheckJs);
      if (result is String) {
        return parsePlayerStatusResult(result);
      }
    } catch (_) {}
    return (hasPlayer: false, isPlaying: false, details: '');
  }

  /// Wakes the video player by setting muted autoplay and triggering synthetic
  /// pointer/touch/click events on play overlays.
  Future<void> _wakePlayer() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    try {
      await ctrl.evaluateJavascript(source: _kWakePlayerJs);
    } catch (_) {}
  }

  /// Disposes the headless WebView. Idempotent. Called automatically
  /// in [resniff]'s `finally` block.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _controller = null;
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
  }

  /// Loads [sourcePageUrl] headlessly with shared cookies/storage and returns
  /// **all** media URLs the rendered DOM and network entries expose.
  ///
  /// Returns an empty list when nothing is found or the page cannot load.
  /// The instance is disposed automatically.
  Future<List<String>> resniffAll(String sourcePageUrl) async {
    if (!Platform.isAndroid && !Platform.isIOS) return const [];
    if (_isDisposed) return const [];
    if (!sourcePageUrl.startsWith('http://') && !sourcePageUrl.startsWith('https://')) {
      return const [];
    }

    final loadCompleter = Completer<bool>();

    try {
      _headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(sourcePageUrl)),
        initialSettings: InAppWebViewSettings(
          incognito: false,
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          cacheEnabled: true,
          cacheMode: CacheMode.LOAD_DEFAULT,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          useOnLoadResource: false,
          useShouldInterceptRequest: true,
        ),
        onLoadStop: (controller, url) {
          if (!loadCompleter.isCompleted) {
            loadCompleter.complete(true);
          }
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true && !loadCompleter.isCompleted) {
            loadCompleter.complete(false);
          }
        },
      );
      await _headless!.run();
      _controller = _headless!.webViewController;
      if (_controller == null) return const [];

      final ok = await loadCompleter.future.timeout(
        _defaultTimeout,
        onTimeout: () => false,
      );
      if (_isDisposed || !ok) return const [];

      // Give JS time to execute and the player to initialise.
      await Future<void>.delayed(_jsGracePeriod);
      if (_isDisposed) return const [];

      final results = await pollUntilFound(
        () async {
          final fromDom = await _queryCandidatesFromDom();
          if (fromDom.isNotEmpty) return fromDom;
          return null;
        },
        timeout: _defaultTimeout,
        interval: _resourcePollDelay,
        wakeUp: _isDisposed ? null : _wakePlayer,
      );
      if (results != null) return results.toSet().toList();

      return const [];
    } catch (_) {
      return const [];
    } finally {
      await dispose();
    }
  }
}
