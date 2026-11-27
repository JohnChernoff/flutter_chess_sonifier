import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xpgn_reader/xpgn_reader.dart';

// Same pattern PgnDatabase uses for a header line: [White "Steinitz, Wilhelm"]
final RegExp _tagPattern = RegExp(
  r'^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$',
);

/// The header block of a PGN as a map (empty for a bare movetext).
Map<String, String> parsePgnHeaders(String pgn) {
  final headers = <String, String>{};
  for (final line in pgn.split('\n')) {
    final m = _tagPattern.firstMatch(line);
    if (m != null) {
      headers[m[1]!] = m[2]!.replaceAllMapped(
        RegExp(r'\\(["\\])'),
            (x) => x[1]!,
      );
    } else if (headers.isNotEmpty && line.trim().isNotEmpty) {
      break; // first movetext line ends the header block
    }
  }
  return headers;
}

/// Joins a PGN game to its analysis. Python and Dart both see the same PGN
/// headers, so these five identify a game.
String gameKey(Map<String, String> headers) => [
  for (final k in const ['Event', 'Round', 'White', 'Black', 'Date'])
    (headers[k] ?? '').trim().toLowerCase(),
].join('|');

Map<String, dynamic> _decode(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

/// Loads the XPGN asset and looks games up by PGN headers.
///
/// The file is decoded once (off the UI thread where isolates exist), but an
/// [XpgnGame] with its derived metrics is only built when a game is asked for.
class XpgnDatabase {
  final String assetPath;
  final Tuning tuning;

  XpgnDatabase({
    this.assetPath = 'assets/pgn/wc.xpgn.json',
    this.tuning = const Tuning(),
  });

  EngineInfo _engine = const EngineInfo();
  List<Map> _games = [];
  final Map<String, int> _byKey = {};
  final Map<int, XpgnGame> _cache = {};
  Future<void>? _initFuture;

  bool isReady = false;
  String? error;

  int get gameCount => _games.length;

  Future<void> initialize() => _initFuture ??= _load();

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString(assetPath);
      final json = await compute(_decode, text);

      final engine = json['engine'];
      _engine = EngineInfo.fromJson(
        engine == null ? null : Map<String, dynamic>.from(engine as Map),
      );

      _games = [for (final g in json['games'] as List) g as Map];
      for (var i = 0; i < _games.length; i++) {
        final raw = _games[i]['headers'] as Map? ?? const {};
        final headers = {
          for (final e in raw.entries) e.key.toString(): e.value.toString(),
        };
        _byKey.putIfAbsent(gameKey(headers), () => i);
      }
      isReady = true;
    } catch (e) {
      error = e.toString();
      isReady = false;
    }
  }

  /// The analysis for the game with these PGN headers, or null.
  XpgnGame? find(Map<String, String> headers) {
    final i = _byKey[gameKey(headers)];
    if (i == null) return null;
    return _cache[i] ??= XpgnGame.fromJson(
      Map<String, dynamic>.from(_games[i]),
      engine: _engine,
      tuning: tuning,
    );
  }
}