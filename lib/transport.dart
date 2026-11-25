import 'package:flutter/material.dart';
import 'package:zug_music/sequencer.dart';

class TransportBar extends StatefulWidget {
  final MidiSequencer seq;
  const TransportBar(this.seq, {super.key});
  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _resumeAfterDrag = false;

  static String _fmt(double s) {
    final t = s.floor();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final seq = widget.seq;
    return ListenableBuilder(
      listenable: seq,
      builder: (context, _) {
        final dur = seq.duration;
        final ready = dur > 0;
        return Row(children: [
          IconButton(
            icon: Icon(seq.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: !ready ? null : () => seq.isPlaying ? seq.pause() : seq.play(),
          ),
          Expanded(
            child: Slider(
              value: seq.currentTime.clamp(0.0, dur).toDouble(),
              min: 0,
              max: ready ? dur : 1,
              onChangeStart: (_) {
                _resumeAfterDrag = seq.isPlaying;
                seq.pause();
              },
              onChanged: ready ? seq.seek : null,
              onChangeEnd: (_) {
                if (_resumeAfterDrag) seq.play();
              },
            ),
          ),
          Text('${_fmt(seq.currentTime)} / ${_fmt(dur)}'),
        ]);
      },
    );
  }
}
