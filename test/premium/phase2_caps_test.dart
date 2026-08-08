import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';
import 'package:aurora_downloader/premium/free_cap_store.dart';
import 'package:aurora_downloader/premium/phase2_caps.dart';

void main() {
  group('Phase2Caps audioExtract', () {
    test('Pro+ unlimited bypasses store', () async {
      // Pro+ returns true without touching FreeCapStore.
      expect(await Phase2Caps.tryConsumeAudioExtract(EntitlementTier.pro), isTrue);
      expect(await Phase2Caps.tryConsumeAudioExtract(EntitlementTier.ultra), isTrue);
    });

    test('audioExtract gate matrix', () {
      expect(
        ProFeatures.allows(ProFeature.audioExtract, EntitlementTier.free),
        isFalse,
      );
      expect(
        ProFeatures.allows(ProFeature.audioExtract, EntitlementTier.pro),
        isTrue,
      );
      expect(
        ProFeatures.allows(ProFeature.audioExtract, EntitlementTier.ultra),
        isTrue,
      );
    });

    test('free daily cap constant matches plan', () {
      expect(ProFeatures.freeAudioExtractPerDay, 3);
    });
  });

  group('Phase2Caps vault', () {
    test('vaultInventoryOk free cap at 25', () {
      // 24 items → ok, 25 items → still ok (< not <=), 26 → over.
      expect(Phase2Caps.vaultInventoryOk(24, EntitlementTier.free), isTrue);
      expect(Phase2Caps.vaultInventoryOk(25, EntitlementTier.free), isFalse);
      expect(Phase2Caps.vaultInventoryOk(26, EntitlementTier.free), isFalse);
    });

    test('vaultInventoryOk Pro+ unlimited', () {
      expect(Phase2Caps.vaultInventoryOk(999, EntitlementTier.pro), isTrue);
      expect(Phase2Caps.vaultInventoryOk(999, EntitlementTier.ultra), isTrue);
    });

    test('maxFreeVaultItems constant', () {
      expect(Phase2Caps.maxFreeVaultItems, 25);
      expect(Phase2Caps.maxFreeVaultItems, ProFeatures.freeVaultItems);
    });

    test('countVaultFiles returns 0 for non-existent dir', () {
      final missing = Directory('/nonexistent_vault_test_dir');
      expect(Phase2Caps.countVaultFiles(missing), 0);
    });
  });

  group('Phase 2 gate matrix completeness', () {
    // Ensure every Phase 2 feature has correct min tier.
    for (final entry in [
      (ProFeature.seriesGrab, 'seriesGrab'),
      (ProFeature.audioExtract, 'audioExtract'),
      (ProFeature.privateVault, 'privateVault'),
      (ProFeature.clipboardCatch, 'clipboardCatch'),
      (ProFeature.richNotifications, 'richNotifications'),
      (ProFeature.webdavBackup, 'webdavBackup'),
      (ProFeature.duplicateFinder, 'duplicateFinder'),
      (ProFeature.themePack, 'themePack'),
      (ProFeature.noNag, 'noNag'),
    ]) {
      test('${entry.$2} is pro minimum', () {
        expect(ProFeatures.minimumTier[entry.$1], EntitlementTier.pro);
        expect(ProFeatures.allows(entry.$1, EntitlementTier.free), isFalse);
        expect(ProFeatures.allows(entry.$1, EntitlementTier.pro), isTrue);
        expect(ProFeatures.allows(entry.$1, EntitlementTier.ultra), isTrue);
      });
    }
  });
}
