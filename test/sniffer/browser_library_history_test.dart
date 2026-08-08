import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/browser_library.dart';

BrowserLibrary _libraryWith(List<BrowserHistoryEntry> history) {
  return BrowserLibrary(
    favorites: const [],
    savedPages: const [],
    history: history,
  );
}

BrowserHistoryEntry _entry(String url, {DateTime? at, String? title}) {
  return BrowserHistoryEntry(
    title: title ?? url,
    url: url,
    visitedAt: at ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('withVisit', () {
    test('puts the newest visit at the front', () {
      final library = _libraryWith([_entry('https://a.example')]);
      final updated = library.withVisit('https://b.example', 'B');

      expect(updated.history.first.url, 'https://b.example');
      expect(updated.history.first.title, 'B');
      expect(updated.history, hasLength(2));
    });

    test('collapses a revisit instead of duplicating it', () {
      // A site visited repeatedly should occupy one row, not fifty.
      var library = _libraryWith([
        _entry('https://a.example'),
        _entry('https://b.example'),
      ]);
      for (var i = 0; i < 50; i++) {
        library = library.withVisit('https://a.example', 'A');
      }

      expect(library.history, hasLength(2));
      expect(library.history.first.url, 'https://a.example');
      expect(
        library.history.where((h) => h.url == 'https://a.example'),
        hasLength(1),
      );
    });

    test('caps the list, dropping the oldest', () {
      final existing = [
        for (var i = 0; i < 10; i++) _entry('https://old-$i.example'),
      ];
      final updated = _libraryWith(existing).withVisit('https://new.example', 'N', limit: 5);

      expect(updated.history, hasLength(5));
      expect(updated.history.first.url, 'https://new.example');
      // The four most recent survivors, and nothing older.
      expect(
        updated.history.map((h) => h.url).toList(),
        ['https://new.example', 'https://old-0.example', 'https://old-1.example',
         'https://old-2.example', 'https://old-3.example'],
      );
    });

    test('stays at the cap across many visits when one is given', () {
      var library = _libraryWith([]);
      for (var i = 0; i < 500; i++) {
        library = library.withVisit('https://site-$i.example', 'S$i', limit: 50);
        expect(library.history.length, lessThanOrEqualTo(50));
      }
      expect(library.history, hasLength(50));
      expect(library.history.first.url, 'https://site-499.example');
    });

    test('keeps every distinct visit when no limit is given', () {
      // History must not be silently truncated: the freeze was caused by
      // re-serialising the whole library per visit, not by its size, so the fix
      // belongs in the store and must not cost the user their record.
      var library = _libraryWith([]);
      for (var i = 0; i < 3000; i++) {
        library = library.withVisit('https://site-$i.example', 'S$i');
      }
      expect(library.history, hasLength(3000));
      expect(library.history.first.url, 'https://site-2999.example');
      expect(library.history.last.url, 'https://site-0.example');
    });

    test('a limit of 1 keeps only the current page', () {
      final updated = _libraryWith([
        _entry('https://a.example'),
        _entry('https://b.example'),
      ]).withVisit('https://c.example', 'C', limit: 1);

      expect(updated.history, hasLength(1));
      expect(updated.history.single.url, 'https://c.example');
    });

    test('leaves the rest of the library untouched', () {
      final library = BrowserLibrary(
        favorites: [
          BrowserFavorite(
            id: 'fav1',
            title: 'Kept',
            url: 'https://fav.example',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        savedPages: const [],
        history: const [],
        folders: [
          BookmarkFolder(
            id: 'f1',
            name: 'Folder',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final updated = library.withVisit('https://a.example', 'A');

      expect(updated.favorites, hasLength(1));
      expect(updated.favorites.single.url, 'https://fav.example');
      expect(updated.folders, hasLength(1));
      expect(updated.folders.single.id, 'f1');
    });

    test('records the supplied timestamp', () {
      final at = DateTime(2026, 7, 30, 9, 41);
      final updated = _libraryWith([]).withVisit('https://a.example', 'A', at: at);
      expect(updated.history.single.visitedAt, at);
    });

    test('a revisit does not resurrect a dropped entry under a limit', () {
      // Guards the interaction between dedupe and the bounded view: skipping the
      // matching URL must not let one extra older entry past the cap.
      final existing = [
        for (var i = 0; i < 10; i++) _entry('https://old-$i.example'),
      ];
      final updated = _libraryWith(existing)
          .withVisit('https://old-5.example', 'Revisit', limit: 3);

      expect(updated.history, hasLength(3));
      expect(updated.history.first.url, 'https://old-5.example');
      expect(
        updated.history.where((h) => h.url == 'https://old-5.example'),
        hasLength(1),
      );
    });
  });
}
