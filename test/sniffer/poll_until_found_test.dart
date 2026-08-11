import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/headless_resniffer.dart';

void main() {
  group('pollUntilFound', () {
    test('returns immediately when the first probe hits', () async {
      var probes = 0;
      final result = await pollUntilFound(
        () async {
          probes++;
          return ['https://x.example/a.m3u8'];
        },
        interval: const Duration(milliseconds: 10),
      );
      expect(result, ['https://x.example/a.m3u8']);
      expect(probes, 1);
    });

    test('polls until a hit appears (slow player)', () async {
      var probes = 0;
      final result = await pollUntilFound(
        () async {
          probes++;
          return probes >= 3 ? ['https://x.example/b.m3u8'] : null;
        },
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(seconds: 2),
      );
      expect(result, ['https://x.example/b.m3u8']);
      expect(probes, 3);
    });

    test('returns null when nothing appears before timeout', () async {
      final result = await pollUntilFound(
        () async => null,
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(milliseconds: 60),
      );
      expect(result, isNull);
    });

    test('wakeUp runs exactly once after the first empty probe', () async {
      var probes = 0;
      var wakes = 0;
      final result = await pollUntilFound(
        () async {
          probes++;
          return probes >= 2 ? ['https://x.example/c.m3u8'] : null;
        },
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(seconds: 2),
        wakeUp: () async {
          wakes++;
        },
      );
      expect(result, ['https://x.example/c.m3u8']);
      expect(wakes, 1);
    });

    test('wakeUp is not called when the first probe hits', () async {
      var wakes = 0;
      final result = await pollUntilFound(
        () async => ['https://x.example/d.m3u8'],
        interval: const Duration(milliseconds: 10),
        wakeUp: () async {
          wakes++;
        },
      );
      expect(result, ['https://x.example/d.m3u8']);
      expect(wakes, 0);
    });

    test('wakeUp result is probed on the next iteration (play-click path)',
        () async {
      // Simulates a click-to-play player: the wake triggers the playlist
      // fetch, which the probe sees on its next run.
      var probes = 0;
      var wakes = 0;
      final result = await pollUntilFound(
        () async {
          probes++;
          return wakes > 0 ? ['https://x.example/e.m3u8'] : null;
        },
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(seconds: 2),
        wakeUp: () async {
          wakes++;
        },
      );
      expect(result, ['https://x.example/e.m3u8']);
      expect(wakes, 1);
    });
  });
}
