
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chess_sonifier/pgn_database.dart';

Future<GameRef?> showGamePicker(
    BuildContext context,
    PgnDatabase database,
    ) {
  return showDialog<GameRef>(
    context: context,
    builder: (_) => GamePickerDialog(database: database),
  );
}

class GamePickerDialog extends StatefulWidget {
  final PgnDatabase database;

  const GamePickerDialog({
    super.key,
    required this.database,
  });

  @override
  State<GamePickerDialog> createState() =>
      _GamePickerDialogState();
}

class _GamePickerDialogState extends State<GamePickerDialog> {
  final searchController = TextEditingController();
  String query = '';

  List<GameRef> get results =>
      widget.database.search(query);

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = results;

    return Dialog(
      child: SizedBox(
        width: 650,
        height: 650,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'World Championship Games',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search player, year, event...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => query = value);
                },
              ),

              const SizedBox(height: 8),

              Text(
                '${games.length} games',
                style: Theme.of(context).textTheme.bodySmall,
              ),

              const Divider(),

              Expanded(
                child: games.isEmpty
                    ? const Center(
                  child: Text('No games found.'),
                )
                    : ListView.builder(
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];

                    return ListTile(
                      dense: true,
                      title: Text(
                        game.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${game.date}  ·  '
                            '${game.event}  ·  '
                            'Round ${game.round}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        game.result,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context, game);
                      },
                    );
                  },
                ),
              ),

              const Divider(),

              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.casino),
                    label: const Text('Random'),
                    onPressed: games.isEmpty
                        ? null
                        : () => Navigator.pop(
                        context, games[Random().nextInt(games.length)]),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
