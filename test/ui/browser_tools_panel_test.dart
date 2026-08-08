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

  void setLargeSurfaceSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Browser Tools & Overflow Panel - 4-Tier Test Suite', () {
    late List<OverflowMenuEntry> mockSettingsEntries;
    late List<OverflowMenuEntry> mockToolEntries;
    late List<String> tappedLabels;
    late List<String> reorderedTools;
    late List<String> reorderedSettings;

    setUp(() {
      tappedLabels = [];
      reorderedTools = [];
      reorderedSettings = [];
      OverflowMenuSegmentStore.last = OverflowMenuSegment.settings;

      mockSettingsEntries = [
        OverflowMenuEntry(
          icon: Icons.download_rounded,
          label: 'Defaults',
          onTap: () => tappedLabels.add('Defaults'),
        ),
        OverflowMenuEntry(
          icon: Icons.shield_rounded,
          label: 'Adblock',
          onTap: () => tappedLabels.add('Adblock'),
        ),
        OverflowMenuEntry(
          icon: Icons.wifi_rounded,
          label: 'Network',
          onTap: () => tappedLabels.add('Network'),
        ),
      ];

      mockToolEntries = [
        OverflowMenuEntry(
          icon: Icons.security_outlined,
          label: 'Stealth Mode: Off',
          onTap: () => tappedLabels.add('Stealth Mode: Off'),
        ),
        OverflowMenuEntry(
          icon: Icons.shield_outlined,
          label: 'Incognito: Off',
          onTap: () => tappedLabels.add('Incognito: Off'),
        ),
        OverflowMenuEntry(
          icon: Icons.tab_rounded,
          label: 'Open in Custom Tab',
          onTap: () => tappedLabels.add('Open in Custom Tab'),
        ),
        OverflowMenuEntry(
          icon: Icons.history_rounded,
          label: 'History',
          onTap: () => tappedLabels.add('History'),
        ),
        OverflowMenuEntry(
          icon: Icons.star_rounded,
          label: 'Favorites',
          onTap: () => tappedLabels.add('Favorites'),
        ),
        OverflowMenuEntry(
          icon: Icons.offline_pin_rounded,
          label: 'Saved pages',
          onTap: () => tappedLabels.add('Saved pages'),
        ),
        OverflowMenuEntry(
          icon: Icons.save_alt_rounded,
          label: 'Save page',
          onTap: () => tappedLabels.add('Save page'),
        ),
        OverflowMenuEntry(
          icon: Icons.find_in_page_rounded,
          label: 'Find on page',
          onTap: () => tappedLabels.add('Find on page'),
        ),
        OverflowMenuEntry(
          icon: Icons.assignment_ind_rounded,
          label: 'Autofill',
          onTap: () => tappedLabels.add('Autofill'),
        ),
        OverflowMenuEntry(
          icon: Icons.chrome_reader_mode_rounded,
          label: 'Reader mode',
          onTap: () => tappedLabels.add('Reader mode'),
        ),
        OverflowMenuEntry(
          icon: Icons.shield,
          label: 'Adblock: On',
          onTap: () => tappedLabels.add('Adblock: On'),
        ),
        OverflowMenuEntry(
          icon: Icons.ads_click,
          label: 'Block element',
          onTap: () => tappedLabels.add('Block element'),
        ),
        OverflowMenuEntry(
          icon: Icons.undo,
          label: 'Reset blocks',
          onTap: () => tappedLabels.add('Reset blocks'),
        ),
        OverflowMenuEntry(
          icon: Icons.refresh_rounded,
          label: 'Re-scan media',
          onTap: () => tappedLabels.add('Re-scan media'),
        ),
        OverflowMenuEntry(
          icon: Icons.cookie_rounded,
          label: 'Clear cookies',
          onTap: () => tappedLabels.add('Clear cookies'),
        ),
      ];
    });

    // ==========================================
    // Tier 1: Feature Coverage (All 15 Tools)
    // ==========================================
    group('Tier 1: Feature Coverage', () {
      testWidgets('renders all 15 tools in Tools segment', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Test Page',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.tools,
                  );
                },
                child: const Text('Open Tools'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Tools'));
        await tester.pumpAndSettle();

        expect(find.text('Stealth Mode: Off'), findsOneWidget);
        expect(find.text('Incognito: Off'), findsOneWidget);
        expect(find.text('Open in Custom Tab'), findsOneWidget);

        final listFinder = find.byType(ReorderableListView);
        expect(listFinder, findsOneWidget);

        final allToolLabels = [
          'Stealth Mode: Off',
          'Incognito: Off',
          'Open in Custom Tab',
          'History',
          'Favorites',
          'Saved pages',
          'Save page',
          'Find on page',
          'Autofill',
          'Reader mode',
          'Adblock: On',
          'Block element',
          'Reset blocks',
          'Re-scan media',
          'Clear cookies',
        ];

        for (final label in allToolLabels) {
          await tester.dragUntilVisible(
            find.text(label),
            listFinder,
            const Offset(0, -80),
          );
          expect(find.text(label), findsOneWidget);
        }
      });

      testWidgets('each of the 15 tool entries triggers its onTap callback', (tester) async {
        setLargeSurfaceSize(tester);

        for (int i = 0; i < mockToolEntries.length; i++) {
          final targetEntry = mockToolEntries[i];
          tappedLabels.clear();

          await tester.pumpWidget(
            buildTestableWidget(
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showBrowserOverflowPopup(
                      context,
                      pageTitle: 'Test Page',
                      pageUrl: 'https://example.com',
                      settingsEntries: mockSettingsEntries,
                      toolEntries: mockToolEntries,
                      initialSegment: OverflowMenuSegment.tools,
                    );
                  },
                  child: const Text('Open Tools'),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Tools'));
          await tester.pumpAndSettle();

          final listFinder = find.byType(ReorderableListView);
          await tester.dragUntilVisible(
            find.text(targetEntry.label),
            listFinder,
            const Offset(0, -80),
          );

          await tester.tap(find.text(targetEntry.label));
          await tester.pumpAndSettle();

          expect(tappedLabels, contains(targetEntry.label));
        }
      });
    });

    // ==========================================
    // Tier 2: Boundary & Corner Cases
    // ==========================================
    group('Tier 2: Boundary & Corner Cases', () {
      testWidgets('handles empty title and URL gracefully (defaults to Current page and A avatar)', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: '',
                    pageUrl: '',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                  );
                },
                child: const Text('Open Menu'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Menu'));
        await tester.pumpAndSettle();

        expect(find.text('Current page'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
      });

      testWidgets('handles non-HTTP schemes (e.g. chrome://newtab, file:///sdcard/doc.pdf)', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'New Tab',
                    pageUrl: 'chrome://newtab',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                  );
                },
                child: const Text('Open Custom Scheme'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Custom Scheme'));
        await tester.pumpAndSettle();

        expect(find.text('New Tab'), findsOneWidget);
      });

      testWidgets('handles null pageTitle and null pageUrl without throwing', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: null,
                    pageUrl: null,
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                  );
                },
                child: const Text('Open Nulls'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Nulls'));
        await tester.pumpAndSettle();

        expect(find.text('Current page'), findsOneWidget);
      });
    });

    // ==========================================
    // Tier 3: Cross-Feature Combinations
    // ==========================================
    group('Tier 3: Cross-Feature Combinations', () {
      testWidgets('switching between Settings & Tools segments updates view and persists segment state', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Example',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                  );
                },
                child: const Text('Open Popup'),
              ),
            ),
          ),
        );

        // 1. Open popup (defaults to Settings segment)
        await tester.tap(find.text('Open Popup'));
        await tester.pumpAndSettle();

        expect(find.text('Defaults'), findsOneWidget);
        expect(find.text('Stealth Mode: Off'), findsNothing);

        // 2. Switch to Tools segment
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();

        expect(find.text('Stealth Mode: Off'), findsOneWidget);
        expect(find.text('Defaults'), findsNothing);
        expect(OverflowMenuSegmentStore.last, equals(OverflowMenuSegment.tools));

        // 3. Dismiss popup by tapping outside barrier
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // 4. Re-open popup without explicit initialSegment -> should restore Tools segment
        await tester.tap(find.text('Open Popup'));
        await tester.pumpAndSettle();

        expect(find.text('Stealth Mode: Off'), findsOneWidget);

        // 5. Switch back to Settings segment
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(find.text('Defaults'), findsOneWidget);
        expect(OverflowMenuSegmentStore.last, equals(OverflowMenuSegment.settings));
      });

      testWidgets('reordering tool entries notifies onReorderTools callback and updates order', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Reorder Test',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.tools,
                    onReorderTools: (newOrder) => reorderedTools = newOrder,
                  );
                },
                child: const Text('Open Tools Reorder'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Tools Reorder'));
        await tester.pumpAndSettle();

        final itemFinder = find.byKey(const ValueKey('tools_Stealth Mode: Off'));
        expect(itemFinder, findsOneWidget);

        final itemCenter = tester.getCenter(itemFinder);
        final TestGesture gesture = await tester.startGesture(itemCenter);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
        await gesture.moveBy(const Offset(0, 150));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(reorderedTools, isNotEmpty);
      });

      testWidgets('reordering settings entries notifies onReorderSettings callback', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Settings Reorder Test',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.settings,
                    onReorderSettings: (newOrder) => reorderedSettings = newOrder,
                  );
                },
                child: const Text('Open Settings Reorder'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Settings Reorder'));
        await tester.pumpAndSettle();

        final itemFinder = find.byKey(const ValueKey('settings_Defaults'));
        expect(itemFinder, findsOneWidget);

        final itemCenter = tester.getCenter(itemFinder);
        final TestGesture gesture = await tester.startGesture(itemCenter);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
        await gesture.moveBy(const Offset(0, 150));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(reorderedSettings, isNotEmpty);
      });
    });

    // ==========================================
    // Tier 4: Real-World Application Scenarios
    // ==========================================
    group('Tier 4: Real-World Application Scenarios', () {
      testWidgets('full popup lifecycle: open popup -> switch segment -> tap tool action -> closes popup & executes action', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Lifecycle Test Page',
                    pageUrl: 'https://aurora.app',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.settings,
                  );
                },
                child: const Text('Launch Menu'),
              ),
            ),
          ),
        );

        // Step 1: Open popup from user gesture
        await tester.tap(find.text('Launch Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Lifecycle Test Page'), findsOneWidget);

        // Step 2: Switch to Tools segment
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();

        // Step 3: Tap a tool action (e.g. 'Saved pages')
        await tester.tap(find.text('Saved pages'));
        await tester.pumpAndSettle();

        // Step 4: Verify popup auto-dismisses and callback executes
        expect(find.text('Lifecycle Test Page'), findsNothing);
        expect(tappedLabels, contains('Saved pages'));
      });

      testWidgets('dragging reorder handles reorders items interactively via gesture', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Drag Handle Test',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.tools,
                    onReorderTools: (newOrder) => reorderedTools = newOrder,
                  );
                },
                child: const Text('Open Drag Test'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Drag Test'));
        await tester.pumpAndSettle();

        final itemFinder = find.byKey(const ValueKey('tools_Stealth Mode: Off'));
        expect(itemFinder, findsOneWidget);

        final itemCenter = tester.getCenter(itemFinder);
        final TestGesture gesture = await tester.startGesture(itemCenter);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
        await gesture.moveBy(const Offset(0, 150));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(reorderedTools, isNotEmpty);
      });

      testWidgets('tapping multiple tools sequentially across multiple menu launches', (tester) async {
        setLargeSurfaceSize(tester);

        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Multi-Tap Test',
                    pageUrl: 'https://example.com',
                    settingsEntries: mockSettingsEntries,
                    toolEntries: mockToolEntries,
                  );
                },
                child: const Text('Open Menu Multi'),
              ),
            ),
          ),
        );

        // First launch: Open menu -> switch to Tools -> tap 'Stealth Mode: Off'
        await tester.tap(find.text('Open Menu Multi'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stealth Mode: Off'));
        await tester.pumpAndSettle();

        // Second launch: Open menu (persists on Tools segment) -> tap 'Incognito: Off'
        await tester.tap(find.text('Open Menu Multi'));
        await tester.pumpAndSettle();
        expect(find.text('Incognito: Off'), findsOneWidget);
        await tester.tap(find.text('Incognito: Off'));
        await tester.pumpAndSettle();

        // Third launch: Open menu -> switch to Settings -> tap 'Defaults'
        await tester.tap(find.text('Open Menu Multi'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Defaults'));
        await tester.pumpAndSettle();

        expect(tappedLabels, equals(['Stealth Mode: Off', 'Incognito: Off', 'Defaults']));
      });
    });
  });
}
