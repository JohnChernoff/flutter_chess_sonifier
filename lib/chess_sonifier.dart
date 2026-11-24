/// Chess game -> timed note events. A Dart port of GameSonifier.java.
///
/// Pure Dart (no Flutter, no chess library): the caller describes each move and
/// the position it was played from, and gets back [SonNote]s. Time is in
/// SECONDS and one ply is one second, which matches the video side (one move
/// animation == `frameRate` frames == one second), so audio and video stay in
/// sync without any tempo conversion.
library;

import 'dart:math';
import 'package:chess/chess.dart';
import 'package:zug_music/key.dart';
import 'package:zug_music/scale.dart';
import 'package:zug_music/sequencer.dart';
import 'package:zug_music/zug_midi.dart';
import 'package:zug_music/zug_music.dart';
import 'chess_midi_adapter.dart';

/// Same order as chesslib's PieceType (pawn = 0 ... king = 5).
//enum PieceKind { pawn, knight, bishop, rook, queen, king }

enum TrackType { melody1, melody2, melody3, melody4, rhythm1, harmony, capture, check }

enum RhythmType { chords, arp, loop }

enum MelodyStyle { distance, piece }

/// Starting pitch and range of one melodic voice (MIDI note numbers).
class VoiceSpec {
  final int start, minPitch, maxPitch;
  const VoiceSpec(this.start, this.minPitch, this.maxPitch);
}

/// One note. [velocity] is MIDI-style (0-127); times are in seconds.
class SonNote {
  final TrackType track;
  final int pitch;
  final int velocity;
  final double start;
  final double duration;
  const SonNote(this.track, this.pitch, this.velocity, this.start, this.duration);

  double get end => start + duration;

  @override
  String toString() =>
      '${track.name} p$pitch v$velocity @${start.toStringAsFixed(3)} +${duration.toStringAsFixed(3)}';
}

class _NoteRec {
  final ZugNote note;
  final PieceType piece;
  const _NoteRec(this.note, this.piece);
}

class ChessSonifier {

  final Map<TrackType, MidiInstrument> instrumentOverrides = {};
  late final mgr = MidiManager();
  late MidiSequencer _sqr;
  MidiSequencer get sequencer => _sqr;
  late final Future<void> ready;

  final Random _rnd;
  final List<ZugMelody> voices;

  /// Rhythm figures are laid down every [tempo] plies.
  double tempo;
  MelodyStyle style;

  /// Reflect melodies back into range instead of pinning them at the edge.
  bool bounce;

  /// Offsets (seconds, relative to the move's ply) of the capture and check
  /// cues. Both come straight from the Java version: the capture lands 1.5 s
  /// after the move starts, and the check cue is placed 1.5 s BEFORE the
  /// current ply, i.e. just ahead of the move that gave the check.
  double captureOffset = .15;
  double checkOffset = -.15;

  /// Note durations (in seconds) indexed by how far the move reached.
  final List<double> noteLengths = [.25, .25, .5, .5, 1, 1, 2, 2];

  ZugKey key = ZugKey(ZugNote.noteC, Scale.majorScale);
  RhythmType rhythmType = RhythmType.chords;

  /// Every note produced so far, in the order it was generated.
  final List<SonNote> notes = [];

  final List<_NoteRec> _noteList = [];
  int _noteLoopIndex = 0;
  int _currentSolo = 0;
  final Map<bool, int> _rankProgress = {true: 3, false: 3};

  int get currentSoloist => _currentSolo;

  /// End of the last note, in seconds.
  double get duration => notes.fold(0.0, (d, n) => max(d, n.end));

  EnsemblePreset preset;

  ChessSonifier({
    required this.preset,
    Random? random,
    this.tempo = 2,
    this.style = MelodyStyle.distance,
    this.bounce = false,
  })  : assert(preset.voices.isNotEmpty && preset.voices.length <= 4, 'melody1..melody4 only'),
        _rnd = random ?? Random(),
        voices = [
          for (final v in preset.voices) ZugMelody(v.start, minPitch: v.minPitch, maxPitch: v.maxPitch)
        ] {
    for (final v in voices) {
      v.reset(); // starts every voice in the middle of its range
    }
    _setRandomSoloist(true);
    ready = mgr.load(preset.assignments).then((_) {
      mgr.masterVolume = .5;
      mgr.muted = false;
      _sqr = MidiSequencer(mgr);
    });
  }

  void setMasterVolume(double volume) {
    mgr.masterVolume = volume.clamp(0.0, 1.0);
  }

