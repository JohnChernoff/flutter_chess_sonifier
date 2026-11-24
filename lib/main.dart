import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'chess_midi_adapter.dart';

final ChessSonifier sonifier = ChessSonifier(voices: EnsemblePreset.orchestra.voices);

void main() {
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

  @override
  Widget build(BuildContext context) {
   return Scaffold(body: Center(child: Column(children: [
     Row(children: [
       ChessBoard(
           controller: chessBoardController,
           size: 500,
           blackPieceColor: Colors.white,
           onMove: (from,to,prom) {
             print(from);
             print(to);
             print(prom);
             print(chessBoardController.getFen());
           }),
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
     ElevatedButton(onPressed: () {
       print(pgnController.text);
       final chess = Chess();
       if (chess.load_pgn(pgnController.text)) {
         print("Loaded PGN");

         final moves = chess.history.map((s) => s.move).toList();

         // Restore the initial position.
         while (chess.history.isNotEmpty) {
           chess.undo_move();
         }
         int ply = 0;
         // Now replay the moves in chronological order.
         for (final move in moves) {
           print(move.debug);
           chess.make_move(move);
           sonifier.sonifyMove(move, ply++, chess);
         }
       }
     }, child: Text("Sonify"))
   ])));
  }
}
