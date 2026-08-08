import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger M1_5 Adversarial Empirical Stress Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('challenger_m1_5_stress_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Verification Focus 1 & 2: High-Volume Burst - 100 Concurrent Exports with Nonce Collision Verification', () async {
      final baseQueue = List.generate(
        50,
        (i) => {
          'id': 'burst_task_$i',
          'url': 'https://burst.example.com/item_$i.bin',
          'bytes': 1048576 * i,
        },
      );

      final count = 100;
      final futures = List.generate(count, (index) {
        return UnifiedBackupDatabase.exportTransactionalDatabase(
          downloadQueue: baseQueue,
          settings: {'burstIndex': index},
          favorites: [],
          folders: [],
          history: [],
          savedPages: [],
          tabs: [],
          downloadRules: null,
          extra: {'exportNonceIndex': index},
          targetDirectory: tempDir,
        );
      });

      final files = await Future.wait(futures);

      // Verify all 100 exports produced files
      expect(files.length, equals(count));

      // 1. Verify that rapidly triggered exports create distinct, non-colliding backup files with nonces
      final pathSet = files.map((f) => f.path).toSet();
      expect(pathSet.length, equals(count), reason: 'All 100 generated export file paths must be strictly unique');

      // Check directory contents on disk
      final dirFiles = tempDir.listSync().whereType<File>().toList();
      expect(dirFiles.length, equals(count), reason: 'Disk directory must contain exactly 100 unique export files');

      // Check that zero .tmp files were leaked
      final tmpFiles = dirFiles.where((f) => f.path.endsWith('.tmp')).toList();
      expect(tmpFiles, isEmpty, reason: 'Zero temporary files should remain after 100 concurrent exports');

      // Verify file nonces in filename
      for (final file in files) {
        final filename = file.path.split(RegExp(r'[/\\]')).last;
        expect(filename, matches(RegExp(r'^aurora_backup_.+_\d+_\d+\.json$')),
            reason: 'Filename should match pattern aurora_backup_<timestamp>_<timestamp_micros>_<random_nonce>.json');
      }

      // Verify each file parses and holds its specific index payload
      for (var i = 0; i < files.length; i++) {
        final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(files[i].path);
        expect(parsed['exportNonceIndex'], equals(i));
        expect((parsed['downloadQueue'] as List).length, equals(50));
      }
    });

    test('Verification Focus 3: Non-finite doubles (double.nan, double.infinity, double.negativeInfinity) in version fields', () async {
      // 1. Double values directly in map passed to fromJson
      final doubleCases = [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final val in doubleCases) {
        final rawMap = <String, dynamic>{
          'version': val,
          'timestamp': '2026-08-02T06:00:00.000Z',
          'data': {'testKey': 'testVal'},
        };

        expect(
          () => UnifiedBackupPayload.fromJson(rawMap),
          returnsNormally,
          reason: 'UnifiedBackupPayload.fromJson should not throw UnsupportedError when version is $val',
        );

        final payload = UnifiedBackupPayload.fromJson(rawMap);
        expect(payload.version, equals(1), reason: 'Non-finite double version ($val) should safely fallback to version 1');
      }

      // 2. String representations of non-finite doubles in version
      final stringDoubleCases = [
        'NaN',
        'nan',
        'Infinity',
        '-Infinity',
        '+Infinity',
        'inf',
        '-inf',
      ];

      for (final strVal in stringDoubleCases) {
        final rawMap = <String, dynamic>{
          'version': strVal,
          'timestamp': '2026-08-02T06:00:00.000Z',
          'data': {'testKey': 'testVal'},
        };

        expect(
          () => UnifiedBackupPayload.fromJson(rawMap),
          returnsNormally,
          reason: 'UnifiedBackupPayload.fromJson should handle string version "$strVal" without crashing',
        );

        final payload = UnifiedBackupPayload.fromJson(rawMap);
        expect(payload.version, equals(1), reason: 'Malformed version string "$strVal" should fallback to version 1');
      }
    });

    test('Verification Focus 4: High-volume Isolate Executions under Concurrent Invocations', () async {
      // Create 20 JSON backup files and 20 mock 1DM backup files
      final jsonFiles = <File>[];
      for (var i = 0; i < 20; i++) {
        final f = File('${tempDir.path}/test_json_$i.json');
        final content = jsonEncode({
          'version': 2,
          'timestamp': '2026-08-02',
          'data': {
            'downloadQueue': [
              {'id': 'item_$i', 'title': 'Item $i'}
            ],
            'settings': {'index': i}
          }
        });
        await f.writeAsString(content);
        jsonFiles.add(f);
      }

      final dmbakFiles = <File>[];
      for (var i = 0; i < 20; i++) {
        final f = File('${tempDir.path}/test_1dm_$i.1dmbak');
        final xml = '<download_info><tag>idm_task_$i</tag><uri>https://ex.com/$i</uri><name>file_$i.mp4</name></download_info>';
        final zipBytes = _buildMock1DmZip({'info_$i.json': jsonEncode(xml)});
        await f.writeAsBytes(zipBytes);
        dmbakFiles.add(f);
      }

      // Launch 80 concurrent off-thread isolate parsing calls simultaneously
      final parseFutures = <Future<Map<String, dynamic>>>[];
      for (var i = 0; i < 40; i++) {
        parseFutures.add(UnifiedBackupDatabase.parseBackupFileTransactional(jsonFiles[i % 20].path));
        parseFutures.add(UnifiedBackupDatabase.parseBackupFileTransactional(dmbakFiles[i % 20].path));
      }

      final results = await Future.wait(parseFutures);
      expect(results.length, equals(80));

      for (var i = 0; i < results.length; i++) {
        final res = results[i];
        expect(res, isA<Map<String, dynamic>>());
        expect(res.containsKey('downloadQueue'), isTrue);
      }
    });

    test('Adversarial Edge Case: Non-encodable payload exception handling & clean cleanup', () async {
      // Pass an object that cannot be converted to JSON by jsonEncode
      final invalidMap = <String, dynamic>{
        'invalidObject': Object(), // Not JSON serializable
      };

      expect(
        () => UnifiedBackupDatabase.exportTransactionalDatabase(
          downloadQueue: [invalidMap],
          settings: {},
          favorites: [],
          folders: [],
          history: [],
          savedPages: [],
          tabs: [],
          downloadRules: null,
          extra: null,
          targetDirectory: tempDir,
        ),
        throwsA(anything),
        reason: 'Should throw JsonUnsupportedObjectError or similar when non-encodable object is passed',
      );

      // Verify directory remains clean with 0 leftover files or temp files
      final remaining = tempDir.listSync();
      expect(remaining, isEmpty, reason: 'Failed export due to non-encodable object must leave no orphan files on disk');
    });
  });
}

Uint8List _buildMock1DmZip(Map<String, String> files) {
  final List<int> bytes = [];

  for (final entry in files.entries) {
    final nameBytes = utf8.encode(entry.key);
    final contentBytes = utf8.encode(entry.value);

    bytes.addAll([0x50, 0x4b, 0x03, 0x04]);
    bytes.addAll([0x14, 0x00]);
    bytes.addAll([0x00, 0x00]);
    bytes.addAll([0x00, 0x00]);
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    final compSize = contentBytes.length;
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    final fnLen = nameBytes.length;
    bytes.addAll([fnLen & 0xFF, (fnLen >> 8) & 0xFF]);
    bytes.addAll([0x00, 0x00]);
    bytes.addAll(nameBytes);
    bytes.addAll(contentBytes);
    bytes.addAll([0x50, 0x4b, 0x07, 0x08]);
    bytes.addAll([0x00, 0x00, 0x00, 0x00]);
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
    bytes.addAll([compSize & 0xFF, (compSize >> 8) & 0xFF, (compSize >> 16) & 0xFF, (compSize >> 24) & 0xFF]);
  }

  return Uint8List.fromList(bytes);
}
