import 'dart:math' as math;

import 'package:xpgn_reader/xpgn_reader.dart';

/// A game's analysed "feel" over time, ready for the sonifier to query.
///
/// Time is in sonifier seconds: second `t` shows position `t + 1`, because the
/// board shows move 1 at time 0. Values are interpolated between plies so
/// dynamics move smoothly instead of stepping once a second.
class GameFeel {
  /// One entry per ply, index 0 = the starting position.
  final List<PlyFeel> curve;

  /// PGN result: "1-0", "0-1", "1/2-1/2" or "*".
  final String result;

  /// Raw arousal at which the music reaches full intensity. Raw arousal rarely
  /// gets near 1.0, so this stretches the usable range. Calibrate it against
  /// the Arousal line in the viewer.
  final double arousalScale;

  GameFeel(this.curve, this.result, {this.arousalScale = 0.5});

  factory GameFeel.fromGame(
      XpgnGame game, {
        double arousalScale = 0.5,
        int smoothing = 3,
      }) {
    final curve = game.feel(window: smoothing);
    return GameFeel(
      curve.isEmpty ? const [PlyFeel(0, 0)] : curve,
      game.header('Result', '*'),
      arousalScale: arousalScale,
    );
  }

  int get lastPly => curve.length - 1;

  /// Intensity at time [t], normalised to 0..1.
  double arousalAt(double t) =>
      (_at(t, (f) => f.arousal) / arousalScale).clamp(0.0, 1.0).toDouble();

  /// -1 (Black better) .. +1 (White better) at time [t].
  double valenceAt(double t) => _at(t, (f) => f.valence);

  double _at(double t, double Function(PlyFeel) pick) {
    final x = (t + 1).clamp(0.0, lastPly.toDouble()).toDouble();
    final i = x.floor();
    final j = math.min(i + 1, lastPly);
    final f = x - i;
    return pick(curve[i]) * (1 - f) + pick(curve[j]) * f;
  }
}

/// Stable per-game seed from its moves, so the same game always sounds the
/// same. Kept below 2^31 so the arithmetic is identical on web, where Dart
/// ints are doubles.
int gameSeed(Iterable<String> moves) {
  var h = 17;
  for (final m in moves) {
    for (final c in m.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
  }
  return h;
}
