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

  @override
  void initState() {
    super.initState();
    pgnController.text = "e4 e5 Nf3";
    //chessBoardController.game = chess;
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
         height: 500,
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
    print(pgnController.text);
    if (chess.load_pgn(pgnController.text)) { //print("Loaded PGN");
      sonifier.startGame();
      final movelist = chess.history.map((s) => s.move).toList();
      resetGame();
      int ply = 0;
      // Now replay the moves in chronological order.
      for (final move in movelist) { //print(move.debug);
        sonifier.sonifyMove(move, ply++, chess);
        chess.make_move(move);
      }
      sonifier.play();
      playGame(movelist);
    }
  }

  void resetGame() {
    while (chess.history.isNotEmpty) {
      chess.undo_move();
    }
  }

  Future<void> playGame(List<Move> movelist) async {
    resetGame();
    for (final move in movelist) {
      chess.make_move(move);
      chessBoardController.loadFen(chess.fen);
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
