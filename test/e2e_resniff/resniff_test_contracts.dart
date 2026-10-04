/// Strongly-typed sealed result hierarchy for all resniff operations.
/// Follows Project Pattern and PROJECT.md § Interface Contracts.
sealed class ResniffResult {
  const ResniffResult();

  bool get isSuccess => this is ResniffSuccess;
  String? get freshUrl => switch (this) {
    ResniffSuccess(:final url) => url,
    _ => null,
  };
  String get userFacingMessage;
  String? get diagnosticDetails;
  bool get isActionable;
}

class ResniffSuccess extends ResniffResult {
  final String url;
  final Map<String, String>? headers;
  final double confidence;
  const ResniffSuccess(this.url, {this.headers, this.confidence = 1.0});

  @override
  String get userFacingMessage => 'Fresh media link discovered successfully.';

  @override
  String? get diagnosticDetails =>
      'Confidence: ${(confidence * 100).round()}% | URL: $url';

  @override
  bool get isActionable => false;
}

class ResniffUnchanged extends ResniffResult {
  final String url;
  const ResniffUnchanged(this.url);

  @override
  String get userFacingMessage => 'Link is unchanged. Media URL is identical.';

  @override
  String? get diagnosticDetails => 'URL: $url';

  @override
  bool get isActionable => false;
}

class ResniffNoMediaFound extends ResniffResult {
  final String? details;
  final int candidatesInspected;
  const ResniffNoMediaFound({this.details, this.candidatesInspected = 0});

  @override
  String get userFacingMessage =>
      'No media streams could be located on the source page.';

  @override
  String? get diagnosticDetails =>
      details ??
      (candidatesInspected == 0
          ? 'Inspected 0 candidate(s).'
          : 'None of $candidatesInspected candidates matched original stream.');

  @override
  bool get isActionable => true;
}

class ResniffChallengeDetected extends ResniffResult {
  final String challengeType;
  final String? details;
  const ResniffChallengeDetected({
    this.challengeType = 'cloudflare_turnstile',
    this.details,
  });

  @override
  String get userFacingMessage =>
      'Security challenge detected ($challengeType). Open in browser to complete verification.';

  @override
  String? get diagnosticDetails =>
      'Challenge: $challengeType${details != null ? ' ($details)' : ''}';

  @override
  bool get isActionable => true;
}

class ResniffPageLoadTimeout extends ResniffResult {
  final Duration elapsed;
  final String? lastState;
  const ResniffPageLoadTimeout({
    this.elapsed = const Duration(seconds: 20),
    this.lastState,
  });

  @override
  String get userFacingMessage =>
      'Page load timed out after ${elapsed.inSeconds} seconds.';

  @override
  String get diagnosticDetails =>
      'Timeout: ${elapsed.inMilliseconds}ms${lastState != null ? ' (State: $lastState)' : ''} (network_read_timeout) Last known state: ${lastState ?? "loading"}';

  @override
  bool get isActionable => true;
}

class ResniffSourceUnavailable extends ResniffResult {
  final int? statusCode;
  final String? error;
  final bool isDnsFailure;
  const ResniffSourceUnavailable({
    this.statusCode,
    this.error,
    this.isDnsFailure = false,
  });

  @override
  String get userFacingMessage {
    if (isDnsFailure) {
      return 'Source page domain could not be resolved (DNS failure).';
    }
    if (statusCode == 404) {
      return 'Source page not found (404). Video may have been deleted.';
    }
    if (statusCode == 410) {
      return 'Source page is gone permanently (410).';
    }
    if (statusCode != null) {
      return 'Source page returned HTTP $statusCode.';
    }
    return error ?? 'Source page could not be accessed.';
  }

  @override
  String? get diagnosticDetails =>
      'Unavailable: ${isDnsFailure ? 'DNS failure: true' : (statusCode != null ? 'HTTP $statusCode' : error ?? 'Unknown')}';

  @override
  bool get isActionable => !isDnsFailure;
}

class ResniffPlayerInteractionRequired extends ResniffResult {
  final String? details;
  const ResniffPlayerInteractionRequired({this.details});

  @override
  String get userFacingMessage =>
      'Player requires direct manual interaction. Tap play inside browser to initiate stream.';

  @override
  String get diagnosticDetails =>
      details ?? 'Click-to-play direct player interaction needed';

  @override
  bool get isActionable => true;
}

/// Candidate match scoring model.
class StreamMatchCandidate {
  final String url;
  final double score;
  final String reason;

  const StreamMatchCandidate({
    required this.url,
    required this.score,
    required this.reason,
  });
}

