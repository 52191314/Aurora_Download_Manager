import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/settings/download_settings.dart';
import 'package:aurora_downloader/sniffer/capture/capture_media_row.dart';
import 'package:aurora_downloader/sniffer/capture/capture_thumbnail.dart';
import 'package:aurora_downloader/sniffer/media_capture_analyzer.dart';
import 'package:aurora_downloader/sniffer/models/sniffed_media.dart';
import 'package:aurora_downloader/sniffer/sheets/sniffed_media_sheet.dart';

SniffedMedia _media({
  String url = 'https://cdn.example.com/movie.mp4',
  String name = 'movie.mp4',
  MediaType type = MediaType.video,
  int? contentLengthBytes,
  Duration? duration,
  String? contentType,
  String? containerFormat,
  int? width,
  int? height,
  String? videoCodec,
  String? audioCodec,
  int? bandwidth,
  double? frameRate,
  int? sampleRate,
  int? channels,
  bool? isLive,
  bool isSizeEstimated = false,
  bool isCacheRestored = false,
  String? thumbnailUrl,
  Map<String, String> headers = const {},
  String? sourcePageUrl,
}) {
  return SniffedMedia(
    url: url,
    name: name,
    type: type,
    contentLengthBytes: contentLengthBytes,
    duration: duration,
    contentType: contentType,
    containerFormat: containerFormat,
    width: width,
    height: height,
    videoCodec: videoCodec,
    audioCodec: audioCodec,
    bandwidth: bandwidth,
    frameRate: frameRate,
    sampleRate: sampleRate,
    channels: channels,
    isLive: isLive,
    isSizeEstimated: isSizeEstimated,
    isCacheRestored: isCacheRestored,
    thumbnailUrl: thumbnailUrl,
    headers: headers,
    sourcePageUrl: sourcePageUrl,
  );
}

CaptureGroup _group(
  SniffedMedia media, {
  String? qualityLabel,
  int variants = 1,
}) {
  CaptureCandidate candidate(SniffedMedia m) => CaptureCandidate(
        media: m,
        groupKey: 'g',
        confidence: 1,
        qualityLabel: qualityLabel,
      );
  return CaptureGroup(
    groupKey: 'g',
    candidates: [
      candidate(media),
      for (var i = 1; i < variants; i++) candidate(media),
    ],
  );
}

List<String> _labels(List<CaptureChip> chips) =>
    chips.map((c) => c.label).toList();

