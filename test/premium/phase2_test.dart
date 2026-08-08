import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/premium/pro_entitlement.dart';
import 'package:aurora_downloader/premium/pro_features.dart';

void main() {
  group('SeriesGrab free cap', () {
    test('freeSeriesGrabAllows within cap', () {
      expect(ProFeatures.freeSeriesGrabAllows(3), isTrue);
      expect(ProFeatures.freeSeriesGrabAllows(5), isTrue);
      expect(ProFeatures.freeSeriesGrabAllows(6), isFalse);
    });

    test('freeSeriesGrabEnqueueCount caps at 5', () {
      expect(ProFeatures.freeSeriesGrabEnqueueCount(3), 3);
      expect(ProFeatures.freeSeriesGrabEnqueueCount(5), 5);
      expect(ProFeatures.freeSeriesGrabEnqueueCount(10), 5);
      expect(ProFeatures.freeSeriesGrabEnqueueCount(100), 5);
    });

    test('constant matches doc value', () {
      expect(ProFeatures.freeSeriesGrabEpisodes, 5);
    });
  });

  group('Batch free cap helpers', () {
    test('freeBatchAllows within cap', () {
      expect(ProFeatures.freeBatchAllows(3), isTrue);
      expect(ProFeatures.freeBatchAllows(5), isTrue);
      expect(ProFeatures.freeBatchAllows(6), isFalse);
    });

    test('freeBatchEnqueueCount caps at 5', () {
      expect(ProFeatures.freeBatchEnqueueCount(3), 3);
      expect(ProFeatures.freeBatchEnqueueCount(5), 5);
      expect(ProFeatures.freeBatchEnqueueCount(10), 5);
    });
  });

  group('noNag feature gate', () {
    test('noNag requires pro', () {
      expect(ProFeatures.allows(ProFeature.noNag, EntitlementTier.free), isFalse);
      expect(ProFeatures.allows(ProFeature.noNag, EntitlementTier.pro), isTrue);
      expect(ProFeatures.allows(ProFeature.noNag, EntitlementTier.ultra), isTrue);
    });

    test('Pro+ never sees Pro-tier upsell (noNag rule)', () {
      // Verify that every Phase 1-2 Pro-tier feature is allowed for pro/ultra
      // — this is the positive side of the noNag rule (Pro users can use Pro features).
      for (final f in ProFeature.values) {
        final min = ProFeatures.minimumTier[f]!;
        if (min == EntitlementTier.pro) {
          expect(ProFeatures.allows(f, EntitlementTier.pro), isTrue);
          expect(ProFeatures.allows(f, EntitlementTier.ultra), isTrue);
        }
      }
    });
  });

  group('clipboardCatch feature gate', () {
    test('clipboardCatch requires pro', () {
      expect(
        ProFeatures.allows(ProFeature.clipboardCatch, EntitlementTier.free),
        isFalse,
      );
      expect(
        ProFeatures.allows(ProFeature.clipboardCatch, EntitlementTier.pro),
        isTrue,
      );
      expect(
        ProFeatures.allows(ProFeature.clipboardCatch, EntitlementTier.ultra),
        isTrue,
      );
    });

    test('displayName is correct', () {
      expect(
        ProFeatures.displayName(ProFeature.clipboardCatch),
        'Clipboard URL catch',
      );
    });
  });

  group('All Phase 2 minimum tier integrity', () {
    test('seriesGrab, audioExtract, privateVault, clipboardCatch, noNag are pro', () {
      for (final f in [
        ProFeature.seriesGrab,
        ProFeature.audioExtract,
        ProFeature.privateVault,
        ProFeature.clipboardCatch,
        ProFeature.richNotifications,
        ProFeature.webdavBackup,
        ProFeature.duplicateFinder,
        ProFeature.themePack,
        ProFeature.noNag,
      ]) {
        expect(ProFeatures.minimumTier[f], EntitlementTier.pro);
        expect(ProFeatures.allows(f, EntitlementTier.free), isFalse);
        expect(ProFeatures.allows(f, EntitlementTier.pro), isTrue);
        expect(ProFeatures.allows(f, EntitlementTier.ultra), isTrue);
      }
    });
  });
}
