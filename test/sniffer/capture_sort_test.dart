import 'package:aurora_downloader/settings/download_settings.dart';
import 'package:aurora_downloader/sniffer/browser_library.dart';
import 'package:aurora_downloader/sniffer/capture_sort.dart';
import 'package:aurora_downloader/sniffer/models/sniffed_media.dart';
import 'package:aurora_downloader/sniffer/sheets/favorite_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sortSniffedMedia by name', () {
    SniffedMedia m(String name) => SniffedMedia(
          url: 'https://x/$name',
          name: name,
          type: MediaType.video,
          sniffedAt: DateTime.now(),
        );
    final sorted = sortSniffedMedia(
      [m('zeta'), m('alpha'), m('mid')],
      SniffedMediaSort.name,
    );
    expect(sorted.map((e) => e.name).toList(), ['alpha', 'mid', 'zeta']);
  });

  test('applyFavoriteEdit updates folder and tags', () {
    final fav = BrowserFavorite(
      id: '1',
      title: 'T',
      url: 'https://example.com',
      createdAt: DateTime.now(),
    );
    final library = BrowserLibrary(
      favorites: [fav],
      folders: const [],
      history: const [],
      savedPages: const [],
    );
    final updated = applyFavoriteEdit(
      library,
      fav,
      const EditFavoriteResult(folderId: 'f1', tags: ['a', 'b']),
    );
    expect(updated.favorites.single.folderId, 'f1');
    expect(updated.favorites.single.tags, ['a', 'b']);
  });

  group('sortSniffedMedia', () {
    final t0 = DateTime.utc(2024, 1, 1);
    DateTime t(int seconds) => t0.add(Duration(seconds: seconds));

    SniffedMedia m({
      required String url,
      String? name,
      MediaType type = MediaType.video,
      required DateTime sniffedAt,
      int? size,
      Duration? duration,
    }) {
      return SniffedMedia(
        url: url,
        name: name ?? url,
        type: type,
        sniffedAt: sniffedAt,
        contentLengthBytes: size,
        duration: duration,
      );
    }

    List<String> urls(List<SniffedMedia> list) =>
        list.map((e) => e.url).toList();

    test('name mode uses numeric-aware natural sort', () {
      final items = [
        m(url: 'https://x/e10', name: 'Episode 10', sniffedAt: t(0)),
        m(url: 'https://x/e2', name: 'Episode 2', sniffedAt: t(1)),
        m(url: 'https://x/e1', name: 'Episode 1', sniffedAt: t(2)),
      ];
      final sorted = sortSniffedMedia(items, SniffedMediaSort.name);
      expect(
        sorted.map((e) => e.name).toList(),
        ['Episode 1', 'Episode 2', 'Episode 10'],
      );
    });

    test('natural sort is case-insensitive', () {
      final items = [
        m(url: 'https://x/a', name: 'file10', sniffedAt: t(0)),
        m(url: 'https://x/b', name: 'FILE2', sniffedAt: t(1)),
        m(url: 'https://x/c', name: 'file1', sniffedAt: t(2)),
      ];
      final sorted = sortSniffedMedia(items, SniffedMediaSort.name);
      expect(
        sorted.map((e) => e.name).toList(),
        ['file1', 'FILE2', 'file10'],
      );
    });

    test('re-sorting equal-key items is a stable no-op', () {
      // 40 items share one name (equal primary key) but differ in sniffedAt
      // and url. Dart's List.sort is unstable above 32 elements, so the
      // explicit tie-breakers must make re-sorting idempotent.
      final items = List.generate(40, (i) {
        return m(
          url: 'https://x/item$i',
          name: 'same',
          sniffedAt: t(i),
        );
      });
      final first = sortSniffedMedia(items, SniffedMediaSort.name);
      final second = sortSniffedMedia(first, SniffedMediaSort.name);
      expect(urls(first), urls(second));
      // Tie-break: newest sniffedAt first (item39..item0).
      expect(
        urls(first),
        List.generate(40, (i) => 'https://x/item${39 - i}'),
      );
    });

    test('size mode sinks unknown sizes to the bottom, stably', () {
      final items = [
        m(url: 'https://x/known1', name: 'a', sniffedAt: t(0), size: 100),
        m(url: 'https://x/unknown1', name: 'u1', sniffedAt: t(2)),
        m(url: 'https://x/known2', name: 'b', sniffedAt: t(1), size: 50),
        m(url: 'https://x/unknown2', name: 'u2', sniffedAt: t(3)),
      ];
      final sorted = sortSniffedMedia(items, SniffedMediaSort.size);
      final result = urls(sorted);
      // Known sizes first, descending.
      expect(result.sublist(0, 2), ['https://x/known1', 'https://x/known2']);
      // Unknown sizes last, ordered by sniffedAt desc (newest first).
      expect(result.sublist(2), ['https://x/unknown2', 'https://x/unknown1']);
    });

    test('duration mode sinks unknown durations to the bottom, stably', () {
      final items = [
        m(
          url: 'https://x/known1',
          name: 'a',
          sniffedAt: t(0),
          duration: const Duration(seconds: 10),
        ),
        m(url: 'https://x/unknown1', name: 'u1', sniffedAt: t(2)),
        m(
          url: 'https://x/known2',
          name: 'b',
          sniffedAt: t(1),
          duration: const Duration(seconds: 5),
        ),
        m(url: 'https://x/unknown2', name: 'u2', sniffedAt: t(3)),
      ];
      final sorted = sortSniffedMedia(items, SniffedMediaSort.duration);
      final result = urls(sorted);
      expect(result.sublist(0, 2), ['https://x/known1', 'https://x/known2']);
      expect(result.sublist(2), ['https://x/unknown2', 'https://x/unknown1']);
    });

    test('name/type/size/duration tie-break by sniffedAt desc then url', () {
      for (final mode in const [
        SniffedMediaSort.name,
        SniffedMediaSort.type,
        SniffedMediaSort.size,
        SniffedMediaSort.duration,
      ]) {
        final a = m(
          url: 'https://x/older',
          name: 'n',
          type: MediaType.video,
          sniffedAt: t(0),
          size: 10,
          duration: const Duration(seconds: 10),
        );
        final b = m(
          url: 'https://x/newer',
          name: 'n',
          type: MediaType.video,
          sniffedAt: t(1),
          size: 10,
          duration: const Duration(seconds: 10),
        );
        // Equal primary key in every mode -> tie-break by sniffedAt desc.
        final sorted = sortSniffedMedia([a, b], mode);
        expect(urls(sorted), ['https://x/newer', 'https://x/older'],
            reason: 'mode=$mode');
      }
    });

    test('newest mode ties (equal sniffedAt) fall back to url ascending', () {
      final a = m(url: 'https://x/b', name: 'b', sniffedAt: t(0));
      final b = m(url: 'https://x/a', name: 'a', sniffedAt: t(0));
      final sorted = sortSniffedMedia([a, b], SniffedMediaSort.newest);
      expect(urls(sorted), ['https://x/a', 'https://x/b']);
    });

    test('type mode groups by type name then ties by sniffedAt', () {
      final items = [
        m(
          url: 'https://x/v1',
          name: 'v1',
          type: MediaType.video,
          sniffedAt: t(0),
        ),
        m(
          url: 'https://x/a1',
          name: 'a1',
          type: MediaType.audio,
          sniffedAt: t(1),
        ),
        m(
          url: 'https://x/v2',
          name: 'v2',
          type: MediaType.video,
          sniffedAt: t(2),
        ),
      ];
      final sorted = sortSniffedMedia(items, SniffedMediaSort.type);
      // 'audio' < 'video'; among videos, newest sniffedAt first.
      expect(urls(sorted), ['https://x/a1', 'https://x/v2', 'https://x/v1']);
    });
  });
}
