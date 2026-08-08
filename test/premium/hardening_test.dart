import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/vault_service.dart';
import 'package:aurora_downloader/premium/webdav_backup_service.dart';

void main() {
  group('VaultService.sanitizeVaultName', () {
    test('accepts generated names', () {
      expect(VaultService.sanitizeVaultName('1710000000.vault'), isNotNull);
    });

    test('rejects path traversal', () {
      expect(VaultService.sanitizeVaultName('../secret'), isNull);
      expect(VaultService.sanitizeVaultName('a/b.vault'), isNull);
      expect(VaultService.sanitizeVaultName(r'..\x'), isNull);
    });

    test('rejects empty / dots', () {
      expect(VaultService.sanitizeVaultName(''), isNull);
      expect(VaultService.sanitizeVaultName('.'), isNull);
      expect(VaultService.sanitizeVaultName('..'), isNull);
    });
  });

  group('validateWebdavUrl', () {
    test('https always ok', () {
      expect(validateWebdavUrl('https://backup.example.com/dav'), isNull);
    });

    test('http private LAN ok', () {
      expect(validateWebdavUrl('http://192.168.1.10/dav'), isNull);
      expect(validateWebdavUrl('http://10.0.0.5/webdav'), isNull);
      expect(validateWebdavUrl('http://172.16.0.1/'), isNull);
      expect(validateWebdavUrl('http://127.0.0.1:8080/'), isNull);
    });

    test('http public host rejected', () {
      expect(validateWebdavUrl('http://example.com/dav'), isNotNull);
      expect(validateWebdavUrl('http://8.8.8.8/dav'), isNotNull);
    });

    test('invalid scheme rejected', () {
      expect(validateWebdavUrl('ftp://nas.local/'), isNotNull);
      expect(validateWebdavUrl('not a url'), isNotNull);
    });
  });

  group('sanitizeBackupRemoteName', () {
    test('accepts aurora_backup_*', () {
      expect(
        sanitizeBackupRemoteName('aurora_backup_2026-07-20T12-00-00.zip'),
        isNotNull,
      );
    });

    test('rejects path tricks', () {
      expect(sanitizeBackupRemoteName('../etc/passwd'), isNull);
      expect(sanitizeBackupRemoteName('aurora_backup_/../../x'), isNull);
      expect(sanitizeBackupRemoteName('other_file.json'), isNull);
    });
  });
}
