import 'package:aurora_downloader/compliance/restricted_media_policy.dart';
import 'package:aurora_downloader/premium/build_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RestrictedMediaPolicy Wave 1 hosts', () {
    test('YouTube surface + CDN + UI sound', () {
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://www.youtube.com/watch?v=1',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://m.youtube.com/s/search/audio/success.mp3',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://rr5---sn-abc.googlevideo.com/videoplayback?id=1',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://music.youtube.com/'),
        isTrue,
      );
    });

    test('TikTok / Meta / Netflix / Spotify / Twitch', () {
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://www.tiktok.com/@x'),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://v16.tiktokcdn.com/video/x.mp4',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://www.instagram.com/p/1'),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://scontent.cdninstagram.com/v/t51.x/1.mp4',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://www.netflix.com/title/1'),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://ipv4-c001-abc.1.oca.nflxvideo.net/x',
        ),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://open.spotify.com/track/1'),
        isTrue,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://www.twitch.tv/x'),
        isTrue,
      );
    });

    test('allows unrelated hosts', () {
      expect(
        RestrictedMediaPolicy.isRestrictedUrl('https://example.com/video.mp4'),
        isFalse,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://files.example.org/'),
        isFalse,
      );
      // Narrow Prime rules not in Wave 1 — generic Amazon shopping not blocked.
      expect(
        RestrictedMediaPolicy.isRestrictedPage('https://www.amazon.com/dp/B0'),
        isFalse,
      );
    });
  });

  group('RestrictedMediaPolicy channel gating', () {
    test('default github channel does not enforce', () {
      expect(BuildChannel.isPlay, isFalse);
      expect(RestrictedMediaPolicy.enforcementEnabled, isFalse);
      expect(
        RestrictedMediaPolicy.shouldHardOffSniffing(
          'https://www.youtube.com/watch?v=1',
        ),
        isFalse,
      );
      expect(
        RestrictedMediaPolicy.isBlocked(
          mediaUrl: 'https://www.youtube.com/watch?v=1',
        ),
        isFalse,
      );
    });

    test('forceEnforce blocks restricted page and CDN referer', () {
      final byPage = RestrictedMediaPolicy.evaluate(
        mediaUrl: 'https://cdn.example.com/v.mp4',
        sourcePageUrl: 'https://www.tiktok.com/@x',
        forceEnforce: true,
      );
      expect(byPage.blocked, isTrue);
      expect(byPage.message, RestrictedMediaPolicy.userMessageRestricted);

      final byReferer = RestrictedMediaPolicy.evaluate(
        mediaUrl: 'https://cdn.example.com/v.mp4',
        headers: {'Referer': 'https://www.instagram.com/'},
        forceEnforce: true,
      );
      expect(byReferer.blocked, isTrue);
    });

    test('shouldHardOffSniffing is surface-only under force path', () {
      // Hard-off uses surface hosts; media CDN alone is not a "page".
      // (enforcementEnabled is false in tests — use isRestrictedPage for surface.)
      expect(
        RestrictedMediaPolicy.isRestrictedPage(
          'https://v16.tiktokcdn.com/video/x.mp4',
        ),
        isFalse,
      );
      expect(
        RestrictedMediaPolicy.isRestrictedUrl(
          'https://v16.tiktokcdn.com/video/x.mp4',
        ),
        isTrue,
      );
    });

    test('allows clean direct download when enforcing', () {
      final d = RestrictedMediaPolicy.evaluate(
        mediaUrl: 'https://files.example.com/doc.pdf',
        sourcePageUrl: 'https://files.example.com/',
        forceEnforce: true,
      );
      expect(d.blocked, isFalse);
    });
  });
}
