import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/free_cap_store.dart';
import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';

void main() {
  group('Concurrency clamps', () {
    test('user max-concurrent setting is authoritative (turbo removed)', () {
      const tier = EntitlementTier.ultra;
      // Mirrors main.dart: userSetting -> tierMax clamp, no turbo override.
      int effectiveConcurrent(int userSetting) =>
          userSetting.clamp(1, ProFeatures.maxConcurrentFor(tier));
      expect(effectiveConcurrent(4), 4,
          reason: 'regression: user-set 4 silently became 64 under turbo');
      expect(effectiveConcurrent(0), 1);
      expect(effectiveConcurrent(999), ProFeatures.maxConcurrentFor(tier));

      int effectiveChunks(int userSetting) =>
          userSetting.clamp(1, ProFeatures.chunksFor(tier));
      expect(effectiveChunks(16), 16,
          reason: 'regression: user-set 16 chunks silently became 64');
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
