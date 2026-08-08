import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/controllers/site_profile_matcher.dart';
import 'package:aurora_downloader/sniffer/models/site_profile.dart';

void main() {
  SiteProfile _profile({
    required String name,
    required String hostPattern,
    bool enabled = true,
  }) {
    return SiteProfile(
      id: name,
      name: name,
      hostPattern: hostPattern,
      enabled: enabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  group('findMatchingProfile', () {
    test('exact host match', () {
      final profiles = [
        _profile(name: 'Example', hostPattern: 'example.com'),
      ];
      final result = findMatchingProfile('https://example.com/page', profiles);
      expect(result, isNotNull);
      expect(result!.name, 'Example');
    });

    test('wildcard subdomain match (*.example.com)', () {
      final profiles = [
        _profile(name: 'Wildcard', hostPattern: '*.example.com'),
      ];
      expect(
        findMatchingProfile('https://sub.example.com/page', profiles)?.name,
        'Wildcard',
      );
      expect(
        findMatchingProfile('https://deep.sub.example.com/page', profiles)
            ?.name,
        'Wildcard',
      );
    });

    test('wildcard does NOT match bare domain', () {
      final profiles = [
        _profile(name: 'Wildcard', hostPattern: '*.example.com'),
      ];
      expect(
        findMatchingProfile('https://example.com/page', profiles),
        isNull,
      );
    });

    test('disabled profiles are skipped', () {
      final profiles = [
        _profile(
          name: 'Disabled',
          hostPattern: 'example.com',
          enabled: false,
        ),
      ];
      expect(
        findMatchingProfile('https://example.com/page', profiles),
        isNull,
      );
    });

    test('first enabled match wins (order)', () {
      final profiles = [
        _profile(name: 'First', hostPattern: '*.example.com'),
        _profile(name: 'Second', hostPattern: '*.example.com'),
      ];
      final result =
          findMatchingProfile('https://sub.example.com/page', profiles);
      expect(result, isNotNull);
      expect(result!.name, 'First');
    });

    test('literal IP returns null', () {
      final profiles = [
        _profile(name: 'IP', hostPattern: '192.168.1.1'),
      ];
      expect(
        findMatchingProfile('http://192.168.1.1/', profiles),
        isNull,
      );
    });

    test('non-HTTP URL returns null', () {
      final profiles = [
        _profile(name: 'Any', hostPattern: '*'),
      ];
      expect(
        findMatchingProfile('file:///path/to/file', profiles),
        isNull,
      );
    });

    test('no match returns null', () {
      final profiles = [
        _profile(name: 'Foo', hostPattern: 'foo.com'),
      ];
      expect(
        findMatchingProfile('https://bar.com/page', profiles),
        isNull,
      );
    });

    test('empty profiles list returns null', () {
      expect(
        findMatchingProfile('https://example.com', []),
        isNull,
      );
    });

    test('case-insensitive matching', () {
      final profiles = [
        _profile(name: 'Case', hostPattern: 'Example.COM'),
      ];
      expect(
        findMatchingProfile('https://EXAMPLE.com/page', profiles)?.name,
        'Case',
      );
    });

    test('whitespace in pattern is trimmed', () {
      final profiles = [
        _profile(name: 'Space', hostPattern: '  example.com  '),
      ];
      expect(
        findMatchingProfile('https://example.com/page', profiles)?.name,
        'Space',
      );
    });

    test('empty pattern after wildcard returns null', () {
      final profiles = [
        _profile(name: 'Bad', hostPattern: '*.'),
      ];
      expect(
        findMatchingProfile('https://example.com/page', profiles),
        isNull,
      );
    });
  });
}
