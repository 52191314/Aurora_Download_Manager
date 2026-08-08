import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/idm_backup_parser.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';

/// Helper to create standard synthetic 1DM zip entries in memory for testing
List<int> createSyntheticZipEntry({
  required String filename,
  required List<int> uncompressedData,
}) {
  final compBytes = ZLibEncoder(raw: true).convert(uncompressedData);
  final fnBytes = utf8.encode(filename);

  final builder = BytesBuilder();
  // Local Header: PK\x03\x04
  builder.add([0x50, 0x4b, 0x03, 0x04]);
  builder.add([0x14, 0x00]); // Version
  builder.add([0x08, 0x00]); // Flag (Data descriptor present)
  builder.add([0x08, 0x00]); // Deflate
  builder.add([0x00, 0x00, 0x00, 0x00]); // Mod time/date
  builder.add([0x00, 0x00, 0x00, 0x00]); // CRC32
  builder.add([0x00, 0x00, 0x00, 0x00]); // Comp size (0 for data descriptor)
  builder.add([0x00, 0x00, 0x00, 0x00]); // Uncomp size (0 for data descriptor)

  final fnLenBytes = (ByteData(2)..setUint16(0, fnBytes.length, Endian.little)).buffer.asUint8List();
  builder.add(fnLenBytes);
  builder.add([0x00, 0x00]); // Extra len

  builder.add(fnBytes); // Filename
  builder.add(compBytes); // Compressed Data Payload

  // Data Descriptor: PK\x07\x08
  builder.add([0x50, 0x4b, 0x07, 0x08]);
  builder.add([0x00, 0x00, 0x00, 0x00]); // CRC32
  final cSizeData = (ByteData(4)..setUint32(0, compBytes.length, Endian.little)).buffer.asUint8List();
  builder.add(cSizeData);
  final uSizeData = (ByteData(4)..setUint32(0, uncompressedData.length, Endian.little)).buffer.asUint8List();
  builder.add(uSizeData);

  return builder.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IdmBackupParser', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('idm_parser_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Parses synthetic .1dmbak file with XML download tasks, bookmarks, and history', () async {
      final zipBuilder = BytesBuilder();

      // 1. Download Info XML entry
      const xmlContent = '''<download_info>
  <tag>task_1dm_101</tag>
  <uri>https://example.com/videos/sample.mp4</uri>
  <name>sample.mp4</name>
  <dir>/sdcard/Download/Movies</dir>
  <referer>https://example.com/watch</referer>
  <userAgent>Mozilla/5.0 AuroraTest</userAgent>
  <length>1048576</length>
  <torrent_finished>1048576</torrent_finished>
  <addedOn>1600000000000</addedOn>
  <completedOn>1600000060000</completedOn>
  <state>105</state>
  <contentType>video/mp4</contentType>
</download_info>''';
      final xmlJsonWrapper = json.encode(xmlContent);
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'download_info_1',
        uncompressedData: utf8.encode(xmlJsonWrapper),
      ));

      // 2. Bookmarks JSON entry
      final bookmarksData = [
        {
          'mUrl': 'https://flutter.dev',
          'mTitle': 'Flutter Home',
          'mFolder': 'Development',
          'uuid': 'fav_flutter_1',
          'modifiedDate': 1600000100000,
        }
      ];
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'key_bookmarks.json',
        uncompressedData: utf8.encode(json.encode(bookmarksData)),
      ));

      // 3. History JSON entry
      final historyData = [
        {
          'mUrl': 'https://dart.dev',
          'mTitle': 'Dart Language',
          'modifiedDate': 1600000200000,
        }
      ];
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'key_history.json',
        uncompressedData: utf8.encode(json.encode(historyData)),
      ));

      final testFile = File('${tempDir.path}/backup.1dmbak');
      await testFile.writeAsBytes(zipBuilder.toBytes());

      final result = await IdmBackupParser.parse(testFile.path);

      expect(result.containsKey('downloadQueue'), isTrue);
      expect(result.containsKey('favorites'), isTrue);
      expect(result.containsKey('folders'), isTrue);
      expect(result.containsKey('history'), isTrue);

      final queue = result['downloadQueue'] as List;
      expect(queue.length, equals(1));
      final task = queue.first as Map<String, dynamic>;
      expect(task['id'], equals('task_1dm_101'));
      expect(task['url'], equals('https://example.com/videos/sample.mp4'));
      expect(task['savePath'], equals('completed/Movies/sample.mp4'));
      expect(task['state'], equals('completed'));
      expect(task['totalBytes'], equals(1048576));
      expect(task['downloadedBytes'], equals(1048576));
      expect(task['headers'], equals({'Referer': 'https://example.com/watch', 'User-Agent': 'Mozilla/5.0 AuroraTest'}));
      expect(task['sourcePageUrl'], equals('https://example.com/watch'));
      expect(task['contentType'], equals('video/mp4'));

      final favorites = result['favorites'] as List;
      expect(favorites.length, equals(1));
      final fav = favorites.first as Map<String, dynamic>;
      expect(fav['id'], equals('fav_flutter_1'));
      expect(fav['title'], equals('Flutter Home'));
      expect(fav['url'], equals('https://flutter.dev'));
      expect(fav['folderId'], equals('folder_1'));

      final folders = result['folders'] as List;
      expect(folders.length, equals(1));
      expect(folders.first['name'], equals('Development'));

      final history = result['history'] as List;
      expect(history.length, equals(1));
      expect(history.first['title'], equals('Dart Language'));
      expect(history.first['url'], equals('https://dart.dev'));
    });

    test('Sanitizes path traversal in filenames and directories and filters dangerous schemes', () async {
      final zipBuilder = BytesBuilder();

      // Task with path traversal name & dir and safe URL
      const xmlTraversals = '''<download_info>
  <tag>task_traversal</tag>
  <uri>https://example.com/safe.bin</uri>
  <name>../../evil_script.sh</name>
  <dir>/sdcard/Download/../../secret_dir</dir>
  <state>0</state>
  <length>200</length>
  <torrent_finished>50</torrent_finished>
</download_info>''';
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'download_info_traversal',
        uncompressedData: utf8.encode(json.encode(xmlTraversals)),
      ));

      // Task with dangerous file:// scheme
      const xmlDangerous = '''<download_info>
  <tag>task_dangerous</tag>
  <uri>file:///etc/passwd</uri>
  <name>passwd</name>
  <state>105</state>
</download_info>''';
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'download_info_dangerous',
        uncompressedData: utf8.encode(json.encode(xmlDangerous)),
      ));

      // Bookmark with dangerous content:// scheme
      final dangerousBookmarks = [
        {'mUrl': 'content://media/external/images/media/1', 'mTitle': 'Dangerous Content'}
      ];
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'key_bookmarks.json',
        uncompressedData: utf8.encode(json.encode(dangerousBookmarks)),
      ));

      final testFile = File('${tempDir.path}/security_test.1dm');
      await testFile.writeAsBytes(zipBuilder.toBytes());

      final result = await IdmBackupParser.parse(testFile.path);

      final queue = result['downloadQueue'] as List;
      expect(queue.length, equals(1)); // Dangerous file:// scheme was filtered out

      final task = queue.first as Map<String, dynamic>;
      expect(task['id'], equals('task_traversal'));
      expect(task['savePath'], equals('completed/secret_dir/evil_script.sh'));
      expect(task['savePath'].contains('..'), isFalse);
      expect(task['state'], equals('paused'));
      expect(task['downloadedBytes'], equals(50));

      final favorites = result['favorites'] as List;
      expect(favorites, isEmpty); // Dangerous content:// scheme was filtered out
    });

    test('Throws FileSystemException when parsing non-existent file', () async {
      final nonExistentPath = '${tempDir.path}/does_not_exist.1dmbak';
      expect(
        () async => await IdmBackupParser.parse(nonExistentPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Handles corrupted byte streams gracefully without throwing unhandled exceptions', () async {
      final corruptFile = File('${tempDir.path}/corrupt.1dmbak');
      await corruptFile.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 0x99, 0x88, 0x77, 0x66]);

      final result = await IdmBackupParser.parse(corruptFile.path);
      expect(result['downloadQueue'], isEmpty);
      expect(result['favorites'], isEmpty);
      expect(result['history'], isEmpty);
    });

    test('UnifiedBackupDatabase.parseBackupFileTransactional sniffs PK\\x03\\x04 magic bytes and extension', () async {
      final zipBuilder = BytesBuilder();

      const xmlContent = '''<download_info>
  <tag>task_magic</tag>
  <uri>https://example.com/magic.zip</uri>
  <name>magic.zip</name>
  <state>105</state>
</download_info>''';
      zipBuilder.add(createSyntheticZipEntry(
        filename: 'download_info_magic',
        uncompressedData: utf8.encode(json.encode(xmlContent)),
      ));

      // Save file with a non-1dm extension (.bak) but with PK\x03\x04 header
      final magicFile = File('${tempDir.path}/backup_unknown_ext.bak');
      await magicFile.writeAsBytes(zipBuilder.toBytes());

      final result = await UnifiedBackupDatabase.parseBackupFileTransactional(magicFile.path);
      final queue = result['downloadQueue'] as List;
      expect(queue.length, equals(1));
      expect((queue.first as Map)['id'], equals('task_magic'));
    });
  });
}
