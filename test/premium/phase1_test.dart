import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/free_cap_store.dart';
import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';
import 'package:aurora_downloader/premium/turbo_policy.dart';

void main() {
  group('TurboPolicy', () {
    test('free has no turbo; pro+ does', () {
      expect(TurboPolicy.isActive(EntitlementTier.free), isFalse);
      expect(TurboPolicy.isActive(EntitlementTier.pro), isTrue);
      expect(TurboPolicy.isActive(EntitlementTier.ultra), isTrue);
    });

    test('free uses user setting; pro+ uses tier max', () {
      const userSetting = 2;
      expect(
        TurboPolicy.resolveConcurrent(userSetting, EntitlementTier.free),
        userSetting,
      );
      expect(
        TurboPolicy.resolveConcurrent(userSetting, EntitlementTier.pro),
        ProFeatures.maxConcurrentFor(EntitlementTier.pro),
      );
      expect(
        TurboPolicy.resolveChunks(userSetting, EntitlementTier.ultra),
        ProFeatures.chunksFor(EntitlementTier.ultra),
      );
    });
  });

  group('FreeCapStore', () {
    test('free batch cap constant is 5', () {
      expect(ProFeatures.freeBatchCaptureItems, 5);
    });

    test('sendToPc daily limit constant is 20', () {
      expect(ProFeatures.freeSendToPcPerDay, 20);
    });

    test('allows matrix for Phase 1 features', () {
      for (final f in [
        ProFeature.batchCapture,
        ProFeature.turboEngine,
        ProFeature.deadLinkRevival,
        ProFeature.sendToPc,
      ]) {
        expect(ProFeatures.allows(f, EntitlementTier.free), isFalse);
        expect(ProFeatures.allows(f, EntitlementTier.pro), isTrue);
        expect(ProFeatures.allows(f, EntitlementTier.ultra), isTrue);
      }
    });
  });

  group('EntitlementTier', () {
    test('isAtLeast ordering', () {
      expect(EntitlementTier.free.isAtLeastPro, isFalse);
      expect(EntitlementTier.pro.isAtLeastPro, isTrue);
      expect(EntitlementTier.ultra.isAtLeastPro, isTrue);
      expect(EntitlementTier.pro.isAtLeast(EntitlementTier.ultra), isFalse);
      expect(EntitlementTier.ultra.isAtLeast(EntitlementTier.pro), isTrue);
    });
  });
}
