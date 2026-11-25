import 'package:flutter/material.dart';
import 'package:zug_music/zug_midi.dart';
import 'chess_sonifier.dart';

class SettingsWidget extends StatefulWidget {
  final ChessSonifier sonifier;
  const SettingsWidget(this.sonifier,{super.key});
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
      return ListView(
        scrollDirection: Axis.vertical,
        children: [
          buildSettings(),
          _instrumentCard
        ],
      );
  }

  Widget buildSettings() {
    final sonifier = widget.sonifier;
    return Card(
        child: ExpansionTile(
          title: const Text('Sonification Settings'),
          initiallyExpanded: false,
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
              title: const Text('Starting Rhythm Type'),
              trailing: DropdownButton<RhythmType>(
                value: sonifier.startingRhythm,
                items: [
                  for (final type in RhythmType.values)
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
          ],
        ),
    );
  }
}

class InstrumentCard extends StatefulWidget {
  final ChessSonifier sonifier;
  final List<TrackType> tracks;

  InstrumentCard(this.sonifier, {super.key}) : tracks = [
    ...TrackType.values.where(
          (t) => t.index < sonifier.voices.length,
    ),
    TrackType.rhythm1,
    TrackType.capture,
    TrackType.check,
  ];

  @override
  State<StatefulWidget> createState() => _InstrumentCardState();

}

class _InstrumentCardState extends State<InstrumentCard> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Instruments'),
        children: [
          for (final track in widget.tracks)
            ListTile(
              dense: true,
              title: Text(track.name),
              trailing: DropdownButton<MidiInstrument>(
                value: widget.sonifier.instrumentFor(track),
                isExpanded: false,
                items: SettingsWidget._instrumentItems,
                onChanged: (instrument) async {
                  if (instrument == null) return;

                  await widget.sonifier.setInstrument(track, instrument);

                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}
