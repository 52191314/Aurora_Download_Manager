import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_entitlement_store.dart';
import 'package:aurora_downloader/premium/pro_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tierForProductId / maxTierForOwned', () {
    test('maps product IDs to tiers', () {
      expect(tierForProductId(kAuroraProProductId), EntitlementTier.pro);
      expect(tierForProductId(kAuroraUltraProductId), EntitlementTier.ultra);
      expect(
        tierForProductId(kAuroraUltraUpgradeProductId),
        EntitlementTier.ultra,
      );
      expect(tierForProductId('unknown'), isNull);
    });

    test('maxTierForOwned derives highest tier', () {
      expect(maxTierForOwned([]), EntitlementTier.free);
      expect(maxTierForOwned({kAuroraProProductId}), EntitlementTier.pro);
      expect(
        maxTierForOwned({kAuroraUltraProductId}),
        EntitlementTier.ultra,
      );
      expect(
        maxTierForOwned({kAuroraProProductId, kAuroraUltraUpgradeProductId}),
        EntitlementTier.ultra,
      );
      expect(
        maxTierForOwned({kAuroraUltraUpgradeProductId}),
        EntitlementTier.ultra,
      );
    });
  });

  group('freshInstallTier (OSS release default)', () {
    test('github release build defaults to ultra (fully unlocked edition)',
        () {
      expect(
        ProEntitlement.freshInstallTier(
          EntitlementTier.free,
          releaseMode: true,
          githubChannel: true,
        ),
        EntitlementTier.ultra,
      );
    });

    test('play release build keeps purchase-derived tier', () {
      expect(
        ProEntitlement.freshInstallTier(
          EntitlementTier.free,
          releaseMode: true,
          githubChannel: false,
        ),
        EntitlementTier.free,
      );
      expect(
        ProEntitlement.freshInstallTier(
          EntitlementTier.ultra,
          releaseMode: true,
          githubChannel: false,
        ),
        EntitlementTier.ultra,
      );
    });

    test('debug/profile github build keeps purchase-derived tier', () {
      expect(
        ProEntitlement.freshInstallTier(
          EntitlementTier.free,
          releaseMode: false,
          githubChannel: true,
        ),
        EntitlementTier.free,
      );
    });
  });

  group('ProFeatures.allows matrix', () {
    test('every feature allows at or above its minimum tier', () {
      for (final feature in ProFeature.values) {
        final min = ProFeatures.minimumTier[feature]!;
        expect(ProFeatures.allows(feature, min), isTrue,
            reason: '$feature should allow at its min tier $min');
        // A tier below min must be denied.
        final below = EntitlementTier.values.firstWhere(
          (t) => t.index < min.index,
          orElse: () => min,
        );
        if (below != min) {
          expect(ProFeatures.allows(feature, below), isFalse,
              reason: '$feature should deny below min');
        }
      }
    });

    test('Pro features deny free, allow pro/ultra', () {
      const proFeatures = [
        ProFeature.advancedStall,
        ProFeature.autoHostGroups,
        ProFeature.customFilterListUrl,
        ProFeature.downloadRules,
        ProFeature.driveSync,
        ProFeature.extraFilterLists,
        ProFeature.higherConcurrency,
        ProFeature.higherChunks,
        ProFeature.perSiteUA,
        ProFeature.proxy,
        ProFeature.scheduledAutoBackup,
        ProFeature.scheduledDownloads,
        ProFeature.siteProfiles,
        ProFeature.trackerPack,
        ProFeature.unlimitedCosmeticRules,
        ProFeature.unlimitedTabGroups,
        ProFeature.wifiOnly,
        ProFeature.batchCapture,
        ProFeature.turboEngine,
        ProFeature.deadLinkRevival,
        ProFeature.sendToPc,
        ProFeature.seriesGrab,
        ProFeature.audioExtract,
        ProFeature.privateVault,
        ProFeature.clipboardCatch,
        ProFeature.richNotifications,
        ProFeature.webdavBackup,
        ProFeature.duplicateFinder,
        ProFeature.themePack,
        ProFeature.noNag,
      ];
      for (final f in proFeatures) {
        expect(ProFeatures.allows(f, EntitlementTier.free), isFalse);
        expect(ProFeatures.allows(f, EntitlementTier.pro), isTrue);
        expect(ProFeatures.allows(f, EntitlementTier.ultra), isTrue);
      }
    });

    test('Ultra features deny free/pro, allow ultra', () {
      const ultraFeatures = [
        ProFeature.serverGradeEngine,
        ProFeature.ffmpegSuite,
        ProFeature.ultraExtras,
        ProFeature.watcher,
        ProFeature.automationApi,
        ProFeature.vaultSync,
      ];
      for (final f in ultraFeatures) {
        expect(ProFeatures.allows(f, EntitlementTier.free), isFalse);
        expect(ProFeatures.allows(f, EntitlementTier.pro), isFalse);
        expect(ProFeatures.allows(f, EntitlementTier.ultra), isTrue);
      }
    });

    test('tierBadge reflects minimum tier', () {
      expect(ProFeatures.tierBadge(ProFeature.wifiOnly), 'PRO');
      expect(ProFeatures.tierBadge(ProFeature.ffmpegSuite), 'ULTRA');
    });

    test('allowsBool back-compat shim', () {
      expect(ProFeatures.allowsBool(ProFeature.wifiOnly, false), isFalse);
      expect(ProFeatures.allowsBool(ProFeature.wifiOnly, true), isTrue);
    });
  });

  group('ProEntitlement owned-set logic', () {
    late ProEntitlement entitlement;

    setUp(() {
      entitlement = ProEntitlement();
    });

    test('grantFromProductId UNIONs (never replaces with singleton)', () async {
      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(entitlement.tier, EntitlementTier.pro);
      expect(entitlement.ownedProductIds, {kAuroraProProductId});

      // Stream event for upgrade must union, not replace.
      await entitlement.grantFromProductId(kAuroraUltraUpgradeProductId);
      expect(entitlement.tier, EntitlementTier.ultra);
      expect(
        entitlement.ownedProductIds,
        {kAuroraProProductId, kAuroraUltraUpgradeProductId},
      );
    });

    test('applyOwnedProducts REPLACEs from full snapshot', () async {
      await entitlement.grantFromProductId(kAuroraProProductId);
      await entitlement.grantFromProductId(kAuroraUltraUpgradeProductId);
      expect(entitlement.ownedProductIds.length, 2);

      // Full BC snapshot says only ultra_unlock now owned.
      await entitlement.applyOwnedProducts(
        {kAuroraUltraProductId},
        source: EntitlementSource.play,
        reconcileSucceeded: true,
      );
      expect(entitlement.tier, EntitlementTier.ultra);
      expect(entitlement.ownedProductIds, {kAuroraUltraProductId});
    });

    test('empty BC snapshot downgrades to free', () async {
      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(entitlement.tier, EntitlementTier.pro);

      await entitlement.applyOwnedProducts(
        {},
        source: EntitlementSource.play,
        reconcileSucceeded: true,
      );
      expect(entitlement.tier, EntitlementTier.free);
      expect(entitlement.ownedProductIds, isEmpty);
      expect(entitlement.lastReconcileOk, isTrue);
      expect(entitlement.lastReconcileAt, isNotNull);
    });

    test('upgrade-only ownership → ultra (arbitrage)', () async {
      await entitlement.applyOwnedProducts(
        {kAuroraUltraUpgradeProductId},
        source: EntitlementSource.play,
        reconcileSucceeded: true,
      );
      expect(entitlement.tier, EntitlementTier.ultra);
    });

    test('recordReconcileFailure does not change tier/owned', () async {
      await entitlement.grantFromProductId(kAuroraProProductId);
      final owned = entitlement.ownedProductIds;
      await entitlement.recordReconcileFailure();
      expect(entitlement.tier, EntitlementTier.pro);
      expect(entitlement.ownedProductIds, owned);
      expect(entitlement.lastReconcileOk, isFalse);
    });

    test('revokeAll clears owned and tier', () async {
      await entitlement.grantFromProductId(kAuroraUltraProductId);
      await entitlement.revokeAll();
      expect(entitlement.tier, EntitlementTier.free);
      expect(entitlement.ownedProductIds, isEmpty);
    });

    test('debug override wins over derived tier and is never persisted', () {
      entitlement.setDebugTier(EntitlementTier.ultra);
      expect(entitlement.tier, EntitlementTier.ultra);
      expect(entitlement.source, EntitlementSource.debug);
      entitlement.setDebugTier(null);
      expect(entitlement.tier, EntitlementTier.free);
    });

    test('deprecated grantPro wrapper unions pro', () async {
      await entitlement.grantPro();
      expect(entitlement.tier, EntitlementTier.pro);
      expect(entitlement.ownedProductIds, {kAuroraProProductId});
    });
  });

  group('ProEntitlementStore v1 → v2 migration', () {
    test('v1 isPro true migrates to pro with empty owned', () {
      final data = {'isPro': true, 'source': 'play'};
      expect(ProEntitlementStore.tierFromData(data), EntitlementTier.pro);
      expect(ProEntitlementStore.ownedFromData(data), isEmpty);
    });

    test('v1 isPro false migrates to free', () {
      final data = {'isPro': false};
      expect(ProEntitlementStore.tierFromData(data), EntitlementTier.free);
    });

    test('v2 parses tier/owned/source/reconcile', () {
      final data = {
        'schemaVersion': 2,
        'tier': 'ultra',
        'source': 'play',
        'ownedProductIds': ['aurora_ultra_unlock'],
        'lastReconcileAt': '2026-07-19T12:00:00.000Z',
        'lastReconcileOk': true,
      };
      expect(ProEntitlementStore.tierFromData(data), EntitlementTier.ultra);
      expect(
        ProEntitlementStore.ownedFromData(data),
        {kAuroraUltraProductId},
      );
      expect(ProEntitlementStore.sourceFromData(data), EntitlementSource.play);
      expect(ProEntitlementStore.reconcileOkFromData(data), isTrue);
      expect(ProEntitlementStore.reconcileAtFromData(data), isNotNull);
    });

    test('unknown tier string defaults to free', () {
      final data = {'schemaVersion': 2, 'tier': 'bogus'};
      expect(ProEntitlementStore.tierFromData(data), EntitlementTier.free);
    });
  });

  group('Dual clamp order (tier caps)', () {
    test('free effective 3/8', () {
      const tier = EntitlementTier.free;
      expect(ProFeatures.maxConcurrentFor(tier), 3);
      expect(ProFeatures.chunksFor(tier), 8);
      expect(ProFeatures.hlsSegmentCapFor(tier), 4);
    });

    test('pro effective 16/32', () {
      const tier = EntitlementTier.pro;
      expect(ProFeatures.maxConcurrentFor(tier), 16);
      expect(ProFeatures.chunksFor(tier), 32);
      expect(ProFeatures.hlsSegmentCapFor(tier), 8);
    });

    test('ultra effective 64/64 with HLS 64', () {
      const tier = EntitlementTier.ultra;
      expect(ProFeatures.maxConcurrentFor(tier), 64);
      expect(ProFeatures.chunksFor(tier), 64);
      expect(ProFeatures.hlsSegmentCapFor(tier), 64);
    });

    test('default chunksPerTask 16 clamps to 8 for free', () {
      const userSetting = 16;
      final effective = userSetting
          .clamp(1, ProFeatures.chunksFor(EntitlementTier.free))
          .clamp(1, 64);
      expect(effective, 8);
    });
  });

  group('Free taste caps', () {
    test('batch soft first-5', () {
      expect(ProFeatures.freeBatchCaptureItems, 5);
    });
    test('series grab 5 per action', () {
      expect(ProFeatures.freeSeriesGrabEpisodes, 5);
    });
    test('audio extract 3/day, sendToPc 20/day, vault 25', () {
      expect(ProFeatures.freeAudioExtractPerDay, 3);
      expect(ProFeatures.freeSendToPcPerDay, 20);
      expect(ProFeatures.freeVaultItems, 25);
    });
  });

  group('Generosity bump (R-PR-06)', () {
    test('free filter list slots = 3', () {
      expect(ProFeatures.freeFilterListSlots, 3);
    });
    test('max free tab groups = 3', () {
      expect(ProFeatures.maxFreeTabGroups, 3);
    });
    test('max free cosmetic rules = 25', () {
      expect(ProFeatures.maxFreeCosmeticRules, 25);
    });
  });

  group('ProEntitlement change notification (R-PR-01 fix)', () {
    late ProEntitlement entitlement;

    setUp(() {
      entitlement = ProEntitlement();
    });

    test('grantFromProductId notifies listeners when tier changes', () async {
      int notifyCount = 0;
      entitlement.addListener(() => notifyCount++);

      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(notifyCount, 1,
          reason: 'Should notify when tier changes from free to pro');

      // Granting same product again — owned unchanged, tier unchanged,
      // source unchanged → no notify.
      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(notifyCount, 1,
          reason: 'Should NOT notify when nothing changes');

      // Granting upgrade → tier changes to ultra.
      await entitlement.grantFromProductId(kAuroraUltraUpgradeProductId);
      expect(notifyCount, 2,
          reason: 'Should notify when tier changes from pro to ultra');
    });

    test('applyOwnedProducts notifies listeners when tier changes', () async {
      int notifyCount = 0;
      entitlement.addListener(() => notifyCount++);

      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(notifyCount, 1);

      // applyOwnedProducts with same owned set + same tier → no notify.
      await entitlement.applyOwnedProducts(
        {kAuroraProProductId},
        source: EntitlementSource.play,
        reconcileSucceeded: true,
      );
      expect(notifyCount, 1,
          reason: 'Should NOT notify when owned/tier/source unchanged');

      // applyOwnedProducts with empty set → downgrade to free.
      await entitlement.applyOwnedProducts(
        {},
        source: EntitlementSource.play,
        reconcileSucceeded: true,
      );
      expect(notifyCount, 2,
          reason: 'Should notify when tier downgrades from pro to free');
    });

    test('grantFromProductId notifies when source changes', () async {
      int notifyCount = 0;
      entitlement.addListener(() => notifyCount++);

      // First grant with default play source.
      await entitlement.grantFromProductId(kAuroraProProductId);
      expect(notifyCount, 1);

      // Second grant with different source (legacy) — source changes.
      await entitlement.grantFromProductId(
        kAuroraUltraProductId,
        source: EntitlementSource.legacy,
      );
      expect(notifyCount, 2,
          reason: 'Should notify when source or tier changes');
    });
  });
}
