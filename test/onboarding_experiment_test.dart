import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:aurora_downloader/settings/onboarding_experiment.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('onboarding_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OnboardingExperiment Tests', () {
    test('defaults compileTimeFlag to true (product first-launch tour)', () {
      expect(OnboardingExperiment.compileTimeFlag, isTrue);
    });

    test('tracks completion state in config file', () async {
      expect(await OnboardingExperiment.hasCompletedOnboarding(), isFalse);

      await OnboardingExperiment.markCompleted();
      expect(await OnboardingExperiment.hasCompletedOnboarding(), isTrue);

      await OnboardingExperiment.resetOnboarding();
      expect(await OnboardingExperiment.hasCompletedOnboarding(), isFalse);
    });

    test('shouldAutoShowTour is true until completed', () async {
      expect(await OnboardingExperiment.shouldAutoShowTour(), isTrue);
      await OnboardingExperiment.markCompleted();
      expect(await OnboardingExperiment.shouldAutoShowTour(), isFalse);
      await OnboardingExperiment.resetOnboarding();
      expect(await OnboardingExperiment.shouldAutoShowTour(), isTrue);
    });

    test('supports setting local experiment overrides', () async {
      expect(await OnboardingExperiment.getExperimentOverride(), isNull);
      // Product default: enabled when no override.
      expect(await OnboardingExperiment.isEnabled(), isTrue);

      await OnboardingExperiment.setExperimentOverride(true);
      expect(await OnboardingExperiment.getExperimentOverride(), isTrue);
      expect(await OnboardingExperiment.isEnabled(), isTrue);

      await OnboardingExperiment.setExperimentOverride(false);
      expect(await OnboardingExperiment.getExperimentOverride(), isFalse);
      expect(await OnboardingExperiment.isEnabled(), isFalse);
      expect(await OnboardingExperiment.shouldAutoShowTour(), isFalse);

      // "Show app tour" path: reset clears override so the tour can run again.
      await OnboardingExperiment.resetOnboarding();
      expect(await OnboardingExperiment.getExperimentOverride(), isNull);
      expect(await OnboardingExperiment.shouldAutoShowTour(), isTrue);

      await OnboardingExperiment.setExperimentOverride(null);
      expect(await OnboardingExperiment.getExperimentOverride(), isNull);
    });
  });
}