void main() {
  group('prettyCodecLabel', () {
    test('maps RFC 6381 manifest codecs to readable names', () {
      expect(prettyCodecLabel('avc1.640028'), 'H.264');
      expect(prettyCodecLabel('hvc1.1.6.L93.B0'), 'H.265');
      expect(prettyCodecLabel('mp4a.40.2'), 'AAC');
      expect(prettyCodecLabel('av01.0.05M.08'), 'AV1');
      expect(prettyCodecLabel('vp09.00.10.08'), 'VP9');
    });

    test('maps short probe-style names too', () {
      expect(prettyCodecLabel('h264'), 'H.264');
      expect(prettyCodecLabel('opus'), 'Opus');
      expect(prettyCodecLabel('ec-3'), 'E-AC-3');
    });

    test('passes unknown codecs through uppercased rather than dropping them', () {
      expect(prettyCodecLabel('theora'), 'THEORA');
    });

    test('returns null for empty, blank, or absurdly long values', () {
      expect(prettyCodecLabel(null), isNull);
      expect(prettyCodecLabel(''), isNull);
      expect(prettyCodecLabel('   '), isNull);
      expect(prettyCodecLabel('averyverylongcodecname'), isNull);
    });
  });

  group('formatCaptureBitrate', () {
    test('uses Mbps above 1 Mbit and kbps below', () {
      expect(formatCaptureBitrate(4200000), '4.2 Mbps');
      expect(formatCaptureBitrate(1000000), '1.0 Mbps');
      expect(formatCaptureBitrate(128000), '128 kbps');
    });
  });

  group('buildCaptureChips', () {
    test('leads with quality and surfaces video picture specs', () {
      final media = _media(
        contentLengthBytes: 148 * 1024 * 1024,
        videoCodec: 'avc1.640028',
        frameRate: 60,
        height: 1080,
      );
      final chips = buildCaptureChips(
        media,
        _group(media, qualityLabel: '1080p'),
        hls: false,
      );
      expect(_labels(chips), ['1080p', '148.0 MB', 'H.264', '60fps']);
      expect(chips.first.tone, CaptureChipTone.accent);
    });

    test('falls back to height when the group has no quality label', () {
      final media = _media(height: 720);
      final chips = buildCaptureChips(media, _group(media), hls: false);
      expect(_labels(chips), contains('720p'));
    });

    test('LIVE takes the lead and is toned as live', () {
      final media = _media(isLive: true, height: 720);
      final chips = buildCaptureChips(media, _group(media), hls: true);
      expect(chips.first.label, 'LIVE');
      expect(chips.first.tone, CaptureChipTone.live);
    });

    test('audio leads with sample rate and channels, not picture specs', () {
      final media = _media(
        type: MediaType.audio,
        sampleRate: 48000,
        channels: 2,
        audioCodec: 'mp4a.40.2',
        contentLengthBytes: 5 * 1024 * 1024,
      );
      final chips = buildCaptureChips(media, _group(media), hls: false);
      expect(_labels(chips), ['5.0 MB', '48 kHz', 'Stereo', 'AAC']);
    });

    test('marks an estimated size with a leading tilde', () {
      final media = _media(
        contentLengthBytes: 2 * 1024 * 1024,
        isSizeEstimated: true,
      );
      final chips = buildCaptureChips(media, _group(media), hls: false);
      expect(_labels(chips), contains('~2.0 MB'));
    });

    test('keeps broadcast frame rates precise instead of rounding them', () {
      final media = _media(frameRate: 29.97);
      final chips = buildCaptureChips(media, _group(media), hls: false);
      expect(_labels(chips), contains('29.97fps'));
    });

    test('honours the size display mode', () {
      final media = _media(contentLengthBytes: 1024 * 1024, height: 480);
      final chips = buildCaptureChips(
        media,
        _group(media),
        hls: false,
        displayMode: SniffedMediaDisplayMode.duration,
      );
      expect(_labels(chips), isNot(contains('1.0 MB')));
    });

    test('caps the chip count so a narrow row cannot wrap into a wall', () {
      final media = _media(
        contentLengthBytes: 1024 * 1024,
        videoCodec: 'avc1',
        frameRate: 60,
        bandwidth: 4200000,
        height: 1080,
        isLive: true,
      );
      final chips = buildCaptureChips(media, _group(media), hls: false);
      expect(chips, hasLength(4));
    });
  });

  group('buildCaptureSubtitle', () {
    test('shows the container and variant count', () {
      final media = _media(containerFormat: 'mp4');
      final subtitle = buildCaptureSubtitle(
        media,
        _group(media, variants: 3),
        hls: false,
      );
      expect(subtitle, 'MP4 · 3 variants');
    });

    test('labels HLS ahead of the container', () {
      final media = _media(containerFormat: 'mp4');
      expect(buildCaptureSubtitle(media, _group(media), hls: true), 'HLS');
    });

    test('omits duration because the poster badge already carries it', () {
      final media = _media(
        containerFormat: 'mp4',
        duration: const Duration(minutes: 12, seconds: 34),
      );
      final subtitle = buildCaptureSubtitle(media, _group(media), hls: false);
      expect(subtitle, 'MP4');
    });

    test('repeats duration only when LIVE took the badge slot', () {
      final media = _media(
        containerFormat: 'mp4',
        isLive: true,
        duration: const Duration(minutes: 12, seconds: 34),
      );
      final subtitle = buildCaptureSubtitle(media, _group(media), hls: false);
      expect(subtitle, 'MP4 · 12:34');
    });

    test('flags items restored from the previous session', () {
      final media = _media(containerFormat: 'mp4', isCacheRestored: true);
      final subtitle = buildCaptureSubtitle(media, _group(media), hls: false);
      expect(subtitle, 'MP4 · from last session');
    });

    test('falls back to the content type when no container was derived', () {
      final media = _media(contentType: 'video/mp4; codecs="avc1"');
      final subtitle = buildCaptureSubtitle(media, _group(media), hls: false);
      expect(subtitle, 'video/mp4');
    });

    test('drops the container when a chip already says it', () {
      // qualityLabel falls back to the content type on an unenriched capture,
      // so the row showed a "video/mp4" chip and an "MP4" subtitle at once.
      final media = _media(containerFormat: 'mp4');
      final subtitle = buildCaptureSubtitle(
        media,
        _group(media),
        hls: false,
        chips: const [CaptureChip('video/mp4', CaptureChipTone.accent)],
      );
      expect(subtitle, isEmpty);
    });

    test('collapses container and chip on the subtype, not the whole string', () {
      final media = _media(contentType: 'video/mp4');
      final subtitle = buildCaptureSubtitle(
        media,
        _group(media),
        hls: false,
        chips: const [CaptureChip('MP4', CaptureChipTone.neutral)],
      );
      expect(subtitle, isEmpty);
    });

    test('keeps the container when no chip repeats it', () {
      final media = _media(containerFormat: 'mkv');
      final subtitle = buildCaptureSubtitle(
        media,
        _group(media),
        hls: false,
        chips: const [CaptureChip('1080p', CaptureChipTone.accent)],
      );
      expect(subtitle, 'MKV');
    });

    test('a redundant container does not swallow the rest of the line', () {
      final media = _media(containerFormat: 'mp4', isCacheRestored: true);
      final subtitle = buildCaptureSubtitle(
        media,
        _group(media, variants: 3),
        hls: false,
        chips: const [CaptureChip('video/mp4', CaptureChipTone.accent)],
      );
      expect(subtitle, '3 variants · from last session');
    });
  });

  group('posterUrlFor', () {
    test('uses the harvested poster for playable media', () {
      final media = _media(thumbnailUrl: 'https://cdn.example.com/poster.jpg');
      expect(posterUrlFor(media), 'https://cdn.example.com/poster.jpg');
    });

    test('an image is its own thumbnail', () {
      final media = _media(
        url: 'https://cdn.example.com/photo.jpg',
        type: MediaType.image,
      );
      expect(posterUrlFor(media), 'https://cdn.example.com/photo.jpg');
    });

    test('returns null when nothing was harvested', () {
      expect(posterUrlFor(_media()), isNull);
    });

    test('refuses non-http schemes even if one reaches the model', () {
      expect(posterUrlFor(_media(thumbnailUrl: 'file:///etc/passwd')), isNull);
      expect(posterUrlFor(_media(thumbnailUrl: 'data:image/png;base64,AA')), isNull);
      expect(posterUrlFor(_media(thumbnailUrl: 'blob:https://x/uuid')), isNull);
      expect(
        posterUrlFor(
          _media(url: 'blob:https://x/uuid', type: MediaType.image),
        ),
        isNull,
      );
    });

    test('falls back to the page poster when the element had none', () {
      expect(
        posterUrlFor(_media(), pagePoster: 'https://site.example/card.jpg'),
        'https://site.example/card.jpg',
      );
    });

    test("the element's own poster outranks the page's artwork", () {
      final media = _media(thumbnailUrl: 'https://cdn.example.com/frame.jpg');
      expect(
        posterUrlFor(media, pagePoster: 'https://site.example/card.jpg'),
        'https://cdn.example.com/frame.jpg',
      );
    });

    test('a page poster is still held to the http/https rule', () {
      expect(posterUrlFor(_media(), pagePoster: null), isNull);
      expect(
        posterUrlFor(_media(), pagePoster: 'file:///etc/passwd'),
        isNull,
      );
    });
  });

  group('pagePosterFor', () {
    test('uses page artwork when the page holds one playable capture', () {
      final groups = [_group(_media())];
      expect(
        pagePosterFor(groups, 'https://site.example/card.jpg'),
        'https://site.example/card.jpg',
      );
    });

    test('refuses page artwork on a gallery of many playable captures', () {
      // The whole point: five rows painting one identical social card read as
      // a rendering fault, not a thumbnail.
      final groups = [
        _group(_media(url: 'https://cdn.example.com/a.mp4')),
        _group(_media(url: 'https://cdn.example.com/b.mp4')),
        _group(_media(url: 'https://cdn.example.com/c.mp4')),
      ];
      expect(pagePosterFor(groups, 'https://site.example/card.jpg'), isNull);
    });

    test('HLS variants of one stream still count as a single capture', () {
      final groups = [_group(_media(), variants: 5)];
      expect(
        pagePosterFor(groups, 'https://site.example/card.jpg'),
        'https://site.example/card.jpg',
      );
    });

    test('non-playable captures alongside the video do not tip the count', () {
      final groups = [
        _group(_media()),
        _group(_media(
          url: 'https://cdn.example.com/notes.pdf',
          type: MediaType.document,
        )),
        _group(_media(
          url: 'https://cdn.example.com/still.jpg',
          type: MediaType.image,
        )),
      ];
      expect(
        pagePosterFor(groups, 'https://site.example/card.jpg'),
        'https://site.example/card.jpg',
      );
    });

    test('returns null with no playable capture, and for blank artwork', () {
      expect(pagePosterFor(const [], 'https://site.example/card.jpg'), isNull);
      expect(pagePosterFor([_group(_media())], null), isNull);
      expect(pagePosterFor([_group(_media())], '   '), isNull);
    });
  });
}
