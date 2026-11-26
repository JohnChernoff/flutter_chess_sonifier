import 'dart:math';
import 'chess_sonifier.dart' show SonNote, TrackType;

class MelodyStep {
  final int interval;   // semitones from the previous pitch (0 for rests)
  final double dur;     // seconds
  final bool rest;
  const MelodyStep(this.interval, this.dur, {this.rest = false});
}

class EvolveConfig {
  final int lo, hi;            // pitch range a melody must stay within
  final int window;            // degenerate if the last [window] intervals are all identical
  final double splitEvery;     // duplicate a melody each time it grows this many seconds
  final int maxPool;           // stop splitting once the pool reaches this size
  final int maxRounds;         // safety stop
  const EvolveConfig({
    this.lo = 48,
    this.hi = 84,
    this.window = 8,
    this.splitEvery = 8.0,
    this.maxPool = 64,
    this.maxRounds = 5000,
  }) : assert(window >= 2);
}

class Melody {
  final int startPitch;
  final List<MelodyStep> steps;
  int pitch;
  double length;
  double nextSplitAt;

  Melody._(this.startPitch, this.steps, this.pitch, this.length, this.nextSplitAt);

  factory Melody.fromSteps(int startPitch, List<MelodyStep> steps, double splitEvery) {
    var p = startPitch;
    var len = 0.0;
    for (final s in steps) {
      if (!s.rest) p += s.interval;
      len += s.dur;
    }
    return Melody._(startPitch, List.of(steps), p, len, len + splitEvery);
  }

  Melody clone() => Melody._(startPitch, List.of(steps), pitch, length, nextSplitAt);

  /// Appends [s] only if the result is still viable; otherwise leaves the
  /// melody untouched (so a "dead" melody keeps its last valid state).
  bool tryAdd(MelodyStep s, EvolveConfig cfg) {
    final newPitch = s.rest ? pitch : pitch + s.interval;
    if (newPitch < cfg.lo || newPitch > cfg.hi) return false;
    if (!s.rest && _collapsed(s.interval, cfg.window)) return false;
    steps.add(s);
    pitch = newPitch;
    length += s.dur;
    return true;
  }

  /// True if the last [window] pitched intervals (including [latest]) are all the same.
  bool _collapsed(int latest, int window) {
    final seen = <int>{latest};
    var n = 1;
    for (var i = steps.length - 1; i >= 0 && n < window; i--) {
      if (steps[i].rest) continue;
      seen.add(steps[i].interval);
      n++;
    }
    return n == window && seen.length < 2;
  }
}

/// A short random seed melody: small steps favoured, some rests.
List<MelodyStep> randomSeed(Random rnd, {int length = 12}) {
  const intervals = [-5,-4, -3, -2, -2, -1, -1, -1, 1, 1, 1, 2, 2, 3, 4,5];
  const durs = [.125,.25, .5, .5, 1.0];
  return [
    for (var i = 0; i < length; i++)
      rnd.nextDouble() < .15
          ? MelodyStep(0, durs[rnd.nextInt(durs.length)], rest: true)
          : MelodyStep(intervals[rnd.nextInt(intervals.length)],
          durs[rnd.nextInt(durs.length)]),
  ];
}

/// Beethoven, "Ode to Joy" theme in C major (the full 4-phrase tune, ~32 s at beat = .5).
List<MelodyStep> odeToJoy({double beat = .5}) {
  const c = 60, d = 62, e = 64, f = 65, g = 67, gLow = 55;
  final head = [for (final p in [e, e, f, g, g, f, e, d, c, c, d, e]) (p, 1.0)];

  final notes = <(int, double)>[
    ...head, (e, 1.5), (d, .5), (d, 2.0),          // phrase 1
    ...head, (d, 1.5), (c, .5), (c, 2.0),          // phrase 2
    (d, 1.0), (d, 1.0), (e, 1.0), (c, 1.0),        // bridge
    (d, 1.0), (e, .5), (f, .5), (e, 1.0), (c, 1.0),
    (d, 1.0), (e, .5), (f, .5), (e, 1.0), (d, 1.0),
    (c, 1.0), (d, 1.0), (gLow, 2.0),
    ...head, (d, 1.5), (c, .5), (c, 2.0),          // phrase 4 = phrase 2
  ];
  return stepsFromNotes(notes, beat: beat);
}

