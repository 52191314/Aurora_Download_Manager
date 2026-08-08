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
      // Expecting exception during pump because keys are 'tools_Duplicate Tool' for both items
      dynamic thrownException;
      try {
        await tester.pumpAndSettle();
      } catch (e) {
        thrownException = e;
      }

      final errorDetails = tester.takeException();
      final hasCollisionError = thrownException != null || errorDetails != null;
      // Documenting whether duplicate key exception occurred
      expect(hasCollisionError, isTrue, reason: 'Duplicate entry labels cause ValueKey collision in ReorderableListView');
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

      final listFinder = find.byType(ReorderableListView);
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

      for (int i = 0; i < 50; i++) {
        if (i % 2 == 0) {
          await tester.tap(find.text('Tools'));
        } else {
          await tester.tap(find.text('Settings'));
        }
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();

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

      final item1Finder = find.byKey(const ValueKey('tools_Item 1'));
      final center = tester.getCenter(item1Finder);

      final gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 3000)); // Extreme downward drag
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
