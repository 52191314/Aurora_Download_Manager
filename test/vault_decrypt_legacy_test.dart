import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Standalone test verifying PKCS#7 unpadding logic for legacy CBC blobs.
Uint8List? unpadPkcs7(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  final pad = bytes.last;
  if (pad < 1 || pad > 16 || pad > bytes.length) return null;
  for (var i = bytes.length - pad; i < bytes.length; i++) {
    if (bytes[i] != pad) return null;
  }
  return Uint8List.sublistView(bytes, 0, bytes.length - pad);
}

void main() {
  group('Legacy CBC PKCS#7 Unpadding Tests', () {
    final key = enc.Key.fromUtf8('12345678901234567890123456789012'); // 32-byte AES-256 key
    final iv = enc.IV.fromUtf8('1234567890123456'); // 16-byte IV

    test('CBC mode encrypts with PKCS#7 padding and unpads correctly', () {
      final originalText = 'Hello Aurora Vault CBC Test Payload';
      final originalBytes = Uint8List.fromList(originalText.codeUnits);

      // Encrypt with default PKCS7 padding
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encryptBytes(originalBytes, iv: iv);

      // Decrypt with raw blocks (padding: null)
      final rawDecrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: null));
      final rawDecrypted = Uint8List.fromList(rawDecrypter.decryptBytes(encrypted, iv: iv));

      // Raw decrypted block length is padded to 16-byte boundary (48 bytes for 35 bytes payload)
      expect(rawDecrypted.length, greaterThan(originalBytes.length));
      expect(rawDecrypted.length % 16, equals(0));

      // Unpad PKCS#7
      final unpadded = unpadPkcs7(rawDecrypted);
      expect(unpadded, isNotNull);
      expect(String.fromCharCodes(unpadded!), equals(originalText));
    });

    test('Rejects corrupted PKCS#7 padding', () {
      final badPadded = Uint8List.fromList([1, 2, 3, 4, 5, 5, 5, 5]);
      final result = unpadPkcs7(badPadded);
      expect(result, isNull);
    });

    test('Rejects zero or out-of-range padding values', () {
      final zeroPad = Uint8List.fromList([1, 2, 3, 0]);
      final overflowPad = Uint8List.fromList([1, 2, 3, 20]);
      expect(unpadPkcs7(zeroPad), isNull);
      expect(unpadPkcs7(overflowPad), isNull);
    });
  });
}
