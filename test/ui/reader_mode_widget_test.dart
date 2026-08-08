import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/browser_controller.dart';
import 'package:aurora_downloader/sniffer/reader_mode_widget.dart';
import 'package:aurora_downloader/theme/aurora_palette.dart';
import 'package:aurora_downloader/theme/aurora_theme.dart';
import 'package:aurora_downloader/theme/aurora_tokens.dart';

class FakeSnifferBrowserController implements SnifferBrowserController {
  final String title;
  final String? jsResult;
  final Exception? errorToThrow;

  FakeSnifferBrowserController({
    required this.title,
    this.jsResult,
    this.errorToThrow,
  });

  @override
  Future<String?> pageTitle() async => title;

  @override
  Future<Object?> evaluateJavaScript(String source) async {
    if (errorToThrow != null) throw errorToThrow!;
    return jsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(Widget child) {
    return AuroraPalette(
      colors: AColors.dark(),
      isLight: false,
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: child,
      ),
    );
  }

  group('ReaderModeWidget - Font Scaling & JSON Decoding Tests', () {
    testWidgets('renders structured article content and updates font size via increase and decrease buttons', (tester) async {
      final fakeJson = '{"title":"Test Article","html":"h1::Heading 1\\n\\np::First paragraph with text."}';
      final controller = FakeSnifferBrowserController(title: 'Original Title', jsResult: fakeJson);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Test Article'), findsOneWidget);
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('First paragraph with text.'), findsOneWidget);

      final decreaseBtnFinder = find.byIcon(Icons.text_decrease);
      final increaseBtnFinder = find.byIcon(Icons.text_increase);

      expect(decreaseBtnFinder, findsOneWidget);
      expect(increaseBtnFinder, findsOneWidget);

      // Default font size is 16.0.
      // Tap increase 6 times to reach max 28.0 (16 -> 18 -> 20 -> 22 -> 24 -> 26 -> 28)
      for (int i = 0; i < 6; i++) {
        final IconButton increaseBtn = tester.widget(find.ancestor(of: increaseBtnFinder, matching: find.byType(IconButton)));
        expect(increaseBtn.onPressed, isNotNull);
        await tester.tap(increaseBtnFinder);
        await tester.pumpAndSettle();
      }

      // At 28.0, increase button should be disabled (onPressed == null)
      final IconButton maxedIncreaseBtn = tester.widget(find.ancestor(of: increaseBtnFinder, matching: find.byType(IconButton)));
      expect(maxedIncreaseBtn.onPressed, isNull);

      // Tap decrease 8 times to reach min 12.0 (28 -> 26 -> 24 -> 22 -> 20 -> 18 -> 16 -> 14 -> 12)
      for (int i = 0; i < 8; i++) {
        final IconButton decreaseBtn = tester.widget(find.ancestor(of: decreaseBtnFinder, matching: find.byType(IconButton)));
        expect(decreaseBtn.onPressed, isNotNull);
        await tester.tap(decreaseBtnFinder);
        await tester.pumpAndSettle();
      }

      // At 12.0, decrease button should be disabled (onPressed == null)
      final IconButton minedDecreaseBtn = tester.widget(find.ancestor(of: decreaseBtnFinder, matching: find.byType(IconButton)));
      expect(minedDecreaseBtn.onPressed, isNull);
    });

    testWidgets('handles JSON decoding with commas, quotes, and escaped characters robustly', (tester) async {
      // JSON containing commas in title/content and escaped quotes & colons
      final jsonWithCommas = '{"title":"News, Weather, and Updates: Special Edition","html":"p::Clause 1, clause 2, and \\"quoted text\\": details."}';
      final controller = FakeSnifferBrowserController(title: 'Fallback', jsResult: jsonWithCommas);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('News, Weather, and Updates: Special Edition'), findsOneWidget);
      expect(find.text('Clause 1, clause 2, and "quoted text": details.'), findsOneWidget);
    });

    testWidgets('handles double-encoded JSON strings gracefully', (tester) async {
      // Double encoded JSON string from JS evaluation
      final doubleEncoded = '"{\\"title\\":\\"Double Encoded Title\\",\\"html\\":\\"p::Paragraph in double encoded JSON\\"}"';
      final controller = FakeSnifferBrowserController(title: 'Fallback', jsResult: doubleEncoded);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Double Encoded Title'), findsOneWidget);
      expect(find.text('Paragraph in double encoded JSON'), findsOneWidget);
    });

    testWidgets('displays error state when no content extracted', (tester) async {
      final controller = FakeSnifferBrowserController(title: 'Empty Page', jsResult: '');

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('No readable content found on this page.'), findsOneWidget);
    });
  });
}
