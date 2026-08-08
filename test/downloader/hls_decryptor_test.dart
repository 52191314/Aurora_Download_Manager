import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_downloader/downloader/hls_decryptor.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';

/// Decryptor is isolate-safe and only depends on dart:io + pointycastle, so
/// these tests deliberately avoid flutter/material and any plugin imports.

Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  assert(clean.length % 2 == 0);
  return Uint8List.fromList(List<int>.generate(
    clean.length ~/ 2,
    (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
  ));
}

/// Writes [ciphertext] to a temp file, decrypts it with [key]/[iv], and
/// returns the decrypted bytes. [useIsolate] toggles the Isolate.run entry
/// point vs the same-isolate one.
Future<Uint8List> decryptRoundTrip(
  Uint8List key,
  Uint8List iv,
  Uint8List ciphertext, {
  bool useIsolate = false,
}) async {
  final dir = await Directory.systemTemp.createTemp('hls_dec_');
  try {
    final file = File('${dir.path}/seg.ts');
    await file.writeAsBytes(ciphertext, flush: true);
    if (useIsolate) {
      await HlsDecryptor.decryptInPlace(file, key, iv);
    } else {
      await HlsDecryptor.decryptInPlaceSync(file, key, iv);
    }
    return await file.readAsBytes();
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  group('HlsDecryptor AES-128-CBC', () {
    // FIPS-197 / NIST SP 800-38A F.2.1 AES-128-CBC known-answer vector.
    test('NIST KAT vector decrypts to the known plaintext (raw CBC, 4 blocks)',
        () async {
      final key = hexToBytes('2b7e151628aed2a6abf7158809cf4f3c');
      final iv = hexToBytes('000102030405060708090a0b0c0d0e0f');
      final plaintext = hexToBytes(
        '6bc1bee22e409f96e93d7e117393172a '
        'ae2d8a571e03ac9c9eb76fac45af8e51 '
        '30c81c46a35ce411e5fbc1191a0a52ef '
        'f69f2445df4f9b17ad2b417be66c3710',
      );
      final ciphertext = hexToBytes(
        '7649abac8119b246cee98e9b12e9197d '
        '5086cb9b507219ee95db113a917678b2 '
        '73bed6b8e3c1743b7116e69e22229516 '
        '3ff1caa1681fac09120eca307586e1a7',
      );

      final out = await decryptRoundTrip(key, iv, ciphertext);
      expect(out, orderedEquals(plaintext));
    });

    test('single-block (16-byte) PKCS7-padded segment round-trips', () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      final plain = Uint8List.fromList(
        List<int>.generate(9, (i) => 0x40 + i), // 9 bytes + 7 pad bytes
      );

      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: 'PKCS7',
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );
      expect(cipher.length, 16, reason: 'single encrypted block');

      final out = await decryptRoundTrip(key, iv, cipher);
      expect(out, orderedEquals(plain));
    });

    test('multi-block segment (>= 5 blocks) with padding round-trips',
        () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      final plain = Uint8List.fromList(
        List<int>.generate(5 * 16, (i) => (i * 31) & 0xff), // 80 bytes
      );

      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: 'PKCS7',
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );
      expect(cipher.length, 6 * 16, reason: '6 ciphertext blocks');

      final out = await decryptRoundTrip(key, iv, cipher);
      expect(out, orderedEquals(plain));
    });

    test('segment whose plaintext length is not a multiple of 16 round-trips',
        () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      final plain = Uint8List.fromList(
        List<int>.generate(55, (i) => (i * 11 + 3) & 0xff), // 55 bytes
      );

      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: 'PKCS7',
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );
      expect(cipher.length % 16, 0);
      expect(cipher.length, 64, reason: '55 bytes + 9 pad bytes = 64');

      final out = await decryptRoundTrip(key, iv, cipher);
      expect(out, orderedEquals(plain));
    });

    test('segment streamed in multiple chunks (file written in 3 pieces)',
        () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      // > 64 KB so File.openRead() yields multiple chunks.
      final plain = Uint8List.fromList(
        List<int>.generate(70000, (i) => (i * 13 + 7) & 0xff),
      );
      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: 'PKCS7',
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );

      final dir = await Directory.systemTemp.createTemp('hls_dec_');
      try {
        final file = File('${dir.path}/seg.ts');
        // Write in block-unaligned pieces to stress the pending logic.
        final raf = await file.open(mode: FileMode.write);
        try {
          await raf.writeFrom(Uint8List.sublistView(cipher, 0, 12345));
          await raf.writeFrom(
            Uint8List.sublistView(cipher, 12345, 12345 + 23456),
          );
          await raf.writeFrom(Uint8List.sublistView(cipher, 12345 + 23456));
        } finally {
          await raf.close();
        }

        await HlsDecryptor.decryptInPlaceSync(file, key, iv);
        final out = await file.readAsBytes();
        expect(out, orderedEquals(plain));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('unpadded (raw CBC) segment falls back to no-padding', () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      // Last byte 0x5D (93) > 16, so PKCS7 validation must fail and the raw
      // no-padding fallback returns the full decrypted run.
      final plain = Uint8List.fromList(
        List<int>.generate(48, (i) => (i * 3) & 0xff),
      );
      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: null,
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );
      expect(cipher.length, 48, reason: 'no padding added');

      final out = await decryptRoundTrip(key, iv, cipher);
      expect(out, orderedEquals(plain));
    });

    test('decryptInPlace (background-isolate path) round-trips', () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      final plain = Uint8List.fromList(
        List<int>.generate(32, (i) => (i * 7) & 0xff),
      );
      final cipher = Uint8List.fromList(
        encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key(key),
            mode: encrypt.AESMode.cbc,
            padding: 'PKCS7',
          ),
        ).encryptBytes(plain, iv: encrypt.IV(iv)).bytes,
      );

      final out = await decryptRoundTrip(key, iv, cipher, useIsolate: true);
      expect(out, orderedEquals(plain));
    });

    test('non-multiple-of-16 ciphertext throws StateError and cleans up temp',
        () async {
      final key =
          Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => 16 - i));
      final bad = Uint8List.fromList(
        List<int>.generate(20, (i) => (i + 1) & 0xff), // 20 bytes
      );

      final dir = await Directory.systemTemp.createTemp('hls_dec_');
      try {
        final file = File('${dir.path}/seg.ts');
        await file.writeAsBytes(bad, flush: true);

        await expectLater(
          HlsDecryptor.decryptInPlaceSync(file, key, iv),
          throwsA(isA<StateError>()),
        );
        // Original file untouched; no .dec temp leftover.
        expect(await file.exists(), isTrue);
        expect(File('${file.path}.dec').existsSync(), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
