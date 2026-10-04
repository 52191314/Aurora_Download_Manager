import 'dart:math' as math;

/// A scored candidate media stream evaluated against an original stream URL.
class StreamMatchCandidate {
  /// The candidate media stream URL.
  final String url;

  /// Matching confidence score between 0.0 (no match) and 1.0 (exact match).
  final double score;

  /// Human-readable explanation of how or why this score was determined.
  final String reason;

  const StreamMatchCandidate({
    required this.url,
    required this.score,
    required this.reason,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamMatchCandidate &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          score == other.score &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(url, score, reason);

  @override
  String toString() =>
      'StreamMatchCandidate(url: $url, score: ${score.toStringAsFixed(3)}, reason: $reason)';
}

/// Intelligent stream matching engine that accurately matches refreshed media URLs
/// against original/stale download tasks.
///
/// Handles CDN query token rotations (e.g. `token=...`, `exp=...`, `h=...`),
/// path-embedded hash tokens (e.g. `/hls/<token>/master.m3u8`), sibling CDN domains,
/// and format variations while filtering out ads, telemetry, and tracking manifests.
class StreamMatcher {
  const StreamMatcher._();

  /// Known media extensions supported for download.
  static const Set<String> supportedMediaExtensions = {
    '.m3u8',
    '.mpd',
    '.mp4',
    '.m4s',
    '.webm',
    '.mkv',
    '.ts',
    '.mov',
    '.flv',
    '.avi',
    '.3gp',
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.flac',
    '.wav',
  };

  /// Extensions that indicate static assets or non-media files.
  static const Set<String> nonMediaExtensions = {
    '.gif',
    '.png',
    '.jpg',
    '.jpeg',
    '.svg',
    '.ico',
    '.webp',
    '.bmp',
    '.avif',
    '.css',
    '.js',
    '.json',
    '.html',
    '.htm',
    '.txt',
    '.woff',
    '.woff2',
    '.ttf',
    '.eot',
    '.otf',
    '.map',
    '.xml',
    '.pdf',
  };

  /// Common 2-part ccTLDs for domain root extraction.
  static const Set<String> _twoPartCCTLDs = {
    'co.uk',
    'com.au',
    'co.jp',
    'co.id',
    'com.br',
    'co.nz',
    'co.za',
    'com.tw',
    'com.sg',
    'com.mx',
    'com.ar',
    'co.kr',
    'gov.uk',
    'ac.uk',
    'org.uk',
    'net.au',
    'org.au',
  };

  /// Ad, tracking, and telemetry domains / subdomains.
  static const List<String> _adDomains = [
    'doubleclick.net',
    'googleads',
    'googlesyndication',
    'adservice.google',
    'adnxs.com',
    'advertising.com',
    'adform.net',
    'scorecardresearch.com',
    'quantserve.com',
    'outbrain.com',
    'taboola.com',
    'popads.net',
    'propellerads.com',
    'exoclick.com',
    'trafficjunky.com',
    'juicyads.com',
    'ero-advertising.com',
    'trafficfactory.biz',
    'tsyndicate.com',
    'adx.com',
    'adroll.com',
    'criteo.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'applovin.com',
    'unityads',
    'vungle.com',
    'ironsrc.com',
    'adcolony.com',
    'chartboost.com',
    'analytics.google.com',
    'googletagmanager.com',
    'hotjar.com',
    'mixpanel.com',
    'segment.io',
    'clarity.ms',
    'yandex.ru/metrika',
    'moatads.com',
    'amazon-adsystem.com',
    'facebook.com/tr',
  ];

  /// Regex patterns in path or query identifying advertisement or tracking calls.
  static final RegExp _adPathPatterns = RegExp(
    r'(?:^|[/?&=._-])('
    r'ads?|preroll|midroll|postroll|vast|vpaid|sponsor|promo|banner|'
    r'ad_unit|ad_tag|adserver|adsystem|ping\.m3u8|ping|beacon|telemetry|'
    r'analytics|pixel|track|tracking|stats|metrics|collect|event'
    r')(?:[/?&=._-]|$)',
    caseSensitive: false,
  );

  /// Evaluates [candidates] against [originalMediaUrl] and returns the best
  /// matching candidate, or `null` if none pass [minScoreThreshold].
  static StreamMatchCandidate? findBestMatch({
    required List<String> candidates,
    required String originalMediaUrl,
    String? sourcePageUrl,
    double minScoreThreshold = 0.4,
  }) {
    if (candidates.isEmpty || originalMediaUrl.trim().isEmpty) {
      return null;
    }

    final origUri = Uri.tryParse(originalMediaUrl.trim());
    if (origUri == null || !origUri.hasScheme) {
      return null;
    }

    final scored = <StreamMatchCandidate>[];

    for (final rawCandidate in candidates) {
      final candidate = rawCandidate.trim();
      if (candidate.isEmpty) continue;

      // Filter out obvious ad or tracking URLs immediately.
      if (isAdOrTrackingUrl(candidate)) {
        continue;
      }

      final scoreResult = evaluateCandidate(
        candidate: candidate,
        original: originalMediaUrl.trim(),
        sourcePageUrl: sourcePageUrl?.trim(),
      );

      if (scoreResult.score >= minScoreThreshold) {
        scored.add(scoreResult);
      }
    }

    if (scored.isEmpty) return null;

    // Sort descending by score.
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.first;
  }

  /// Evaluates a single [candidate] against the [original] URL and produces a
  /// scored [StreamMatchCandidate] with diagnostic reason.
  static StreamMatchCandidate evaluateCandidate({
    required String candidate,
    required String original,
    String? sourcePageUrl,
  }) {
    if (candidate == original) {
      return StreamMatchCandidate(
        url: candidate,
        score: 1.0,
        reason: 'Exact URL match',
      );
    }

    final candUri = Uri.tryParse(candidate);
    final origUri = Uri.tryParse(original);

    if (candUri == null || origUri == null || !candUri.hasScheme || !origUri.hasScheme) {
      return StreamMatchCandidate(
        url: candidate,
        score: 0.0,
        reason: 'Malformed URL structure',
      );
    }

    // Check non-media extension discard.
    final candExt = extractMediaExtension(candidate);
    final origExt = extractMediaExtension(original);

    if (candExt != null && nonMediaExtensions.contains(candExt.toLowerCase())) {
      return StreamMatchCandidate(
        url: candidate,
        score: 0.0,
        reason: 'Non-media static asset extension: $candExt',
      );
    }

    // Identical host and path, only query token parameters rotated.
    final candPathNorm = candUri.path.toLowerCase();
    final origPathNorm = origUri.path.toLowerCase();
    final candHostNorm = candUri.host.toLowerCase();
    final origHostNorm = origUri.host.toLowerCase();

    if (candHostNorm == origHostNorm && candPathNorm == origPathNorm) {
      return StreamMatchCandidate(
        url: candidate,
        score: 0.99,
        reason: 'Exact host and path match with refreshed query tokens',
      );
    }

    double score = 0.0;
    final reasons = <String>[];

    // 1. Host & Domain Evaluation (Weight: up to 0.35)
    if (candHostNorm == origHostNorm && candHostNorm.isNotEmpty) {
      score += 0.35;
      reasons.add('Same CDN host ($candHostNorm)');
    } else if (isSameDomainOrSubdomain(candHostNorm, origHostNorm)) {
      score += 0.28;
      reasons.add('Sibling CDN domain (${extractRootDomain(candHostNorm)})');
    } else if (sourcePageUrl != null) {
      final sourceUri = Uri.tryParse(sourcePageUrl);
      if (sourceUri != null &&
          isSameDomainOrSubdomain(candHostNorm, sourceUri.host.toLowerCase())) {
        score += 0.15;
        reasons.add('Host matches source page domain');
      }
    }

    // 2. Extension Evaluation (Weight: up to 0.20)
    if (candExt != null && origExt != null && candExt.toLowerCase() == origExt.toLowerCase()) {
      score += 0.20;
      reasons.add('Identical media format ($candExt)');
    } else if (_areCompatibleMediaFormats(candExt, origExt)) {
      score += 0.10;
      reasons.add('Compatible stream format ($candExt ~ $origExt)');
    } else if (candExt != null && !supportedMediaExtensions.contains(candExt.toLowerCase())) {
      score -= 0.30;
      reasons.add('Unrecognized media extension ($candExt)');
    }

    // 3. Base Filename Evaluation (Weight: up to 0.25)
    final candFilename = extractBaseFilename(candidate).toLowerCase();
    final origFilename = extractBaseFilename(original).toLowerCase();

    if (candFilename.isNotEmpty && origFilename.isNotEmpty) {
      if (candFilename == origFilename) {
        score += 0.25;
        reasons.add('Matching base filename ($candFilename)');
      } else if (candFilename.contains(origFilename) || origFilename.contains(candFilename)) {
        score += 0.18;
        reasons.add('Partial filename match ($candFilename ~ $origFilename)');
      } else if (_isGenericPlaylistName(candFilename) && _isGenericPlaylistName(origFilename)) {
        score += 0.12;
        reasons.add('Standard playlist entrypoint ($candFilename ~ $origFilename)');
      }
    }

    // 4. Path Similarity & Hash Token Tolerance (Weight: up to 0.20)
    final pathSim = computePathSimilarity(candUri.path, origUri.path);
    if (pathSim > 0.0) {
      final pathWeight = pathSim * 0.20;
      score += pathWeight;
      if (pathSim >= 0.8) {
        reasons.add('High path segment overlap (${(pathSim * 100).toInt()}%)');
      } else if (pathSim >= 0.5) {
        reasons.add('Moderate path structure similarity (${(pathSim * 100).toInt()}%)');
      }
    }

    // Clamping partial path matches to at most 0.92 so exact path matches (0.99) always win
    final finalScore = math.max(0.0, math.min(0.92, score));
    final reasonString = reasons.isEmpty
        ? 'Low similarity match'
        : reasons.join('; ');

    return StreamMatchCandidate(
      url: candidate,
      score: double.parse(finalScore.toStringAsFixed(3)),
      reason: reasonString,
    );
  }

  /// Calculates the similarity score between a [candidateUrl] and [originalMediaUrl].
  static double calculateSimilarity(
    String candidateUrl,
    String originalMediaUrl, {
    String? sourcePageUrl,
  }) {
    if (isAdOrTrackingUrl(candidateUrl)) return 0.0;
    final match = evaluateCandidate(
      candidate: candidateUrl,
      original: originalMediaUrl,
      sourcePageUrl: sourcePageUrl,
    );
    return match.score;
  }

  /// Computes path structural similarity between two paths, with tolerance for
  /// dynamic hash / numeric token path segments (e.g. `/hls/<token>/video.m3u8`).
  static double computePathSimilarity(String pathA, String pathB) {
    final segsA = pathA.split('/').where((s) => s.isNotEmpty).toList();
    final segsB = pathB.split('/').where((s) => s.isNotEmpty).toList();

    if (segsA.isEmpty && segsB.isEmpty) return 1.0;
    if (segsA.isEmpty || segsB.isEmpty) return 0.0;

    int exactMatches = 0;
    int tokenMatches = 0;
    final minLen = math.min(segsA.length, segsB.length);
    final maxLen = math.max(segsA.length, segsB.length);

    for (int i = 0; i < minLen; i++) {
      final a = segsA[i].toLowerCase();
      final b = segsB[i].toLowerCase();
      if (a == b) {
        exactMatches++;
      } else if (_isProbableDynamicTokenSegment(a) && _isProbableDynamicTokenSegment(b)) {
        tokenMatches++;
      }
    }

    final totalScore = (exactMatches * 1.0 + tokenMatches * 0.8) / maxLen;
    return math.max(0.0, math.min(1.0, totalScore));
  }

  /// Detects whether a path segment is likely a dynamic hash, timestamp, or token
  /// (e.g. MD5/SHA hex hashes, base64 strings, long numeric IDs).
  static bool _isProbableDynamicTokenSegment(String segment) {
    if (segment.length < 6) return false;
    // Hex hash (e.g. a1b2c3d4e5f6)
    if (RegExp(r'^[a-fA-F0-9]{8,}$').hasMatch(segment)) return true;
    // Pure numeric timestamp or ID of length >= 6
    if (RegExp(r'^\d{6,}$').hasMatch(segment)) return true;
    // Base64-like alphanumeric token (length >= 16 to avoid matching ordinary words)
    if (RegExp(r'^[a-zA-Z0-9_\-~]{16,}$').hasMatch(segment)) return true;
    return false;
  }

  /// Returns true if [hostA] and [hostB] share the same registered root domain
  /// (e.g. `edge1.streamcdn.com` and `edge2.streamcdn.com`).
  static bool isSameDomainOrSubdomain(String hostA, String hostB) {
    final a = hostA.toLowerCase().trim();
    final b = hostB.toLowerCase().trim();
    if (a == b && a.isNotEmpty) return true;
    if (a.isEmpty || b.isEmpty) return false;

    final rootA = extractRootDomain(a);
    final rootB = extractRootDomain(b);
    return rootA.isNotEmpty && rootA == rootB;
  }

  /// Extracts the registered root domain (e.g. `example.com` from `video.cdn.example.com`,
  /// or `site.co.uk` from `stream.site.co.uk`).
  static String extractRootDomain(String host) {
    final cleanHost = host.toLowerCase().trim();
    if (cleanHost.isEmpty) return '';

    final parts = cleanHost.split('.');
    if (parts.length <= 2) return cleanHost;

    // Check for two-part ccTLD like co.uk or com.au
    if (parts.length >= 3) {
      final possibleCcTld = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      if (_twoPartCCTLDs.contains(possibleCcTld)) {
        return '${parts[parts.length - 3]}.$possibleCcTld';
      }
    }

    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }

  /// Extracts the base filename without extension from a URL (e.g. `master` from
  /// `https://example.com/hls/master.m3u8?token=123`).
  static String extractBaseFilename(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return '';
      final last = segments.last;
      final dotIndex = last.lastIndexOf('.');
      if (dotIndex > 0) {
        return last.substring(0, dotIndex);
      }
      return last;
    } catch (_) {
      return '';
    }
  }

  /// Extracts the media extension in lowercase (e.g. `.m3u8`, `.mp4`) from a URL.
  static String? extractMediaExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final dotIndex = path.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < path.length - 1) {
        final ext = path.substring(dotIndex).toLowerCase();
        // Ignore extension if it has slashes after the dot
        if (!ext.contains('/')) {
          return ext;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns true if [url] is identified as an advertisement, tracking pixel,
  /// telemetry endpoint, or non-media tracking manifest.
  static bool isAdOrTrackingUrl(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.isEmpty) return true;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return true;

    final host = uri.host.toLowerCase();
    for (final adDomain in _adDomains) {
      if (host == adDomain ||
          host.endsWith('.$adDomain') ||
          host.contains(adDomain) ||
          lower.contains(adDomain)) {
        return true;
      }
    }

    // Ping playlist checks
    if (lower.contains('ping.m3u8') || lower.contains('/ping')) {
      return true;
    }

    // Path & query ad pattern matches
    if (_adPathPatterns.hasMatch(uri.path) ||
        (uri.hasQuery && _adPathPatterns.hasMatch(uri.query))) {
      return true;
    }

    // Static asset extensions
    final ext = extractMediaExtension(url);
    if (ext != null && nonMediaExtensions.contains(ext)) {
      return true;
    }

    return false;
  }

  /// Checks if two different media formats are compatible streams of the same asset
  /// (e.g. HLS `.m3u8` and progressive `.mp4`, or DASH `.mpd` and `.m4s`).
  static bool _areCompatibleMediaFormats(String? extA, String? extB) {
    if (extA == null || extB == null) return false;
    final a = extA.toLowerCase();
    final b = extB.toLowerCase();

    if (a == b) return true;

    const streamSets = [
      {'.m3u8', '.mp4', '.ts'},
      {'.mpd', '.m4s', '.mp4'},
      {'.webm', '.mp4', '.mkv'},
      {'.mp3', '.m4a', '.aac'},
    ];

    for (final set in streamSets) {
      if (set.contains(a) && set.contains(b)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if a base filename is a generic streaming playlist entrypoint
  /// (e.g. `master`, `index`, `playlist`, `manifest`, `stream`).
  static bool _isGenericPlaylistName(String name) {
    const genericNames = {
      'master',
      'index',
      'playlist',
      'manifest',
      'stream',
      'video',
      'media',
      'chunklist',
      'prog_index',
    };
    return genericNames.contains(name.toLowerCase());
  }
}
