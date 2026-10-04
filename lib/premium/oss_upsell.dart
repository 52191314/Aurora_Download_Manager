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
/// Features are limited to the free tier in this edition. There is no
/// purchase path; the snackbar informs the user that the feature requires
/// Aurora Pro or Ultra from the Play Store edition.
Future<void> showProUpsell(
  BuildContext context,
  ProFeature feature, {
  EntitlementTier? userTier,
}) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${ProFeatures.displayName(feature)} requires Aurora '
        '${ProFeatures.tierBadge(feature)}.',
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}
