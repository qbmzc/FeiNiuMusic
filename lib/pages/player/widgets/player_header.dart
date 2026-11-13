import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/settings_state.dart';
import '../../../app/state/song_state.dart';
import 'cast_button.dart';
import 'player_favorite_button.dart';
import 'player_typography.dart';

class PlayerHeader extends StatelessWidget {
  final Signal<SongEntity?> songSignal;
  final PlayerStylePreset stylePreset;

  /// 竖屏经典布局的投屏按钮在顶栏，标题行不再重复显示。
  final bool showCastButton;
  final EdgeInsetsGeometry padding;

  const PlayerHeader({
    super.key,
    required this.songSignal,
    this.stylePreset = PlayerStylePreset.classic,
    this.showCastButton = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
        final title = song?.title ?? '未知歌曲';
        final artist = song?.artistDisplayName ?? '未知歌手';
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: PlayerTypography.title(scheme),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: PlayerTypography.subtitle(scheme),
                    ),
                  ],
                ),
              ),
              PlayerFavoriteButton(song: song),
              // DLNA 投屏按钮（仅 Android 显示）
              if (showCastButton) CastButton(songSignal: songSignal),
            ],
          ),
        );
      },
    );
  }
}
