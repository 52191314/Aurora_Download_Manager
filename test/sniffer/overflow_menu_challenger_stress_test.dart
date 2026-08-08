import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/sniffer_screen.dart';
import 'package:aurora_downloader/sniffer/sheets/browser_overflow_popup.dart';
import 'package:aurora_downloader/settings/download_settings.dart';
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

  group('Challenger 2 Empirical Verification: Overflow Menu & Key Normalization', () {
    // ----------------------------------------------------
    // Section 1: Key Normalization & Reordering Stability
    // ----------------------------------------------------
    group('Key Normalization & Reordering Stability', () {
      test('SnifferScreen.normalizeMenuEntryKey maps dynamic labels to canonical keys', () {
        // Stealth Mode dynamic variations
        expect(SnifferScreen.normalizeMenuEntryKey('Stealth Mode: On'), equals('Stealth Mode'));
        expect(SnifferScreen.normalizeMenuEntryKey('Stealth Mode: Off'), equals('Stealth Mode'));
        expect(SnifferScreen.normalizeMenuEntryKey('Stealth Mode: Enabled'), equals('Stealth Mode'));

        // Incognito dynamic variations
        expect(SnifferScreen.normalizeMenuEntryKey('Incognito: On'), equals('Incognito'));
        expect(SnifferScreen.normalizeMenuEntryKey('Incognito: Off'), equals('Incognito'));

        // Adblock dynamic variations
        expect(SnifferScreen.normalizeMenuEntryKey('Adblock: On'), equals('Adblock'));
        expect(SnifferScreen.normalizeMenuEntryKey('Adblock: Off'), equals('Adblock'));
        expect(SnifferScreen.normalizeMenuEntryKey('Ads allowed'), equals('Adblock'));

        // Static tool entries retain exact label
        expect(SnifferScreen.normalizeMenuEntryKey('Open in Custom Tab'), equals('Open in Custom Tab'));
        expect(SnifferScreen.normalizeMenuEntryKey('History'), equals('History'));
        expect(SnifferScreen.normalizeMenuEntryKey('Favorites'), equals('Favorites'));
        expect(SnifferScreen.normalizeMenuEntryKey('Saved pages'), equals('Saved pages'));
        expect(SnifferScreen.normalizeMenuEntryKey('Save page'), equals('Save page'));
        expect(SnifferScreen.normalizeMenuEntryKey('Find on page'), equals('Find on page'));
        expect(SnifferScreen.normalizeMenuEntryKey('Autofill'), equals('Autofill'));
        expect(SnifferScreen.normalizeMenuEntryKey('Reader mode'), equals('Reader mode'));
        expect(SnifferScreen.normalizeMenuEntryKey('Block element'), equals('Block element'));
        expect(SnifferScreen.normalizeMenuEntryKey('Reset blocks'), equals('Reset blocks'));
        expect(SnifferScreen.normalizeMenuEntryKey('Re-scan media'), equals('Re-scan media'));
        expect(SnifferScreen.normalizeMenuEntryKey('Clear cookies'), equals('Clear cookies'));
      });

      test('Custom menuToolOrder retains item position when dynamic labels toggle state', () {
        // Custom order using normalized keys
        final customOrder = [
          'Clear cookies',
          'Stealth Mode',
          'History',
          'Adblock',
          'Incognito',
          'Save page',
        ];

        // Simulate state A (Stealth Off, Incognito Off, Adblock Off)
        final entriesStateA = [
          OverflowMenuEntry(icon: Icons.security, label: 'Stealth Mode: Off', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Incognito: Off', onTap: () {}),
          OverflowMenuEntry(icon: Icons.tab, label: 'Open in Custom Tab', onTap: () {}),
          OverflowMenuEntry(icon: Icons.history, label: 'History', onTap: () {}),
          OverflowMenuEntry(icon: Icons.save, label: 'Save page', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Adblock: Off', onTap: () {}),
          OverflowMenuEntry(icon: Icons.cookie, label: 'Clear cookies', onTap: () {}),
        ];

        // Helper to simulate SnifferScreen._sortOverflowEntries
        List<OverflowMenuEntry> sortEntries(List<OverflowMenuEntry> entries, List<String> order) {
          if (order.isEmpty) return entries;
          final sorted = <OverflowMenuEntry>[];
          final map = <String, OverflowMenuEntry>{};
          for (final e in entries) {
            final key = SnifferScreen.normalizeMenuEntryKey(e.label);
            map[key] = e;
          }
          for (final key in order) {
            final normKey = SnifferScreen.normalizeMenuEntryKey(key);
            final entry = map.remove(normKey);
            if (entry != null) {
              sorted.add(entry);
            }
          }
          sorted.addAll(map.values);
          return sorted;
        }

        final sortedA = sortEntries(entriesStateA, customOrder);
        final labelsA = sortedA.map((e) => e.label).toList();
        expect(labelsA[0], equals('Clear cookies'));
        expect(labelsA[1], equals('Stealth Mode: Off'));
        expect(labelsA[2], equals('History'));
        expect(labelsA[3], equals('Adblock: Off'));
        expect(labelsA[4], equals('Incognito: Off'));
        expect(labelsA[5], equals('Save page'));
        expect(labelsA[6], equals('Open in Custom Tab')); // Unspecified appended at end

        // Simulate state B (Stealth On, Incognito On, Adblock On)
        final entriesStateB = [
          OverflowMenuEntry(icon: Icons.security, label: 'Stealth Mode: On', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Incognito: On', onTap: () {}),
          OverflowMenuEntry(icon: Icons.tab, label: 'Open in Custom Tab', onTap: () {}),
          OverflowMenuEntry(icon: Icons.history, label: 'History', onTap: () {}),
          OverflowMenuEntry(icon: Icons.save, label: 'Save page', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Adblock: On', onTap: () {}),
          OverflowMenuEntry(icon: Icons.cookie, label: 'Clear cookies', onTap: () {}),
        ];

        final sortedB = sortEntries(entriesStateB, customOrder);
        final labelsB = sortedB.map((e) => e.label).toList();
        expect(labelsB[0], equals('Clear cookies'));
        expect(labelsB[1], equals('Stealth Mode: On'));
        expect(labelsB[2], equals('History'));
        expect(labelsB[3], equals('Adblock: On'));
        expect(labelsB[4], equals('Incognito: On'));
        expect(labelsB[5], equals('Save page'));
        expect(labelsB[6], equals('Open in Custom Tab'));

        // Simulate state C (Adblock: Ads allowed)
        final entriesStateC = [
          OverflowMenuEntry(icon: Icons.security, label: 'Stealth Mode: Off', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Incognito: Off', onTap: () {}),
          OverflowMenuEntry(icon: Icons.tab, label: 'Open in Custom Tab', onTap: () {}),
          OverflowMenuEntry(icon: Icons.history, label: 'History', onTap: () {}),
          OverflowMenuEntry(icon: Icons.save, label: 'Save page', onTap: () {}),
          OverflowMenuEntry(icon: Icons.shield, label: 'Ads allowed', onTap: () {}),
          OverflowMenuEntry(icon: Icons.cookie, label: 'Clear cookies', onTap: () {}),
        ];

        final sortedC = sortEntries(entriesStateC, customOrder);
        final labelsC = sortedC.map((e) => e.label).toList();
        expect(labelsC[3], equals('Ads allowed')); // Adblock stays in position 3!
      });
    });

    // ----------------------------------------------------
    // Section 2: Stress Testing 15 Overflow Tool Callbacks
    // ----------------------------------------------------
    group('Stress Testing 15 Overflow Tool Callbacks', () {
      late List<String> executedCallbacks;

      setUp(() {
        executedCallbacks = [];
      });

      testWidgets('All 15 tool callbacks render and execute safely under rapid triggers', (tester) async {
        setLargeSurfaceSize(tester);

        final mockToolEntries = [
          OverflowMenuEntry(
            icon: Icons.security_outlined,
            label: 'Stealth Mode: Off',
            onTap: () => executedCallbacks.add('Stealth Mode'),
          ),
          OverflowMenuEntry(
            icon: Icons.shield_outlined,
            label: 'Incognito: Off',
            onTap: () => executedCallbacks.add('Incognito'),
          ),
          OverflowMenuEntry(
            icon: Icons.tab_rounded,
            label: 'Open in Custom Tab',
            onTap: () => executedCallbacks.add('Open in Custom Tab'),
          ),
          OverflowMenuEntry(
            icon: Icons.history_rounded,
            label: 'History',
            onTap: () => executedCallbacks.add('History'),
          ),
          OverflowMenuEntry(
            icon: Icons.star_rounded,
            label: 'Favorites',
            onTap: () => executedCallbacks.add('Favorites'),
          ),
          OverflowMenuEntry(
            icon: Icons.offline_pin_rounded,
            label: 'Saved pages',
            onTap: () => executedCallbacks.add('Saved pages'),
          ),
          OverflowMenuEntry(
            icon: Icons.save_alt_rounded,
            label: 'Save page',
            onTap: () => executedCallbacks.add('Save page'),
          ),
          OverflowMenuEntry(
            icon: Icons.find_in_page_rounded,
            label: 'Find on page',
            onTap: () => executedCallbacks.add('Find on page'),
          ),
          OverflowMenuEntry(
            icon: Icons.assignment_ind_rounded,
            label: 'Autofill',
            onTap: () => executedCallbacks.add('Autofill'),
          ),
          OverflowMenuEntry(
            icon: Icons.chrome_reader_mode_rounded,
            label: 'Reader mode',
            onTap: () => executedCallbacks.add('Reader mode'),
          ),
          OverflowMenuEntry(
            icon: Icons.shield,
            label: 'Adblock: On',
            onTap: () => executedCallbacks.add('Adblock'),
          ),
          OverflowMenuEntry(
            icon: Icons.ads_click,
            label: 'Block element',
            onTap: () => executedCallbacks.add('Block element'),
          ),
          OverflowMenuEntry(
            icon: Icons.undo,
            label: 'Reset blocks',
            onTap: () => executedCallbacks.add('Reset blocks'),
          ),
          OverflowMenuEntry(
            icon: Icons.refresh_rounded,
            label: 'Re-scan media',
            onTap: () => executedCallbacks.add('Re-scan media'),
          ),
          OverflowMenuEntry(
            icon: Icons.cookie_rounded,
            label: 'Clear cookies',
            onTap: () => executedCallbacks.add('Clear cookies'),
          ),
        ];

        // Launch popup
        await tester.pumpWidget(
          buildTestableWidget(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBrowserOverflowPopup(
                    context,
                    pageTitle: 'Empirical Verification Page',
                    pageUrl: 'https://aurora.example.com',
                    settingsEntries: [],
                    toolEntries: mockToolEntries,
                    initialSegment: OverflowMenuSegment.tools,
                  );
                },
                child: const Text('Open Stress Menu'),
              ),
            ),
          ),
        );

        // Tap each tool entry and verify callback execution & pop resilience
        for (int i = 0; i < mockToolEntries.length; i++) {
          await tester.tap(find.text('Open Stress Menu'));
          await tester.pumpAndSettle();

          final entry = mockToolEntries[i];
          final listFinder = find.byType(ReorderableListView);
          await tester.dragUntilVisible(
            find.text(entry.label),
            listFinder,
            const Offset(0, -80),
          );

          await tester.tap(find.text(entry.label));
          await tester.pumpAndSettle();
        }

        expect(executedCallbacks.length, equals(15));
        expect(executedCallbacks, containsAll([
          'Stealth Mode',
          'Incognito',
          'Open in Custom Tab',
          'History',
          'Favorites',
          'Saved pages',
          'Save page',
          'Find on page',
          'Autofill',
          'Reader mode',
          'Adblock',
          'Block element',
          'Reset blocks',
          'Re-scan media',
          'Clear cookies',
        ]));
      });
    });
  });
}
