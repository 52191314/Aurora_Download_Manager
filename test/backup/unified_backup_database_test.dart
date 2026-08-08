import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedBackupDatabase (Solution B)', () {
    test('exportTransactionalDatabase & parseBackupFileTransactional roundtrip', () async {
      final tempDir = await Directory.systemTemp.createTemp('unified_backup_test_');

      final downloadQueue = [
        {
          'id': 'task_1',
          'url': 'https://example.com/video.mp4',
          'savePath': 'completed/video.mp4',
          'state': 'completed',
          'totalBytes': 102400,
          'downloadedBytes': 102400,
        }
      ];
      final settings = {
        'downloadDestination': 'Download/Aurora Downloader',
        'maxConcurrentDownloads': 5,
      };
      final favorites = [
        {
          'id': 'fav_1',
          'title': 'Test Site',
          'url': 'https://example.com',
        }
      ];

      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: downloadQueue,
        settings: settings,
        favorites: favorites,
        folders: [],
        history: [],
        savedPages: [],
        tabs: [],
        downloadRules: null,
        extra: null,
        targetDirectory: tempDir,
      );

      expect(await file.exists(), isTrue);

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
      expect(parsed.containsKey('downloadQueue'), isTrue);
      expect(parsed.containsKey('settings'), isTrue);
      expect(parsed.containsKey('favorites'), isTrue);

      final q = parsed['downloadQueue'] as List;
      expect(q.length, equals(1));
      expect(q.first['id'], equals('task_1'));

      await tempDir.delete(recursive: true);
    });

    test('parseBackupFileTransactional handles legacy payloads cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('legacy_test_');
      final legacyFile = File('${tempDir.path}/legacy.json');
      await legacyFile.writeAsString('{"favorites":[{"title":"Legacy","url":"https://legacy.com"}]}');

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(legacyFile.path);
      expect(parsed.containsKey('favorites'), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('exportTransactionalDatabase includes tabGroups when provided', () async {
      final tempDir = await Directory.systemTemp.createTemp('tab_groups_test_');
      final tabGroups = [
        {'id': 'group_1', 'name': 'Work', 'color': 0xFF0000FF}
      ];

      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: [],
        settings: {},
        favorites: [],
        folders: [],
        history: [],
        savedPages: [],
        tabs: [],
        tabGroups: tabGroups,
        downloadRules: null,
        extra: null,
        targetDirectory: tempDir,
      );

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
      expect(parsed.containsKey('tabGroups'), isTrue);
      final groups = parsed['tabGroups'] as List;
      expect(groups.length, equals(1));
      expect(groups.first['id'], equals('group_1'));

      await tempDir.delete(recursive: true);
    });

    test('parseBackupFileTransactional handles corrupted JSON cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('corrupt_test_');
      final corruptFile = File('${tempDir.path}/corrupt.json');
      await corruptFile.writeAsString('{ invalid json string ...');

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(corruptFile.path);
      expect(parsed, isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('UnifiedBackupPayload.fromJson type safety with malformed payloads', () {
      // String version
      final payload1 = UnifiedBackupPayload.fromJson({
        'version': '2',
        'timestamp': 12345,
        'data': {'item': 1},
      });
      expect(payload1.version, equals(2));
      expect(payload1.timestamp, equals('12345'));
      expect(payload1.data['item'], equals(1));

      // Malformed version and non-map data
      final payload2 = UnifiedBackupPayload.fromJson({
        'version': 'invalid',
        'timestamp': null,
        'data': 'not a map',
        'fallbackKey': 'fallbackValue',
      });
      expect(payload2.version, equals(1));
      expect(payload2.timestamp, equals(''));
      expect(payload2.data['fallbackKey'], equals('fallbackValue'));
    });
  });
}

