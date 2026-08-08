import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedBackupDatabase Stress & Concurrency Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_stress_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Concurrent Exports: 20 simultaneous exports to same directory', () async {
      final downloadQueue = List.generate(
        100,
        (i) => {
          'id': 'task_$i',
          'url': 'https://example.com/item_$i.mp4',
          'savePath': 'completed/item_$i.mp4',
          'state': i % 2 == 0 ? 'completed' : 'paused',
          'totalBytes': 102400 * (i + 1),
          'downloadedBytes': 102400 * (i + 1),
        },
      );

      final settings = {'maxDownloads': 5, 'theme': 'dark'};

      // Launch 20 concurrent export operations simultaneously
      final futures = List.generate(20, (index) {
        return UnifiedBackupDatabase.exportTransactionalDatabase(
          downloadQueue: downloadQueue,
          settings: settings,
          favorites: [{'id': 'fav_$index', 'url': 'https://example.com/$index'}],
          folders: [],
          history: [],
          savedPages: [],
          tabs: [],
          downloadRules: null,
          extra: {'exportIndex': index},
          targetDirectory: tempDir,
        );
      });

      // Await all 20 exports
      final files = await Future.wait(futures);

      expect(files.length, equals(20));
      expect(files.map((f) => f.path).toSet().length, equals(20));
      expect(tempDir.listSync().whereType<File>().length, equals(20));

      // Verify each generated file exists and is valid JSON that parses cleanly
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        expect(await file.exists(), isTrue);

        final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
        expect(parsed.containsKey('downloadQueue'), isTrue);
        expect((parsed['downloadQueue'] as List).length, equals(100));
        expect(parsed['exportIndex'], equals(index));
      }
    });

    test('Isolate Boundary & Large Data Volume: 10,000 tasks snapshot', () async {
      final largeQueue = List.generate(
        10000,
        (i) => {
          'id': 'large_task_$i',
          'url': 'https://cdn.example.com/large_file_$i.zip',
          'savePath': 'downloads/file_$i.zip',
          'state': 'completed',
          'totalBytes': 1073741824, // 1 GB
          'downloadedBytes': 1073741824,
          'createdAt': '2026-08-01T12:00:00.000Z',
          'headers': {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TestBrowser/1.0',
            'Referer': 'https://example.com/referrer_link_$i',
            'Authorization': 'Bearer sample_token_$i',
          },
        },
      );

      final Stopwatch stopwatch = Stopwatch()..start();

      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: largeQueue,
        settings: {'large': true},
        favorites: List.generate(1000, (i) => {'id': 'fav_$i', 'title': 'Bookmark $i 🚀', 'url': 'https://example.com/$i'}),
        folders: [],
        history: List.generate(2000, (i) => {'title': 'History item $i', 'url': 'https://example.com/h/$i'}),
        savedPages: [],
        tabs: [],
        downloadRules: null,
        extra: null,
        targetDirectory: tempDir,
      );

      stopwatch.stop();
      // Verify export completed efficiently
      final exportMs = stopwatch.elapsedMilliseconds;
      expect(await file.exists(), isTrue);

      final fileSize = await file.length();
      // Expect file size to be substantial (> 2 MB)
      expect(fileSize, greaterThan(2000000));

      stopwatch.reset();
      stopwatch.start();
      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
      stopwatch.stop();
      final parseMs = stopwatch.elapsedMilliseconds;

      expect((parsed['downloadQueue'] as List).length, equals(10000));
      expect((parsed['favorites'] as List).length, equals(1000));
      expect((parsed['history'] as List).length, equals(2000));

      // Print timing metrics for record
      print('Large payload export: $exportMs ms, parse: $parseMs ms, file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('Atomic File Write & Overwrite behavior', () async {
      // Create a dummy file that might exist
      final dummyFile = File('${tempDir.path}/aurora_backup_existing.json');
      await dummyFile.writeAsString('stale content');

      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: [{'id': 'new_task'}],
        settings: {},
        favorites: [],
        folders: [],
        history: [],
        savedPages: [],
        tabs: [],
        downloadRules: null,
        extra: null,
        targetDirectory: tempDir,
      );

      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('new_task'));
      expect(content, isNot(contains('stale content')));

      // Ensure no leftover .tmp files remain in directory
      final dirEntities = tempDir.listSync();
      final tmpFiles = dirEntities.where((e) => e.path.endsWith('.tmp')).toList();
      expect(tmpFiles, isEmpty, reason: 'No temporary .tmp files should be leaked after export');
    });

    test('Isolate Safety with Complex and Non-ASCII / UTF-8 Unicode', () async {
      final unicodeData = [
        {
          'id': 'task_unicode_1',
          'name': 'Vídeo de teste 🎥 🚀 日本語 テスト 中文, 😊, 🎉, 🔀',
          'description': 'Special chars: \u0000 \n \r \t \\ / " \' < > &',
          'path': 'C:\\Users\\Test\\Downloads\\Special File (1).mp4',
        }
      ];

      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: unicodeData,
        settings: {'language': 'pt-BR / ja-JP / zh-CN'},
        favorites: [],
        folders: [],
        history: [],
        savedPages: [],
        tabs: [],
        downloadRules: null,
        extra: unicodeData.first,
        targetDirectory: tempDir,
      );

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
      final q = parsed['downloadQueue'] as List;
      expect(q.first['name'], equals('Vídeo de teste 🎥 🚀 日本語 テスト 中文, 😊, 🎉, 🔀'));
      expect(q.first['description'], equals('Special chars: \u0000 \n \r \t \\ / " \' < > &'));
    });

    test('1DM Backup Pathway Off-Thread Ingestion with Synthetic .1dmbak Archive', () async {
      // Build a minimal valid 1DM .1dmbak zip in memory
      final xmlContent = '''
<download_info>
  <tag>1dm_test_task_99</tag>
  <uri>https://1dm.example.com/video.mkv</uri>
  <name>video.mkv</name>
  <dir>/storage/emulated/0/Download/1DM</dir>
  <referer>https://1dm.example.com/page</referer>
  <userAgent>1DM+ Downloader</userAgent>
  <length>52428800</length>
  <torrent_finished>52428800</torrent_finished>
  <addedOn>1700000000000</addedOn>
  <completedOn>1700000100000</completedOn>
  <state>105</state>
  <contentType>video/x-matroska</contentType>
</download_info>
''';

      final bookmarksJson = jsonEncode([
        {
          'uuid': '1dm_fav_1',
          'mTitle': '1DM Favorite Site',
          'mUrl': 'https://1dm.example.com',
          'mFolder': 'Imported 1DM',
          'modifiedDate': 1700000000000,
        }
      ]);

      final zipBytes = _buildMock1DmZip({
        'download_info_1.json': jsonEncode(xmlContent),
        'key_bookmarks.json': bookmarksJson,
      });

      final dmbakFile = File('${tempDir.path}/backup_export.1dmbak');
      await dmbakFile.writeAsBytes(zipBytes);

      // Parse via parseBackupFileTransactional off-thread isolate
      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(dmbakFile.path);

      expect(parsed.containsKey('downloadQueue'), isTrue);
      expect(parsed.containsKey('favorites'), isTrue);
      expect(parsed.containsKey('folders'), isTrue);

      final queue = parsed['downloadQueue'] as List;
      expect(queue.length, equals(1));
      expect(queue.first['id'], equals('1dm_test_task_99'));
      expect(queue.first['url'], equals('https://1dm.example.com/video.mkv'));
      expect(queue.first['state'], equals('completed'));
      expect(queue.first['totalBytes'], equals(52428800));

      final favs = parsed['favorites'] as List;
      expect(favs.length, equals(1));
      expect(favs.first['title'], equals('1DM Favorite Site'));

      final folders = parsed['folders'] as List;
      expect(folders.length, equals(1));
      expect(folders.first['name'], equals('Imported 1DM'));
    });
  });
}

