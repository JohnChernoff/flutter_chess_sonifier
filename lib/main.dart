import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'chess_midi_adapter.dart';

late final ChessSonifier sonifier;

void main() {
  sonifier = ChessSonifier(preset: EnsemblePreset.orchestra);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Sonifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SonifierApp(title: 'Chess Sonifier'),
    );
  }
}

class SonifierApp extends StatefulWidget {
  final String title;
  const SonifierApp({super.key, required this.title});

  @override
  State<SonifierApp> createState() => _SonifierAppState();
}

class _SonifierAppState extends State<SonifierApp> {
  late final ChessBoardController chessBoardController = ChessBoardController();
  late final TextEditingController pgnController = TextEditingController();
  final chess = Chess();
  List<Move> replayMoves = [];
  int displayedPly = 0;

  @override
  void initState() {
    super.initState();
    pgnController.text = "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 d5 Ne5 bxc3 Nxc4 Qd4 f5 Qxc4 d6";
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(body: Center(child: Column(children: [
     Row(children: [
       ValueListenableBuilder<Chess>(
         valueListenable: chessBoardController,
         builder: (context, game, _) {
           return ChessBoard(
             controller: chessBoardController,
             size: 500,
             blackPieceColor: Colors.white,
           );
         },
       ),
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
       )
     ]),
     ElevatedButton(onPressed: sonify, child: Text("Sonify"))
   ])));
  }

  void sonify() {
    if (!chess.load_pgn(pgnController.text)) return;
    sonifier.sequencer!.addListener(syncBoardToAudio);

    sonifier.startGame();

    replayMoves = chess.history.map((s) => s.move).toList();

    // Generate the music from the initial position forward.
    resetGame();

    int ply = 0;
    for (final move in replayMoves) {
      sonifier.sonifyMove(move, ply++, chess);
      chess.make_move(move);
    }

    // Return to the initial position for visual playback.
    resetGame();
    displayedPly = 0;
    chessBoardController.loadFen(chess.fen);

    sonifier.play();
  }

  void resetGame() {
    while (chess.history.isNotEmpty) {
      chess.undo_move();
    }
  }

  void syncBoardToAudio() {
    final seq = sonifier.sequencer;
    if (!seq.isPlaying) return;

    // At time 0, show move 1; at time 1, show move 2, etc.
    final targetPly = (seq.currentTime.floor() + 1)
        .clamp(0, replayMoves.length)
        .toInt();

    if (targetPly == displayedPly) return;

    // Handle backward seeking.
    if (targetPly < displayedPly) {
      resetGame();
      displayedPly = 0;
    }

    while (displayedPly < targetPly) {
      chess.make_move(replayMoves[displayedPly]);
      displayedPly++;
    }

    chessBoardController.loadFen(chess.fen);
  }
}
