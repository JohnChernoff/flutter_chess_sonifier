
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GameRef {
  final int offset;
  final int length;
  final int index;
  final Map<String, String> headers;

  const GameRef({
    required this.offset,
    required this.length,
    required this.index,
    required this.headers,
  });

  String get white => headers['White'] ?? 'Unknown';
  String get black => headers['Black'] ?? 'Unknown';
  String get date => headers['Date'] ?? '????.??.??';
  String get event => headers['Event'] ?? 'Unknown event';
  String get round => headers['Round'] ?? '?';
  String get result => headers['Result'] ?? '*';
  String get site => headers['Site'] ?? '';

  String get description => '$white – $black';
}

class PgnDatabase extends ChangeNotifier {
  final String assetPath;

  PgnDatabase({
    this.assetPath = 'assets/pgn/WorldChampionships.pgn',
  });

  String? _pgn;
  List<GameRef> _games = [];

  bool isLoading = false;
  String? error;

  List<GameRef> get games => _games;
  bool get isReady => _pgn != null;

  Future<void>? _initFuture;

  Future<void> initialize() {
    return _initFuture ??= _load();
  }

  Future<void> _load() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      _pgn = await rootBundle.loadString(assetPath);
      _games = _buildIndex(_pgn!);
    } catch (e) {
      error = e.toString();
      _pgn = null;
      _games = [];
    }

    isLoading = false;
    notifyListeners();
  }

  // PGN header line:
  // [White "Steinitz, Wilhelm"]
  static final RegExp _tagPattern = RegExp(
    r'^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$',
  );

  String _unescape(String value) {
    return value.replaceAllMapped(
      RegExp(r'\\(["\\])'),
          (m) => m[1]!,
    );
  }

  List<GameRef> _buildIndex(String pgn) {
    final games = <GameRef>[];

    int? gameStart;
    int lineStart = 0;
    int gameIndex = 0;

    bool inMovetext = false;
    final headers = <String, String>{};

    void finishGame(int end) {
      if (gameStart == null) return;

      games.add(GameRef(
        offset: gameStart!,
        length: end - gameStart!,
        index: gameIndex++,
        headers: Map.unmodifiable(headers),
      ));

      gameStart = null;
      headers.clear();
      inMovetext = false;
    }

    while (lineStart < pgn.length) {
      final newline = pgn.indexOf('\n', lineStart);
      final lineEnd = newline == -1 ? pgn.length : newline;

      final line = pgn.substring(lineStart, lineEnd);
      final match = _tagPattern.firstMatch(line);

      if (match != null) {
        // A header after movetext means a new game.
        if (inMovetext) {
          finishGame(lineStart);
        }

        gameStart ??= lineStart;

        final tag = match[1]!;
        final value = _unescape(match[2]!);

        headers[tag] = value;
      } else if (line.trim().isNotEmpty && gameStart != null) {
        inMovetext = true;
      }

      if (newline == -1) break;
      lineStart = newline + 1;
    }

    finishGame(pgn.length);

    // Chronological ordering. Unknown dates go last.
    games.sort((a, b) {
      final da = a.date;
      final db = b.date;

      final unknownA = da.contains('?');
      final unknownB = db.contains('?');

      if (unknownA != unknownB) {
        return unknownA ? 1 : -1;
      }

      final comparison = da.compareTo(db);

      if (comparison != 0) return comparison;
      return a.index.compareTo(b.index);
    });

    return List.unmodifiable(games);
  }

  // Retrieve the original PGN, including headers and moves.
  String getGame(GameRef game) {
    final pgn = _pgn;
    if (pgn == null) {
      throw StateError('PGN database is not initialized.');
    }

    return pgn.substring(
      game.offset,
      game.offset + game.length,
    ).trim();
  }

  // Search player names, event, site, date, round, ECO, etc.
  List<GameRef> search(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return _games;

    return _games.where((game) {
      return game.headers.values.any(
            (value) => value.toLowerCase().contains(q),
      );
    }).toList(growable: false);
  }

  void disposeDatabase() {
    _pgn = null;
    _games = [];
    dispose();
  }
}
