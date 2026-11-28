import 'dart:math';
import 'dart:typed_data';

import 'package:zug_music/zug_midi.dart';

import 'chess_sonifier.dart';

/// General MIDI drum-kit note numbers for the drum tracks. The sonifier
/// itself plays every drum at pitch 60 through its own kit, so exporting
/// needs a real GM mapping to sound right in a DAW.
const _gmDrum = {
  TrackType.bass: 36,  // bass drum 1
  TrackType.cow: 56,   // cowbell
  TrackType.mid: 47,   // low-mid tom
  TrackType.snare: 38, // acoustic snare
};

/// GM program number for an instrument. ADJUST if MidiInstrument's enum
/// order isn't GM order (index 0 = Acoustic Grand Piano ... 127).
int defaultProgramOf(MidiInstrument i) => i.index % 128;

class _Ev {
  final int tick, order; // order: note-offs (0) sort before note-ons (1)
  final List<int> data;
  _Ev(this.tick, this.order, this.data);
}

void _vlq(List<int> out, int v) {
  final parts = <int>[v & 0x7f];
  while ((v >>= 7) > 0) {
    parts.add((v & 0x7f) | 0x80);
  }
  out.addAll(parts.reversed);
}

List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
List<int> _u16(int v) => [(v >> 8) & 255, v & 255];

List<int> _chunk(String type, List<int> body) =>
    [...type.codeUnits, ..._u32(body.length), ...body];

List<int> _trackChunk(String name, List<_Ev> events, {List<int> head = const []}) {
  events.sort((a, b) => a.tick != b.tick ? a.tick - b.tick : a.order - b.order);
  final body = <int>[0, 0xFF, 0x03, name.length, ...name.codeUnits, ...head];
  var last = 0;
  for (final e in events) {
    _vlq(body, e.tick - last);
    body.addAll(e.data);
    last = e.tick;
  }
  body.addAll([0, 0xFF, 0x2F, 0x00]);
  return _chunk('MTrk', body);
}

extension MidiExport on ChessSonifier {
  /// Standard MIDI File (format 1) of [notes]: one track per voice, drums on
  /// channel 10. Tempo is 60 bpm, so one ply is exactly one quarter note.
  Uint8List toMidiBytes({
    int ppq = 480,
    int Function(MidiInstrument)? programOf,
    bool includeDrums = true,
    String title = 'Chess Sonification',
  }) {
    endGame(); // flush any sustained melody note still pending
    programOf ??= defaultProgramOf;
    int tick(double s) => (s * ppq).round(); // 1 s == 1 beat at 60 bpm

    // Tempo + time signature live in a conductor track.
    final conductor = _trackChunk(title, [], head: [
      0, 0xFF, 0x51, 0x03, ..._u32(1000000).sublist(1), // 60 bpm
      0, 0xFF, 0x58, 0x04, 4, 2, 24, 8,                 // 4/4
    ]);

    final chunks = <List<int>>[conductor];
    var channel = 0;
    for (final t in TrackType.values) {
      if (t.drums && !includeDrums) continue;
      final ch = t.drums ? 9 : channel;
      final evs = <_Ev>[];
      if (!t.drums) {
        evs.add(_Ev(0, 0, [0xC0 | ch, programOf(instrumentFor(t)) & 127]));
      }
      var any = false;
      for (final n in notes.where((n) => n.track == t)) {
        if (n.velocity <= 0) continue;
        any = true;
        final pitch = t.drums ? _gmDrum[t]! : n.pitch.clamp(0, 127);
        final vel = n.velocity.clamp(1, 127);
        final on = tick(n.start);
        final off = max(on + 1, tick(n.end));
        evs.add(_Ev(on, 1, [0x90 | ch, pitch, vel]));
        evs.add(_Ev(off, 0, [0x80 | ch, pitch, 0]));
      }
      if (!t.drums) channel++;
      if (any) chunks.add(_trackChunk(t.name, evs));
    }

    return Uint8List.fromList([
      ..._chunk('MThd', [..._u16(1), ..._u16(chunks.length), ..._u16(ppq)]),
      for (final c in chunks) ...c,
    ]);
  }
}
