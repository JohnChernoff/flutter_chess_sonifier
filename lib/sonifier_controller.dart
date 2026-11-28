import 'package:chess/chess.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:wp_chessboard/wp_chessboard.dart';
import 'package:xpgn_reader/xpgn_reader.dart';
import 'package:zug_music/sequencer.dart';
import 'chess_sonifier.dart';
import 'game_feel.dart';
import 'midi_export.dart';

typedef PlyCallback = void Function(int ply, XMove? lastMove);

/// Owns everything that used to live in _SonifierAppState: sonifying a game,
/// keeping the board in step with the audio, and telling the outside world
/// what is going on. UI-free, so a game screen can drive it directly.
class SonifierController extends ChangeNotifier {
  SonifierController(
      this.sonifier, {
        this.onLoaded,
        this.onPly,
        this.onFinished,
      });

  final ChessSonifier sonifier;
  final WPChessboardController board = WPChessboardController();

  /// A game has been sonified and the board reset (before playback starts).
  VoidCallback? onLoaded;

  /// The displayed position changed. [ply] is 0 for the start position;
  /// [lastMove] is null then. Fires on scrubbing as well as normal playback.
  PlyCallback? onPly;

  /// Audio (including its tail) reached the end. Fires once per play-through;
  /// scrub back and let it run again and it fires again.
  VoidCallback? onFinished;

  dc.Chess _chess = dc.Chess();
  List<XMove> _moves = [];
  GameFeel? _feel;
  int? _seed;
  int _shown = 0;
  bool _finished = false;
  bool _disposed = false;

  MidiSequencer get sequencer => sonifier.sequencer;
  bool get hasGame => _moves.isNotEmpty;
  int get plyCount => _moves.length;
  int get currentPly => _shown;
  bool get isFinished => _finished;
  bool get isPlaying => sequencer.isPlaying;
  List<XMove> get moves => List.unmodifiable(_moves);

  /// Parse a PGN and sonify it. Returns false if the PGN is invalid.
  /// [analysis] is ignored if its ply count doesn't match the game.
  Future<bool> loadPgn(String pgn, {XpgnGame? analysis, bool autoPlay = true}) async {
    final tmp = dc.Chess();
    if (!tmp.load_pgn(pgn)) return false;
    if (analysis != null && analysis.moveCount != tmp.history.length) analysis = null;
    await load(
      analysis?.movelist ?? tmp.history.map((m) => XMove.fromMove(m.move)).toList(),
      feel: analysis == null ? null : GameFeel.fromGame(analysis),
      autoPlay: autoPlay,
    );
    return true;
  }

  /// Sonify [moves] from the standard starting position.
  Future<void> load(
      List<XMove> moves, {
        GameFeel? feel,
        int? seed,
        bool autoPlay = true,
      }) async {
    await sonifier.ready;
    if (_disposed) return;

    // Nothing should react to the sequencer while the tracks are rebuilt.
    sequencer.removeListener(_sync);

    _moves = moves;
    _feel = feel;
    _seed = seed;
    sonifier
      ..seedWith(seed ?? gameSeed(moves.map((m) => m.fromAlgebraic + m.toAlgebraic)))
      ..feel = feel
      ..sonifyGame(moves);

    _chess = dc.Chess();
    _shown = 0;
    _finished = false;
    board.setFen(_chess.fen);

    sequencer.addListener(_sync);
    onLoaded?.call();
    notifyListeners();
    if (autoPlay) await sonifier.play();
  }

  /// Re-sonify the current game, e.g. after settings changed. Keeps playing
  /// if it was playing (unless [autoPlay] says otherwise).
  Future<void> reload({bool? autoPlay}) {
    final play = autoPlay ?? sequencer.isPlaying;
    return load(_moves, feel: _feel, seed: _seed, autoPlay: play);
  }

  /// The current game as a Standard MIDI File, or null if nothing is loaded.
  Uint8List? exportMidi() => hasGame ? sonifier.toMidiBytes() : null;

  void restart() {
    _finished = false;
    sequencer.seek(0);
    sequencer.play();
  }

  void stop() => sequencer.stop();

  void _sync() {
    if (_moves.isEmpty || _disposed) return;
    final seq = sequencer;

    final atEnd = seq.duration > 0 && seq.currentTime >= seq.duration;
    final int target;
    if (atEnd) {
      target = _moves.length;                     // parked at the end
    } else if (seq.isPlaying || seq.currentTime > 0) {
      target = seq.currentTime.floor() + 1;       // time 0 = move 1 while playing
    } else {
      target = 0;                                 // paused at 0 = start position
    }
    final ply = target.clamp(0, _moves.length).toInt();

    if (ply != _shown) {
      if (ply < _shown) {
        _chess = dc.Chess();
        _shown = 0;
      }
      while (_shown < ply) {
        _chess.make_move(_moves[_shown]);
        _shown++;
      }
      board.setFen(_chess.fen);
      onPly?.call(_shown, _shown == 0 ? null : _moves[_shown - 1]);
      notifyListeners();
    }

    if (atEnd && !_finished) {
      _finished = true;
      onFinished?.call();
      notifyListeners();
    } else if (!atEnd && _finished) {
      _finished = false;                          // scrubbed back
    }
  }

  @override
  void dispose() {
    _disposed = true;
    sequencer.removeListener(_sync);
    sequencer.stop();
    super.dispose();
  }
}