/// Utility function to build uncompressed ZIP archive bytes for 1DM mock tests.
Uint8List _buildMock1DmZip(Map<String, String> files) {
  final List<int> bytes = [];

  for (final entry in files.entries) {
    final nameBytes = utf8.encode(entry.key);
    final contentBytes = utf8.encode(entry.value);

    // Local file header signature PK\x03\x04
    bytes.addAll([0x50, 0x4b, 0x03, 0x04]);
    // Version needed (2.0)
    bytes.addAll([0x14, 0x00]);
    // General purpose flag
    bytes.addAll([0x00, 0x00]);
    // Compression method (0 = uncompressed)
    bytes.addAll([0x00, 0x00]);
    // Last mod time / date
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    // CRC-32 (dummy 0 for test)
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    // Compressed size
    final compSize = contentBytes.length;
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    // Uncompressed size
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    // Filename length
    final fnLen = nameBytes.length;
    bytes.addAll([fnLen & 0xFF, (fnLen >> 8) & 0xFF]);
    // Extra field length (0)
    bytes.addAll([0x00, 0x00]);
    // Filename
    bytes.addAll(nameBytes);
    // File content
    bytes.addAll(contentBytes);
    // Data descriptor signature PK\x07\x08
    bytes.addAll([0x50, 0x4b, 0x07, 0x08]);
    // CRC-32
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    // Comp size
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    // Uncomp size
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
  }

  return Uint8List.fromList(bytes);
}
