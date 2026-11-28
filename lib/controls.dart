import 'dart:math';

import 'package:flutter/material.dart';
import 'package:zug_music/zug_midi.dart';
import 'chess_sonifier.dart';

class SettingsWidget extends StatefulWidget {
  final ChessSonifier sonifier;
  final bool shrinkWrap;
  final bool bare;
  const SettingsWidget(this.sonifier,{this.shrinkWrap = false, this.bare = false, super.key});
  static final _instrumentItems = [
    for (final i in MidiInstrument.values)
      DropdownMenuItem(value: i, child: Text(i.name)),
  ];

  @override
  State<StatefulWidget> createState() => _SettingsWidgetState();

}

class _SettingsWidgetState extends State<SettingsWidget> {
  late final Widget _instrumentCard = InstrumentCard(widget.sonifier);

  @override
  Widget build(BuildContext context) {
    if (widget.bare) return buildSettings();   // sheet use: settings only
    return ListView(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [buildSettings(), _instrumentCard],
    );
  }

  Widget buildSettings() {
    final sonifier = widget.sonifier;
    final items = <Widget>[
      // Rhythm spacing
      if (!sonifier.tempoFeel) ListTile(
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
        title: const Text('Starting Rhythm Type'),
        trailing: DropdownButton<CompType>(
          value: sonifier.startingRhythm,
          items: [
            for (final type in CompType.values)
              DropdownMenuItem(
                value: type,
                child: Text(type.name),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => sonifier.startingRhythm = value);
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
    ];

    return widget.bare ? Column(children: items) : Card(child: ExpansionTile(title: const Text("Settings"), children: items));
  }
}

class InstrumentCard extends StatefulWidget {
  final ChessSonifier sonifier;
  final List<TrackType> tracks;
  final bool bare;

  InstrumentCard(this.sonifier, {super.key, this.bare = false}) : tracks = [
    ...TrackType.values.where((t) => !t.drums && t.index < sonifier.voices.length),
    TrackType.comp,
    TrackType.capture,
    TrackType.check,
    ...TrackType.values.where((t) => t.drums),
  ];

  @override
  State<StatefulWidget> createState() => _InstrumentCardState();

}

class _InstrumentCardState extends State<InstrumentCard> {

  static final _pool = [
    for (final i in MidiInstrument.values)
      if (i.bank != MidiBank.soundFX && i.bank != MidiBank.perc) i,
  ];


  bool _busy = false;

  Future<void> _randomize() async {
    setState(() => _busy = true);
    final rnd = Random();
    for (final t in widget.tracks) {
      await widget.sonifier.setInstrument(t, _pool[rnd.nextInt(_pool.length)]);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final body = <Widget>[
      ListTile(
        dense: true,
        title: const Text('Randomize all'),
        trailing: _busy
            ? const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
          icon: const Icon(Icons.casino),
          onPressed: _randomize,
        ),
      ),
      for (final track in widget.tracks)
        _TrackRow(widget.sonifier, track, key: ValueKey(track)),
    ];
    return widget.bare ? Column(children: body) : Card(
      child: ExpansionTile(
        title: const Text('Instruments'),
        children: body,
      ),
    );
  }
}

class _TrackRow extends StatefulWidget {
  final ChessSonifier sonifier;
  final TrackType track;
  const _TrackRow(this.sonifier, this.track, {super.key});

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  Widget _toggle(String label, bool on, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: SizedBox(
      width: 32,
      height: 28,
      child: on
          ? FilledButton(
          style: FilledButton.styleFrom(
              padding: EdgeInsets.zero, backgroundColor: color),
          onPressed: onTap,
          child: Text(label))
          : OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onTap,
          child: Text(label)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.sonifier;
    final track = widget.track;
    final inst = s.instrumentObjectFor(track);   // null until the audio has loaded

    return ListTile(
      dense: true,
      title: Row(children: [
        Expanded(child: Text(track.name)),
        if (inst != null) ...[
          _toggle('M', inst.mute, Colors.red.shade700,
                  () => setState(() => s.mgr.toggleMute(inst))),
          _toggle('S', inst.solo, Colors.amber.shade800,
                  () => setState(() => s.mgr.toggleSolo(inst))),
        ],
        if (!track.drums) ...[
          const SizedBox(width: 8),
          SizedBox(width: 150, child: DropdownButton<MidiInstrument>(
            isExpanded: true,
            value: s.instrumentFor(track),
            items: SettingsWidget._instrumentItems,
            onChanged: (i) async {
              if (i == null) return;
              await s.setInstrument(track, i);
              if (mounted) setState(() {});
            },
          )),
        ],
      ]),
      subtitle: inst == null
          ? null
          : Slider(
        value: inst.level.clamp(0.0, 2.0),
        min: 0,
        max: 2,
        divisions: 40,
        label: '${(inst.level * 100).round()}%',
        onChanged: (v) => setState(() => inst.level = v),
      ),
    );
  }
}

