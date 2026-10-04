import 'package:aurora_downloader/sniffer/known_sites_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lookupKnownSite', () {
    test('matches every host captured in the 2026-09 failure report', () {
      expect(lookupKnownSite('https://open.stealth.si/')?.hostSuffix, 'open.stealth.si');
      expect(
        lookupKnownSite('https://vd687.okcdn.ru/video/abc.m3u8?tkn=x')?.hostSuffix,
        'okcdn.ru',
      );
      expect(
        lookupKnownSite(
          'https://ugc-cdn-caching-n3dykgb0psbvigeweq.cloudwindow-route.com/a.ts',
        )?.hostSuffix,
        'cloudwindow-route.com',
      );
      expect(lookupKnownSite('https://str-15.filestore.app/f/1')?.hostSuffix, 'filestore.app');
      expect(lookupKnownSite('https://search.app.goo.gl/abc')?.hostSuffix, 'goo.gl');
      expect(lookupKnownSite('https://webtor.io/')?.hostSuffix, 'webtor.io');
      expect(lookupKnownSite('https://www.limetorrents.fun/x')?.hostSuffix, 'limetorrents.fun');
    });

    test('healthy hosts match nothing', () {
      expect(lookupKnownSite('https://archive.org/'), isNull);
      expect(lookupKnownSite('https://cdn.example.com/f.mp4'), isNull);
      expect(lookupKnownSite(''), isNull);
    });

    test('suffix matching does not leak past a label boundary', () {
      expect(lookupKnownSite('https://evil-okcdn.ru.example.com/'), isNull);
      expect(lookupKnownSite('https://notfilestore.app/'), isNull);
    });

    test('accepts bare hosts as well as URLs', () {
      expect(lookupKnownSite('str-15.filestore.app')?.hostSuffix, 'filestore.app');
      expect(lookupKnownSite('vd687.okcdn.ru/path/x')?.hostSuffix, 'okcdn.ru');
    });

    test('prefers the longest (most specific) suffix', () {
      // okcdn.ru entry must win over any broader entry if one is ever added.
      final hit = lookupKnownSite('https://vd687.okcdn.ru/x');
      expect(hit?.behaviors.contains('refreshOnExpire'), isTrue);
    });

    test('dead-TLS host is flagged as a warning, CDN timeouts as info', () {
      expect(lookupKnownSite('https://open.stealth.si')?.severity, SiteWarning.warning);
      expect(
        lookupKnownSite('https://ugc-cdn-caching-x.cloudwindow-route.com')?.severity,
        SiteWarning.info,
      );
    });
  });
}
