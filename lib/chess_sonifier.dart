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
import 'game_feel.dart';

/// Same order as chesslib's PieceType (pawn = 0 ... king = 5).
//enum PieceKind { pawn, knight, bishop, rook, queen, king }

enum TrackType {
  melody1(false),
  melody2(false),
  melody3(false),
  melody4(false),
  comp(false),
  harmony(false),
  capture(false),
  check(false),
  bass(true),
  cow(true),
  mid(true),
  snare(true)
  ;
  final bool drums;
  const TrackType(this.drums);
}

enum CompType { chords, arp, loop, ranks }

enum RankPitchMode { absolute, interval }   // 'degree' no longer fits, since it's semitones now

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
  late final MidiSequencer sequencer = MidiSequencer(mgr);
  late final Future<void> ready;

  Random _rnd;
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
  double captureOffset = .33;
  double checkOffset = -.15;

  /// Note durations (in seconds) indexed by how far the move reached.
  final List<double> noteLengths = [.25, .25, .5, .5, 1, 1, 2, 2];

  ZugKey key = ZugKey(ZugNote.noteC, Scale.majorScale);
  CompType rhythmType = CompType.ranks;

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

  CompType startingRhythm = CompType.ranks;
  RankPitchMode rankMode = RankPitchMode.absolute;
  int _rankPitch = 60;                         // last pitch, for interval mode
  static const _rankLo = 32, _rankHi = 92;     // three octaves
  PieceType lastMovedPiece = PieceType.KING;
  late final ZugMelody _rankVoice = ZugMelody(60, minPitch: 48, maxPitch: 84);
  // A melody note waiting for the next melodic event to tell it how long to last.
  ({TrackType track, int pitch, int velocity, double start})? _pendingMelody;

  /// Engine analysis for the current game; null for un-analysed PGNs.
  GameFeel? feel;

  bool _seeded = false;

  /// Same moves in, same random choices out. Call before [startGame].
  void seedWith(int seed) {
    _rnd = Random(seed);
    _seeded = true;
  }

  ChessSonifier({
    required this.preset,
    Random? random,
    this.tempo = 1, //2,
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
    ready = mgr
        .load(preset.assignments)
        .then((_) => mgr.loadDrumKit(drumKit.values.toList()))
        .then((_) {
      for (final d in mgr.drumMap.values) { d.level = 1.0; d.mute = true; }
      instrumentObjectFor(TrackType.check)?.level = .33;
      instrumentObjectFor(TrackType.capture)?.level = .25;
      mgr.masterVolume = .5;
      mgr.muteDrums = false;
      mgr.muted = false;
    });
  }

  Instrument? instrumentObjectFor(TrackType t) =>
      t.drums ? mgr.drumMap[drumKit[t]] : mgr.orchMap[t.name];

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
    rhythmType = startingRhythm;
    for (final v in voices) { v.reset(); v.currentTick = 0; }
    _setRandomSoloist(true);
    sequencer.stop();
    sequencer.clearTracks();
    _rankVoice.reset();
    _rankPitch = 60;
    lastMovedPiece = PieceType.KING;
    _pendingMelody = null;
  }

  /// Sonify one move. Call it with the position BEFORE the move is made.
  void sonifyMove(Move move, int ply, Chess board) {
    //print("Sonifying: ${move.debug}");
    if (move.captured != null) {
      final pitch =
          key.getNextPitch(ZugPitch(48 + key.keyNote.index), move.captured!.interval).pitch;
      _add(TrackType.capture, pitch, 99, ply + captureOffset, 1);
    }

    if (voices[_currentSolo].currentTick < ply - 4) {
      // The soloist has fallen well behind the game clock: pick a (possibly new) soloist and bring it up to date.
      _setRandomSoloist(true);
      voices[_currentSolo].currentTick = ply.toDouble();
    }

    if (rhythmType != CompType.ranks) {
      _addMelody(move);
    } else {
      //if (move.piece == lastMovedPiece || move.piece == PieceType.PAWN || board.in_check || move.captured != null) {
      if (move.piece != lastMovedPiece && !board.in_check && move.captured == null) {
        _addFancyRankMelody(move,ply);
      }
    }

    if (board.in_check) {
      _add(TrackType.check, defMinPitch + move.to, 99, ply + checkOffset, 1);
    }

    if (ply % tempo == 0) {
      switch (rhythmType) {
        case CompType.chords:
          _addRhythmChords(board, ply, cross: true);
        case CompType.arp:
          _addArpeggio(board, ply, 4);
        case CompType.loop:
          _addNoteLoop(ply, 8, 4, straight: true);
        case CompType.ranks:
          _addRankFigure(board, ply, move);
      }

      if (rhythmType == CompType.ranks) {

      }

      _addBeat(board,ply,move);
    }

    // A pawn reaching a new rank for its side changes key and rhythm.
    final rank = move.white ? move.toRank : 7 - move.toRank;
    if (move.piece == PieceType.PAWN && rank > _rankProgress[move.white]!) {
      _rankProgress[move.white] = rank;
      _newKey(move, ply);
      if (rhythmType != CompType.ranks) _setRandomRhythmType(false);
    }

    lastMovedPiece = move.piece;
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
      rhythmType = CompType.values[_rnd.nextInt(CompType.values.length)];
    } while (!allowSame && prev == rhythmType);
  }

  // The Java used Scale.values()[ply % 3] (major, natural minor, blues). The
  // Dart Scale enum is ordered differently (index 2 is harmonic minor), so
  // the three scales are listed by name.
  static const _keyScales = [Scale.majorScale, Scale.naturalMinorScale, Scale.bluesScale];

  void _newKey(Move move, int ply) {
    key = ZugKey(ZugNote.values[move.toFile], _keyScales[ply % 3]);
  }

  void addVoiceNote(ZugMelody voice, int interval, double dur, Move m) {
    voice.setPitchFrom(key.getNextPitch(voice, interval, bounce: bounce));
    _add(TrackType.values[_currentSolo], voice.pitch, 50, voice.currentTick, dur);
    voice.currentTick += dur;
    _noteList.add(_NoteRec(voice.note, m.piece));
  }

  // ---------------------------------------------------------------------
  // Melody
  // ---------------------------------------------------------------------
  void _addMelody(Move m) { //print("Adding melody: ${m.debug}");
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
        //print("Reach: $reach");
        dur = noteLengths[reach];
      case MelodyStyle.piece:
        interval = m.piece.interval * (m.white ? 1 : -1);
        dur = noteLengths[min(distance.toInt(), noteLengths.length - 1)] * 2;
    }

    addVoiceNote(voice, interval, dur, m);
  }

  void _addFancierRankMelody(Move m, int ply) {

  }

  void _addFancyRankMelody(Move m, int ply) {
    final voice = voices[_currentSolo];
    voice.currentTick = ply.toDouble();   // each group is exactly 1 s long
    IntervalMap intMap = IntervalMap.fromMove(m);
    //print("Move: ${m.pan}, IntMap: $intMap");
    double dur;
    if (royalty(m.piece)) {
      dur = 1/3;
      addVoiceNote(voice, intMap.absDist, dur, m);
      addVoiceNote(voice, intMap.toFile, dur, m);
      addVoiceNote(voice, intMap.toRank, dur, m);
    } else if (linePiece(m.piece)) {
      dur = 1/2;
      addVoiceNote(voice, intMap.fileDist, dur, m);
      addVoiceNote(voice, intMap.rankDist, dur, m);
    } else if (m.piece == PieceType.KNIGHT) {
      dur = 1/4;
      addVoiceNote(voice, intMap.fromFile, dur, m);
      addVoiceNote(voice, intMap.fromRank, dur, m);
      addVoiceNote(voice, intMap.toFile, dur, m);
      addVoiceNote(voice, intMap.toRank, dur, m);
    } else {
      dur = 1;
      addVoiceNote(voice, intMap.toRank, dur, m);
    }
  }

  void _addRankMelody(Move m, int ply) {
    final voice = voices[_currentSolo];
    final dx = (m.fromFile - m.toFile).toDouble();
    final dy = (m.fromRank - m.toRank).toDouble();
    final steps = sqrt(dx * dx + dy * dy).round();
    final up = ChessUtil.toBoardIndex(m.from) < ChessUtil.toBoardIndex(m.to);
    final start = ply.toDouble();

    voice.currentTick = start;
    voice.setPitchFrom(key.getNextPitch(voice, up ? steps : -steps, bounce: bounce));

    _flushMelody(start);                 // the previous note ends where this one begins
    _pendingMelody = (
    track: TrackType.values[_currentSolo],
    pitch: voice.pitch,
    velocity: 50,
    start: start,
    );

    _noteList.add(_NoteRec(voice.note, m.piece));
  }

  /// Emit the pending note, ending at [end]. Does nothing if none is pending.
  void _flushMelody(double end) {
    final p = _pendingMelody;
    if (p == null) return;
    _pendingMelody = null;
    final d = end - p.start;
    if (d > 0) _add(p.track, p.pitch, p.velocity, p.start, d);
  }

  void endGame([double tail = 2.0]) {
    _flushMelody(max(duration, (_pendingMelody?.start ?? 0) + 1) + tail);
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
          TrackType.comp,
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

  /// Fold by octaves so the pitch class survives.
  int _foldIntoRange(int pitch) {
    while (pitch > _rankHi) { pitch -= 12; }
    while (pitch < _rankLo) { pitch += 12; }
    return pitch;
  }

  void _addRankFigure(Chess board, int ply, Move move) { //return;
    const slots = 8;
    const slotDur = 1 / slots;
    final values = _rankValues(board, move);

    for (int r = 0; r < slots; r++) {
      final n = values[r];
      if (n == 0) continue; // empty rank = 32nd rest

      final int pitch;
      switch (rankMode) {
        case RankPitchMode.absolute:
        // root + total semitones, folded into range
          pitch = _foldIntoRange(48 + key.keyNote.index + n);
        case RankPitchMode.interval:
        // total semitones up from the previous pitch (rests don't advance it)
          _rankPitch = _foldIntoRange(_rankPitch + n);
          pitch = _rankPitch;
      }
      _add(TrackType.comp, pitch, 50, ply + r * slotDur, slotDur);
    }
  }

  void _addBeat(Chess board, int ply, Move move) {
    const slots = 8;
    const slotDur = 1 / slots;
    for (final trackType in TrackType.values.where((t) => t.drums)) {
      final values = _beatValues(board, trackType, move);
      for (int r = 0; r < slots; r++) {
        final v = values[r];
        if (v == 0) continue; // empty rank = 32nd rest
        final t = ply + r * slotDur;
        //print("Adding: $trackType => $t");
        _add(trackType, 60, v, t, slotDur);
      }
    }
  }

  List<int> _beatValues(Chess board, TrackType trackType, Move move) {
    final beats = List.filled(8, 0);
    for (int rank = 0; rank < 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final piece = board.pieceAt(file, rank);
        if (piece != null) {
          if (trackType == TrackType.bass && piece == PieceType.KING) {
            beats[rank] = 50; break;
          }
          if (trackType == TrackType.cow && majorPiece(piece)) {
            beats[rank] = 50; break;
          }
          if (trackType == TrackType.mid && minorPiece(piece)) {
            beats[rank] = 50; break;
          }
          if (trackType == TrackType.snare && piece == PieceType.PAWN) {
            beats[rank] = 50; break;
          }
        }
      }
    }
    return beats;
  }

  bool minorPiece(PieceType p) => p == PieceType.KNIGHT || p == PieceType.BISHOP;
  bool majorPiece(PieceType p) => p == PieceType.ROOK || p == PieceType.QUEEN;
  bool royalty(PieceType p) => p == PieceType.QUEEN || p == PieceType.KING;
  bool linePiece(PieceType p) => p == PieceType.QUEEN || p == PieceType.ROOK || p == PieceType.BISHOP;

  /// Total value on each rank (index 0 = rank 1)
  List<int> _rankValues(Chess board, Move move, {skipType = true}) {
    final v = List.filled(8, 0);
    final movedPiece = board.get(algebraic(Chess.file(move.from),Chess.rank(move.from)));
    if (movedPiece == null) return v;

    for (int rank = 0; rank < 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final piece = board.get(algebraic(file, rank));
        if (piece != null) {
          if (piece.type == move.piece && movedPiece.type != PieceType.PAWN && skipType) {
            v[rank] = 0; break;
          } else {
            v[rank] += (piece.type.interval * (piece.color == movedPiece.color ? 1 : -1));
          }
        }
      }
      v[rank] = (v[rank] * .5).ceil();
    }
    //print("Move: ${move.pan}, values: $v");
    return v;
  }

  String algebraic(int file, int rank) {
    return 'abcdefgh'.substring(file, file + 1) + '87654321'.substring(rank, rank + 1);
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
        TrackType.comp,
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
      _add(TrackType.comp, pitch, 50, ply + sub, 1 / count);
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
    endGame();
    final tracks = buildMidiTracks(notes, preset, mgr);
    for (final track in tracks) { //print(track.events);
      sequencer.addTrack(track);
    }
    //print("Playing tracks: ${tracks.length}");
    sequencer.seek(0);
    sequencer.play();
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

  Future<void> playNotes(List<SonNote> n) async {
    await ready;
    sequencer.stop();
    sequencer.clearTracks();
    notes..clear()..addAll(n);
    await play();
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

class IntervalMap {
  final int rankDist, fileDist, absDist, fromRank, fromFile, toRank, toFile;

  const IntervalMap({
    required this.rankDist,
    required this.fileDist,
    required this.absDist,
    required this.fromRank,
    required this.fromFile,
    required this.toRank,
    required this.toFile,
  });

  factory IntervalMap.fromMove(Move m) {
    int bc = m.color == Color.BLACK ? -7 : 0;
    final side = m.color == Color.WHITE ? 1 : -1;
    final dx = (m.toFile - m.fromFile).toDouble();
    final dy = (m.toRank - m.fromRank).toDouble() * side;
    final interval = sqrt(dx * dx + dy * dy).round();
    return IntervalMap(
        rankDist: dy.toInt(),
        fileDist: dx.toInt(),
        absDist: interval,
        fromRank: coordToInterval((m.fromRank + bc).abs()),
        fromFile: coordToInterval((m.fromFile + bc).abs()),
        toRank: coordToInterval((m.toRank + bc).abs()),
        toFile: coordToInterval((m.toFile + bc).abs())
    );
  }

  @override
  String toString() {
    return "[rankDist: $rankDist, fileDist: $fileDist, absDist: $absDist, "
        "fromRank: $fromRank, fromFile: $fromFile, toRank: $toRank, toFile: $toFile]";
  }

  static int coordToInterval(int c) => c == 0 ? 0 : c - 4;
}
