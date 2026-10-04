import 'dart:convert';

/// Sealed hierarchy representing all possible outcomes of a headless or
/// automated stream re-sniffing operation.
///
/// Every outcome provides strongly-typed diagnostic state, clear user-facing
/// guidance, and serialization helpers for persistent diagnostic logs.
sealed class ResniffResult {
  const ResniffResult();

  /// True if the resniff operation discovered a usable fresh media URL.
  bool get isSuccess => this is ResniffSuccess;

  /// The refreshed media URL if [isSuccess] is true; otherwise null.
  String? get freshUrl => switch (this) {
        ResniffSuccess(:final url) => url,
        _ => null,
      };

  /// User-understandable, honest English description of this result.
  String get userFacingMessage;

  /// Developer / telemetry diagnostic string detailing the outcome.
  String? get diagnosticDetails;

  /// True if this failure state can be acted upon by the user (e.g. by
  /// opening the source page in the browser to solve challenges or trigger
  /// media playback).
  bool get isActionable;

  /// Serializes this result to a JSON-compatible Map.
  Map<String, dynamic> toJson();

  /// Deserializes a [ResniffResult] from a JSON-compatible Map.
  factory ResniffResult.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'success':
        return ResniffSuccess(
          json['url'] as String,
          headers: (json['headers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ),
          confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        );
      case 'unchanged':
        return ResniffUnchanged(json['url'] as String);
      case 'no_media_found':
        return ResniffNoMediaFound(
          details: json['details'] as String?,
          candidatesInspected:
              (json['candidatesInspected'] as num?)?.toInt() ?? 0,
        );
      case 'challenge_detected':
        return ResniffChallengeDetected(
          challengeType:
              json['challengeType'] as String? ?? 'cloudflare_turnstile',
          details: json['details'] as String?,
        );
      case 'page_load_timeout':
        return ResniffPageLoadTimeout(
          elapsed: Duration(
            milliseconds: (json['elapsedMs'] as num?)?.toInt() ?? 20000,
          ),
          lastState: json['lastState'] as String?,
        );
      case 'source_unavailable':
        return ResniffSourceUnavailable(
          statusCode: (json['statusCode'] as num?)?.toInt(),
          error: json['error'] as String?,
          isDnsFailure: json['isDnsFailure'] as bool? ?? false,
        );
      case 'player_interaction_required':
        return ResniffPlayerInteractionRequired(
          details: json['details'] as String?,
        );
      default:
        return ResniffNoMediaFound(
          details: 'Unrecognized result type: $type',
        );
    }
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Headless resniff succeeded and found a fresh media stream URL.
class ResniffSuccess extends ResniffResult {
  /// The newly resolved, refreshed media stream URL.
  final String url;

  /// Optional HTTP request headers (e.g. Referer, Cookie, Authorization)
  /// required to request the refreshed stream.
  final Map<String, String>? headers;

  /// Matching confidence score between 0.0 and 1.0.
  final double confidence;

  const ResniffSuccess(
    this.url, {
    this.headers,
    this.confidence = 1.0,
  });

  @override
  bool get isActionable => false;

  @override
  String get userFacingMessage =>
      'Refreshed stream URL found successfully.';

  @override
  String get diagnosticDetails =>
      'Success (confidence: ${(confidence * 100).toStringAsFixed(1)}%): $url'
      '${headers != null && headers!.isNotEmpty ? ' with ${headers!.length} headers' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'success',
        'url': url,
        if (headers != null) 'headers': headers,
        'confidence': confidence,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffSuccess &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          confidence == other.confidence &&
          _mapEquals(headers, other.headers);

  @override
  int get hashCode => Object.hash(
        url,
        confidence,
        _mapHashCode(headers),
      );
}

/// The original media URL was verified and is still valid; no update needed.
class ResniffUnchanged extends ResniffResult {
  /// The active, unchanged media URL.
  final String url;

  const ResniffUnchanged(this.url);

  @override
  bool get isActionable => false;

  @override
  String get userFacingMessage =>
      'Stream URL is still active and unchanged.';

  @override
  String get diagnosticDetails => 'Unchanged: $url';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'unchanged',
        'url': url,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffUnchanged &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// Page loaded successfully, but no matching media stream was detected in
/// the DOM, `<video>` / `<source>` tags, scripts, or network performance entries.
class ResniffNoMediaFound extends ResniffResult {
  /// Detailed description of where detection failed.
  final String? details;

  /// Number of candidate URLs inspected during matching.
  final int candidatesInspected;

  const ResniffNoMediaFound({
    this.details,
    this.candidatesInspected = 0,
  });

  @override
  bool get isActionable => true;

  @override
  String get userFacingMessage {
    if (details != null && details!.isNotEmpty) {
      return details!;
    }
    if (candidatesInspected > 0) {
      return 'No matching media stream found after inspecting $candidatesInspected candidates.';
    }
    return 'No media stream detected on the source page.';
  }

  @override
  String get diagnosticDetails =>
      'NoMediaFound: candidatesInspected=$candidatesInspected'
      '${details != null ? ', details=$details' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'no_media_found',
        if (details != null) 'details': details,
        'candidatesInspected': candidatesInspected,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffNoMediaFound &&
          runtimeType == other.runtimeType &&
          details == other.details &&
          candidatesInspected == other.candidatesInspected;

  @override
  int get hashCode => Object.hash(details, candidatesInspected);
}

/// A bot-detection challenge or WAF verification block was encountered.
class ResniffChallengeDetected extends ResniffResult {
  /// The type of challenge detected (e.g. 'cloudflare_turnstile', 'recaptcha', 'generic_waf').
  final String challengeType;

  /// Additional details or DOM selector where challenge was found.
  final String? details;

  const ResniffChallengeDetected({
    this.challengeType = 'cloudflare_turnstile',
    this.details,
  });

  @override
  bool get isActionable => true;

  @override
  String get userFacingMessage {
    if (details != null && details!.isNotEmpty) {
      return details!;
    }
    final formattedType = switch (challengeType) {
      'cloudflare_turnstile' || 'cloudflare' => 'Cloudflare verification',
      'recaptcha' || 'recaptcha_v2' || 'recaptcha_v3' => 'reCAPTCHA',
      'hcaptcha' => 'hCaptcha',
      _ => 'Security verification ($challengeType)',
    };
    return '$formattedType required. Open in browser to complete verification.';
  }

  @override
  String get diagnosticDetails =>
      'ChallengeDetected: challengeType=$challengeType'
      '${details != null ? ', details=$details' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'challenge_detected',
        'challengeType': challengeType,
        if (details != null) 'details': details,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffChallengeDetected &&
          runtimeType == other.runtimeType &&
          challengeType == other.challengeType &&
          details == other.details;

  @override
  int get hashCode => Object.hash(challengeType, details);
}

/// The headless page load or DOM polling exceeded the allotted time limit.
class ResniffPageLoadTimeout extends ResniffResult {
  /// Total duration elapsed before timing out.
  final Duration elapsed;

  /// Last known state or phase when timeout occurred.
  final String? lastState;

  const ResniffPageLoadTimeout({
    this.elapsed = const Duration(seconds: 20),
    this.lastState,
  });

  @override
  bool get isActionable => true;

  @override
  String get userFacingMessage =>
      'Page loading timed out after ${elapsed.inSeconds}s'
      '${lastState != null ? ' (state: $lastState)' : ''}. '
      'Check connection or open in browser.';

  @override
  String get diagnosticDetails =>
      'PageLoadTimeout: elapsed=${elapsed.inMilliseconds}ms'
      '${lastState != null ? ', lastState=$lastState' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'page_load_timeout',
        'elapsedMs': elapsed.inMilliseconds,
        if (lastState != null) 'lastState': lastState,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffPageLoadTimeout &&
          runtimeType == other.runtimeType &&
          elapsed == other.elapsed &&
          lastState == other.lastState;

  @override
  int get hashCode => Object.hash(elapsed, lastState);
}

/// The source page is unreachable due to HTTP error (404, 410, 500) or DNS failure.
class ResniffSourceUnavailable extends ResniffResult {
  /// HTTP status code returned by the server (e.g. 404, 410, 502).
  final int? statusCode;

  /// Error message or description of the failure.
  final String? error;

  /// True if the domain could not be resolved via DNS.
  final bool isDnsFailure;

  const ResniffSourceUnavailable({
    this.statusCode,
    this.error,
    this.isDnsFailure = false,
  });

  @override
  bool get isActionable => true;

  @override
  String get userFacingMessage {
    if (isDnsFailure) {
      return 'Source page domain could not be resolved (DNS failure).';
    }
    if (statusCode != null) {
      if (statusCode == 404) {
        return 'Source page not found (HTTP 404). The media or page may have been removed.';
      }
      if (statusCode == 410) {
        return 'Source page is gone permanently (HTTP 410).';
      }
      return 'Source page returned HTTP $statusCode${error != null ? ': $error' : ''}.';
    }
    return error ?? 'Source page is unavailable or unreachable.';
  }

  @override
  String get diagnosticDetails =>
      'SourceUnavailable: ${isDnsFailure ? 'DNS failure' : (statusCode != null ? 'HTTP $statusCode' : 'Error')}'
      '${error != null ? ' ($error)' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'source_unavailable',
        if (statusCode != null) 'statusCode': statusCode,
        if (error != null) 'error': error,
        'isDnsFailure': isDnsFailure,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffSourceUnavailable &&
          runtimeType == other.runtimeType &&
          statusCode == other.statusCode &&
          error == other.error &&
          isDnsFailure == other.isDnsFailure;

  @override
  int get hashCode => Object.hash(statusCode, error, isDnsFailure);
}

/// The embedded player requires manual user interaction (e.g. click-to-play,
/// interactive age gate, or custom iframe).
class ResniffPlayerInteractionRequired extends ResniffResult {
  /// Detailed description of the required interaction.
  final String? details;

  const ResniffPlayerInteractionRequired({this.details});

  @override
  bool get isActionable => true;

  @override
  String get userFacingMessage =>
      details ??
      'Player requires manual interaction. Open in browser to start video playback.';

  @override
  String get diagnosticDetails =>
      'PlayerInteractionRequired${details != null ? ': $details' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'player_interaction_required',
        if (details != null) 'details': details,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResniffPlayerInteractionRequired &&
          runtimeType == other.runtimeType &&
          details == other.details;

  @override
  int get hashCode => details.hashCode;
}

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}

int _mapHashCode(Map<String, String>? map) {
  if (map == null) return 0;
  int hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
