import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedBackupDatabase Empirical Stress & Edge Case Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('unified_backup_stress_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Edge Case 1: Empty file, empty string, and whitespace file', () async {
      final emptyFile = File('${tempDir.path}/empty.json');
      await emptyFile.writeAsString('');

      final whitespaceFile = File('${tempDir.path}/whitespace.json');
      await whitespaceFile.writeAsString('   \n\t  \r\n ');

      final parsedEmpty = await UnifiedBackupDatabase.parseBackupFileTransactional(emptyFile.path);
      expect(parsedEmpty, isEmpty, reason: 'Empty file should return empty map without crashing');

      final parsedWhitespace = await UnifiedBackupDatabase.parseBackupFileTransactional(whitespaceFile.path);
      expect(parsedWhitespace, isEmpty, reason: 'Whitespace file should return empty map without crashing');
    });

    test('Edge Case 2: Malformed/Corrupted JSON files', () async {
      final truncatedFile = File('${tempDir.path}/truncated.json');
      await truncatedFile.writeAsString('{"version": 2, "data": {"downloadQueue": [{"id": "task_1"');

      final htmlFile = File('${tempDir.path}/html.json');
      await htmlFile.writeAsString('<html><body>404 Not Found</body></html>');

      final binaryJunkFile = File('${tempDir.path}/binary.json');
      await binaryJunkFile.writeAsBytes([0x00, 0xFF, 0xFE, 0x12, 0x34, 0x56, 0x78, 0x9A]);

      final jsonArrayFile = File('${tempDir.path}/array.json');
      await jsonArrayFile.writeAsString('[1, 2, 3, 4, 5]');

      final jsonPrimitiveFile = File('${tempDir.path}/primitive.json');
      await jsonPrimitiveFile.writeAsString('"Just a string"');

      expect(await UnifiedBackupDatabase.parseBackupFileTransactional(truncatedFile.path), isEmpty);
      expect(await UnifiedBackupDatabase.parseBackupFileTransactional(htmlFile.path), isEmpty);
      expect(await UnifiedBackupDatabase.parseBackupFileTransactional(binaryJunkFile.path), isEmpty);
      expect(await UnifiedBackupDatabase.parseBackupFileTransactional(jsonArrayFile.path), isEmpty);
      expect(await UnifiedBackupDatabase.parseBackupFileTransactional(jsonPrimitiveFile.path), isEmpty);
    });

    test('Edge Case 3: Missing keys, partial envelopes & null fields', () async {
      final noVersionFile = File('${tempDir.path}/no_version.json');
      await noVersionFile.writeAsString('{"data": {"settings": {"key": "val"}}}');

      final noDataFile = File('${tempDir.path}/no_data.json');
      await noDataFile.writeAsString('{"version": 2, "timestamp": "2026-08-02"}');

      final nullDataFile = File('${tempDir.path}/null_data.json');
      await nullDataFile.writeAsString('{"version": 2, "data": null}');

      final parsedNoVersion = await UnifiedBackupDatabase.parseBackupFileTransactional(noVersionFile.path);
      expect(parsedNoVersion.containsKey('data'), isTrue);

      final parsedNoData = await UnifiedBackupDatabase.parseBackupFileTransactional(noDataFile.path);
      expect(parsedNoData['version'], equals(2));

      final parsedNullData = await UnifiedBackupDatabase.parseBackupFileTransactional(nullDataFile.path);
      expect(parsedNullData['version'], equals(2));
      expect(parsedNullData['data'], isNull);
    });

    test('Edge Case 4: Unexpected types in root & payload fields', () async {
      final stringVersionFile = File('${tempDir.path}/string_version.json');
      await stringVersionFile.writeAsString('{"version": "2", "data": {"favorites": []}}');

      final stringDataFile = File('${tempDir.path}/string_data.json');
      await stringDataFile.writeAsString('{"version": 2, "data": "not_a_map"}');

      final listDataFile = File('${tempDir.path}/list_data.json');
      await listDataFile.writeAsString('{"version": 2, "data": [1, 2, 3]}');

      final parsedStringVersion = await UnifiedBackupDatabase.parseBackupFileTransactional(stringVersionFile.path);
      // Because rawMap has 'version' key and 'data' is Map, parseBackupFileTransactional unwraps 'data'
      expect(parsedStringVersion.containsKey('favorites'), isTrue);

      final parsedStringData = await UnifiedBackupDatabase.parseBackupFileTransactional(stringDataFile.path);
      // 'data' is not a Map so it returns rawMap containing version and data
      expect(parsedStringData['data'], equals('not_a_map'));

      final parsedListData = await UnifiedBackupDatabase.parseBackupFileTransactional(listDataFile.path);
      expect(parsedListData['data'], equals([1, 2, 3]));
    });

    test('Edge Case 5: UnifiedBackupPayload.fromJson type safety analysis', () {
      final validJson = {'version': 2, 'timestamp': '2026-08-02', 'data': {'a': 1}};
      final payloadValid = UnifiedBackupPayload.fromJson(validJson);
      expect(payloadValid.version, equals(2));
      expect(payloadValid.data['a'], equals(1));

      final legacyJson = {'favorites': [{'id': '1'}]};
      final payloadLegacy = UnifiedBackupPayload.fromJson(legacyJson);
      expect(payloadLegacy.version, equals(1));
      expect(payloadLegacy.data['favorites'], isNotNull);

      // Verify resilient handling when version is a String
      final stringVersionJson = {'version': '2', 'timestamp': '2026', 'data': {'b': 2}};
      final payloadStringVer = UnifiedBackupPayload.fromJson(stringVersionJson);
      expect(payloadStringVer.version, equals(2));
      expect(payloadStringVer.data['b'], equals(2));
    });

    test('Edge Case 6: Non-existent file path handling', () async {
      final nonExistentPath = '${tempDir.path}/does_not_exist.json';
      expect(
        () async => await UnifiedBackupDatabase.parseBackupFileTransactional(nonExistentPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Stress Test: Large Dataset Payload export & parse roundtrip', () async {
      final largeQueue = List.generate(
        10000,
        (index) => {
          'id': 'task_$index',
          'url': 'https://example.com/stream/segment_$index.ts',
          'savePath': 'downloads/video_part_$index.ts',
          'state': index % 2 == 0 ? 'completed' : 'downloading',
          'totalBytes': 5000000,
          'downloadedBytes': index % 2 == 0 ? 5000000 : 2500000,
          'headers': {
            'User-Agent': 'AuroraDownloader/1.0 (Mobile Browser Engine)',
            'Authorization': 'Bearer sample_token_$index',
          },
        },
      );

      final largeHistory = List.generate(
        5000,
        (index) => {
          'id': 'hist_$index',
          'url': 'https://example.com/page_$index',
          'title': 'Sample Page Title Number $index with Extra Metadata',
          'visitedAt': DateTime.now().toIso8601String(),
        },
      );

      final Stopwatch exportStopwatch = Stopwatch()..start();
      final file = await UnifiedBackupDatabase.exportTransactionalDatabase(
        downloadQueue: largeQueue,
        settings: {'largeSetting': 'A' * 10000},
        favorites: [],
        folders: [],
        history: largeHistory,
        savedPages: [],
        tabs: [],
        downloadRules: null,
        extra: {'customMeta': 'B' * 50000},
        targetDirectory: tempDir,
      );
      exportStopwatch.stop();

      expect(await file.exists(), isTrue);
      final fileLength = await file.length();
      expect(fileLength, greaterThan(1000000), reason: 'Payload should be over 1MB');

      final Stopwatch parseStopwatch = Stopwatch()..start();
      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(file.path);
      parseStopwatch.stop();

      expect(parsed.containsKey('downloadQueue'), isTrue);
      expect((parsed['downloadQueue'] as List).length, equals(10000));
      expect((parsed['history'] as List).length, equals(5000));
      expect(parsed['customMeta'], equals('B' * 50000));

      // Assert performance thresholds: export < 5s, parse < 5s
      expect(exportStopwatch.elapsedMilliseconds, lessThan(5000));
      expect(parseStopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
