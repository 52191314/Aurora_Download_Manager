/// Compile-time distribution channel for Aurora builds.
///
/// Pass at build time:
/// ```bash
/// flutter build apk --dart-define=AURORA_BUILD_CHANNEL=play
/// flutter build apk --dart-define=AURORA_BUILD_CHANNEL=github
/// ```
///
/// Default is `github` so open-source / sideload APKs never ship a billing
/// client path by accident.
///
/// OSS edition note: the effective entitlement tier is always **free** —
/// Pro/Ultra features are locked. There is no billing path in this edition.
class BuildChannel {
  BuildChannel._();

  static const String raw = String.fromEnvironment(
    'AURORA_BUILD_CHANNEL',
    defaultValue: 'github',
  );

  /// Google Play Store distributed build (Play Billing required for Pro).
  static bool get isPlay => raw.toLowerCase() == 'play';

  /// F-Droid compliant build (no prebuilt binaries, ExoPlayer fallback).
  static bool get isFdroid => raw.toLowerCase() == 'fdroid';

  /// GitHub / sideload fat build (all prebuilts bundled).
  static bool get isGithub => !isPlay && !isFdroid;

  static String get label => isFdroid ? 'fdroid' : (isPlay ? 'play' : 'github');
}