  void startGame() {
    notes.clear();
    _noteList.clear();
    _noteLoopIndex = 0;
    _rankProgress[true] = 3;
    _rankProgress[false] = 3;
    key = ZugKey(ZugNote.noteC, Scale.majorScale);
    rhythmType = RhythmType.chords;
    for (final v in voices) { v.reset(); v.currentTick = 0; }
    _setRandomSoloist(true);
    _sqr.stop();
    _sqr.clearTracks();
  }

  /// Sonify one move. Call it with the position BEFORE the move is made.
  void sonifyMove(Move move, int ply, Chess board) {
    print("Sonifying: ${move.debug}");
    if (move.captured != null) {
      final pitch =
          key.getNextPitch(ZugPitch(48 + key.keyNote.index), move.captured!.interval).pitch;
      _add(TrackType.capture, pitch, 99, ply + captureOffset, 1);
    } else if (voices[_currentSolo].currentTick < ply - 4) {
      // The soloist has fallen well behind the game clock: pick a (possibly new) soloist and bring it up to date.
      _setRandomSoloist(true);
      voices[_currentSolo].currentTick = ply.toDouble();
    }

    _addMelody(move);

    if (board.in_check) {
      _add(TrackType.check, defMinPitch + move.to, 99, ply + checkOffset, 1);
    }

    if (ply % tempo == 0) {
      switch (rhythmType) {
        case RhythmType.chords:
          _addRhythmChords(board, ply, cross: true);
        case RhythmType.arp:
          _addArpeggio(board, ply, 4);
        case RhythmType.loop:
          _addNoteLoop(ply, 8, 4, straight: true);
      }
    }

    // A pawn reaching a new rank for its side changes key and rhythm.
    final rank = move.white ? move.toRank : 7 - move.toRank;
    if (move.piece == PieceType.PAWN && rank > _rankProgress[move.white]!) {
      _rankProgress[move.white] = rank;
      _newKey(move, ply);
      _setRandomRhythmType(false);
    }
  }

  // ---------------------------------------------------------------------
  // Choices
  // ---------------------------------------------------------------------
  void _setRandomSoloist(bool allowSame) {
    final prev = _currentSolo;
    do {
      _currentSolo = _rnd.nextInt(voices.length);
    } while (!allowSame && prev == _currentSolo && voices.length > 1);
  }

  void _setRandomRhythmType(bool allowSame) {
    final prev = rhythmType;
    do {
      rhythmType = RhythmType.values[_rnd.nextInt(RhythmType.values.length)];
    } while (!allowSame && prev == rhythmType);
  }

  // The Java used Scale.values()[ply % 3] (major, natural minor, blues). The
  // Dart Scale enum is ordered differently (index 2 is harmonic minor), so
  // the three scales are listed by name.
  static const _keyScales = [Scale.majorScale, Scale.naturalMinorScale, Scale.bluesScale];

  void _newKey(Move move, int ply) {
    key = ZugKey(ZugNote.values[move.toFile], _keyScales[ply % 3]);
  }

  // ---------------------------------------------------------------------
  // Melody
  // ---------------------------------------------------------------------
  void _addMelody(Move m) {
    print("Adding melody: ${m.debug}");
    final voice = voices[_currentSolo];
    final dx = (m.fromFile - m.toFile).toDouble();
    final dy = (m.fromRank - m.toRank).toDouble();
    final distance = sqrt(dx * dx + dy * dy);
    final reach = m.white ? m.toRank : 7 - m.toRank;

    final int interval;
    final double dur;
    switch (style) {
      case MelodyStyle.distance:
        // Up the board = up the scale, by the length of the move.
        interval = (ChessUtil.toBoardIndex(m.from) < ChessUtil.toBoardIndex(m.to) ? distance : -distance).floor();
        print("Reach: $reach");
        dur = noteLengths[reach];
      case MelodyStyle.piece:
        interval = m.piece.interval * (m.white ? 1 : -1);
        dur = noteLengths[min(distance.toInt(), noteLengths.length - 1)] * 2;
    }

    voice.setPitchFrom(key.getNextPitch(voice, interval, bounce: bounce));
    _add(TrackType.values[_currentSolo], voice.pitch, 50, voice.currentTick, dur);
    voice.currentTick += dur;
    _noteList.add(_NoteRec(voice.note, m.piece));
  }

  // ---------------------------------------------------------------------
  // Rhythm figures
  // ---------------------------------------------------------------------

