import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:aurora_downloader/l10n/app_localizations.dart';
import 'package:aurora_downloader/sniffer/external_app_preference_store.dart';
import 'package:aurora_downloader/theme/aurora_palette.dart';
import 'package:aurora_downloader/theme/aurora_tokens.dart';
import 'package:aurora_downloader/ui/pages/settings_page.dart';

/// The store persists through `getApplicationDocumentsDirectory()`. Without this
/// the write hangs on an unmocked platform channel and the page never gets its
/// post-save `setState`, so the UI silently stops tracking the store.
/// Mirrors the pattern in `test/onboarding_experiment_test.dart`.
class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  MockPathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

/// Wraps the page in the minimum tree it needs: a MaterialApp for routing and
/// ScaffoldMessenger, plus the AuroraPalette that `context.ac` asserts on.
/// Localization delegates mirror the real app so pages using
/// AppLocalizations.of(context) resolve.
Widget _host() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuroraPalette(
        colors: AColors.dark(),
        isLight: false,
        child: const ExternalAppsPrefsPage(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('external_apps_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    ExternalAppPreferenceStore.resetForTesting();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {
      // Windows can still hold the store's file handle when a background write
      // is in flight; the OS reclaims its own temp dir regardless.
    }
  });

  testWidgets('empty state renders when no choices are saved', (tester) async {
    ExternalAppPreferenceStore.resetForTesting({});

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Every app asks first'), findsOneWidget);
    // Reset action is hidden when there is nothing to reset.
    expect(find.byIcon(Icons.restart_alt_rounded), findsNothing);
  });

  testWidgets('saved decisions are listed with friendly labels', (tester) async {
    ExternalAppPreferenceStore.resetForTesting({
      'package:org.telegram.messenger': ExternalAppDecision.alwaysAllow,
      'scheme:market': ExternalAppDecision.alwaysDeny,
    });

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Play Store'), findsOneWidget);
    expect(find.text('Always open'), findsOneWidget);
    expect(find.text('Never open'), findsOneWidget);
    // Raw keys shown as secondary text.
    expect(find.text('package:org.telegram.messenger'), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
    expect(find.text('Every app asks first'), findsNothing);
  });

  testWidgets('entries are sorted by display label', (tester) async {
    ExternalAppPreferenceStore.resetForTesting({
      'scheme:whatsapp': ExternalAppDecision.alwaysAllow,
      'scheme:discord': ExternalAppDecision.alwaysAllow,
      'scheme:market': ExternalAppDecision.alwaysDeny,
    });

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((s) => s == 'Discord' || s == 'Play Store' || s == 'WhatsApp')
        .toList();
    expect(titles, ['Discord', 'Play Store', 'WhatsApp']);
  });

  testWidgets('changing a decision to Ask removes it from the list',
      (tester) async {
    ExternalAppPreferenceStore.resetForTesting({
      'scheme:market': ExternalAppDecision.alwaysDeny,
    });

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Play Store'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask every time').last);
    await tester.pumpAndSettle();

    expect(
      await ExternalAppPreferenceStore.instance.decisionFor('scheme:market'),
      ExternalAppDecision.ask,
    );
    expect(find.text('Every app asks first'), findsOneWidget);
  });

  testWidgets('reset all clears every saved choice after confirmation',
      (tester) async {
    ExternalAppPreferenceStore.resetForTesting({
      'scheme:market': ExternalAppDecision.alwaysDeny,
      'scheme:tg': ExternalAppDecision.alwaysAllow,
    });

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reset all external app choices?'), findsOneWidget);

    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();

    expect(
      await ExternalAppPreferenceStore.instance.allDecisions(),
      isEmpty,
    );
    expect(find.text('Every app asks first'), findsOneWidget);
  });

  testWidgets('cancelling reset keeps the saved choices', (tester) async {
    ExternalAppPreferenceStore.resetForTesting({
      'scheme:market': ExternalAppDecision.alwaysDeny,
    });

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Play Store'), findsOneWidget);
    expect(
      await ExternalAppPreferenceStore.instance.decisionFor('scheme:market'),
      ExternalAppDecision.alwaysDeny,
    );
  });
}
