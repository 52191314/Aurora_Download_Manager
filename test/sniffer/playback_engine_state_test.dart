import 'package:flutter/widgets.dart';
// `fail` is hidden because PlaybackEngineBase has a method of the same name,
// and the top-level matcher shadows it inside the fake below — calling it
// would abort the test instead of failing the stream.
import 'package:flutter_test/flutter_test.dart' hide fail;

import 'package:aurora_downloader/sniffer/player/playback_engine.dart';
import 'package:aurora_downloader/sniffer/player/playback_source.dart';
import 'package:aurora_downloader/sniffer/player/playback_state.dart';

/// Exercises [PlaybackEngineBase] without a decoder. The stall watchdog and the
/// recovery path are the logic that turned a silent black screen into a
/// reportable state, so they are worth pinning down.
class _FakeEngine extends PlaybackEngineBase {
  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.videoPlayer;

  @override
  Future<void> open(PlaybackSource source) async {
    currentSource = source;
    emit(const PlaybackState(status: PlaybackStatus.ready));
    armStallWatchdog();
  }

  /// Test hooks onto the protected surface.
  void becomeBuffering(bool v) =>
      update((s) => s.copyWith(isBuffering: v));
  void advanceTo(Duration d) => notePosition(d);
  void failWith(String m) => fail(m);
  void setDuration(Duration d) => update((s) => s.copyWith(duration: d));
  void setSize(Size s) => update((st) => st.copyWith(videoSize: s));

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Widget buildSurface({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.shrink();
}

PlaybackSource _source() => const PlaybackSource(
      url: 'https://cdn.example.com/stream.m3u8',
      title: 'Test',
      headers: {'Referer': 'https://example.com/', 'Cookie': 'sid=secret'},
    );

void main() {
  group('stall watchdog', () {
    test('marks a stream stalled when it opens and never advances', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      expect(engine.value.status, PlaybackStatus.ready);

      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
      expect(engine.value.status, PlaybackStatus.stalled);
      await engine.dispose();
    });

    test('does not fire while the stream is buffering', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      engine.becomeBuffering(true);

      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
      expect(engine.value.status, PlaybackStatus.ready);
      await engine.dispose();
    });

    test('does not fire once the clock has advanced', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      engine.advanceTo(const Duration(seconds: 1));

      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
      expect(engine.value.status, PlaybackStatus.ready);
      expect(engine.value.everAdvanced, isTrue);
      await engine.dispose();
    });

    test('does not resurrect a stream that already failed', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      engine.failWith('403');

      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
      expect(engine.value.status, PlaybackStatus.failed);
      await engine.dispose();
    });

    test('does not fire after dispose', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      await engine.dispose();
      // The assertion is that no ValueNotifier-after-dispose error is thrown.
      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
    });
  });

  group('recovery', () {
    test('a stalled stream that starts moving returns to ready', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );
      expect(engine.value.status, PlaybackStatus.stalled);

      engine.advanceTo(const Duration(milliseconds: 400));
      expect(engine.value.status, PlaybackStatus.ready);
      expect(engine.value.everAdvanced, isTrue);
      await engine.dispose();
    });

    test('a zero position does not clear a stall', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      await Future<void>.delayed(
        PlaybackEngineBase.stallTimeout + const Duration(milliseconds: 250),
      );

      engine.advanceTo(Duration.zero);
      expect(engine.value.status, PlaybackStatus.stalled);
      await engine.dispose();
    });
  });

  group('failure', () {
    test('records the message and clears playing/buffering', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      engine.becomeBuffering(true);
      engine.failWith('The server refused this stream (403).');

      expect(engine.value.status, PlaybackStatus.failed);
      expect(engine.value.errorMessage, contains('403'));
      expect(engine.value.isBuffering, isFalse);
      expect(engine.value.isPlaying, isFalse);
      await engine.dispose();
    });
  });

  group('diagnostics', () {
    test('never leaks header values, only names', () async {
      final engine = _FakeEngine();
      await engine.open(_source());

      final diag = engine.diagnostics();
      final dump = diag.toString();
      expect(dump, contains('Referer'));
      expect(dump, contains('Cookie'));
      // The whole point: names are diagnostic, values are session secrets.
      expect(dump, isNot(contains('sid=secret')));
      await engine.dispose();
    });

    test('reports live streams as such rather than 0:00', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      expect(engine.diagnostics()['duration'], 'live/unknown');

      engine.setDuration(const Duration(minutes: 3, seconds: 4));
      expect(engine.diagnostics()['duration'], '3:04');
      await engine.dispose();
    });

    test('reports video size only once a track is known', () async {
      final engine = _FakeEngine();
      await engine.open(_source());
      expect(engine.diagnostics()['videoSize'], 'none');

      engine.setSize(const Size(1920, 1080));
      expect(engine.diagnostics()['videoSize'], '1920x1080');
      await engine.dispose();
    });
  });

  group('PlaybackState', () {
    test('falls back to 16:9 before a frame reports dimensions', () {
      const s = PlaybackState();
      expect(s.hasVideoTrack, isFalse);
      expect(s.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('treats a zero duration as live', () {
      const s = PlaybackState();
      expect(s.isLive, isTrue);
      expect(
        const PlaybackState(duration: Duration(minutes: 1)).isLive,
        isFalse,
      );
    });

    test('shows the surface while stalled so a recovering frame is not hidden',
        () {
      const stalled = PlaybackState(status: PlaybackStatus.stalled);
      expect(stalled.canShowSurface, isTrue);
      expect(
        const PlaybackState(status: PlaybackStatus.opening).canShowSurface,
        isFalse,
      );
    });

    test('clearError removes the message rather than preserving it', () {
      const s = PlaybackState(errorMessage: 'boom');
      expect(s.copyWith(clearError: true).errorMessage, isNull);
      expect(s.copyWith().errorMessage, 'boom');
    });
  });
}
