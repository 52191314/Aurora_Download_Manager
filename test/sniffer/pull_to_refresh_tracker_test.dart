import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/pull_to_refresh_tracker.dart';

void main() {
  group('PullToRefreshTracker', () {
    test('no overscroll never triggers', () {
      final t = PullToRefreshTracker();
      expect(t.onScroll(0, refreshing: false), isFalse);
      expect(t.onScroll(50, refreshing: false), isFalse);
      expect(t.pullDistance, 0);
    });

    test('pull below threshold does not trigger on release', () {
      final t = PullToRefreshTracker();
      t.onScroll(-10, refreshing: false);
      t.onScroll(-40, refreshing: false);
      expect(t.pullDistance, 40);
      expect(t.onScroll(0, refreshing: false), isFalse);
      expect(t.pullDistance, 0);
    });

    test('pull past threshold triggers exactly once on release', () {
      final t = PullToRefreshTracker();
      t.onScroll(-80, refreshing: false);
      t.onScroll(-130, refreshing: false);
      expect(t.onScroll(0, refreshing: false), isTrue);
      // Subsequent neutral scroll events must not re-fire.
      expect(t.onScroll(0, refreshing: false), isFalse);
      expect(t.onScroll(10, refreshing: false), isFalse);
    });

    test('deepest point wins (cumulative min, release via partial return)', () {
      final t = PullToRefreshTracker();
      t.onScroll(-150, refreshing: false);
      // Releasing gradually: intermediate negative values must not reset.
      t.onScroll(-90, refreshing: false);
      t.onScroll(-30, refreshing: false);
      expect(t.onScroll(0, refreshing: false), isTrue);
    });

    test('refreshing suppresses the trigger but still resets', () {
      final t = PullToRefreshTracker();
      t.onScroll(-140, refreshing: false);
      expect(t.onScroll(0, refreshing: true), isFalse);
      expect(t.pullDistance, 0);
      // A fresh pull after the refresh completes works again.
      t.onScroll(-140, refreshing: false);
      expect(t.onScroll(0, refreshing: false), isTrue);
    });

    test('pullDistance mirrors overscroll and resets on release', () {
      final t = PullToRefreshTracker();
      t.onScroll(-60, refreshing: false);
      expect(t.pullDistance, 60);
      t.onScroll(-10, refreshing: false);
      expect(t.pullDistance, 10);
      t.onScroll(0, refreshing: false);
      expect(t.pullDistance, 0);
    });
  });
}
