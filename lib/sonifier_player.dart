import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wp_chessboard/wp_chessboard.dart';

import 'controls.dart';
import 'sonifier_controller.dart';
import 'transport.dart';

/// Board, optional transport bar, and a row of icons, all in one column.
///
///   SonifierPlayer(ctl)                                   // full
///   SonifierPlayer(ctl, showTransport: false,             // game mode
///       showSettings: false, showInstruments: false)
class SonifierPlayer extends StatefulWidget {
  const SonifierPlayer(
      this.controller, {
        super.key,
        this.showTransport = true,
        this.allowTransportToggle = true,
        this.showSettings = true,
        this.showInstruments = true,
        this.showMute = true,
        this.initiallyMuted = false,
        this.onExportMidi,
        this.exportName = 'chess_sonification.mid',
        this.resonifyOnSettingsClose = true,
        this.maxBoardSize = 560,
        this.actions = const [],
      });

  final SonifierController controller;

  /// Initial transport visibility; the toggle icon changes it at runtime.
  final bool showTransport;
  final bool allowTransportToggle;
  final bool showSettings;
  final bool showInstruments;
  final bool showMute;

  /// Start with the sound off (the mute icon turns it back on).
  final bool initiallyMuted;

  /// The export icon is shown only when this is provided. It receives the
  /// MIDI bytes and a suggested file name; saving/sharing is up to the app.
  final Future<void> Function(Uint8List bytes, String fileName)? onExportMidi;
  final String exportName;

  /// Settings (not instruments) only take effect when the game is
  /// re-sonified, so do that when the settings sheet closes.
  final bool resonifyOnSettingsClose;

  final double maxBoardSize;

  /// Extra icons appended to the row (e.g. "new game", "hint").
  final List<Widget> actions;

  @override
  State<SonifierPlayer> createState() => _SonifierPlayerState();
}

class _SonifierPlayerState extends State<SonifierPlayer> {
  late bool _transport = widget.showTransport;
  bool _muted = false;

  SonifierController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyMuted) {
      _muted = true;
      // Runs after the sonifier's own load-time `muted = false`.
      _c.sonifier.ready.then((_) {
        if (mounted) _c.sonifier.mgr.muted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final avail = min(box.maxWidth, widget.maxBoardSize);
      // Leave room for the transport and icon row when height is bounded.
      final size = box.hasBoundedHeight
          ? min(avail, max(200.0, box.maxHeight - (_transport ? 120 : 64)))
          : avail;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WPChessboard(
                size: size,
                pieceSpeed: 1000, // one move animation == one second of audio
                squareBuilder: defSquareBuilder,
                pieceMap: WPChessboard.defPieceMap,
                controller: _c.board,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.topCenter,
                child: _transport
                    ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TransportBar(_c.sequencer),
                )
                    : const SizedBox(width: double.infinity),
              ),
              _iconRow(),
            ],
          ),
        ),
      );
    });
  }

  Widget _iconRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.showSettings)
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Sonification settings',
            onPressed: _openSettings,
          ),
        if (widget.showInstruments)
          IconButton(
            icon: const Icon(Icons.piano),
            tooltip: 'Instruments',
            onPressed: () => _sheet(InstrumentCard(_c.sonifier, bare: true)),
          ),
        if (widget.showMute)
          IconButton(
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            tooltip: _muted ? 'Unmute' : 'Mute',
            onPressed: () => setState(() {
              _muted = !_muted;
              _c.sonifier.mgr.muted = _muted;
            }),
          ),
        if (widget.onExportMidi != null)
          ListenableBuilder(
            listenable: _c,
            builder: (context, child) => IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Export MIDI',
              onPressed: _c.hasGame ? _export : null,
            ),
          ),
        if (widget.allowTransportToggle)
          IconButton(
            icon: Icon(_transport ? Icons.expand_more : Icons.play_circle_outline),
            tooltip: _transport ? 'Hide transport' : 'Show transport',
            onPressed: () => setState(() => _transport = !_transport),
          ),
        ...widget.actions,
      ],
    );
  }

  Future<void> _export() async {
    final bytes = _c.exportMidi();
    if (bytes != null) await widget.onExportMidi!(bytes, widget.exportName);
  }

  Future<void> _openSettings() async {
    await _sheet(SettingsWidget(_c.sonifier, shrinkWrap: true, bare: true));
    if (widget.resonifyOnSettingsClose && _c.hasGame) await _c.reload();
  }

  Future<void> _sheet(Widget body) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .9,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 16),
        children: [body],
      ),
    ),
  );
}
