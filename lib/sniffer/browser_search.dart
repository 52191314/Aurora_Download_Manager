import '../settings/download_settings.dart';
import 'external_scheme.dart';

class BrowserSearch {
  /// Resolves raw text from the address bar, history, or tab restoration into
  /// a valid [Uri].
  ///
  /// Adheres to RFC 3986 scheme specifications. If [rawInput] cannot be parsed
  /// as a valid URI (or has illegal scheme characters like spaces before colons,
  /// malformed ports, or leading digits in schemes), it safely encodes the text
  /// as a query URL using [searchEngine] instead of throwing a [FormatException].
  static Uri resolveInput(String rawInput, SearchEngine searchEngine) {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return _safeParseSearchUrl(searchEngine.buildSearchUrl(input));
    }

    try {
      final parsed = Uri.tryParse(input);
      // http(s) with host, or app schemes without a host (tg:resolve?…, magnet:…).
      // Schemes with dots (e.g. 'example.com:8080') are domains, not app schemes.
      if (parsed != null && parsed.hasScheme && !parsed.scheme.contains('.')) {
        if (parsed.host.isNotEmpty || isExternalAppUri(parsed)) {
          return parsed;
        }
      }

      if (_looksLikeHost(input)) {
        final httpsUri = Uri.tryParse('https://$input');
        if (httpsUri != null && httpsUri.hasAuthority) {
          return httpsUri;
        }
      }

      return _safeParseSearchUrl(searchEngine.buildSearchUrl(input));
    } catch (_) {
      return _safeParseSearchUrl(searchEngine.buildSearchUrl(input));
    }
  }

  /// Bulletproof helper that guarantees a valid [Uri] is returned without
  /// ever throwing [FormatException] under any input condition.
  static Uri safeResolve(String rawInput, [SearchEngine? searchEngine]) {
    final engine = searchEngine ?? SearchEngine.google;
    try {
      return resolveInput(rawInput, engine);
    } catch (_) {
      try {
        return Uri.parse(engine.buildSearchUrl(rawInput));
      } catch (_) {
        return Uri.parse('about:blank');
      }
    }
  }

  /// Internal helper to parse pre-built search URLs safely.
  static Uri _safeParseSearchUrl(String searchUrl) {
    try {
      return Uri.parse(searchUrl);
    } catch (_) {
      return Uri.parse('about:blank');
    }
  }

  static bool _looksLikeHost(String input) {
    if (input.contains(RegExp(r'\s'))) return false;
    if (input.startsWith('?')) return false;
    final host = input.split('/').first.split(':').first;
    return host.contains('.') && !host.startsWith('.') && !host.endsWith('.');
  }
}
