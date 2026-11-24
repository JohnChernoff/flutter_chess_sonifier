import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'package:zug_music/zug_midi.dart';
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
        buildSettings(),
        buildInstrumentControls(),
      ],)
     ]),
     ElevatedButton(onPressed: sonify, child: Text("Sonify")),
   ])));
  }

  Future<void> sonify() async {
    if (!chess.load_pgn(pgnController.text)) return;
    await sonifier.ready;

    sonifier.sequencer.addListener(syncBoardToAudio);

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

  Widget buildSettings() {
    return SizedBox(
      width: 420,
      child: Card(
        child: ExpansionTile(
          title: const Text('Sonification Settings'),
          initiallyExpanded: true,
          children: [
            // Master volume
            ListTile(
              title: const Text('Master Volume'),
              subtitle: Slider(
                value: sonifier.mgr.masterVolume.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                divisions: 20,
                label: '${(sonifier.mgr.masterVolume * 100).round()}%',
                onChanged: (value) {
                  setState(() => sonifier.setMasterVolume(value));
                },
              ),
            ),

            // Rhythm spacing
            ListTile(
              title: const Text('Rhythm Spacing'),
              subtitle: Slider(
                value: sonifier.tempo.clamp(1.0, 8.0),
                min: 1,
                max: 8,
                divisions: 7,
                label: '${sonifier.tempo.round()} plies',
                onChanged: (value) {
                  setState(() => sonifier.tempo = value);
                },
              ),
            ),

            // Rhythm type
            ListTile(
              title: const Text('Rhythm Type'),
              trailing: DropdownButton<RhythmType>(
                value: sonifier.rhythmType,
                items: [
                  for (final type in RhythmType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => sonifier.rhythmType = value);
                },
              ),
            ),

            // Melody style
            ListTile(
              title: const Text('Melody Style'),
              trailing: DropdownButton<MelodyStyle>(
                value: sonifier.style,
                items: [
                  for (final style in MelodyStyle.values)
                    DropdownMenuItem(
                      value: style,
                      child: Text(style.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => sonifier.style = value);
                },
              ),
            ),

            // Capture timing
            ListTile(
              title: const Text('Capture Offset'),
              subtitle: Slider(
                value: sonifier.captureOffset.clamp(0.0, 0.5),
                min: 0,
                max: 0.5,
                divisions: 10,
                label: '${sonifier.captureOffset.toStringAsFixed(2)} s',
                onChanged: (value) {
                  setState(() => sonifier.captureOffset = value);
                },
              ),
            ),

            // Check timing
            ListTile(
              title: const Text('Check Offset'),
              subtitle: Slider(
                value: sonifier.checkOffset.clamp(-0.5, 0.0),
                min: -0.5,
                max: 0,
                divisions: 10,
                label: '${sonifier.checkOffset.toStringAsFixed(2)} s',
                onChanged: (value) {
                  setState(() => sonifier.checkOffset = value);
                },
              ),
            ),

            SwitchListTile(
              title: const Text('Bounce Melodies'),
              value: sonifier.bounce,
              onChanged: (value) {
                setState(() => sonifier.bounce = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInstrumentControls() {
    final tracks = [
      ...TrackType.values.where(
            (t) => t.index < sonifier.voices.length,
      ),
      TrackType.rhythm1,
      TrackType.capture,
      TrackType.check,
    ];

    return SizedBox(
      width: 420,
      child: Card(
        child: ExpansionTile(
          title: const Text('Instruments'),
          children: [
            for (final track in tracks)
              ListTile(
                dense: true,
                title: Text(track.name),
                trailing: DropdownButton<MidiInstrument>(
                  value: sonifier.instrumentFor(track),
                  isExpanded: false,
                  items: [
                    for (final instrument in MidiInstrument.values)
                      DropdownMenuItem(
                        value: instrument,
                        child: Text(instrument.name),
                      ),
                  ],
                  onChanged: (instrument) async {
                    if (instrument == null) return;

                    await sonifier.setInstrument(track, instrument);

                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
