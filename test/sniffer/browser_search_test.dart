import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/browser_search.dart';
import 'package:aurora_downloader/settings/download_settings.dart';

void main() {
  group('BrowserSearch URI resolution and malformed input resilience', () {
    const engine = SearchEngine.google;

    test('resolves standard http and https URLs', () {
      final u1 = BrowserSearch.resolveInput('https://flutter.dev', engine);
      expect(u1.scheme, equals('https'));
      expect(u1.host, equals('flutter.dev'));

      final u2 = BrowserSearch.resolveInput('http://example.com/test?a=1', engine);
      expect(u2.scheme, equals('http'));
      expect(u2.host, equals('example.com'));
      expect(u2.queryParameters['a'], equals('1'));
    });

    test('resolves domain-like input to https', () {
      final u = BrowserSearch.resolveInput('github.com', engine);
      expect(u.scheme, equals('https'));
      expect(u.host, equals('github.com'));
    });

    test('resolves search query with spaces to search engine URL', () {
      final u = BrowserSearch.resolveInput('flutter best practices', engine);
      expect(u.host, equals('www.google.com'));
      expect(u.queryParameters['q'], equals('flutter best practices'));
    });

    test('handles empty or whitespace-only input safely', () {
      final u1 = BrowserSearch.resolveInput('', engine);
      expect(u1.host, equals('www.google.com'));

      final u2 = BrowserSearch.resolveInput('   ', engine);
      expect(u2.host, equals('www.google.com'));
    });

    test('does NOT throw FormatException on illegal scheme character (space before colon)', () {
      // "foo :bar" has a space before colon which causes Uri.parse to throw
      // FormatException: Illegal scheme character (at character 4).
      expect(
        () => BrowserSearch.resolveInput('foo :bar', engine),
        returnsNormally,
      );
      final u = BrowserSearch.resolveInput('foo :bar', engine);
      expect(u.host, equals('www.google.com'));
      expect(u.queryParameters['q'], equals('foo :bar'));
    });

    test('does NOT throw FormatException on IP address with port', () {
      // "192.168.1.1:8080" starts with digits before colon -> Scheme not starting with alphabetic character
      expect(
        () => BrowserSearch.resolveInput('192.168.1.1:8080', engine),
        returnsNormally,
      );
      final u = BrowserSearch.resolveInput('192.168.1.1:8080', engine);
      expect(u.host.isNotEmpty || u.path.isNotEmpty, isTrue);
    });

    test('does NOT throw FormatException on invalid port', () {
      expect(
        () => BrowserSearch.resolveInput('example.com:invalid', engine),
        returnsNormally,
      );
      final u = BrowserSearch.resolveInput('example.com:invalid', engine);
      expect(u.host, equals('www.google.com'));
    });

    test('does NOT throw FormatException on unmatched host brackets', () {
      expect(
        () => BrowserSearch.resolveInput('http://[invalid', engine),
        returnsNormally,
      );
      final u = BrowserSearch.resolveInput('http://[invalid', engine);
      expect(u, isNotNull);
    });

    test('preserves valid external app schemes', () {
      final magnet = BrowserSearch.resolveInput(
        'magnet:?xt=urn:btih:1234567890abcdef',
        engine,
      );
      expect(magnet.scheme, equals('magnet'));

      final tg = BrowserSearch.resolveInput('tg:resolve?domain=test', engine);
      expect(tg.scheme, equals('tg'));
    });

    test('BrowserSearch.safeResolve never throws and returns a valid Uri', () {
      final edgeCases = [
        'foo :bar',
        'site:something',
        '192.168.1.1:8080',
        'example.com:invalid',
        'http://[invalid',
        '   ',
        ':leading:colon:',
        '???',
        'https://valid.org/path',
      ];

      for (final input in edgeCases) {
        expect(
          () => BrowserSearch.safeResolve(input, engine),
          returnsNormally,
          reason: 'Failed on input: $input',
        );
        final uri = BrowserSearch.safeResolve(input, engine);
        expect(uri, isNotNull);
      }
    });
  });
}
