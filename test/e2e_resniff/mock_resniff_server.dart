import 'dart:async';
import 'dart:io';

/// Configurable mock HTTP server for testing resniff scenarios, HLS/MP4 token expiry,
/// Cloudflare challenges, headers propagation, and cookie verification.
class MockResniffServer {
  late HttpServer _server;
  final List<HttpRequestLog> _requestLogs = [];
  bool _isDisposed = false;

  // Configuration hooks
  String? validToken = 'valid_token_123';
  String? freshToken = 'fresh_token_456';
  bool simulateTurnstileChallenge = false;
  bool simulateRecaptcha = false;
  bool simulateDnsFailure = false;
  int? forcedStatusCode;
  Duration? responseDelay;
  List<String> htmlMediaCandidates = [];
  Map<String, String> requiredHeaders = {};
  String? requiredCookie;

  List<HttpRequestLog> get requestLogs => List.unmodifiable(_requestLogs);

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handleRequest);
  }

  void _handleRequest(HttpRequest request) async {
    if (_isDisposed) return;

    final headerMap = <String, String>{};
    request.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headerMap[name.toLowerCase()] = values.first;
      }
    });

    final log = HttpRequestLog(
      method: request.method,
      path: request.uri.path,
      queryParameters: request.uri.queryParameters,
      headers: headerMap,
    );
    _requestLogs.add(log);

    if (responseDelay != null) {
      await Future<void>.delayed(responseDelay!);
    }

    if (forcedStatusCode != null) {
      request.response.statusCode = forcedStatusCode!;
      request.response.headers.contentType = ContentType.text;
      request.response.write('Forced Status $forcedStatusCode');
      await request.response.close();
      return;
    }

    // Required headers validation
    for (final entry in requiredHeaders.entries) {
      final val = request.headers.value(entry.key);
      if (val != entry.value) {
        request.response.statusCode = 400;
        request.response.write('Missing or invalid header: ${entry.key}');
        await request.response.close();
        return;
      }
    }

    // Cookie validation
    if (requiredCookie != null) {
      final cookies = request.headers[HttpHeaders.cookieHeader] ?? [];
      final hasCookie = cookies.any((c) => c.contains(requiredCookie!));
      if (!hasCookie) {
        request.response.statusCode = 403;
        request.response.write('Missing required cookie: $requiredCookie');
        await request.response.close();
        return;
      }
    }

    final path = request.uri.path;
    final token = request.uri.queryParameters['token'];

    // 1. Source HTML page
    if (path.endsWith('.html') || path == '/' || path.startsWith('/page')) {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.html;

      if (simulateTurnstileChallenge) {
        request.response.write('''
<!DOCTYPE html>
<html>
<head><title>Just a moment...</title></head>
<body>
  <div id="cf-turnstile-wrapper">
    <div class="cf-turnstile" data-sitekey="0x4AAAAAAAA"></div>
    <p>Please verify you are a human</p>
  </div>
</body>
</html>
''');
      } else if (simulateRecaptcha) {
        request.response.write('''
<!DOCTYPE html>
<html>
<head><title>Security Check</title></head>
<body>
  <div class="g-recaptcha" data-sitekey="recaptcha_key_here"></div>
</body>
</html>
''');
      } else {
        final mediaTags = htmlMediaCandidates.map((url) {
          if (url.endsWith('.m3u8') || url.endsWith('.mpd') || url.endsWith('.mp4')) {
            return '<video controls><source src="$url" type="application/x-mpegURL"></video>';
          }
          return '<a href="$url">Media link</a>';
        }).join('\n');

        request.response.write('''
<!DOCTYPE html>
<html>
<head><title>Watch Video</title></head>
<body>
  <h1>Video Stream Page</h1>
  <div class="player-container">
    $mediaTags
  </div>
</body>
</html>
''');
      }
      await request.response.close();
      return;
    }

    // 2. HLS Master / Media Playlists
    if (path.endsWith('.m3u8')) {
      if (token == null || (token != validToken && token != freshToken)) {
        request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.text;
        request.response.write('Forbidden: Expired or Invalid Stream Token');
        await request.response.close();
        return;
      }

      request.response.statusCode = 200;
      request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
      if (path.contains('master')) {
        request.response.write('''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720
index_720p.m3u8?token=$token
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080
index_1080p.m3u8?token=$token
''');
      } else {
        request.response.write('''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10.0,
segment_0.ts?token=$token
#EXTINF:10.0,
segment_1.ts?token=$token
#EXTINF:10.0,
segment_2.ts?token=$token
#EXT-X-ENDLIST
''');
      }
      await request.response.close();
      return;
    }

    // 3. TS Segments or MP4 files
    if (path.endsWith('.ts') || path.endsWith('.mp4')) {
      if (token == null || (token != validToken && token != freshToken)) {
        request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.text;
        request.response.write('Forbidden: Token Expired');
        await request.response.close();
        return;
      }

      final fakeBytes = List<int>.filled(1024, 0xAA);
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.set('Content-Length', fakeBytes.length.toString());
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.add(fakeBytes);
      await request.response.close();
      return;
    }

    // Default 404
    request.response.statusCode = 404;
    request.response.write('Not Found');
    await request.response.close();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _server.close(force: true);
  }
}

class HttpRequestLog {
  final String method;
  final String path;
  final Map<String, String> queryParameters;
  final Map<String, String> headers;

  HttpRequestLog({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
  });
}
