import 'package:chess/chess.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'package:flutter_chess_sonifier/controls.dart';
import 'package:flutter_chess_sonifier/transport.dart';
import 'package:wp_chessboard/wp_chessboard.dart';
import 'chess_midi_adapter.dart';

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

  @override
  void initState() {
    super.initState();
    pgnController.text = "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 d5 Ne5 bxc3 Nxc4 Qd4 f5 Qxc4 d6";
    chessBoardController.setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
  }

  @override
  void dispose() {
    widget.sonifier.sequencer.removeListener(syncBoardToAudio);
    pgnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(body: Center(child:
     Row(children: [
       Column(children: [
         SizedBox(
           width: 500,
           height: 128,
           child: TextField(
             controller: pgnController,
             expands: true,
             maxLines: null,
             minLines: null,
             textAlignVertical: TextAlignVertical.top,
             style: const TextStyle(
               fontFamily: 'monospace',
               fontSize: 14,
             ),
             decoration: const InputDecoration(
               border: OutlineInputBorder(),
               hintText: 'Paste PGN here...',
               alignLabelWithHint: true,
             ),
           ),
         ),
         WPChessboard(
             size: 500,
             pieceSpeed: 1000,
             squareBuilder: defSquareBuilder,
             pieceMap: WPChessboard.defPieceMap,
             controller: chessBoardController),
         SizedBox(height: 8),
         ElevatedButton(onPressed: sonify, child: Text("Sonify")),
         SizedBox(height: 8),
         SizedBox(width: 500, child: TransportBar(widget.sonifier.sequencer))
       ]),
       Expanded(child: SettingsWidget(widget.sonifier)),
    ]),
   ));
  }

  Future<void> sonify() async {
    final tmpChess = dc.Chess();
    if (!tmpChess.load_pgn(pgnController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid Pgn")));
      return;
    }
    await widget.sonifier.ready;
    chess = tmpChess;
    widget.sonifier.sequencer
      ..removeListener(syncBoardToAudio)
      ..addListener(syncBoardToAudio);

    widget.sonifier.startGame();

    replayMoves = chess.history.map((s) => s.move).toList();

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

}
