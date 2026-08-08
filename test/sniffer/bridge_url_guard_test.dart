import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/bridge_url_guard.dart';

void main() {
  const publicPage = 'https://example.com/watch/1';
  const lanPage = 'http://192.168.1.50:8096/web/index.html';

  group('isAllowedBridgeUrl — scheme handling', () {
    test('allows http and https media on a public page', () {
      expect(
        isAllowedBridgeUrl('https://cdn.example.com/a.m3u8', pageUrl: publicPage),
        isTrue,
      );
      expect(
        isAllowedBridgeUrl('http://cdn.example.com/a.mp4', pageUrl: publicPage),
        isTrue,
      );
    });

    test('rejects file:, content:, data:, blob:, javascript:, intent:', () {
      for (final url in [
        'file:///data/data/com.personal.aurora_downloader/shared_prefs/x.xml',
        'file:///etc/hosts',
        'content://media/external/video/media/42',
        'data:text/html;base64,PHNjcmlwdD4=',
        'blob:https://example.com/1234',
        'javascript:alert(1)',
        'intent://scan/#Intent;scheme=zxing;end',
      ]) {
        expect(
          isAllowedBridgeUrl(url, pageUrl: publicPage),
          isFalse,
          reason: 'should reject $url',
        );
      }
    });

    test('rejects relative, empty, and hostless input', () {
      for (final url in ['', '   ', '/relative/path.mp4', 'not a url', 'https://']) {
        expect(
          isAllowedBridgeUrl(url, pageUrl: publicPage),
          isFalse,
          reason: 'should reject "$url"',
        );
      }
    });
  });

  group('isAllowedBridgeUrl — remote page cannot pivot to private hosts', () {
    test('blocks RFC1918, loopback, and link-local targets', () {
      for (final url in [
        'http://192.168.1.1/admin',
        'http://10.0.0.1/',
        'http://172.16.0.1/',
        'http://172.31.255.254/',
        'http://127.0.0.1:8080/v1/tasks',
        'http://localhost:8080/v1/status',
        'http://169.254.169.254/latest/meta-data/',
        'http://0.0.0.0/',
        'http://router.local/',
        'http://nas.internal/',
        'http://[::1]/',
      ]) {
        expect(
          isAllowedBridgeUrl(url, pageUrl: publicPage),
          isFalse,
          reason: 'remote page should not reach $url',
        );
      }
    });

    test('172.15 and 172.32 are public — the /12 boundary is respected', () {
      expect(isAllowedBridgeUrl('http://172.15.0.1/', pageUrl: publicPage), isTrue);
      expect(isAllowedBridgeUrl('http://172.32.0.1/', pageUrl: publicPage), isTrue);
    });

    test('a normal domain that merely looks numeric is not treated as private', () {
      expect(
        isAllowedBridgeUrl('https://192.168.1.1.example.com/a.mp4', pageUrl: publicPage),
        isTrue,
      );
    });
  });

  group('isAllowedBridgeUrl — LAN browsing still works', () {
    test('a private page may sniff media from its own private network', () {
      expect(
        isAllowedBridgeUrl('http://192.168.1.50:8096/stream.m3u8', pageUrl: lanPage),
        isTrue,
      );
      expect(
        isAllowedBridgeUrl('http://192.168.1.99/other.mp4', pageUrl: lanPage),
        isTrue,
      );
    });

    test('a private page may still reference public media', () {
      expect(
        isAllowedBridgeUrl('https://cdn.example.com/a.mp4', pageUrl: lanPage),
        isTrue,
      );
    });

    test('a private page still cannot use a non-http scheme', () {
      expect(isAllowedBridgeUrl('file:///etc/hosts', pageUrl: lanPage), isFalse);
    });

    test('unparseable page URL denies a private target', () {
      expect(
        isAllowedBridgeUrl('http://192.168.1.50/a.mp4', pageUrl: 'about:blank'),
        isFalse,
      );
      expect(
        isAllowedBridgeUrl('http://192.168.1.50/a.mp4', pageUrl: ''),
        isFalse,
      );
    });
  });

  group('isPrivateHost', () {
    test('classifies IPv4 ranges', () {
      expect(isPrivateHost('10.1.2.3'), isTrue);
      expect(isPrivateHost('192.168.0.1'), isTrue);
      expect(isPrivateHost('127.0.0.1'), isTrue);
      expect(isPrivateHost('100.64.0.1'), isTrue); // CGNAT
      expect(isPrivateHost('224.0.0.1'), isTrue); // multicast
      expect(isPrivateHost('8.8.8.8'), isFalse);
      expect(isPrivateHost('1.1.1.1'), isFalse);
    });

    test('classifies IPv6 forms', () {
      expect(isPrivateHost('::1'), isTrue);
      expect(isPrivateHost('fe80::1'), isTrue);
      expect(isPrivateHost('fd00::1'), isTrue);
      expect(isPrivateHost('::ffff:192.168.1.1'), isTrue);
      expect(isPrivateHost('2606:4700:4700::1111'), isFalse);
    });

    test('classifies local hostname suffixes', () {
      expect(isPrivateHost('localhost'), isTrue);
      expect(isPrivateHost('printer.local'), isTrue);
      expect(isPrivateHost('db.internal'), isTrue);
      expect(isPrivateHost('example.com'), isFalse);
    });

    test('empty host is treated as private (fail closed)', () {
      expect(isPrivateHost(''), isTrue);
      expect(isPrivateHost('   '), isTrue);
    });

    test('malformed IPv4 literals fall through to domain handling', () {
      expect(isPrivateHost('192.168.1'), isFalse);
      expect(isPrivateHost('192.168.1.999'), isFalse);
      expect(isPrivateHost('10.0.0.1.5'), isFalse);
    });
  });
}
