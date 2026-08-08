import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';
import 'package:aurora_downloader/sniffer/browser_library.dart';
import 'package:aurora_downloader/sniffer/video_library.dart';

BrowserFavorite _site(String id, {String? folderId}) => BrowserFavorite(
      id: id,
      title: 'Site $id',
      url: 'https://example.com/$id',
      createdAt: DateTime(2026, 1, 1),
      folderId: folderId,
    );

BrowserFavorite _video(String id) => BrowserFavorite(
      id: id,
      title: 'Video $id',
      url: 'https://cdn.example.com/$id.mp4',
      createdAt: DateTime(2026, 1, 1),
      kind: LibraryEntryKind.video,
    );

BrowserLibrary _lib({
  List<BrowserFavorite> favorites = const [],
  List<BrowserHistoryEntry> history = const [],
}) =>
    BrowserLibrary(favorites: favorites, savedPages: const [], history: history);

void main() {
  group('migration', () {
    test('a favorite written before the split reads back as a site', () {
      // Exactly the shape the old writer produced — no `kind` at all.
      final legacy = BrowserFavorite.fromJson({
        'id': 'a',
        'title': 'Old bookmark',
        'url': 'https://example.com',
        'createdAt': DateTime(2025, 5, 1).toIso8601String(),
      });
      expect(legacy.kind, LibraryEntryKind.site);
      expect(legacy.isVideo, isFalse);
    });

    test('a history entry written before the split reads back as a site', () {
      final legacy = BrowserHistoryEntry.fromJson({
        'title': 'Old page',
        'url': 'https://example.com',
        'visitedAt': DateTime(2025, 5, 1).toIso8601String(),
      });
      expect(legacy.kind, LibraryEntryKind.site);
    });

    test('an unrecognised kind degrades to site rather than throwing', () {
      final odd = BrowserFavorite.fromJson({
        'id': 'a',
        'title': 't',
        'url': 'https://example.com',
        'createdAt': DateTime(2025, 5, 1).toIso8601String(),
        'kind': 'podcast',
      });
      expect(odd.kind, LibraryEntryKind.site);
    });

    test('kind survives a round trip', () {
      final v = _video('v1');
      expect(BrowserFavorite.fromJson(v.toJson()).kind, LibraryEntryKind.video);
    });
  });

  group('splitting', () {
    test('separates sites from videos', () {
      final lib = _lib(favorites: [_site('a'), _video('v1'), _site('b')]);
      expect(lib.siteFavorites.map((f) => f.id), ['a', 'b']);
      expect(lib.videoFavorites.map((f) => f.id), ['v1']);
    });

    test('videos never leak into a bookmark folder view', () {
      final lib = _lib(favorites: [_site('a'), _video('v1')]);
      // Unsorted is folderId == null — the bucket a video would fall into.
      expect(lib.favoritesInFolder(null).map((f) => f.id), ['a']);
    });
  });

  group('addFavorite', () {
    test('free tier stops at the inventory cap', () async {
      final full = _lib(
        favorites: [
          for (var i = 0; i < ProFeatures.freeVideoLibraryItems; i++)
            _video('v$i'),
        ],
      );
      final result = await VideoLibrary.addFavorite(
        library: full,
        tier: EntitlementTier.free,
        url: 'https://cdn.example.com/new.mp4',
        title: 'New',
      );
      expect(result.outcome, VideoSaveOutcome.capped);
      expect(result.changed, isFalse);
    });

    test('pro is unlimited', () async {
      final full = _lib(
        favorites: [
          for (var i = 0; i < ProFeatures.freeVideoLibraryItems + 5; i++)
            _video('v$i'),
        ],
      );
      final result = await VideoLibrary.addFavorite(
        library: full,
        tier: EntitlementTier.pro,
        url: 'https://cdn.example.com/new.mp4',
        title: 'New',
      );
      expect(result.outcome, VideoSaveOutcome.saved);
    });

    test('site bookmarks do not count against the video cap', () async {
      final lib = _lib(
        favorites: [for (var i = 0; i < 50; i++) _site('s$i')],
      );
      final result = await VideoLibrary.addFavorite(
        library: lib,
        tier: EntitlementTier.free,
        url: 'https://cdn.example.com/new.mp4',
        title: 'New',
      );
      expect(result.outcome, VideoSaveOutcome.saved);
    });

    test('saving the same video twice is reported, not duplicated', () async {
      final lib = _lib(favorites: [_video('v1')]);
      final result = await VideoLibrary.addFavorite(
        library: lib,
        tier: EntitlementTier.free,
        url: 'https://cdn.example.com/v1.mp4',
        title: 'Again',
      );
      expect(result.outcome, VideoSaveOutcome.duplicate);
      expect(result.library.videoFavorites, hasLength(1));
    });

    test('stores the poster and source page for later replay', () async {
      final result = await VideoLibrary.addFavorite(
        library: _lib(),
        tier: EntitlementTier.pro,
        url: 'https://cdn.example.com/a.mp4',
        title: 'A',
        thumbnailUrl: 'https://cdn.example.com/a.jpg',
        sourcePageUrl: 'https://example.com/watch',
      );
      final saved = result.library.videoFavorites.single;
      expect(saved.thumbnailUrl, 'https://cdn.example.com/a.jpg');
      expect(saved.sourcePageUrl, 'https://example.com/watch');
    });
  });

  group('recordPlay', () {
    test('replaying moves the entry to the top instead of duplicating', () {
      var lib = _lib();
      lib = VideoLibrary.recordPlay(
        library: lib,
        tier: EntitlementTier.pro,
        url: 'https://cdn.example.com/a.mp4',
        title: 'A',
      );
      lib = VideoLibrary.recordPlay(
        library: lib,
        tier: EntitlementTier.pro,
        url: 'https://cdn.example.com/b.mp4',
        title: 'B',
      );
      lib = VideoLibrary.recordPlay(
        library: lib,
        tier: EntitlementTier.pro,
        url: 'https://cdn.example.com/a.mp4',
        title: 'A',
      );
      expect(lib.videoHistory, hasLength(2));
      expect(lib.videoHistory.first.url, 'https://cdn.example.com/a.mp4');
    });

    test('free tier keeps a rolling window of the newest entries', () {
      var lib = _lib();
      for (var i = 0; i < ProFeatures.freeVideoLibraryItems + 4; i++) {
        lib = VideoLibrary.recordPlay(
          library: lib,
          tier: EntitlementTier.free,
          url: 'https://cdn.example.com/$i.mp4',
          title: 'V$i',
        );
      }
      expect(
        lib.videoHistory,
        hasLength(ProFeatures.freeVideoLibraryItems),
      );
      // Newest survives, oldest is dropped — not the other way round.
      final urls = lib.videoHistory.map((h) => h.url);
      expect(urls.first, contains('13.mp4'));
      expect(urls, isNot(contains('https://cdn.example.com/0.mp4')));
    });

    test('page history is never reordered or dropped by a video play', () {
      final pages = [
        BrowserHistoryEntry(
          title: 'P1',
          url: 'https://example.com/1',
          visitedAt: DateTime(2026, 1, 1),
        ),
        BrowserHistoryEntry(
          title: 'P2',
          url: 'https://example.com/2',
          visitedAt: DateTime(2026, 1, 2),
        ),
      ];
      final lib = VideoLibrary.recordPlay(
        library: _lib(history: pages),
        tier: EntitlementTier.free,
        url: 'https://cdn.example.com/a.mp4',
        title: 'A',
      );
      expect(lib.siteHistory.map((h) => h.url),
          ['https://example.com/1', 'https://example.com/2']);
    });
  });

  test('clearVideoHistory leaves page history intact', () {
    var lib = _lib(history: [
      BrowserHistoryEntry(
        title: 'P1',
        url: 'https://example.com/1',
        visitedAt: DateTime(2026, 1, 1),
      ),
    ]);
    lib = VideoLibrary.recordPlay(
      library: lib,
      tier: EntitlementTier.pro,
      url: 'https://cdn.example.com/a.mp4',
      title: 'A',
    );
    final cleared = VideoLibrary.clearVideoHistory(lib);
    expect(cleared.videoHistory, isEmpty);
    expect(cleared.siteHistory, hasLength(1));
  });
}
