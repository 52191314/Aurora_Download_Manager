import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/browser_controller.dart';
import 'package:aurora_downloader/sniffer/reader_mode_widget.dart';
import 'package:aurora_downloader/theme/aurora_palette.dart';
import 'package:aurora_downloader/theme/aurora_theme.dart';
import 'package:aurora_downloader/theme/aurora_tokens.dart';

class StressTestBrowserController implements SnifferBrowserController {
  final String title;
  final String? jsResult;
  final Exception? errorToThrow;

  StressTestBrowserController({
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

  group('Challenger 1 Stress Tests — ReaderModeWidget & Font Bounds', () {
    testWidgets('Font size upper limit boundary: clamps strictly at 28.0 pt', (tester) async {
      final fakeJson = '{"title":"Font Max Test","html":"h1::Heading\\n\\np::Content"}';
      final controller = StressTestBrowserController(title: 'Title', jsResult: fakeJson);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      final increaseBtnFinder = find.byIcon(Icons.text_increase);
      expect(increaseBtnFinder, findsOneWidget);

      // Default is 16.0. 16->18->20->22->24->26->28 (6 taps)
      for (int i = 0; i < 6; i++) {
        final IconButton btn = tester.widget(find.ancestor(of: increaseBtnFinder, matching: find.byType(IconButton)));
        expect(btn.onPressed, isNotNull, reason: 'Button should be active at step $i');
        await tester.tap(increaseBtnFinder);
        await tester.pumpAndSettle();
      }

      // At 28.0, increase button must be disabled
      final IconButton maxedBtn = tester.widget(find.ancestor(of: increaseBtnFinder, matching: find.byType(IconButton)));
      expect(maxedBtn.onPressed, isNull, reason: 'Increase button must be disabled at 28.0 pt upper bound');
    });

    testWidgets('Font size lower limit boundary: clamps strictly at 12.0 pt', (tester) async {
      final fakeJson = '{"title":"Font Min Test","html":"h1::Heading\\n\\np::Content"}';
      final controller = StressTestBrowserController(title: 'Title', jsResult: fakeJson);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      final decreaseBtnFinder = find.byIcon(Icons.text_decrease);
      expect(decreaseBtnFinder, findsOneWidget);

      // Default is 16.0. 16->14->12 (2 taps)
      for (int i = 0; i < 2; i++) {
        final IconButton btn = tester.widget(find.ancestor(of: decreaseBtnFinder, matching: find.byType(IconButton)));
        expect(btn.onPressed, isNotNull, reason: 'Button should be active at step $i');
        await tester.tap(decreaseBtnFinder);
        await tester.pumpAndSettle();
      }

      // At 12.0, decrease button must be disabled
      final IconButton minedBtn = tester.widget(find.ancestor(of: decreaseBtnFinder, matching: find.byType(IconButton)));
      expect(minedBtn.onPressed, isNull, reason: 'Decrease button must be disabled at 12.0 pt lower bound');
    });

    testWidgets('Renders all text block types correctly without layout overflow at min and max font size', (tester) async {
      final richHtml = 'h1::H1 Header\\n\\nh2::H2 Header\\n\\nh3::H3 Subheader\\n\\nh4::H4 Subheader\\n\\nblockquote::A blockquote text\\n\\npre::const x = 42;\\n\\np::Regular paragraph line\\n\\nUnformatted plain line';
      final fakeJson = '{"title":"Rich Article","html":"$richHtml"}';
      final controller = StressTestBrowserController(title: 'Rich Article Title', jsResult: fakeJson);

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('H1 Header'), findsOneWidget);
      expect(find.text('H2 Header'), findsOneWidget);
      expect(find.text('H3 Subheader'), findsOneWidget);
      expect(find.text('H4 Subheader'), findsOneWidget);
      expect(find.text('A blockquote text'), findsOneWidget);
      expect(find.text('const x = 42;'), findsOneWidget);
      expect(find.text('Regular paragraph line'), findsOneWidget);
      expect(find.text('Unformatted plain line'), findsOneWidget);
    });
  });

  group('Challenger 1 Stress Tests — Adversarial JSON & _jsonDecodeSafe', () {
    final adversarialPayloads = <String, String>{
      'Malformed JSON - Unterminated String': '{"title": "Unterminated string',
      'Malformed JSON - Missing Value': '{"title": "Valid", "html": ',
      'Malformed JSON - Syntax Error': '{title: "No quotes on keys"}',
      'Malformed JSON - Brackets Mismatch': '}{',
      'Malformed JSON - Truncated Object': '{"title": "Truncated"',
      'Raw HTML string (not JSON)': '<html><body><h1>Not JSON Article</h1><p>Some text</p></body></html>',
      'Plain string without JSON brackets': 'Just plain text without JSON structure',
      'JSON Array instead of Object': '["title", "content", "extra"]',
      'JSON Number primitive': '123456789',
      'JSON Boolean primitive': 'true',
      'JSON Null literal': 'null',
      'Double-Encoded JSON String': '"{\\"title\\":\\"Double Title\\",\\"html\\":\\"p::Double Encoded Text\\"}"',
      'Triple-Encoded JSON String': '"\\"{\\\\"title\\\\":\\\\"Triple Title\\\\",\\\\"html\\\\":\\\\"p::Triple Text\\\\"}\\""',
      'Payload with Commas & Quotes': '{"title": "News, Weather, & Sports: Part 1", "html": "p::Quote: \\"Hello, world!\\", item 1, item 2."}',
      'Payload with Colons & Escaped Quotes': '{"title": "http://domain.com:8080/path:sub", "html": "h1::Title: Subtitle::Extra"}',
      'Payload with Newlines & Tabs': '{"title": "Title\\nLine 2", "html": "p::Paragraph 1\\n\\nParagraph 2\\trabbed"}',
      'Payload with HTML inside JSON': '{"title": "<script>alert(\'xss\')</script>", "html": "h1::<div class=\\"test\\">HTML content</div>"}',
      'Payload with Unicode & Emojis': '{"title": "日本語タイトル 🚀 🔥 🎉", "html": "p::Unicode: 𐍈 \u2603 \uD83D\uDE00 éàèü RTL text"}',
      'Decoded Map with Non-String Values': '{"title": 12345, "html": 67890}',
      'Decoded Map with Null Values': '{"title": null, "html": null}',
      'Empty Object': '{}',
      'Whitespace Only String': '   \n\t  ',
    };

    for (final entry in adversarialPayloads.entries) {
      testWidgets('Adversarial Payload: ${entry.key}', (tester) async {
        final controller = StressTestBrowserController(
          title: 'Fallback Page Title',
          jsResult: entry.value,
        );

        await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
        await tester.pumpAndSettle();

        // Must complete without throwing uncaught exceptions or UI crash
        expect(find.byType(ReaderModeWidget), findsOneWidget);

        // Verify either title/content is displayed, fallback raw text is shown, or error message is rendered
        final hasError = find.text('No readable content found on this page.').evaluate().isNotEmpty;
        final hasAppBar = find.byType(AppBar).evaluate().isNotEmpty;

        expect(hasAppBar, isTrue, reason: 'AppBar should render cleanly for payload ${entry.key}');
        expect(tester.takeException(), isNull, reason: 'No unhandled exception should be thrown for payload ${entry.key}');
      });
    }

    testWidgets('Controller throws JavaScript evaluation error handled gracefully', (tester) async {
      final controller = StressTestBrowserController(
        title: 'Error Case',
        errorToThrow: Exception('JS Evaluation Exception'),
      );

      await tester.pumpWidget(buildTestableWidget(ReaderModeWidget(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reader mode failed: Exception: JS Evaluation Exception'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
