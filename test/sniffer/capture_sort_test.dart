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
}
