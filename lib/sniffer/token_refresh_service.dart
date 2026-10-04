import 'dart:async';
import 'dart:io';

import '../downloader/models.dart';
import 'headless_resniffer.dart';
import 'resniff_result.dart';
import '../premium/pro_features.dart';

// ignore: implementation_imports
import 'package:aurora_downloader/premium/pro_upsell_sheet.dart';

/// Centralised dead-link / token-expiry revival (P4).
///
/// Extracts the headless refresh logic previously inlined in
/// `sniffer_screen._reloadForFreshUrl` so every enqueue + queue-restore path
/// can rebind to a single implementation. Unlike the old code, the path
/// matcher uses the **media URL** ([DownloadTask.url]) rather than the
/// visible tab's current address — so revival still works when the user has
/// navigated away from the source page.
///
/// Auto revival is **gated** by [ProFeature.deadLinkRevival]: callers must
/// check the entitlement before invoking [refresh] automatically. Manual
/// refresh (user-initiated) always works and is never gated.
class TokenRefreshService {
  static ResniffResult? debugMockResult;
  TokenRefreshService._();

  /// Max automatic headless tries per task per process. Beyond this we stop
  /// to avoid burning battery on a link that will not revive.
  static const int maxAutoTries = 2;

  static final Map<String, int> _autoTried = {};

  /// Whether [task] has exhausted its automatic retry budget.
  static bool autoBudgetExhausted(DownloadTask task) =>
      (_autoTried[task.id] ?? 0) >= maxAutoTries;

  static void _recordAutoTry(DownloadTask task) {
    _autoTried[task.id] = (_autoTried[task.id] ?? 0) + 1;
  }

  /// Refreshes the playlist/manifest URL for [task] using a headless WebView.
  ///
  /// Returns a strongly-typed [ResniffResult]. Never throws.
  static Future<ResniffResult> refresh(DownloadTask task) async {
    if (debugMockResult != null) {
      await Future.delayed(const Duration(seconds: 1));
      return debugMockResult!;
    }
    final sourcePageUrl = task.sourcePageUrl;
    if (sourcePageUrl == null || !sourcePageUrl.startsWith('http')) {
      return const ResniffSourceUnavailable(
        error: 'Missing source page URL',
      );
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ResniffSourceUnavailable(
        error: 'Headless resniff is only supported on mobile platforms',
      );
    }
    try {
      final resniffer = HeadlessPageResniffer();
      final result = await resniffer.resniff(
        sourcePageUrl,
        originalMediaUrl: task.url,
        headers: task.headers,
      );
      return result;
    } catch (e) {
      return ResniffSourceUnavailable(
        error: 'Headless resniff failed: $e',
      );
    }
  }

  /// Automatic revival entry point used by the download engine on token
  /// expiry. Returns a [ResniffResult] when revival is evaluated.
  ///
  /// [allowed] should be `ProFeatures.allows(ProFeature.deadLinkRevival, tier)`.
  /// When false (free tier), this returns [ResniffSourceUnavailable] with
  /// [kAutoRefreshLockedReason] and marks [task.errorMessage].
  /// Manual refresh paths must NOT call this — they call [refresh] directly.
  static Future<ResniffResult> autoRefresh(
    DownloadTask task, {
    required bool allowed,
  }) async {
    if (!allowed) {
      task.errorMessage = kAutoRefreshLockedReason;
      return const ResniffSourceUnavailable(error: kAutoRefreshLockedReason);
    }
    if (autoBudgetExhausted(task)) {
      return const ResniffSourceUnavailable(
        error: 'Automatic link revival retry budget exhausted',
      );
    }
    _recordAutoTry(task);
    return refresh(task);
  }

  /// Resets the auto-retry counter for [task] (useful in tests or when retrying).
  static void resetAutoTry(DownloadTask task) {
    _autoTried.remove(task.id);
  }

  /// Clears all auto-retry tracking counters across tasks.
  static void clearBudgets() {
    _autoTried.clear();
  }

  /// Failure reason set on a task when automatic revival is blocked by the
  /// free-tier gate. Surfaced in the queue UI so the user knows why.
  static const String kAutoRefreshLockedReason =
      'Automatic link repair is an Aurora Pro feature. Use manual Refresh '
      '(free for everyone), or unlock Pro for automatic repair.';

  /// Wraps a base [onTokenExpired] closure with the [ProFeature.deadLinkRevival]
  /// entitlement gate.
  ///
  /// The gate is evaluated at **invocation** time (not creation) so a user
  /// who upgrades to Pro mid-session immediately gains auto revival. When the
  /// gate is closed (free tier), [task.errorMessage] is set to
  /// [kAutoRefreshLockedReason] and [ResniffSourceUnavailable] is returned.
  ///
  /// Manual refresh paths must NOT use this wrapper; they call [refresh]
  /// directly and remain free for everyone.
  static Future<ResniffResult> Function({bool forceReload}) gatedClosure(
    DownloadTask task,
    Future<ResniffResult> Function({bool forceReload}) base,
  ) {
    return ({bool forceReload = false}) async {
      final ent = proUpsellEntitlement;
      final allowed = ent != null &&
          ProFeatures.allows(ProFeature.deadLinkRevival, ent.tier);
      if (!allowed) {
        task.errorMessage = kAutoRefreshLockedReason;
        return const ResniffSourceUnavailable(error: kAutoRefreshLockedReason);
      }
      return base(forceReload: forceReload);
    };
  }
}
