import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/capture/capture_frame_cache.dart';
import 'package:aurora_downloader/sniffer/models/sniffed_media.dart';

SniffedMedia _video({
  String url = 'https://cdn.example.com/clip.mp4',
  MediaType type = MediaType.video,
  Map<String, String> headers = const {},
  String? sourcePageUrl,
}) {
  return SniffedMedia(
    url: url,
    name: 'clip.mp4',
    type: type,
    headers: headers,
    sourcePageUrl: sourcePageUrl,
  );
}

Uint8List _bytes(int fill) => Uint8List.fromList([fill, fill, fill]);

/// Records calls and lets each decode be completed by hand, so the queueing
/// behaviour can be observed rather than raced against.
class _FakeDecoder {
  final List<String> calls = <String>[];
  final Map<String, Completer<Uint8List?>> pending =
      <String, Completer<Uint8List?>>{};

  Future<Uint8List?> call(
    String url, {
    required Map<String, String> headers,
    required int maxWidth,
  }) {
    calls.add(url);
    return (pending[url] ??= Completer<Uint8List?>()).future;
  }

  /// Tolerates being called before the decode is actually issued: the cache
  /// awaits a concurrency slot first, so the call lands a microtask later.
  void finish(String url, Uint8List? value) {
    (pending[url] ??= Completer<Uint8List?>()).complete(value);
  }

  void explode(String url) {
    (pending[url] ??= Completer<Uint8List?>())
        .completeError(StateError('decoder blew up'));
  }
}

void main() {
  group('canDecode', () {
    test('accepts remote video only', () {
      expect(CaptureFrameCache.canDecode(_video()), isTrue);
    });

    test('refuses non-video captures', () {
      // Audio cover art would be a different retriever call; documents and
      // images have no frame to decode at all.
      for (final type in [
        MediaType.audio,
        MediaType.image,
        MediaType.document,
        MediaType.archive,
        MediaType.torrent,
        MediaType.playlist,
      ]) {
        expect(
          CaptureFrameCache.canDecode(_video(type: type)),
          isFalse,
          reason: '$type should not be decoded',
        );
      }
    });

    test('refuses sources that were never real streams', () {
      expect(
        CaptureFrameCache.canDecode(_video(url: 'blob:https://x/uuid')),
        isFalse,
      );
      expect(
        CaptureFrameCache.canDecode(_video(url: 'file:///sdcard/a.mp4')),
        isFalse,
      );
      expect(CaptureFrameCache.canDecode(_video(url: 'not a url at all')), isFalse);
    });
  });

  group('headersFor', () {
    test('adds the source page as referer when none was captured', () {
      final headers = CaptureFrameCache.headersFor(
        _video(sourcePageUrl: 'https://site.example/watch/1'),
      );
      expect(headers['Referer'], 'https://site.example/watch/1');
    });

    test('does not overwrite a referer the sniffer already resolved', () {
      final headers = CaptureFrameCache.headersFor(
        _video(
          headers: const {'referer': 'https://site.example/real'},
          sourcePageUrl: 'https://site.example/other',
        ),
      );
      expect(headers['referer'], 'https://site.example/real');
      expect(headers.containsKey('Referer'), isFalse);
    });
  });

  group('frameFor', () {
    test('caches a decoded frame and never decodes it twice', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);
      final item = _video();

      final first = cache.frameFor(item);
      fake.finish(item.url, _bytes(1));
      expect(await first, _bytes(1));

      expect(await cache.frameFor(item), _bytes(1));
      expect(fake.calls, [item.url]);
      expect(cache.cached(item.url), _bytes(1));
    });

    test('coalesces concurrent callers onto one decode', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);
      final item = _video();

      final a = cache.frameFor(item);
      final b = cache.frameFor(item);
      final c = cache.frameFor(item);
      fake.finish(item.url, _bytes(2));

      expect(await a, _bytes(2));
      expect(await b, _bytes(2));
      expect(await c, _bytes(2));
      expect(fake.calls, hasLength(1));
    });

    test('a URL with no frame is never retried', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);
      final item = _video();

      final first = cache.frameFor(item);
      fake.finish(item.url, null);
      expect(await first, isNull);

      expect(cache.hasFailed(item.url), isTrue);
      expect(await cache.frameFor(item), isNull);
      // A CDN that refuses range requests refuses them every time; retrying on
      // each rebuild would spend the battery for nothing.
      expect(fake.calls, hasLength(1));
    });

    test('an empty payload counts as no frame', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);
      final item = _video();

      final first = cache.frameFor(item);
      fake.finish(item.url, Uint8List(0));
      expect(await first, isNull);
      expect(cache.hasFailed(item.url), isTrue);
    });

    test('a throwing decoder is a failure, not a crash', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);
      final item = _video();

      final first = cache.frameFor(item);
      fake.explode(item.url);
      expect(await first, isNull);
      expect(cache.hasFailed(item.url), isTrue);
    });

    test('skips captures it cannot decode without calling the platform', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call);

      expect(await cache.frameFor(_video(type: MediaType.document)), isNull);
      expect(await cache.frameFor(_video(url: 'blob:https://x/1')), isNull);
      expect(fake.calls, isEmpty);
    });
  });

  group('bounds', () {
    test('holds no more than maxConcurrent decodes in flight', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call, maxConcurrent: 2);

      for (var i = 0; i < 5; i++) {
        cache.frameFor(_video(url: 'https://cdn.example.com/$i.mp4'));
      }
      await pumpEventQueue();

      expect(fake.calls, hasLength(2));
      expect(cache.activeDecodes, 2);

      // Retiring one admits exactly one more, not the whole backlog.
      fake.finish('https://cdn.example.com/0.mp4', _bytes(0));
      await pumpEventQueue();
      expect(fake.calls, hasLength(3));

      fake.finish('https://cdn.example.com/1.mp4', _bytes(1));
      await pumpEventQueue();
      expect(fake.calls, hasLength(4));
    });

    test('evicts the least recently used frame past maxEntries', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call, maxEntries: 2);

      for (var i = 0; i < 3; i++) {
        final url = 'https://cdn.example.com/$i.mp4';
        final future = cache.frameFor(_video(url: url));
        fake.finish(url, _bytes(i));
        await future;
      }

      expect(cache.cachedCount, 2);
      expect(cache.cached('https://cdn.example.com/0.mp4'), isNull);
      expect(cache.cached('https://cdn.example.com/2.mp4'), _bytes(2));
    });

    test('reading a frame keeps it from being the next one evicted', () async {
      final fake = _FakeDecoder();
      final cache = CaptureFrameCache(decoder: fake.call, maxEntries: 2);

      Future<void> decode(int i) async {
        final url = 'https://cdn.example.com/$i.mp4';
        final future = cache.frameFor(_video(url: url));
        fake.finish(url, _bytes(i));
        await future;
      }

      await decode(0);
      await decode(1);
      // Touch 0 so 1 becomes the oldest.
      expect(cache.cached('https://cdn.example.com/0.mp4'), _bytes(0));
      await decode(2);

      expect(cache.cached('https://cdn.example.com/0.mp4'), _bytes(0));
      expect(cache.cached('https://cdn.example.com/1.mp4'), isNull);
    });
  });
}
