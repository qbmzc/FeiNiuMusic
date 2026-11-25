import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/services/lyrics/lyrics_service.dart';
import '../app/services/player_service.dart';
import '../app/state/song_state.dart';
import 'tv_lite_focusable.dart';
import 'tv_lite_widgets.dart';

/// 精简播放页：封面 + 歌名 + 当前一句歌词 + 进度 + 三个控制键。
///
/// 不滚动歌词、不做背景取色/模糊/封面旋转；随播放进度刷新的只有进度条和
/// 歌词行两小块。
class TvLitePlayerPage extends StatelessWidget {
  const TvLitePlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<SongEntity?>(
          valueListenable: player.currentSong,
          builder: (context, song, _) {
            if (song == null) {
              return const TvLiteMessage(text: '还没有播放歌曲');
            }
            return _PlayerBody(song: song);
          },
        ),
      ),
    );
  }
}

class _PlayerBody extends StatelessWidget {
  final SongEntity song;

  const _PlayerBody({required this.song});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = math.min(
          constraints.maxHeight - 96,
          constraints.maxWidth * 0.36,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
          child: Row(
            children: [
              TvLiteCover(
                coverId: song.coverId,
                updatedAt: song.updatedAt,
                size: coverSize,
                radius: 16,
              ),
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      song.artistDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _CurrentLyricLine(),
                    const SizedBox(height: 28),
                    const RepaintBoundary(child: _Progress()),
                    const SizedBox(height: 24),
                    const _Controls(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurrentLyricLine extends StatelessWidget {
  const _CurrentLyricLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 72,
      child: ValueListenableBuilder<String?>(
        valueListenable: LyricsService.instance.currentLineText,
        builder: (context, line, _) => Text(
          line ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, position, _) {
        final total = player.duration.value ?? Duration.zero;
        final value = total.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatTvLiteDuration(position)} / '
              '${formatTvLiteDuration(total)}',
              style: TextStyle(color: muted),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return Row(
      children: [
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          onSelect: () => unawaited(player.previous()),
        ),
        const SizedBox(width: 20),
        ValueListenableBuilder<bool>(
          valueListenable: player.isPlaying,
          builder: (context, playing, _) => _ControlButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            autofocus: true,
            large: true,
            onSelect: () => unawaited(player.togglePlayPause()),
          ),
        ),
        const SizedBox(width: 20),
        _ControlButton(
          icon: Icons.skip_next_rounded,
          onSelect: () => unawaited(player.next()),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool large;

  const _ControlButton({
    required this.icon,
    required this.onSelect,
    this.autofocus = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvLiteFocusable(
      onSelect: onSelect,
      autofocus: autofocus,
      selected: true,
      radius: 40,
      padding: EdgeInsets.all(large ? 18 : 14),
      child: Icon(icon, size: large ? 44 : 34),
    );
  }
}
