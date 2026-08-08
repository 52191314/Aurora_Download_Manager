import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/free_cap_store.dart';
import 'package:aurora_downloader/premium/free_taste.dart';
import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';

void main() {
  setUp(() {
    FreeCapStore.debugReset();
  });

  group('FreeTasteMode per feature', () {
    test('batchCapture → softActionCap', () {
      expect(FreeTaste.mode(ProFeature.batchCapture),
          FreeTasteMode.softActionCap);
    });

    test('seriesGrab → softActionCap', () {
      expect(
          FreeTaste.mode(ProFeature.seriesGrab), FreeTasteMode.softActionCap);
    });

    test('audioExtract → dailyQuota', () {
      expect(
          FreeTaste.mode(ProFeature.audioExtract), FreeTasteMode.dailyQuota);
    });

    test('sendToPc → dailyQuota', () {
      expect(FreeTaste.mode(ProFeature.sendToPc), FreeTasteMode.dailyQuota);
    });

    test('privateVault → inventoryCap', () {
      expect(
          FreeTaste.mode(ProFeature.privateVault), FreeTasteMode.inventoryCap);
    });

    test('pure Pro features → null (hard lock)', () {
      expect(FreeTaste.mode(ProFeature.proxy), isNull);
      expect(FreeTaste.mode(ProFeature.wifiOnly), isNull);
      expect(FreeTaste.mode(ProFeature.deadLinkRevival), isNull);
    });

    test('Ultra features → null (hard lock)', () {
      expect(FreeTaste.mode(ProFeature.serverGradeEngine), isNull);
      expect(FreeTaste.mode(ProFeature.ffmpegSuite), isNull);
    });
  });

  group('FreeTaste.evaluate — Pro+ unlimited', () {
    for (final tier in [EntitlementTier.pro, EntitlementTier.ultra]) {
      test('$tier is unlimited for all free-taste features', () async {
        for (final feature in ProFeature.values) {
          final mode = FreeTaste.mode(feature);
          if (mode == null) continue; // skip hard-lock features
          final decision = await FreeTaste.evaluate(
            feature: feature,
            tier: tier,
          );
          expect(decision.allowed, isTrue,
              reason: '$feature should allow $tier');
          expect(decision.reason, 'unlimited');
        }
      });
    }
  });

  group('FreeTaste.evaluate — softActionCap (free)', () {
    test('batchCapture: first-5 allowed, rest denied', () async {
      // Select 3 items → 3 allowed (within 5).
      final d1 = await FreeTaste.evaluate(
        feature: ProFeature.batchCapture,
        tier: EntitlementTier.free,
        actionSize: 3,
      );
      expect(d1.allowed, isTrue);
      expect(d1.allowedCount, 3);

      // Select 12 items → only 5 allowed (soft cap).
      final d2 = await FreeTaste.evaluate(
        feature: ProFeature.batchCapture,
        tier: EntitlementTier.free,
        actionSize: 12,
      );
      expect(d2.allowed, isTrue);
      expect(d2.allowedCount, 5);
    });

    test('seriesGrab: first-5 episodes', () async {
      final d = await FreeTaste.evaluate(
        feature: ProFeature.seriesGrab,
        tier: EntitlementTier.free,
        actionSize: 12,
      );
      expect(d.allowed, isTrue);
      expect(d.allowedCount, 5);
    });

    test('0 actionSize → denied', () async {
      final d = await FreeTaste.evaluate(
        feature: ProFeature.batchCapture,
        tier: EntitlementTier.free,
        actionSize: 0,
      );
      expect(d.allowed, isFalse);
    });
  });

  group('FreeTaste.evaluate — inventoryCap (free)', () {
    test('privateVault: 24 items ok, 25 denied', () async {
      final d1 = await FreeTaste.evaluate(
        feature: ProFeature.privateVault,
        tier: EntitlementTier.free,
        inventoryCount: 24,
      );
      expect(d1.allowed, isTrue);

      final d2 = await FreeTaste.evaluate(
        feature: ProFeature.privateVault,
        tier: EntitlementTier.free,
        inventoryCount: 25,
      );
      expect(d2.allowed, isFalse);

      final d3 = await FreeTaste.evaluate(
        feature: ProFeature.privateVault,
        tier: EntitlementTier.free,
        inventoryCount: 999,
      );
      expect(d3.allowed, isFalse);
    });
  });

  group('FreeTaste.evaluate — hardLock features (free)', () {
    test('proxy denied for free', () async {
      final d = await FreeTaste.evaluate(
        feature: ProFeature.proxy,
        tier: EntitlementTier.free,
      );
      expect(d.allowed, isFalse);
      expect(d.reason, 'denied');
    });
  });

  group('FreeTaste.evaluate — dailyQuota peek vs consume', () {
    test('sendToPc free peek allows multi-unit within daily limit', () async {
      final peek = await FreeTaste.evaluate(
        feature: ProFeature.sendToPc,
        tier: EntitlementTier.free,
        n: 3,
        consume: false,
      );
      expect(peek.allowed, isTrue);
      expect(peek.reason, 'taste');
      // Peek must not spend quota.
      final again = await FreeTaste.evaluate(
        feature: ProFeature.sendToPc,
        tier: EntitlementTier.free,
        n: 20,
        consume: false,
      );
      expect(again.allowed, isTrue);
    });

    test('sendToPc free consume then deny over limit', () async {
      final ok = await FreeTaste.evaluate(
        feature: ProFeature.sendToPc,
        tier: EntitlementTier.free,
        n: 20,
        consume: true,
      );
      expect(ok.allowed, isTrue);
      final denied = await FreeTaste.evaluate(
        feature: ProFeature.sendToPc,
        tier: EntitlementTier.free,
        n: 1,
        consume: true,
      );
      expect(denied.allowed, isFalse);
    });

    test('pro sendToPc ignores n and is unlimited', () async {
      final d = await FreeTaste.evaluate(
        feature: ProFeature.sendToPc,
        tier: EntitlementTier.pro,
        n: 99,
        consume: true,
      );
      expect(d.allowed, isTrue);
      expect(d.reason, 'unlimited');
    });
  });

  group('FreeTasteDecision constructors', () {
    test('allowedUnlimited singleton', () {
      const d = FreeTasteDecision.allowedUnlimited;
      expect(d.allowed, isTrue);
      expect(d.allowedCount, isNull);
      expect(d.reason, 'unlimited');
    });

    test('denied singleton', () {
      const d = FreeTasteDecision.denied;
      expect(d.allowed, isFalse);
      expect(d.allowedCount, isNull);
      expect(d.reason, 'denied');
    });
  });
}
