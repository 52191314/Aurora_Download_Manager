import 'package:flutter_test/flutter_test.dart' hide StreamMatcher;
import 'package:aurora_downloader/sniffer/stream_matcher.dart';

void main() {
  group('StreamMatcher Candidate & Model Tests', () {
    test('StreamMatchCandidate equality, hashCode, and toString', () {
      const candidate1 = StreamMatchCandidate(
        url: 'https://cdn.example.com/hls/video.m3u8?token=xyz',
        score: 0.98,
        reason: 'Exact host and path match with refreshed query tokens',
      );

      const candidate2 = StreamMatchCandidate(
        url: 'https://cdn.example.com/hls/video.m3u8?token=xyz',
        score: 0.98,
        reason: 'Exact host and path match with refreshed query tokens',
      );

      const candidate3 = StreamMatchCandidate(
        url: 'https://cdn.example.com/hls/video.m3u8?token=abc',
        score: 0.85,
        reason: 'Different query',
      );

      expect(candidate1, equals(candidate2));
      expect(candidate1.hashCode, equals(candidate2.hashCode));
      expect(candidate1 == candidate3, isFalse);
      expect(candidate1.toString(), contains('0.980'));
      expect(candidate1.toString(), contains('Exact host and path match'));
    });
  });

  group('StreamMatcher Ad & Tracking URL Filtering', () {
    test('Identifies known ad and tracking domains', () {
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://googleads.g.doubleclick.net/pagead/ads?client=123'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://adservice.google.com/adsid/google/ui'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://syndication.exoclick.com/splash.php'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.tsyndicate.com/api/v1/ad.js'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://a.juicyads.com/adserver.php'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://analytics.google.com/g/collect'),
        isTrue,
      );
    });

    test('Identifies ad path keywords and ping playlists', () {
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/media/preroll.mp4'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/ads/video_ad_1080p.m3u8'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/hls/ping.m3u8'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/hls/master.m3u8/ping'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/api/telemetry?event=playback'),
        isTrue,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://cdn.example.com/beacon/pixel.gif'),
        isTrue,
      );
    });

    test('Identifies non-media static asset extensions', () {
      expect(StreamMatcher.isAdOrTrackingUrl('https://example.com/thumb.png'), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl('https://example.com/poster.jpg'), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl('https://example.com/script.js'), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl('https://example.com/styles.css'), isTrue);
      expect(StreamMatcher.isAdOrTrackingUrl('https://example.com/manifest.json'), isTrue);
    });

    test('Preserves legitimate media URLs', () {
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://edge01.media-cdn.org/hls/v1/master.m3u8?token=xyz123'),
        isFalse,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://stream.mysite.com/videos/episode1_1080p.mp4'),
        isFalse,
      );
      expect(
        StreamMatcher.isAdOrTrackingUrl('https://dash.streaming.io/manifest.mpd'),
        isFalse,
      );
    });
  });

  group('StreamMatcher Domain & Root Extraction', () {
    test('Extracts root domains accurately including ccTLDs', () {
      expect(StreamMatcher.extractRootDomain('cdn1.example.com'), 'example.com');
      expect(StreamMatcher.extractRootDomain('video.edge.stream.example.com'), 'example.com');
      expect(StreamMatcher.extractRootDomain('media.stream.co.uk'), 'stream.co.uk');
      expect(StreamMatcher.extractRootDomain('edge.video.com.au'), 'video.com.au');
      expect(StreamMatcher.extractRootDomain('api.server.co.id'), 'server.co.id');
      expect(StreamMatcher.extractRootDomain('localhost'), 'localhost');
      expect(StreamMatcher.extractRootDomain('192.168.1.100'), '1.100');
    });

    test('isSameDomainOrSubdomain checks domain affinity', () {
      expect(
        StreamMatcher.isSameDomainOrSubdomain('cdn1.example.com', 'cdn2.example.com'),
        isTrue,
      );
      expect(
        StreamMatcher.isSameDomainOrSubdomain('edge-01.media.site.org', 'edge-02.media.site.org'),
        isTrue,
      );
      expect(
        StreamMatcher.isSameDomainOrSubdomain('cdn.example.com', 'cdn.anotherexample.com'),
        isFalse,
      );
      expect(
        StreamMatcher.isSameDomainOrSubdomain('stream.co.uk', 'stream.com'),
        isFalse,
      );
    });
  });

  group('StreamMatcher Path & Extension Heuristics', () {
    test('Extracts media extension and base filename correctly', () {
      expect(
        StreamMatcher.extractMediaExtension('https://example.com/hls/stream.m3u8?token=abc'),
        '.m3u8',
      );
      expect(
        StreamMatcher.extractMediaExtension('https://example.com/media/VIDEO_720P.MP4'),
        '.mp4',
      );
      expect(
        StreamMatcher.extractMediaExtension('https://example.com/dash/manifest.mpd'),
        '.mpd',
      );
      expect(
        StreamMatcher.extractMediaExtension('https://example.com/api/get_stream'),
        isNull,
      );

      expect(
        StreamMatcher.extractBaseFilename('https://example.com/hls/master.m3u8?token=abc'),
        'master',
      );
      expect(
        StreamMatcher.extractBaseFilename('https://example.com/media/ep_01_1080p.mp4'),
        'ep_01_1080p',
      );
    });

    test('Computes path similarity with dynamic token tolerance', () {
      // Exact same path
      expect(
        StreamMatcher.computePathSimilarity('/hls/1080p/index.m3u8', '/hls/1080p/index.m3u8'),
        1.0,
      );

      // Path with rotated hex token segment (e.g. 16-char MD5/hex token)
      final hexTokenScore = StreamMatcher.computePathSimilarity(
        '/hls/a1b2c3d4e5f6a1b2/master.m3u8',
        '/hls/f9e8d7c6b5a4f9e8/master.m3u8',
      );
      expect(hexTokenScore, greaterThanOrEqualTo(0.85));

      // Path with rotated numeric timestamp token
      final numTokenScore = StreamMatcher.computePathSimilarity(
        '/video/1718900123456/stream.mp4',
        '/video/1718900789012/stream.mp4',
      );
      expect(numTokenScore, greaterThanOrEqualTo(0.85));

      // Completely unrelated paths
      final unrelatedScore = StreamMatcher.computePathSimilarity(
        '/hls/1080p/index.m3u8',
        '/api/v2/unrelated/asset/download',
      );
      expect(unrelatedScore, lessThan(0.2));
    });
  });

  group('StreamMatcher Candidate Scoring & Selection', () {
    test('Exact match returns score 1.0', () {
      const url = 'https://cdn.example.com/hls/master.m3u8?token=123';
      final result = StreamMatcher.evaluateCandidate(candidate: url, original: url);
      expect(result.score, 1.0);
      expect(result.reason, 'Exact URL match');
    });

    test('Query token rotation on same host and path returns 0.99 score', () {
      const original = 'https://cdn.example.com/hls/master.m3u8?token=old_token_123&exp=1000';
      const candidate = 'https://cdn.example.com/hls/master.m3u8?token=new_token_456&exp=2000';

      final result = StreamMatcher.evaluateCandidate(candidate: candidate, original: original);
      expect(result.score, 0.99);
      expect(result.reason, contains('refreshed query tokens'));
    });

    test('Sibling CDN host with matching path and filename scores high', () {
      const original = 'https://edge01.streamcdn.com/hls/show/ep1/master.m3u8?token=old';
      const candidate = 'https://edge02.streamcdn.com/hls/show/ep1/master.m3u8?token=new';

      final result = StreamMatcher.evaluateCandidate(candidate: candidate, original: original);
      expect(result.score, greaterThanOrEqualTo(0.70));
      expect(result.reason, contains('Sibling CDN domain'));
      expect(result.reason, contains('Identical media format'));
      expect(result.reason, contains('Matching base filename'));
    });

    test('Path hash token rotation scores high', () {
      const original = 'https://cdn.example.com/media/a1b2c3d4e5f6a1b2/video.m3u8?auth=1';
      const candidate = 'https://cdn.example.com/media/f9e8d7c6b5a4f9e8/video.m3u8?auth=2';

      final result = StreamMatcher.evaluateCandidate(candidate: candidate, original: original);
      expect(result.score, greaterThanOrEqualTo(0.80));
    });

    test('findBestMatch filters ads and selects highest scoring candidate', () {
      const original = 'https://media-edge.video.org/hls/episode_1080p/index.m3u8?token=stale_123';
      const sourcePage = 'https://video.org/watch/12345';

      final candidates = [
        'https://googleads.g.doubleclick.net/pagead/ads?ad_type=video', // Ad
        'https://media-edge.video.org/ads/preroll.m3u8', // Ad path
        'https://media-edge.video.org/thumbs/preview.jpg', // Static asset
        'https://unrelated-cdn.com/trailer/sample.mp4', // Unrelated
        'https://media-edge.video.org/hls/episode_1080p/index.m3u8?token=fresh_999', // True refreshed stream
        'https://media-edge.video.org/hls/episode_720p/index.m3u8?token=fresh_777', // Alternate resolution
      ];

      final bestMatch = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: original,
        sourcePageUrl: sourcePage,
      );

      expect(bestMatch, isNotNull);
      expect(
        bestMatch!.url,
        'https://media-edge.video.org/hls/episode_1080p/index.m3u8?token=fresh_999',
      );
      expect(bestMatch.score, 0.99);
    });

    test('findBestMatch returns null when no candidate passes threshold', () {
      const original = 'https://cdn.example.com/hls/show/master.m3u8?token=123';
      final candidates = [
        'https://adservice.google.com/ad.m3u8',
        'https://completely-different.com/music/track.mp3',
      ];

      final bestMatch = StreamMatcher.findBestMatch(
        candidates: candidates,
        originalMediaUrl: original,
        minScoreThreshold: 0.6,
      );

      expect(bestMatch, isNull);
    });

    test('findBestMatch returns null for empty candidates or invalid original URL', () {
      expect(
        StreamMatcher.findBestMatch(
          candidates: [],
          originalMediaUrl: 'https://example.com/stream.m3u8',
        ),
        isNull,
      );
      expect(
        StreamMatcher.findBestMatch(
          candidates: ['https://example.com/stream.m3u8'],
          originalMediaUrl: '   ',
        ),
        isNull,
      );
      expect(
        StreamMatcher.findBestMatch(
          candidates: ['https://example.com/stream.m3u8'],
          originalMediaUrl: 'not_a_valid_url',
        ),
        isNull,
      );
    });

    test('calculateSimilarity returns similarity score directly', () {
      final simExact = StreamMatcher.calculateSimilarity(
        'https://cdn.example.com/stream.m3u8?t=1',
        'https://cdn.example.com/stream.m3u8?t=1',
      );
      expect(simExact, 1.0);

      final simAd = StreamMatcher.calculateSimilarity(
        'https://googleads.doubleclick.net/ad.mp4',
        'https://cdn.example.com/stream.m3u8?t=1',
      );
      expect(simAd, 0.0);
    });
  });
}