/// Stream matcher utility matching freshly sniffed streams to original URLs.
class StreamMatcher {
  static final RegExp _cleanUrlRegex = RegExp(r'[?#].*$');

  static bool isAdOrTrackingUrl(String url) {
    final lower = url.toLowerCase();
    final adKeywords = [
      'pagead',
      'doubleclick',
      'googleads',
      'googlesyndication',
      'adservice',
      'adsystem',
      'adnxs',
      'exoclick',
      'trafficjunky',
      'popads',
      'adsterra',
      'moatads',
      'scorecardresearch',
      '/vast',
      '/vpaid',
      'analytics',
      'telemetry',
      'beacon',
      'tracking',
      '/ads/',
      '/ad/',
      'ad.mp4',
      'ad.m3u8',
    ];
    for (final kw in adKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  static double scoreCandidate({
    required String candidateUrl,
    required String originalMediaUrl,
    String? sourcePageUrl,
  }) {
    if (isAdOrTrackingUrl(candidateUrl)) return 0.0;

    final candUri = Uri.tryParse(candidateUrl);
    final origUri = Uri.tryParse(originalMediaUrl);
    if (candUri == null || origUri == null) return 0.0;

    double score = 0.0;

    // Same clean path (ignoring query tokens)
    final candClean = candidateUrl.replaceAll(_cleanUrlRegex, '');
    final origClean = originalMediaUrl.replaceAll(_cleanUrlRegex, '');
    if (candClean == origClean) {
      score += 0.60;
    } else if (candUri.path == origUri.path) {
      score += 0.50;
    } else if (candUri.pathSegments.isNotEmpty &&
        origUri.pathSegments.isNotEmpty &&
        candUri.pathSegments.last == origUri.pathSegments.last) {
      score += 0.40;
    }

    // Same host / domain
    if (candUri.host == origUri.host) {
      score += 0.20;
    } else if (_getRegistrableDomain(candUri.host) ==
        _getRegistrableDomain(origUri.host)) {
      score += 0.15;
    }

    // Same extension / media type (.m3u8, .mp4, .ts)
    final candExt = _getExtension(candUri.path);
    final origExt = _getExtension(origUri.path);
    if (candExt.isNotEmpty && candExt == origExt) {
      score += 0.15;
    }

    // Same query parameter keys
    final candKeys = candUri.queryParameters.keys.toSet();
    final origKeys = origUri.queryParameters.keys.toSet();
    if (candKeys.isNotEmpty && origKeys.isNotEmpty) {
      final intersection = candKeys.intersection(origKeys);
      if (intersection.isNotEmpty) {
        score += (intersection.length / origKeys.length) * 0.10;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  static String _getExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot).toLowerCase() : '';
  }

  static String _getRegistrableDomain(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return parts.sublist(parts.length - 2).join('.');
  }

  static StreamMatchCandidate? findBestMatch({
    required List<String> candidates,
    required String originalMediaUrl,
    String? sourcePageUrl,
  }) {
    StreamMatchCandidate? best;

    for (final cand in candidates) {
      final score = scoreCandidate(
        candidateUrl: cand,
        originalMediaUrl: originalMediaUrl,
        sourcePageUrl: sourcePageUrl,
      );

      final candClean = cand.replaceAll(_cleanUrlRegex, '');
      final origClean = originalMediaUrl.replaceAll(_cleanUrlRegex, '');
      final candUri = Uri.tryParse(cand);
      final origUri = Uri.tryParse(originalMediaUrl);

      final reasons = <String>[];
      if (candClean == origClean || (candUri != null && origUri != null && candUri.path == origUri.path)) {
        reasons.add('exact path match');
      }
      if (candUri != null && origUri != null && candUri.query != origUri.query) {
        reasons.add('refreshed query token');
      }
      if (candUri != null && origUri != null && candUri.host == origUri.host) {
        reasons.add('same domain');
      }

      if (score >= 0.4) {
        if (best == null || score > best.score) {
          best = StreamMatchCandidate(
            url: cand,
            score: score,
            reason: reasons.join(', '),
          );
        }
      }
    }

    return best;
  }
}

/// Active in-tab resniff session model.
class ResniffSession {
  final String taskId;
  final String taskName;
  final String originalUrl;
  final String sourcePageUrl;
  final DateTime createdAt;

  ResniffSession({
    required this.taskId,
    required this.taskName,
    required this.originalUrl,
    required this.sourcePageUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool matchesCandidate(String mediaUrl) {
    final match = StreamMatcher.findBestMatch(
      candidates: [mediaUrl],
      originalMediaUrl: originalUrl,
      sourcePageUrl: sourcePageUrl,
    );
    return match != null && match.score >= 0.5;
  }
}
