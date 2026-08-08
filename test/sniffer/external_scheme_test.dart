import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/external_scheme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('externalAppKeyForUri & externalAppDisplayNameForUri', () {
    test('identifies android package from intent uri', () {
      final uri = Uri.parse(
        'intent://open?link=abc#Intent;scheme=https;package=org.telegram.messenger;end',
      );
      expect(externalAppKeyForUri(uri), equals('package:org.telegram.messenger'));
      expect(externalAppDisplayNameForUri(uri), equals('Telegram'));
    });

    test('identifies android-app package uri', () {
      final uri = Uri.parse('android-app://com.whatsapp/http/whatsapp.com');
      expect(externalAppKeyForUri(uri), equals('package:com.whatsapp'));
      expect(externalAppDisplayNameForUri(uri), equals('WhatsApp'));
    });

    test('identifies scheme deep link uri', () {
      final uri = Uri.parse('tg://resolve?domain=test');
      expect(externalAppKeyForUri(uri), equals('scheme:tg'));
      expect(externalAppDisplayNameForUri(uri), equals('Telegram'));
    });

    test('identifies mailto and tel schemes', () {
      final mailUri = Uri.parse('mailto:support@example.com');
      expect(externalAppKeyForUri(mailUri), equals('scheme:mailto'));
      expect(externalAppDisplayNameForUri(mailUri), equals('Email'));

      final telUri = Uri.parse('tel:+1234567890');
      expect(externalAppKeyForUri(telUri), equals('scheme:tel'));
      expect(externalAppDisplayNameForUri(telUri), equals('Phone'));
    });

    test('fallback for unknown scheme', () {
      final uri = Uri.parse('customapp://path');
      expect(externalAppKeyForUri(uri), equals('scheme:customapp'));
      expect(externalAppDisplayNameForUri(uri), equals('customapp'));
    });
  });

  group('isExternalAppUri', () {
    test('web navigable schemes return false', () {
      expect(isExternalAppUri(Uri.parse('https://example.com')), isFalse);
      expect(isExternalAppUri(Uri.parse('http://example.com')), isFalse);
      expect(isExternalAppUri(Uri.parse('about:blank')), isFalse);
      expect(isExternalAppUri(Uri.parse('data:text/html,hi')), isFalse);
      expect(isExternalAppUri(Uri.parse('file:///path/to/file')), isFalse);
    });

    test('external schemes return true', () {
      expect(isExternalAppUri(Uri.parse('tg://resolve?domain=test')), isTrue);
      expect(isExternalAppUri(Uri.parse('intent://open#Intent;package=foo;end')), isTrue);
      expect(isExternalAppUri(Uri.parse('market://details?id=foo')), isTrue);
      expect(isExternalAppUri(Uri.parse('mailto:a@b.com')), isTrue);
    });
  });

  group('handleExternalAppUri', () {
    final launchedUrls = <String>[];

    setUp(() {
      launchedUrls.clear();
      externalAppLauncherOverride = (url) async {
        launchedUrls.add(url);
        return true;
      };
      externalAppPromptHandler = null;
      ExternalAppPreferenceStore.resetForTesting();
    });

    tearDown(() {
      externalAppLauncherOverride = null;
      externalAppPromptHandler = null;
      ExternalAppPreferenceStore.resetForTesting();
    });

    test('non-external scheme is ignored', () async {
      final handled = await handleExternalAppUri(Uri.parse('https://google.com'));
      expect(handled, isFalse);
      expect(launchedUrls, isEmpty);
    });

    test('skipPrompt: true launches immediately without asking', () async {
      final uri = Uri.parse('tg://resolve?domain=test');
      final handled = await handleExternalAppUri(uri, skipPrompt: true);
      expect(handled, isTrue);
      expect(launchedUrls, equals(['tg://resolve?domain=test']));
    });

    test('no prompt handler blocks external launch by default (safety)', () async {
      externalAppPromptHandler = null;
      final uri = Uri.parse('tg://resolve?domain=test');
      final handled = await handleExternalAppUri(uri);
      expect(handled, isTrue);
      expect(launchedUrls, isEmpty);
    });

    test('openOnce launches app without saving preference', () async {
      externalAppPromptHandler = ({
        required uri,
        required appKey,
        required displayName,
        pageHost,
      }) async {
        return ExternalAppPromptResult.openOnce;
      };

      final uri = Uri.parse('tg://resolve?domain=test');
      final handled = await handleExternalAppUri(uri);
      expect(handled, isTrue);
      expect(launchedUrls, equals(['tg://resolve?domain=test']));

      final pref = await ExternalAppPreferenceStore.instance.decisionFor('scheme:tg');
      expect(pref, equals(ExternalAppDecision.ask));
    });

    test('alwaysOpen launches app and saves preference', () async {
      externalAppPromptHandler = ({
        required uri,
        required appKey,
        required displayName,
        pageHost,
      }) async {
        return ExternalAppPromptResult.alwaysOpen;
      };

      final uri = Uri.parse('tg://resolve?domain=test');
      final handled = await handleExternalAppUri(uri);
      expect(handled, isTrue);
      expect(launchedUrls, equals(['tg://resolve?domain=test']));

      final pref = await ExternalAppPreferenceStore.instance.decisionFor('scheme:tg');
      expect(pref, equals(ExternalAppDecision.alwaysAllow));

      // Subsequent call does not prompt and launches directly
      launchedUrls.clear();
      externalAppPromptHandler = null; // null handler, but saved pref allows it
      final handled2 = await handleExternalAppUri(uri);
      expect(handled2, isTrue);
      expect(launchedUrls, equals(['tg://resolve?domain=test']));
    });

    test('denyOnce blocks launch without saving preference', () async {
      externalAppPromptHandler = ({
        required uri,
        required appKey,
        required displayName,
        pageHost,
      }) async {
        return ExternalAppPromptResult.denyOnce;
      };

      final uri = Uri.parse('whatsapp://send?phone=123');
      final handled = await handleExternalAppUri(uri);
      expect(handled, isTrue);
      expect(launchedUrls, isEmpty);

      final pref = await ExternalAppPreferenceStore.instance.decisionFor('scheme:whatsapp');
      expect(pref, equals(ExternalAppDecision.ask));
    });

    test('alwaysDeny blocks launch and saves deny preference', () async {
      externalAppPromptHandler = ({
        required uri,
        required appKey,
        required displayName,
        pageHost,
      }) async {
        return ExternalAppPromptResult.alwaysDeny;
      };

      final uri = Uri.parse('whatsapp://send?phone=123');
      final handled = await handleExternalAppUri(uri);
      expect(handled, isTrue);
      expect(launchedUrls, isEmpty);

      final pref = await ExternalAppPreferenceStore.instance.decisionFor('scheme:whatsapp');
      expect(pref, equals(ExternalAppDecision.alwaysDeny));

      // Subsequent call does not prompt and blocks directly
      externalAppPromptHandler = null;
      final handled2 = await handleExternalAppUri(uri);
      expect(handled2, isTrue);
      expect(launchedUrls, isEmpty);
    });
  });
}
