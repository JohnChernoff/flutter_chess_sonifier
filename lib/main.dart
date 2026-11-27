import 'dart:math';

import 'package:chess/chess.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'package:flutter_chess_sonifier/controls.dart';
import 'package:flutter_chess_sonifier/pgn_database.dart';
import 'package:flutter_chess_sonifier/transport.dart';
import 'package:wp_chessboard/wp_chessboard.dart';
import 'chess_midi_adapter.dart';
import 'game_feel.dart';
import 'game_picker.dart';
import 'xpgn_db.dart';
import 'package:xpgn_reader/xpgn_reader.dart';

//TODO: centralize controls, responsive layout(s), MIDI export

void main() {
  ChessSonifier sonifier = ChessSonifier(preset: EnsemblePreset.orchestra);
  runApp(MainApp(sonifier));
}

class MainApp extends StatelessWidget {
  final ChessSonifier sonifier;
  const MainApp(this.sonifier,{super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Sonifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
      ),
      home: SonifierApp(sonifier: sonifier),
    );
  }
}

class SonifierApp extends StatefulWidget {
  final ChessSonifier sonifier;
  const SonifierApp({super.key, required this.sonifier});

  @override
  State<SonifierApp> createState() => _SonifierAppState();
}

class _SonifierAppState extends State<SonifierApp> {
  late final WPChessboardController chessBoardController = WPChessboardController();
  late final TextEditingController pgnController = TextEditingController();
  dc.Chess chess = dc.Chess();
  List<dc.Move> replayMoves = [];
  int displayedPly = 0;
  late final PgnDatabase pgnDatabase;
  late final XpgnDatabase xpgnDatabase;
  bool _useAnalysis = true;
  String? _analysisNote;

  @override
  void initState() {
    super.initState();
    pgnController.text = "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 d5 Ne5 bxc3 Nxc4 Qd4 f5 Qxc4 d6";
    chessBoardController.setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    pgnDatabase = PgnDatabase();
    pgnDatabase.initialize();
    xpgnDatabase = XpgnDatabase();
    xpgnDatabase.initialize();
  }