/// "Happy Birthday" melody in C major, 3/4 (beats are quarter notes).
List<MelodyStep> happyBirthday({double beat = .5}) {
  const g = 67, a = 69, b = 71, c = 72, d = 74, e = 76, f = 77, gHi = 79;

  final notes = <(int, double)>[
    (g, .75), (g, .25), (a, 1.0), (g, 1.0), (c, 1.0), (b, 3.0),      // phrase 1
    (g, .75), (g, .25), (a, 1.0), (g, 1.0), (d, 1.0), (c, 3.0),      // phrase 2
    (g, .75), (g, .25), (gHi, 1.0), (e, 1.0), (c, 1.0), (b, 1.0), (a, 2.0),  // phrase 3
    (f, .75), (f, .25), (e, 1.0), (c, 1.0), (d, 1.0), (c, 3.0),      // phrase 4
  ];
  return stepsFromNotes(notes, beat: beat);
}

/// (MIDI pitch, beats) pairs -> steps. The first step's interval is 0, so
/// pass the first note's pitch as startPitch. One beat = [beat] seconds.
List<MelodyStep> stepsFromNotes(List<(int, double)> notes, {double beat = .5}) {
  final steps = <MelodyStep>[];
  var prev = notes.first.$1;
  for (final (p, b) in notes) {
    steps.add(MelodyStep(p - prev, b * beat));
    prev = p;
  }
  return steps;
}

Melody evolveMelody(
    List<MelodyStep> original, {
      int startPitch = 66,
      int copies = 8,
      EvolveConfig cfg = const EvolveConfig(),
      Random? random,
    }) {
  final rnd = random ?? Random();

  // Weighted sampling = picking uniformly from the original's own lists,
  // so frequent intervals and durations are drawn proportionally more often.
  final intervals = [for (final s in original) if (!s.rest) s.interval];
  final durs = [for (final s in original) s.dur];
  final restFraction = original.where((s) => s.rest).length / original.length;

  MelodyStep draw() {
    final dur = durs[rnd.nextInt(durs.length)];
    if (rnd.nextDouble() < restFraction) return MelodyStep(0, dur, rest: true);
    return MelodyStep(intervals[rnd.nextInt(intervals.length)], dur);
  }

  var pool = [
    for (var i = 0; i < copies; i++)
      Melody.fromSteps(startPitch, original, cfg.splitEvery),
  ];
  var growing = true;

  for (var round = 0; round < cfg.maxRounds; round++) {
    final next = <Melody>[];
    for (final m in pool) {
      if (!m.tryAdd(draw(), cfg)) continue;        // out of range or degenerate: removed
      next.add(m);
      if (growing && m.length >= m.nextSplitAt) {
        m.nextSplitAt += cfg.splitEvery;           // set first, so the clone inherits it
        next.add(m.clone());
      }
    }

    if (next.length >= cfg.maxPool) growing = false;   // attrition only from here on
    if (next.isEmpty) return _longest(pool);           // last ones died together: use previous round
    if (next.length == 1) return next.first;
    pool = next;
  }
  return _longest(pool);
}

Melody _longest(List<Melody> ms) =>
    ms.reduce((a, b) => a.length >= b.length ? a : b);

List<SonNote> melodyToNotes(Melody m,
    {TrackType track = TrackType.melody1, int velocity = 50}) {
  final notes = <SonNote>[];
  var t = 0.0;
  var p = m.startPitch;
  for (final s in m.steps) {
    if (!s.rest) {
      p += s.interval;
      notes.add(SonNote(track, p, velocity, t, s.dur));
    }
    t += s.dur;
  }
  return notes;
}
