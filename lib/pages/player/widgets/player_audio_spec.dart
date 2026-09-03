import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/state/song_state.dart';
import '../../../app/utils/song_audio_spec.dart';

class PlayerAudioSpec extends StatelessWidget {
  final ValueListenable<SongEntity?> songListenable;

  const PlayerAudioSpec({super.key, required this.songListenable});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: songListenable,
      builder: (context, song, _) {
        final text = formatSongAudioSpec(song);
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Tooltip(
            message: '音源规格（原始文件）',
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: color),
              semanticsLabel: '音源规格：$text',
            ),
          ),
        );
      },
    );
  }
}
