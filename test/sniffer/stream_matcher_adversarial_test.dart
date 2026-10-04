import 'package:flutter_test/flutter_test.dart' hide StreamMatcher;
import 'package:aurora_downloader/sniffer/stream_matcher.dart';

void main() {
  group('StreamMatcher Adversarial Test Suite', () {
    group('1. Exotic and Rotated CDN URL Formats', () {
      test('Complex query strings with rotated authentication tokens and nested params', () {
        const original = 'https://s12.edge.media-cloud.com/hls/live/video.m3u8'
            '?auth_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.token123'
            '&expires=1724400000'
            '&sig=7a8b9c0d1e2f'
            '&client_ip=203.0.113.19'
            '&nested_redirect=https%3A%2F%2Fgateway.org%2Fcheck';

        const refreshed = 'https://s12.edge.media-cloud.com/hls/live/video.m3u8'
            '?auth_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.rotatedNewToken456'
            '&expires=1724500000'
            '&sig=9f8e7d6c5b4a'
            '&client_ip=203.0.113.19'
            '&nested_redirect=https%3A%2F%2Fgateway.org%2Fcheck';

        final result = StreamMatcher.evaluateCandidate(
          candidate: refreshed,
          original: original,
        );

        expect(result.score, 0.99);
        expect(result.reason, contains('refreshed query tokens'));
      });

      test('Path-embedded hash tokens (MD5/SHA hex, Base64-like tokens, numeric timestamps)', () {
        // Hex tokens rotated in path
        const origHex = 'https://cdn.streamhub.net/hls/7b3f91a0c4e8d256/1080p/index.m3u8';
        const freshHex = 'https://cdn.streamhub.net/hls/1a2b3c4d5e6f7a8b/1080p/index.m3u8';

        final hexMatch = StreamMatcher.evaluateCandidate(
          candidate: freshHex,
          original: origHex,
        );
        expect(hexMatch.score, greaterThanOrEqualTo(0.80));

        // Base64-like alphanumeric token segment rotated in path
        const origB64 = 'https://cdn.faststream.org/media/T3JpZ2luYWxUb2tlblZhbHVlMTI4/master.m3u8';
        const freshB64 = 'https://cdn.faststream.org/media/UmVmcmVzaGVkVG9rZW5WYWx1ZTk5/master.m3u8';

        final b64Match = StreamMatcher.evaluateCandidate(
          candidate: freshB64,
          original: origB64,
        );
        expect(b64Match.score, greaterThanOrEqualTo(0.80));

        // Millisecond numeric timestamp rotated in path
        const origTs = 'https://cdn.faststream.org/vod/1724400000000/show_ep01.mp4';
        const freshTs = 'https://cdn.faststream.org/vod/1724403600000/show_ep01.mp4';

        final tsMatch = StreamMatcher.evaluateCandidate(
          candidate: freshTs,
          original: origTs,
        );
        expect(tsMatch.score, greaterThanOrEqualTo(0.80));
      });

      test('Subdomain sharding and edge-node rotation on sibling CDN domains', () {
        const origShard = 'https://edge-ashburn-01.video-cdn.net/hls/series/ep2/prog_index.m3u8?t=1';
        const freshShard = 'https://edge-frankfurt-99.video-cdn.net/hls/series/ep2/prog_index.m3u8?t=2';

        final shardMatch = StreamMatcher.evaluateCandidate(
          candidate: freshShard,
          original: origShard,
        );

        expect(shardMatch.score, greaterThanOrEqualTo(0.70));
        expect(shardMatch.reason, contains('Sibling CDN domain'));
      });

      test('Dynamic IP hosts and port variations', () {
        const origIp = 'http://192.168.1.100:8080/live/hls/stream.m3u8?session=old';
        const freshIp = 'http://192.168.1.100:8080/live/hls/stream.m3u8?session=new';

        final ipMatch = StreamMatcher.evaluateCandidate(
          candidate: freshIp,
          original: origIp,
        );
        expect(ipMatch.score, 0.99);

        // Subnet sibling IP
        const diffIp = 'http://192.168.1.101:8080/live/hls/stream.m3u8?session=new';
        final diffIpMatch = StreamMatcher.evaluateCandidate(
          candidate: diffIp,
          original: origIp,
        );
        expect(diffIpMatch.score, greaterThanOrEqualTo(0.40));
      });

      test('CDN signed URL syntaxes (Akamai __hdnea__, CloudFront Policy/Key-Pair-Id)', () {
        const akamaiOrig = 'https://vod.akamai-stream.com/i/video_,720p,1080p,.mp4.csmil/master.m3u8?__hdnea__=st=123~exp=456~acl=/*~hmac=abc';
        const akamaiFresh = 'https://vod.akamai-stream.com/i/video_,720p,1080p,.mp4.csmil/master.m3u8?__hdnea__=st=789~exp=999~acl=/*~hmac=xyz';

        final akamaiMatch = StreamMatcher.evaluateCandidate(
          candidate: akamaiFresh,
          original: akamaiOrig,
        );
        expect(akamaiMatch.score, 0.99);

        const cfOrig = 'https://d111111abcdef8.cloudfront.net/hls/video.m3u8?Expires=1700000000&Signature=abc&Key-Pair-Id=K12345';
        const cfFresh = 'https://d111111abcdef8.cloudfront.net/hls/video.m3u8?Expires=1700005000&Signature=xyz&Key-Pair-Id=K12345';

        final cfMatch = StreamMatcher.evaluateCandidate(
          candidate: cfFresh,
          original: cfOrig,
        );
        expect(cfMatch.score, 0.99);
      });
    });

    group('2. Malformed URLs, Edge Cases, and Exception Safety', () {
      test('Handles empty strings, whitespace-only strings, and newlines without crashing', () {
        expect(StreamMatcher.findBestMatch(candidates: [''], originalMediaUrl: ''), isNull);
        expect(StreamMatcher.findBestMatch(candidates: ['   \n\t  '], originalMediaUrl: '  '), isNull);
        expect(StreamMatcher.isAdOrTrackingUrl(''), isTrue);
        expect(StreamMatcher.isAdOrTrackingUrl('   \n  '), isTrue);
        expect(StreamMatcher.extractBaseFilename(''), '');
        expect(StreamMatcher.extractMediaExtension(''), isNull);
        expect(StreamMatcher.extractRootDomain(''), '');
        expect(StreamMatcher.computePathSimilarity('', ''), 1.0);
        expect(StreamMatcher.computePathSimilarity('/a', ''), 0.0);
      });

      test('Handles invalid schemes, missing hosts, and javascript/data URIs safely', () {
        final invalidCandidates = [
          'javascript:void(0);',
          'data:video/mp4;base64,AAAAHGZ0eXBtcDQyAAAAAG1wNDJpc29t',
          'blob:https://example.com/d5a8cf74-84c3-4217-91f9-f00e57a3e742',
          'http:///bad-path-no-host/stream.m3u8',
          '://no-scheme.com/stream.m3u8',
          'htt ps://spaces-in-url.com/stream.mp4',
          'not_a_url_at_all',
        ];

        for (final bad in invalidCandidates) {
          expect(
            () => StreamMatcher.findBestMatch(
              candidates: [bad],
              originalMediaUrl: 'https://example.com/hls/video.m3u8',
            ),
            returnsNormally,
          );
          expect(
            () => StreamMatcher.evaluateCandidate(
              candidate: bad,
              original: 'https://example.com/hls/video.m3u8',
            ),
            returnsNormally,
          );
          expect(
            () => StreamMatcher.isAdOrTrackingUrl(bad),
            returnsNormally,
          );
        }
      });

      test('Handles IPv6 brackets and invalid port numbers safely', () {
        const validIpv6 = 'http://[2001:db8::1]:8080/live/master.m3u8';
        const refreshedIpv6 = 'http://[2001:db8::1]:8080/live/master.m3u8?token=xyz';

        expect(
          () => StreamMatcher.evaluateCandidate(
            candidate: refreshedIpv6,
            original: validIpv6,
          ),
          returnsNormally,
        );

        final ipv6Match = StreamMatcher.evaluateCandidate(
          candidate: refreshedIpv6,
          original: validIpv6,
        );
        expect(ipv6Match.score, 0.99);

        // Malformed IPv6 / port
        const malformedIpv6 = 'http://[2001:db8::1:8080/unclosed-bracket.m3u8';
        const invalidPort = 'https://example.com:9999999999999999/video.m3u8';

        expect(
          () => StreamMatcher.evaluateCandidate(
            candidate: malformedIpv6,
            original: validIpv6,
          ),
          returnsNormally,
        );
        expect(
          () => StreamMatcher.evaluateCandidate(
            candidate: invalidPort,
            original: validIpv6,
          ),
          returnsNormally,
        );
      });

      test('Handles huge URLs (10,000+ characters) without stack overflow or timeout', () {
        final hugeQuery = List.generate(500, (i) => 'param_$i=value_${i * 99999}').join('&');
        final hugeOrig = 'https://cdn.example.com/hls/video.m3u8?$hugeQuery';
        final hugeCand = 'https://cdn.example.com/hls/video.m3u8?${hugeQuery}_updated';

        final result = StreamMatcher.evaluateCandidate(
          candidate: hugeCand,
          original: hugeOrig,
        );
        expect(result.score, 0.99);
      });

      test('Handles Unicode characters, IDN domains, and emoji paths in URLs', () {
        const unicodeOrig = 'https://xn--e1afmkfd.xn--p1ai/видео/мастер.m3u8?token=123';
        const unicodeCand = 'https://xn--e1afmkfd.xn--p1ai/видео/мастер.m3u8?token=456';

        final result = StreamMatcher.evaluateCandidate(
          candidate: unicodeCand,
          original: unicodeOrig,
        );
        expect(result.score, 0.99);

        const emojiOrig = 'https://cdn.example.com/streams/🎬_anime/episode_01.mp4?sig=1';
        const emojiCand = 'https://cdn.example.com/streams/🎬_anime/episode_01.mp4?sig=2';

        final emojiResult = StreamMatcher.evaluateCandidate(
          candidate: emojiCand,
          original: emojiOrig,
        );
        expect(emojiResult.score, 0.99);
      });
    });

    group('3. Ad Manifest Collision and Word False-Positive Hardening', () {
      test('Filters deceptive ad manifests and tracking endpoints mimicking video files', () {
        final deceptiveAdUrls = [
          'https://adservice.google.com/video_preroll.mp4',
          'https://stats.doubleclick.net/master.m3u8',
          'https://analytics.google.com/hls/1080p/index.m3u8',
          'https://securepubads.g.doubleclick.net/gampad/ads?video=1&output=vast',
          'https://tsyndicate.com/player/vast_video.mp4',
          'https://static.exoclick.com/content/movie_preroll.mp4',
          'https://adserver.rubiconproject.com/vast/stream.m3u8',
          'https://criteo.com/delivery/creative/banner_video.mp4',
          'https://moatads.com/hls/stream.m3u8',
          'https://cdn.example.com/ads/vast/preroll_1080p.mp4',
          'https://cdn.example.com/tracking/pixel.gif?video_url=https://cdn.example.com/video.mp4',
          'https://cdn.example.com/telemetry/ping.m3u8',
          'https://media.site.com/hls/master.m3u8/ping',
          'https://cdn.example.com/api/v1/metrics/event?type=play',
          'https://taboola.com/video/sponsor.mp4',
          'https://outbrain.com/media/promo.m3u8',
        ];

        for (final adUrl in deceptiveAdUrls) {
          expect(
            StreamMatcher.isAdOrTrackingUrl(adUrl),
            isTrue,
            reason: 'Ad URL must be filtered: $adUrl',
          );
        }

        // None of these should ever be chosen by findBestMatch even if named master.m3u8
        final match = StreamMatcher.findBestMatch(
          candidates: deceptiveAdUrls,
          originalMediaUrl: 'https://cdn.example.com/hls/master.m3u8',
        );
        expect(match, isNull, reason: 'All deceptive ad URLs must be rejected by findBestMatch');
      });

      test('Does NOT falsely flag legitimate video URLs that contain "ad" or similar substrings', () {
        final legitimateUrls = [
          'https://cdn.example.com/download/adventure_time_s01e01_1080p.mp4',
          'https://broadway-stream.org/hls/broadcasting_live_master.m3u8',
          'https://sports.org/video/badminton_championship_finals_2026.mp4',
          'https://movies-hub.net/vod/madagascar_movie_hd.mp4',
          'https://media.uni-padova.it/lectures/graduation_parade.m3u8',
          'https://grad.adelaide.edu.au/course/intro_lecture.mp4',
          'https://streaming.tv/download/blade_runner_2049.m3u8',
          'https://cinema.com/shows/head_of_state_ep01.mp4',
          'https://cdn.example.com/vod/shadow_and_bone/master.m3u8',
          'https://music-stream.io/audio/radiohead_live.opus',
          'https://cdn.video.org/series/trading_places.mp4',
        ];

        for (final url in legitimateUrls) {
          expect(
            StreamMatcher.isAdOrTrackingUrl(url),
            isFalse,
            reason: 'Legitimate URL must NOT be flagged as ad: $url',
          );
        }
      });
    });

    group('4. High-Volume Multi-Candidate Stress & Fuzzing', () {
      test('Selects the exact refreshed stream out of 100 mixed adversarial candidates', () {
        const original = 'https://edge01.videocloud.net/hls/season01/ep05_1080p/master.m3u8?token=old_token_123';
        const expectedRefreshed = 'https://edge01.videocloud.net/hls/season01/ep05_1080p/master.m3u8?token=new_token_999';

        final List<String> candidates = [];

        // 20 Ad URLs
        for (int i = 0; i < 20; i++) {
          candidates.add('https://adservice.google.com/ad_unit_$i/preroll.mp4');
          candidates.add('https://stats.doubleclick.net/hls/$i/master.m3u8');
        }

        // 20 Static Assets
        for (int i = 0; i < 20; i++) {
          candidates.add('https://edge01.videocloud.net/thumbs/preview_$i.jpg');
          candidates.add('https://edge01.videocloud.net/scripts/player_$i.js');
        }

        // 20 Completely Unrelated Streams
        for (int i = 0; i < 20; i++) {
          candidates.add('https://unrelated-domain-$i.com/media/audio_track_$i.mp3');
          candidates.add('https://diff-site.org/vod/movie_$i/index.m3u8');
        }

        // 10 Sibling CDN alternate episodes (lower score)
        for (int i = 0; i < 10; i++) {
          candidates.add('https://edge02.videocloud.net/hls/season01/ep${i + 10}_720p/master.m3u8?token=token_$i');
        }

        // Add the true refreshed URL
        candidates.add(expectedRefreshed);

        // Shuffle candidates to ensure ordering invariant
        candidates.shuffle();

        final best = StreamMatcher.findBestMatch(
          candidates: candidates,
          originalMediaUrl: original,
          sourcePageUrl: 'https://videocloud.net/watch/season01-ep05',
        );

        expect(best, isNotNull);
        expect(best!.url, expectedRefreshed);
        expect(best.score, 0.99);
      });
    });
  });
}
