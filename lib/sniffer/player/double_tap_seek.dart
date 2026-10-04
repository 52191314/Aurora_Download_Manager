/// Consecutive double-tap skip used by YouTube / MX Player-style controls.
///
/// First tap on a side skips 10 seconds. Each further tap on the same side
/// within [window] doubles the jump: 10, 20, 40, then caps at [maxSeconds].
/// Switching sides or waiting out the window starts over at 10s.
class DoubleTapSeekCombo {
  DoubleTapSeekCombo({
    this.baseSeconds = 10,
    this.maxSeconds = 80,
    this.window = const Duration(milliseconds: 900),
  });

  final int baseSeconds;
  final int maxSeconds;
  final Duration window;

  int _combo = 0;
  int _sign = 0;
  DateTime? _lastAt;

  int get combo => _combo;

  /// Signed skip from the current position for this tap.
  Duration tap({required bool forward, DateTime? now}) {
    final t = now ?? DateTime.now();
    final sign = forward ? 1 : -1;
    final sameBurst = _lastAt != null &&
        sign == _sign &&
        t.difference(_lastAt!) < window;
    _combo = sameBurst ? _combo + 1 : 1;
    _sign = sign;
    _lastAt = t;
    final shift = _combo - 1;
    final mag = (baseSeconds << shift).clamp(baseSeconds, maxSeconds);
    return Duration(seconds: sign * mag);
  }

  void reset() {
    _combo = 0;
    _sign = 0;
    _lastAt = null;
  }
}