  @override
  void dispose() {
    widget.sonifier.sequencer.removeListener(syncBoardToAudio);
    pgnController.dispose();
    pgnDatabase.dispose();
    super.dispose();
  }

  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) =>
          c.maxWidth >= _wideBreakpoint ? _buildWide(c) : _buildNarrow(c),
        ),
      ),
    );
  }

  Widget _buildWide(BoxConstraints c) {
    // Height left over for the buttons, PGN box, and transport bar.
    const chrome = 330.0;
    final boardSize =
    min(c.maxHeight - chrome, c.maxWidth * 0.55).clamp(280.0, 720.0).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: boardSize + 32,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _mainColumn(boardSize),
          ),
        ),
        Expanded(child: SettingsWidget(widget.sonifier)),
      ],
    );
  }

  Widget _buildNarrow(BoxConstraints c) {
    final boardSize = min(c.maxWidth - 16, 600.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _mainColumn(boardSize),
          const SizedBox(height: 8),
          SettingsWidget(widget.sonifier, shrinkWrap: true),
        ],
      ),
    );
  }

  Widget _mainColumn(double size) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton(onPressed: _selectGame, child: const Text("Select Game")),
            ElevatedButton.icon(
              icon: const Icon(Icons.casino),
              label: const Text("Random"),
              onPressed: () => _randomGame(play: true),
            ),
            ElevatedButton(onPressed: sonify, child: const Text("Sonify")),
            FilterChip(
              label: const Text("Use analysis"),
              selected: _useAnalysis,
              onSelected: (v) => setState(() => _useAnalysis = v),
            ),
            //ElevatedButton(onPressed: _evolve, child: const Text("Evolve")),
          ],
        ),
        if (_analysisNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _analysisNote!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: size,
          height: 96,
          child: TextField(
            controller: pgnController,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste PGN here...',
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        WPChessboard(
          size: size,
          pieceSpeed: 1000,
          squareBuilder: defSquareBuilder,
          pieceMap: WPChessboard.defPieceMap,
          controller: chessBoardController,
        ),
        const SizedBox(height: 8),
        SizedBox(width: size, child: TransportBar(widget.sonifier.sequencer)),
      ],
    );
  }

  Future<void> _selectGame() async {
    final game = await showGamePicker(context, pgnDatabase);
    if (game == null) return;
    setState(() => pgnController.text = pgnDatabase.getGame(game));
  }

  Future<void> sonify() async {
    final tmpChess = dc.Chess();
    if (!tmpChess.load_pgn(pgnController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid Pgn")));
      return;
    }
    final headers = parsePgnHeaders(pgnController.text);

    await widget.sonifier.ready;
    await xpgnDatabase.initialize();

    chess = tmpChess;
    replayMoves = chess.history.map((s) => s.move).toList();

    // Find the engine analysis for this game, if there is any.
    XpgnGame? analysis;
    String note;
    if (!_useAnalysis) {
      note = 'Analysis switched off';
    } else if (!xpgnDatabase.isReady) {
      note = 'No analysis file loaded (${xpgnDatabase.error ?? "unknown error"})';
    } else {
      analysis = xpgnDatabase.find(headers);
      if (analysis == null) {
        note = 'No analysis found for this game';
      } else if (analysis.moveCount != replayMoves.length) {
        note = 'Analysis has ${analysis.moveCount} plies but this game has '
            '${replayMoves.length}; ignoring it';
        analysis = null;
      } else {
        note = 'Using engine analysis';
      }
    }
    if (mounted) setState(() => _analysisNote = note);

    // Nothing should react to the sequencer while the tracks are rebuilt.
    widget.sonifier.sequencer.removeListener(syncBoardToAudio);

    widget.sonifier
      ..seedWith(gameSeed(replayMoves.map((m) => m.fromAlgebraic + m.toAlgebraic)))
      ..feel = analysis == null ? null : GameFeel.fromGame(analysis)
      ..startGame();

    // Generate the music from the initial position forward.
    resetGame();

    int ply = 0;
    for (final move in replayMoves) {
      widget.sonifier.sonifyMove(move, ply++, chess);
      chess.make_move(move);
    }
    if (chess.game_over) {
      widget.sonifier.sonifyMove(dc.Move(chess.turn,chess.kings[chess.turn],
          chess.kings[chess.turn == dc.Color.BLACK ? dc.Chess.WHITE : dc.Chess.BLACK],
          0,dc.PieceType.KING,null,null), ply, chess);
    }

    resetGame();
    displayedPly = 0;
    chessBoardController.setFen(chess.fen);

    widget.sonifier.sequencer
      ..removeListener(syncBoardToAudio)
      ..addListener(syncBoardToAudio);

    widget.sonifier.play();
  }

  void resetGame() {
    while (chess.history.isNotEmpty) {
      chess.undo_move();
    }
  }

  void syncBoardToAudio() {
    final seq = widget.sonifier.sequencer;
    if (replayMoves.isEmpty) return;

    final int targetPly;
    if (seq.duration > 0 && seq.currentTime >= seq.duration) {
      targetPly = replayMoves.length;                 // parked at the end
    } else if (seq.isPlaying || seq.currentTime > 0) {
      targetPly = seq.currentTime.floor() + 1;        // time 0 = move 1 while playing
    } else {
      targetPly = 0;                                  // paused at 0 = starting position
    }
    final ply = targetPly.clamp(0, replayMoves.length).toInt();

    if (ply == displayedPly) return;
    if (ply < displayedPly) { resetGame(); displayedPly = 0; }
    while (displayedPly < ply) {
      chess.make_move(replayMoves[displayedPly]);
      displayedPly++;
    }
    chessBoardController.setFen(chess.fen);
  }

  void _randomGame({bool play = false}) {
    final games = pgnDatabase.search('');
    if (games.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No games loaded yet')));
      return;
    }
    final game = games[Random().nextInt(games.length)];
    setState(() => pgnController.text = pgnDatabase.getGame(game));
    if (play) sonify();
  }

}
