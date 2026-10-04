import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/sheets/browser_overflow_popup.dart';
import 'package:aurora_downloader/theme/aurora_theme.dart';
import 'package:aurora_downloader/theme/aurora_palette.dart';
import 'package:aurora_downloader/theme/aurora_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(Widget child) {
    return AuroraPalette(
      colors: AColors.dark(),
      isLight: false,
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => child,
          ),
        ),
      ),
    );
  }

  void setSurfaceSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Adversarial & Corner Case Stress Tests for Browser Overflow Popup', () {
    // ----------------------------------------------------
    // ADV-1: Duplicate Entry Labels (ValueKey Collision Test)
    // ----------------------------------------------------
    testWidgets('ADV-1: Duplicate entry labels trigger key collision or handle duplicate entries', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      final duplicateEntries = [
        OverflowMenuEntry(
          icon: Icons.history_rounded,
          label: 'Duplicate Tool',
          onTap: () {},
        ),
        OverflowMenuEntry(
          icon: Icons.star_rounded,
          label: 'Duplicate Tool',
          onTap: () {},
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Duplicate Test',
                  pageUrl: 'https://example.com',
                  settingsEntries: duplicateEntries,
                  toolEntries: duplicateEntries,
                  initialSegment: OverflowMenuSegment.tools,
                );
              },
              child: const Text('Open Duplicates'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Duplicates'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Duplicate Tool'), findsWidgets);
    });

    // ----------------------------------------------------
    // ADV-2: Micro-surface / Extreme Small Screen Heights
    // ----------------------------------------------------
    testWidgets('ADV-2: Micro-surface height (200px) does not overflow RenderFlex', (tester) async {
      setSurfaceSize(tester, const Size(360, 200));

      final entries = [
        OverflowMenuEntry(icon: Icons.info, label: 'Tool 1', onTap: () {}),
        OverflowMenuEntry(icon: Icons.info, label: 'Tool 2', onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Micro Screen',
                  pageUrl: 'https://example.com',
                  settingsEntries: entries,
                  toolEntries: entries,
                );
              },
              child: const Text('Open Micro'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Micro'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Micro Screen'), findsOneWidget);
    });

    // ----------------------------------------------------
    // ADV-3: Emoji, Unicode, RTL & Malformed URL Parsing
    // ----------------------------------------------------
    testWidgets('ADV-3: Multibyte Emoji, Unicode RTL and malformed URIs render without crashing', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      final entries = [
        OverflowMenuEntry(icon: Icons.star, label: 'Tool', onTap: () {}),
      ];

      // Test 3a: Emoji host
      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: '🚀 Emoji Page 🎉',
                  pageUrl: 'https://😀😁😂.org/path',
                  settingsEntries: entries,
                  toolEntries: entries,
                );
              },
              child: const Text('Open Emoji'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Emoji'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('🚀 Emoji Page 🎉'), findsOneWidget);

      // Dismiss popup
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Test 3b: Malformed URI format
      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: '',
                  pageUrl: '://invalid-uri-scheme-no-colon-slashes',
                  settingsEntries: entries,
                  toolEntries: entries,
                );
              },
              child: const Text('Open Malformed'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Malformed'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('://invalid-uri-scheme-no-colon-slashes'), findsNWidgets(2)); // Title falls back to host, host is raw string
    });

    // ----------------------------------------------------
    // ADV-4: Massive List (100 Items) & Scrollability Mechanics
    // ----------------------------------------------------
    testWidgets('ADV-4: Scrollability mechanics with 100 tool entries in ReorderableListView', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      final largeToolEntries = List.generate(
        100,
        (i) => OverflowMenuEntry(
          icon: Icons.build,
          label: 'Tool Item #$i',
          onTap: () {},
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Massive List Test',
                  pageUrl: 'https://example.com',
                  settingsEntries: [],
                  toolEntries: largeToolEntries,
                  initialSegment: OverflowMenuSegment.tools,
                );
              },
              child: const Text('Open Large List'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Large List'));
      await tester.pumpAndSettle();

      expect(find.text('Tool Item #0'), findsOneWidget);

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      // Drag down to reveal item #50
      await tester.dragUntilVisible(
        find.text('Tool Item #50'),
        listFinder,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tool Item #50'), findsOneWidget);

      // Drag down to reveal item #99
      await tester.dragUntilVisible(
        find.text('Tool Item #99'),
        listFinder,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tool Item #99'), findsOneWidget);
    });

    // ----------------------------------------------------
    // ADV-5: Rapid Segment Toggle Stress Test (50 Alternating Taps)
    // ----------------------------------------------------
    testWidgets('ADV-5: Rapidly switching segments 50 times does not throw or corrupt state', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      final settings = [OverflowMenuEntry(icon: Icons.settings, label: 'Setting 1', onTap: () {})];
      final tools = [OverflowMenuEntry(icon: Icons.build, label: 'Tool 1', onTap: () {})];

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Toggle Test',
                  pageUrl: 'https://example.com',
                  settingsEntries: settings,
                  toolEntries: tools,
                );
              },
              child: const Text('Open Toggle'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Toggle'));
      await tester.pumpAndSettle();

      expect(find.text('Tool 1'), findsOneWidget);
      expect(find.text('Setting 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ----------------------------------------------------
    // ADV-6: Empty Lists Handling
    // ----------------------------------------------------
    testWidgets('ADV-6: Empty settings and tool lists render cleanly without index error', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Empty Test',
                  pageUrl: 'https://example.com',
                  settingsEntries: [],
                  toolEntries: [],
                );
              },
              child: const Text('Open Empty'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Empty'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Empty Test'), findsOneWidget);
    });

    // ----------------------------------------------------
    // ADV-7: Out of Bounds Drag & Null Callback Reorder
    // ----------------------------------------------------
    testWidgets('ADV-7: Reordering with null callback and extreme drag distance does not crash', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      final toolEntries = [
        OverflowMenuEntry(icon: Icons.looks_one, label: 'Item 1', onTap: () {}),
        OverflowMenuEntry(icon: Icons.looks_two, label: 'Item 2', onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Null Callback Reorder',
                  pageUrl: 'https://example.com',
                  settingsEntries: [],
                  toolEntries: toolEntries,
                  initialSegment: OverflowMenuSegment.tools,
                  onReorderTools: null, // explicit null
                );
              },
              child: const Text('Open Reorder Null'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reorder Null'));
      await tester.pumpAndSettle();

      final item1Finder = find.byKey(const ValueKey('row_0_Item 1'));
      final center = tester.getCenter(item1Finder);

      final gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 3000)); // Extreme downward drag
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // ----------------------------------------------------
    // ADV-8: Merged Single List with Tools, Divider, and Settings
    // ----------------------------------------------------
    testWidgets('ADV-8: Merged modal renders tools, divider, and settings (Backup, Pro, Vault)', (tester) async {
      setSurfaceSize(tester, const Size(1080, 2400));

      bool backupTapped = false;
      bool proTapped = false;

      final tools = [
        OverflowMenuEntry(icon: Icons.history, label: 'History', onTap: () {}),
        OverflowMenuEntry(icon: Icons.download, label: 'Downloads', onTap: () {}),
        const OverflowMenuEntry.divider(),
        OverflowMenuEntry(icon: Icons.security, label: 'Stealth on', onTap: () {}),
      ];

      final settings = [
        const OverflowMenuEntry.header('Settings'),
        OverflowMenuEntry(icon: Icons.tune, label: 'Download Defaults', onTap: () {}),
        OverflowMenuEntry(icon: Icons.backup, label: 'Backup', onTap: () => backupTapped = true),
        OverflowMenuEntry(
          icon: Icons.auto_awesome,
          label: 'Aurora Pro & Ultra',
          badge: 'PRO',
          onTap: () => proTapped = true,
        ),
        OverflowMenuEntry(icon: Icons.shield, label: 'Private Vault', badge: 'PRO', onTap: () {}),
        OverflowMenuEntry(icon: Icons.cloud_sync, label: 'WebDAV Backup', badge: 'PRO', onTap: () {}),
        OverflowMenuEntry(icon: Icons.rss_feed, label: 'Aurora Watcher', badge: 'PRO', onTap: () {}),
        OverflowMenuEntry(icon: Icons.api, label: 'Automation API', badge: 'PRO', onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBrowserOverflowPopup(
                  context,
                  pageTitle: 'Unified Test',
                  pageUrl: 'https://example.com',
                  toolEntries: tools,
                  settingsEntries: settings,
                );
              },
              child: const Text('Open Unified'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Unified'));
      await tester.pumpAndSettle();

      // Verify tools rendered first
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);

      final listFinder = find.byType(ListView);

      // Verify settings header and items
      await tester.dragUntilVisible(
        find.text('SETTINGS'),
        listFinder,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsOneWidget);

      // Verify Backup is present and tap works
      await tester.dragUntilVisible(
        find.text('Backup'),
        listFinder,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backup'), findsOneWidget);
      await tester.tap(find.text('Backup'));
      await tester.pumpAndSettle();
      expect(backupTapped, isTrue);

      // Re-open and verify Pro & Ultra with PRO badge
      await tester.tap(find.text('Open Unified'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Aurora Pro & Ultra'),
        listFinder,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aurora Pro & Ultra'), findsOneWidget);
      await tester.tap(find.text('Aurora Pro & Ultra'));
      await tester.pumpAndSettle();
      expect(proTapped, isTrue);
    });
  });
}
