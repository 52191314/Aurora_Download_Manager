import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/player/double_tap_seek.dart';

void main() {
  test('first tap on a side is 10 seconds', () {
    final c = DoubleTapSeekCombo();
    final t0 = DateTime.utc(2026, 1, 1);
    expect(c.tap(forward: true, now: t0), const Duration(seconds: 10));
    expect(
      c.tap(forward: false, now: t0),
      const Duration(seconds: -10),
    );
  });

  test('same-side taps inside the window double: 10, 20, 40, 80, 80', () {
    final c = DoubleTapSeekCombo();
    var t = DateTime.utc(2026, 1, 1);
    expect(c.tap(forward: true, now: t).inSeconds, 10);
    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: true, now: t).inSeconds, 20);
    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: true, now: t).inSeconds, 40);
    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: true, now: t).inSeconds, 80);
    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: true, now: t).inSeconds, 80);
  });

  test('switching sides or waiting out the window starts over at 10s', () {
    final c = DoubleTapSeekCombo();
    var t = DateTime.utc(2026, 1, 1);
    expect(c.tap(forward: true, now: t).inSeconds, 10);
    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: true, now: t).inSeconds, 20);

    expect(c.tap(forward: false, now: t).inSeconds, -10);

    t = t.add(const Duration(milliseconds: 400));
    expect(c.tap(forward: false, now: t).inSeconds, -20);

    t = t.add(const Duration(milliseconds: 901));
    expect(c.tap(forward: false, now: t).inSeconds, -10);
  });
}
