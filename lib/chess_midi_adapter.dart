/// Bridges [ChessSonifier] output to the zug_music playback classes
/// (MidiTrack / MidiEvent / MidiSequencer / MidiManager).
///
/// The instruments below are General MIDI stand-ins chosen by name for the
/// Reaper patches of the Java version; swap them freely.
library;

import 'package:zug_music/sequencer.dart';
import 'package:zug_music/zug_midi.dart';
import 'chess_sonifier.dart';

/// Replaces the Java `Ensemble` enum: voice ranges plus instruments.
class EnsemblePreset {
  final String name;

  /// One entry per melodic voice (melody1..melody4); [melody] must be the same
  /// length as [voices].
  final List<VoiceSpec> voices;
  final List<MidiInstrument> melody;
  final MidiInstrument rhythm, capture, check;

  const EnsemblePreset({
    required this.name,
    required this.voices,
    required this.melody,
    required this.rhythm,
    required this.capture,
    required this.check,
  });

  /// clarinet / cello / horn / tuba (the old otpc_bbc1 ranges).
  static const orchestra = EnsemblePreset(
    name: 'orchestra',
    voices: [VoiceSpec(60, 52, 88), VoiceSpec(48, 36, 76), VoiceSpec(60, 48, 72), VoiceSpec(36, 24, 66)],
    melody: [MidiInstrument.clarinet, MidiInstrument.cello, MidiInstrument.frenchHorn, MidiInstrument.tuba],
    rhythm: MidiInstrument.pizzStrings,
    capture: MidiInstrument.vibraphone,
    check: MidiInstrument.tubularBells,
  );

  /// Four wide-range synth voices (the old otpc_synth1/2 ranges).
  static const synth = EnsemblePreset(
    name: 'synth',
    voices: [VoiceSpec(60, 24, 108), VoiceSpec(60, 24, 108), VoiceSpec(60, 24, 108), VoiceSpec(60, 24, 108)],
    melody: [
      MidiInstrument.lead2Sawtooth,
      MidiInstrument.lead1Square,
      MidiInstrument.pad3Polysynth,
      MidiInstrument.lead6Voice,
    ],
    rhythm: MidiInstrument.electricPiano1,
    capture: MidiInstrument.marimba,
    check: MidiInstrument.tubularBells,
  );

  MidiInstrument instrumentFor(TrackType track) {
    final i = track.index;
    if (i < melody.length) return melody[i];
    return switch (track) {
      TrackType.capture => capture,
      TrackType.check => check,
      _ => rhythm, // rhythm1 and the (unused) harmony track
    };
  }

  /// Everything the MidiManager has to load before playback.
  List<MidiAssignment> get assignments => [
        for (final t in TrackType.values)
          if (t != TrackType.harmony && (t.index >= 4 || t.index < melody.length))
            MidiAssignment(t.name, instrumentFor(t), defLevel: .5),
      ];
}

/// One [MidiTrack] per sonifier track that actually has notes, in track order.
/// Velocity (0-127) becomes the event volume (0-1).
List<MidiTrack> buildMidiTracks(List<SonNote> notes, EnsemblePreset preset) {
  final tracks = <TrackType, MidiTrack>{};
  final instruments = <TrackType, Instrument>{};
  for (final n in notes) {
    final track = tracks.putIfAbsent(n.track, () => MidiTrack(n.track.name));
    final inst = instruments.putIfAbsent(
        n.track, () => Instrument(iPatch: preset.instrumentFor(n.track), level: .5));
    track.events.add(MidiEvent(inst, n.pitch, n.start, n.duration, volume: n.velocity / 127));
  }
  for (final t in tracks.values) {
    t.events.sort(); // once, rather than addMidiEvent's sort on every note
  }
  return [for (final t in TrackType.values) if (tracks[t] != null) tracks[t]!];
}
