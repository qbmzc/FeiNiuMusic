import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/state/song_state.dart';
import '../../../app/utils/song_audio_spec.dart';

class PlayerAudioSpec extends StatelessWidget {
  final ValueListenable<SongEntity?> songListenable;
  final ValueListenable<String?>? transcodeCodecListenable;

  const PlayerAudioSpec({
    super.key,
    required this.songListenable,
    this.transcodeCodecListenable,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: songListenable,
      builder: (context, song, _) {
        final codecListenable = transcodeCodecListenable;
        if (codecListenable == null) {
          return _buildSpec(context, color, song, null);
        }
        return ValueListenableBuilder<String?>(
          valueListenable: codecListenable,
          builder: (context, codec, _) =>
              _buildSpec(context, color, song, codec),
        );
      },
    );
  }

  Widget _buildSpec(
    BuildContext context,
    Color color,
    SongEntity? song,
    String? transcodeCodec,
  ) {
    final text = formatPlayerAudioSpec(song, playbackCodec: transcodeCodec);
    if (text.isEmpty) return const SizedBox.shrink();
    final isTranscoded = transcodeCodec?.trim().isNotEmpty == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Tooltip(
        message: '实际播放音频信息',
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: color),
          semanticsLabel: isTranscoded ? '原始音源规格与当前转码播放规格：$text' : '音源规格：$text',
        ),
      ),
    );
  }
}
