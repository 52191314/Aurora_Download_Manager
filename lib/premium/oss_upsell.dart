import 'package:flutter/material.dart';

import 'pro_entitlement.dart';
import 'pro_features.dart';

/// App-wide entitlement handle for tier reads, set at startup in main.dart.
///
/// OSS edition: the Play billing handle (`proUpsellBilling`) is gone with
/// `PlayBillingService` — this is the only entitlement reference.
ProEntitlement? proUpsellEntitlement;

/// OSS edition upsell.
///
/// Release builds default the effective tier to Ultra (see
/// `ProEntitlement.freshInstallTier`), so a feature gate can only fire in
/// debug/profile free-tier testing. There is no purchase path, so instead of
/// a billing sheet we show an honest one-liner.
Future<void> showProUpsell(
  BuildContext context,
  ProFeature feature, {
  EntitlementTier? userTier,
}) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${ProFeatures.displayName(feature)} is unlocked in this '
        'open-source build.',
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}
