import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aurora_downloader/premium/vault_crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

/// Streaming AES-GCM must be byte-compatible with the previous one-shot
/// package:encrypt path (same ciphertext layout, same tag) so vault files
/// written by either path decrypt with the other.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_crypto_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // Fixed 32-byte AES-256 key + 12-byte nonce (deterministic tests).
  final key = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 7 + 3) % 256),
  );
  final nonce = Uint8List.fromList(
    List<int>.generate(12, (i) => (i * 13 + 1) % 256),
  );

  Uint8List oneShotEncrypt(Uint8List plain, {Uint8List? header}) {
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.gcm));
    final ct = encrypter.encryptBytes(plain, iv: enc.IV(nonce)).bytes;
    if (header == null) return ct;
    return Uint8List.fromList([...header, ...ct]);
  }

  Uint8List? oneShotDecrypt(Uint8List blob, {int skip = 0}) {
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.gcm));
    final ct = Uint8List.sublistView(blob, skip);
    try {
      return Uint8List.fromList(
        encrypter.decryptBytes(enc.Encrypted(ct), iv: enc.IV(nonce)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> streamedEncrypt(
    Uint8List plain, {
    Uint8List? header,
    int chunkBytes = kVaultStreamChunkBytes,
  }) async {
    final src = File('${tempDir.path}/src.bin')..writeAsBytesSync(plain);
    final dst = File('${tempDir.path}/ct.bin');
    await encryptGcmStream(
      src: src,
      dst: dst,
      key: key,
      nonce: nonce,
      header: header,
      chunkBytes: chunkBytes,
    );
    return dst.readAsBytesSync();
  }

  Future<Uint8List?> streamedDecrypt(
    Uint8List blob, {
    int skip = 0,
    int chunkBytes = kVaultStreamChunkBytes,
  }) async {
    final src = File('${tempDir.path}/blob.bin')..writeAsBytesSync(blob);
    final dst = File('${tempDir.path}/pt.bin');
    try {
      await decryptGcmStream(
        src: src,
        dst: dst,
        key: key,
        nonce: nonce,
        skipBytes: skip,
        chunkBytes: chunkBytes,
      );
      return dst.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  group('GCM streaming vs one-shot compatibility', () {
    test('byte-identical ciphertext for a multi-block + partial-tail payload',
        () async {
      final plain = Uint8List.fromList(
        List<int>.generate(1_000_003, (i) => (i * 31 + 7) % 256),
      );
      final expected = oneShotEncrypt(plain);
      final actual = await streamedEncrypt(plain);
      expect(actual, equals(expected));
    });

    test('empty plaintext produces tag-only output like one-shot', () async {
      final plain = Uint8List(0);
      final expected = oneShotEncrypt(plain);
      final actual = await streamedEncrypt(plain);
      expect(actual, equals(expected));
      expect(actual.length, kVaultGcmTagBytes);
    });

    test('streamed encrypt -> streamed decrypt round-trips', () async {
      for (final size in [0, 1, 15, 16, 17, 1 << 20, (1 << 20) + 1, (1 << 20) * 3]) {
        final plain = Uint8List.fromList(
          List<int>.generate(size, (i) => (i * 3 + size) % 256),
        );
        final blob = await streamedEncrypt(plain);
        final round = await streamedDecrypt(blob);
        expect(round, isNotNull, reason: 'size=$size');
        expect(round, equals(plain), reason: 'size=$size');
      }
    });

    test('one-shot encrypt -> streamed decrypt (old file, new reader)',
        () async {
      final plain = Uint8List.fromList(
        List<int>.generate(123_457, (i) => (i * 5 + 1) % 256),
      );
      final blob = oneShotEncrypt(plain);
      final round = await streamedDecrypt(blob);
      expect(round, equals(plain));
    });

    test('streamed encrypt -> one-shot decrypt (new file, old reader)',
        () async {
      final plain = Uint8List.fromList(
        List<int>.generate(999_999, (i) => (i * 11 + 3) % 256),
      );
      final blob = await streamedEncrypt(plain);
      final round = oneShotDecrypt(blob);
      expect(round, equals(plain));
    });

    test('vault v1 header (0x01 | nonce) is written and skipped correctly',
        () async {
      final plain = Uint8List.fromList(
        List<int>.generate(65_537, (i) => i % 256),
      );
      final header = Uint8List.fromList([0x01, ...nonce]);
      final blob = await streamedEncrypt(plain, header: header);
      expect(blob[0], 0x01);
      expect(blob.sublist(1, 13), equals(nonce));
      // Full blob (header included) must equal the one-shot path with the
      // same layout: version | nonce | ct+tag.
      final expected = oneShotEncrypt(plain, header: header);
      expect(blob, equals(expected));
      // Decrypt skipping the 13-byte header.
      final round = await streamedDecrypt(blob, skip: 13);
      expect(round, equals(plain));
    });

    test('small chunk sizes (odd boundaries) still match one-shot', () async {
      final plain = Uint8List.fromList(
        List<int>.generate(10_000, (i) => (i * 17 + 5) % 256),
      );
      for (final chunk in [7, 16, 100, 4096]) {
        final actual = await streamedEncrypt(plain, chunkBytes: chunk);
        expect(actual, equals(oneShotEncrypt(plain)), reason: 'chunk=$chunk');
        final round = await streamedDecrypt(actual, chunkBytes: chunk);
        expect(round, equals(plain), reason: 'chunk=$chunk');
      }
    });

    test('tampered ciphertext fails tag validation', () async {
      final plain = Uint8List.fromList(
        List<int>.generate(50_000, (i) => i % 251),
      );
      final blob = await streamedEncrypt(plain);
      final tampered = Uint8List.fromList(blob);
      tampered[blob.length ~/ 2] ^= 0x01; // flip a ciphertext byte
      final round = await streamedDecrypt(tampered);
      expect(round, isNull);
    });

    test('tampered tag fails validation with the real exception', () async {
      final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
      final blob = await streamedEncrypt(plain);
      final tampered = Uint8List.fromList(blob);
      tampered[tampered.length - 1] ^= 0xFF; // corrupt last tag byte
      final src = File('${tempDir.path}/t.bin')..writeAsBytesSync(tampered);
      final dst = File('${tempDir.path}/t.out');
      await expectLater(
        decryptGcmStream(src: src, dst: dst, key: key, nonce: nonce),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });

    test('wrong key fails validation', () async {
      final plain = Uint8List.fromList(List<int>.filled(100, 42));
      final blob = await streamedEncrypt(plain);
      final wrongKey = Uint8List.fromList(key);
      wrongKey[0] ^= 0xFF;
      final src = File('${tempDir.path}/w.bin')..writeAsBytesSync(blob);
      final dst = File('${tempDir.path}/w.out');
      await expectLater(
        decryptGcmStream(src: src, dst: dst, key: wrongKey, nonce: nonce),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });
  });

  group('ChunkedBase64', () {
    test('encoder round-trips with arbitrary chunk boundaries', () {
      final raw = List<int>.generate(10_000, (i) => i % 256);
      final encoder = ChunkedBase64Encoder();
      var acc = '';
      final rng = Random(42);
      var i = 0;
      while (i < raw.length) {
        final n = 1 + rng.nextInt(500);
        final end = min(i + n, raw.length);
        acc += encoder.add(raw.sublist(i, end));
        i = end;
      }
      acc += encoder.close();
      expect(acc, base64.encode(raw));
    });

    test('decoder round-trips with arbitrary chunk boundaries', () {
      final raw = List<int>.generate(7_777, (i) => (i * 13) % 256);
      final b64 = base64.encode(raw);
      final decoder = ChunkedBase64Decoder();
      final rng = Random(7);
      var i = 0;
      final out = <int>[];
      while (i < b64.length) {
        final n = 1 + rng.nextInt(120);
        final end = min(i + n, b64.length);
        out.addAll(decoder.add(b64.substring(i, end)));
        i = end;
      }
      out.addAll(decoder.close());
      expect(out, equals(raw));
    });

    test('encoder + decoder round-trip together', () {
      final raw = List<int>.generate(5_555, (i) => (i * 29 + 11) % 256);
      final encoder = ChunkedBase64Encoder();
      final decoder = ChunkedBase64Decoder();
      final out = <int>[];
      final rng = Random(1);
      var i = 0;
      while (i < raw.length) {
        final n = 1 + rng.nextInt(700);
        final end = min(i + n, raw.length);
        out.addAll(decoder.add(encoder.add(raw.sublist(i, end))));
        i = end;
      }
      out.addAll(decoder.add(encoder.close()));
      out.addAll(decoder.close());
      expect(out, equals(raw));
    });
  });
}