  void _addRhythmChords(Chess board, int ply, {required bool cross}) {
    const divisions = 8;
    final slotDuration = tempo / divisions;

    for (int a = 0; a < divisions; a++) {
      final chord = <int>[];

      for (int b = 0; b < 8; b++) {
        final file = cross ? a : b;
        final rank = cross ? b : a;
        final degree = cross ? rank : file;

        if (board.pieceAt(file, rank) != null) {
          // The scanned coordinate determines the scale degree.
          chord.add(
            key.getNextPitch(
              ZugPitch(key.keyNote.index + 48),
              degree,
            ).pitch,
          );
        }
      }

      if (chord.isEmpty) continue;

      final start = ply + a * slotDuration;

      for (final pitch in chord) {
        _add(
          TrackType.rhythm1,
          pitch,
          50,
          start,
          slotDuration,
        );
      }
    }
  }

  bool _isPiece(Chess board, int file, int rank) {
    final p = board.pieceAt(file, rank);
    return p != null && p != PieceType.PAWN;
  }

  /// One note per file, at the rank of the lowest non-pawn piece (a back-rank
  /// piece only counts if nothing else is on the file).
  void _addArpeggio(Chess board, int ply, int o) {
    final slotDuration = tempo / 8;

    for (int file = 0; file < 8; file++) {
      int? selectedRank;

      // Find the lowest non-pawn piece on this file.
      for (int rank = 7; rank >= 0; rank--) {
        if (_isPiece(board, file, rank)) {
          selectedRank = rank;
          break;
        }
      }

      if (selectedRank == null) continue;

      final pitch = key.getNextPitch(
        ZugPitch(key.keyNote.index + octave * o),
        selectedRank,
      ).pitch;

      _add(
        TrackType.rhythm1,
        pitch,
        50,
        ply + file * slotDuration,
        slotDuration,
      );
    }
  }

  /// Replays the melody notes so far, [notes] at a time, as a loop.
  void _addNoteLoop(int ply, int count, int o, {required bool straight}) {
    if (_noteList.isEmpty) return;
    for (int i = 0; i < count; i++) {
      if (_noteList.length <= _noteLoopIndex) _noteLoopIndex = 0;
      final n = _noteList[_noteLoopIndex++];
      final pitch = (octave * o) + n.note.index + key.keyNote.index;
      final sub = (i / (count / tempo)) * (straight ? 1 : n.piece.dur);
      _add(TrackType.rhythm1, pitch, 50, ply + sub, 1 / count);
    }
  }

  void _add(TrackType track, int pitch, int velocity, double start, double dur) {
    notes.add(SonNote(
      track,
      pitch.clamp(defMinPitch, defMaxPitch),
      velocity,
      max(0.0, start), // the check cue can land before time zero early on
      dur,
    ));
  }

  Future<void> play() async {
    await ready;
    final tracks = buildMidiTracks(notes, preset, mgr);
    for (final track in tracks) { //print(track.events);
      _sqr.addTrack(track);
    }
    //print("Playing tracks: ${tracks.length}");
    _sqr.seek(0);
    _sqr.play();
  }

  MidiInstrument instrumentFor(TrackType track) {
    return instrumentOverrides[track] ?? preset.instrumentFor(track);
  }

  Future<void> setInstrument(
      TrackType track,
      MidiInstrument instrument,
      ) async {
    await ready;
    await mgr.changeInstrument(track.name, instrument);
    instrumentOverrides[track] = instrument;
  }

}

extension NumberParsing on PieceType {
  int get interval => switch(this) {
    PieceType.PAWN => 1,
    PieceType.KNIGHT => 2,
    PieceType.BISHOP => 3,
    PieceType.ROOK => 4,
    PieceType.QUEEN => 5,
    PieceType.KING => 6,
    PieceType() => throw UnimplementedError(),
  };

  double get dur => switch(this) {
    PieceType.PAWN => .5,
    PieceType.KNIGHT => 1,
    PieceType.BISHOP => 1.5,
    PieceType.ROOK => .25,
    PieceType.QUEEN => .125,
    PieceType.KING => 2,
    PieceType() => throw UnimplementedError(),
  };
}

extension MoveUtil on Move {
  int get fromFile => Chess.file(from);
  int get fromRank => 7 - Chess.rank(from); // 0 = rank 1
  int get toFile => Chess.file(to);
  int get toRank => 7 - Chess.rank(to);
  bool get white => color == Color.WHITE;
  String get pan => "$fromAlgebraic -> $toAlgebraic";
  String get debug => "[$pan, $from -> $to, FromFile: $fromFile, FromRank: $fromRank, ToFile: $toFile, ToRank: $toRank]";
}

extension ChessUtil on Chess {
  PieceType? pieceAt(int file, int rank) => board[(7 - rank) * 16 + file]?.type;
  /// 0x88 square -> a1 = 0 ... h8 = 63
  static int toBoardIndex(int square) => (7 - (square >> 4)) * 8 + (square & 7);
}
