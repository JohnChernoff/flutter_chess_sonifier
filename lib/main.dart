import 'dart:io';
import 'dart:math';
import 'package:chess/chess.dart' as dc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chess_sonifier/chess_sonifier.dart';
import 'package:flutter_chess_sonifier/pgn_database.dart';
import 'package:flutter_chess_sonifier/sonifier_controller.dart';
import 'package:flutter_chess_sonifier/sonifier_player.dart';
import 'chess_midi_adapter.dart';
import 'game_picker.dart';
import 'xpgn_db.dart';
import 'package:xpgn_reader/xpgn_reader.dart';

void main() {
  runApp(MainApp(ChessSonifier(preset: EnsemblePreset.orchestra)));
}

class MainApp extends StatelessWidget {
  final ChessSonifier sonifier;
  const MainApp(this.sonifier, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chess Sonifier',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, brightness: Brightness.dark),
    ),
    home: SonifierApp(sonifier: sonifier),
  );
}

class SonifierApp extends StatefulWidget {
  final ChessSonifier sonifier;
  const SonifierApp({super.key, required this.sonifier});

  @override
  State<SonifierApp> createState() => _SonifierAppState();
}

class _SonifierAppState extends State<SonifierApp> {
  late final SonifierController ctl = SonifierController(
    widget.sonifier,
    onFinished: () => _toast('Game finished'),
  );
  final pgnController = TextEditingController(
      text: "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 "
          "d5 Ne5 bxc3 Nxc4 Qd4 f5 Qxc4 d6");
  final pgnDatabase = PgnDatabase()..initialize();
  final xpgnDatabase = XpgnDatabase()..initialize();
  bool _useAnalysis = true;
  String? _analysisNote;

  @override
  void dispose() {
    ctl.dispose();
    pgnController.dispose();
    pgnDatabase.dispose();
    super.dispose();
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  ElevatedButton(onPressed: _selectGame, child: const Text('Select Game')),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.casino),
                    label: const Text('Random'),
                    onPressed: _randomGame,
                  ),
                  ElevatedButton(onPressed: sonify, child: const Text('Sonify')),
                  FilterChip(
                    label: const Text('Use analysis'),
                    selected: _useAnalysis,
                    onSelected: (v) => setState(() => _useAnalysis = v),
                  ),
                ]),
                if (_analysisNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_analysisNote!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 8),
                SizedBox(
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
                SonifierPlayer(ctl, onExportMidi: _saveMidi),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveMidi(Uint8List bytes, String name) async {
    // Mobile/web: file_picker writes the bytes. Desktop: it only returns a
    // path, so write the file ourselves.
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export MIDI',
      fileName: name,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['mid'],
    );
    if (path != null && !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(bytes);
    }
  }

  Future<void> _selectGame() async {
    final game = await showGamePicker(context, pgnDatabase);
    if (game == null) return;
    setState(() => pgnController.text = pgnDatabase.getGame(game));
  }

  void _randomGame() {
    final games = pgnDatabase.search('');
    if (games.isEmpty) return _toast('No games loaded yet');
    final game = games[Random().nextInt(games.length)];
    setState(() => pgnController.text = pgnDatabase.getGame(game));
    sonify();
  }

  Future<void> sonify() async {
    final pgn = pgnController.text;
    final tmp = dc.Chess();
    if (!tmp.load_pgn(pgn)) return _toast('Invalid Pgn');

    await widget.sonifier.ready;
    await xpgnDatabase.initialize();

    XpgnGame? analysis;
    String note;
    if (!_useAnalysis) {
      note = 'Analysis switched off';
    } else if (!xpgnDatabase.isReady) {
      note = 'No analysis file loaded (${xpgnDatabase.error ?? "unknown error"})';
    } else {
      analysis = xpgnDatabase.find(parsePgnHeaders(pgn));
      if (analysis == null) {
        note = 'No analysis found for this game';
      } else if (analysis.moveCount != tmp.history.length) {
        note = 'Analysis has ${analysis.moveCount} plies but this game has '
            '${tmp.history.length}; ignoring it';
        analysis = null;
      } else {
        note = 'Using engine analysis';
      }
    }
    if (mounted) setState(() => _analysisNote = note);

    await ctl.loadPgn(pgn, analysis: analysis);
  }
}
