import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/sniffer_screen.dart';

void main() {
  group('SnifferScreen menu entry key normalization', () {
    test('normalizes Stealth Mode dynamic labels persistently', () {
      expect(SnifferScreen.normalizeMenuEntryKey('Stealth Mode: On'), equals('Stealth Mode'));
      expect(SnifferScreen.normalizeMenuEntryKey('Stealth Mode: Off'), equals('Stealth Mode'));
    });

    test('normalizes Incognito dynamic labels persistently', () {
      expect(SnifferScreen.normalizeMenuEntryKey('Incognito: On'), equals('Incognito'));
      expect(SnifferScreen.normalizeMenuEntryKey('Incognito: Off'), equals('Incognito'));
    });

    test('normalizes Adblock dynamic labels persistently', () {
      expect(SnifferScreen.normalizeMenuEntryKey('Adblock: On'), equals('Adblock'));
      expect(SnifferScreen.normalizeMenuEntryKey('Adblock: Off'), equals('Adblock'));
      expect(SnifferScreen.normalizeMenuEntryKey('Ads allowed'), equals('Adblock'));
    });

    test('returns exact label for non-dynamic tool entries', () {
      expect(SnifferScreen.normalizeMenuEntryKey('History'), equals('History'));
      expect(SnifferScreen.normalizeMenuEntryKey('Favorites'), equals('Favorites'));
      expect(SnifferScreen.normalizeMenuEntryKey('Open in Custom Tab'), equals('Open in Custom Tab'));
    });
  });
}
