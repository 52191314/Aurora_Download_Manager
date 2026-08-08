import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/backup/unified_backup_database.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedBackupPayload.fromJson Empirical Malformed & Edge Case Tests', () {
    test('Vector 1: Malformed string versions', () {
      final cases = <dynamic, int>{
        'abc': 1,
        '': 1,
        '   ': 1,
        '1.2.3': 1,
        '0x10': 16, // Dart int.tryParse supports hex notation
        '-5': -5,
        '999999999999999999999999999999': 1, // Overflow int
        '\u0000': 1,
        '2.0': 1,
        'NaN': 1,
        'Infinity': 1,
        '2': 2,
      };

      for (final entry in cases.entries) {
        final json = {
          'version': entry.key,
          'timestamp': '2026-08-02',
          'data': {'key': 'val'},
        };
        expect(
          () => UnifiedBackupPayload.fromJson(json),
          returnsNormally,
          reason: 'Should not crash for version string: "${entry.key}"',
        );
        final payload = UnifiedBackupPayload.fromJson(json);
        expect(
          payload.version,
          equals(entry.value),
          reason: 'Version string "${entry.key}" should parse to ${entry.value}',
        );
      }
    });

    test('Vector 2a: Valid finite float versions (num/double)', () {
      final floatCases = <double, int>{
        1.5: 1,
        2.0: 2,
        0.0: 0,
        -1.5: -1,
        3.1415926535: 3,
      };

      for (final entry in floatCases.entries) {
        final json = {
          'version': entry.key,
          'timestamp': '2026-08-02',
          'data': <String, dynamic>{},
        };
        expect(
          () => UnifiedBackupPayload.fromJson(json),
          returnsNormally,
          reason: 'Float version ${entry.key} should not crash',
        );
        final payload = UnifiedBackupPayload.fromJson(json);
        expect(payload.version, equals(entry.value));
      }
    });

    test('Vector 2b: Special double versions (NaN and Infinity) parse cleanly without throwing UnsupportedError', () {
      for (final specialDouble in [double.nan, double.infinity, double.negativeInfinity]) {
        final json = {
          'version': specialDouble,
          'timestamp': '2026-08-02',
          'data': <String, dynamic>{},
        };

        expect(
          () => UnifiedBackupPayload.fromJson(json),
          returnsNormally,
          reason: 'Special double version $specialDouble should not throw UnsupportedError',
        );
        final payload = UnifiedBackupPayload.fromJson(json);
        expect(payload.version, equals(1));
      }
    });

    test('Vector 3: Missing keys & null fields', () {
      // Completely empty map
      final emptyJson = <String, dynamic>{};
      final pEmpty = UnifiedBackupPayload.fromJson(emptyJson);
      expect(pEmpty.version, equals(1));
      expect(pEmpty.timestamp, equals(''));
      expect(pEmpty.data, isEmpty);

      // Only version
      final pVerOnly = UnifiedBackupPayload.fromJson({'version': 5});
      expect(pVerOnly.version, equals(5));
      expect(pVerOnly.timestamp, equals(''));
      expect(pVerOnly.data.containsKey('version'), isTrue);

      // Only timestamp
      final pTsOnly = UnifiedBackupPayload.fromJson({'timestamp': '2026-08-02'});
      expect(pTsOnly.version, equals(1));
      expect(pTsOnly.timestamp, equals('2026-08-02'));
      expect(pTsOnly.data.containsKey('timestamp'), isTrue);

      // Null values
      final nullJson = <String, dynamic>{
        'version': null,
        'timestamp': null,
        'data': null,
      };
      final pNull = UnifiedBackupPayload.fromJson(nullJson);
      expect(pNull.version, equals(1));
      expect(pNull.timestamp, equals(''));
      expect(pNull.data, equals(nullJson));
    });

    test('Vector 4: Invalid map structures & unexpected data types', () {
      final invalidDataTypes = [
        123,
        45.67,
        true,
        false,
        'just a string',
        [1, 2, 3],
        [{'nested': 'list'}],
      ];

      for (final invalidData in invalidDataTypes) {
        final json = <String, dynamic>{
          'version': 2,
          'timestamp': '2026-08-02',
          'data': invalidData,
        };

        expect(
          () => UnifiedBackupPayload.fromJson(json),
          returnsNormally,
          reason: 'Invalid data type ${invalidData.runtimeType} should not crash',
        );

        final payload = UnifiedBackupPayload.fromJson(json);
        expect(payload.version, equals(2));
        expect(payload.timestamp, equals('2026-08-02'));
        // When data is not a Map, data falls back to json map
        expect(payload.data['version'], equals(2));
        expect(payload.data['data'], equals(invalidData));
      }
    });

    test('Vector 5: Map with non-string keys or complex objects', () {
      final mapWithNonStringKeys = <dynamic, dynamic>{
        100: 'int key',
        true: 'bool key',
        3.14: 'double key',
        'version': 3,
        'data': <dynamic, dynamic>{
          1: 'one',
          2: 'two',
          'strKey': 'val',
        },
      };

      final jsonMap = Map<String, dynamic>.from(
        mapWithNonStringKeys.map((k, v) => MapEntry(k.toString(), v)),
      );

      final payload = UnifiedBackupPayload.fromJson(jsonMap);
      expect(payload.version, equals(3));
      expect(payload.data['1'], equals('one'));
      expect(payload.data['strKey'], equals('val'));
    });

    test('Vector 6: Non-string timestamp representations', () {
      final nonStringTimestamps = [
        1690000000,
        123.456,
        true,
        ['2026-08-02'],
        {'date': '2026-08-02'},
      ];

      for (final ts in nonStringTimestamps) {
        final json = <String, dynamic>{
          'version': 2,
          'timestamp': ts,
          'data': <String, dynamic>{},
        };
        final payload = UnifiedBackupPayload.fromJson(json);
        expect(payload.timestamp, equals(ts.toString()));
      }
    });

    test('Vector 7: Off-thread Isolate.run error propagation for non-existent .1dmbak / .1dm paths', () async {
      final nonExistentDmbak = 'C:/non_existent_path_test_12345/missing.1dmbak';
      final nonExistent1dm = 'C:/non_existent_path_test_12345/missing.1dm';

      expect(
        () async => await UnifiedBackupDatabase.parseBackupFileTransactional(nonExistentDmbak),
        throwsA(isA<FileSystemException>()),
        reason: 'Off-thread Isolate.run must propagate FileSystemException when .1dmbak path does not exist',
      );

      expect(
        () async => await UnifiedBackupDatabase.parseBackupFileTransactional(nonExistent1dm),
        throwsA(isA<FileSystemException>()),
        reason: 'Off-thread Isolate.run must propagate FileSystemException when .1dm path does not exist',
      );
    });

    test('Vector 8: Off-thread Isolate.run parsing of corrupt .1dmbak binary noise', () async {
      final tempDir = await Directory.systemTemp.createTemp('corrupt_1dm_');
      final corrupt1dmFile = File('${tempDir.path}/corrupt_noise.1dmbak');
      // Write random non-ZIP binary garbage
      await corrupt1dmFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);

      final parsed = await UnifiedBackupDatabase.parseBackupFileTransactional(corrupt1dmFile.path);
      expect(parsed, isA<Map<String, dynamic>>());
      expect(parsed['downloadQueue'], isEmpty);
      expect(parsed['favorites'], isEmpty);
      expect(parsed['folders'], isEmpty);
      expect(parsed['history'], isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('Vector 9: Edge case payloads with negative versions, unknown top-level fields, and deep nesting', () {
      final json = <String, dynamic>{
        'version': -99,
        'timestamp': '2026-08-02T06:00:00Z',
        'unknown_field_x': 'some_val',
        'data': {
          'deeply': {
            'nested': {
              'level3': [1, 2, 3]
            }
          },
          'unknown_schema_prop': 12345,
        }
      };

      final payload = UnifiedBackupPayload.fromJson(json);
      expect(payload.version, equals(-99));
      expect(payload.timestamp, equals('2026-08-02T06:00:00Z'));
      expect(payload.data['deeply'], isA<Map>());
      expect(payload.data['unknown_schema_prop'], equals(12345));
    });
  });
}

