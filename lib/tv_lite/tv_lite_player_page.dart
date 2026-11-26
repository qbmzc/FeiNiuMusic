import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_lyric/core/lyric_model.dart';

import '../app/services/lyrics/lyrics_service.dart';
import '../app/services/player_service.dart';
import '../app/state/song_state.dart';
import 'tv_lite_focusable.dart';
import 'tv_lite_queue_page.dart';
import 'tv_lite_widgets.dart';

/// 精简播放页：封面 + 歌名 + 歌词 + 进度 + 控制键（上一首/播放/下一首/
/// 播放模式/播放列表）。
///
/// 不做背景取色/模糊/封面旋转；歌词换行时直接换一屏文字，不做滚动动画。
/// 随播放进度刷新的只有进度条和歌词两小块。
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
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
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
                      maxLines: 1,
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
                    const SizedBox(height: 16),
                    const Expanded(child: RepaintBoundary(child: _Lyrics())),
                    const SizedBox(height: 16),
                    const RepaintBoundary(child: _Progress()),
                    const SizedBox(height: 16),
                    // 窄屏时整体缩小，避免五个按键溢出。
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _Controls(),
                    ),
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

/// 歌词：当前行放在上方三分之一处，前后各显示几行，行数随可用高度变化。
///
/// 换行时整块重建这几行文字（无滚动动画）；当前行有翻译时在下一行显示。
class _Lyrics extends StatelessWidget {
  const _Lyrics();

  static const double _lineHeight = 36;

  @override
  Widget build(BuildContext context) {
    final lyrics = LyricsService.instance;
    final controller = lyrics.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([lyrics.snapshot, controller.lyricNotifier]),
      builder: (context, _) {
        final lines = controller.lyricNotifier.value?.lines ?? const [];
        if (lines.isEmpty) {
          final loading =
              lyrics.snapshot.value.status == LyricsLoadStatus.loading;
          return _LyricsHint(text: loading ? '正在加载歌词…' : '暂无歌词');
        }
        return ValueListenableBuilder<int>(
          valueListenable: controller.activeIndexNotifiter,
          builder: (context, active, _) => LayoutBuilder(
            builder: (context, constraints) => _LyricsWindow(
              lines: lines,
              active: active.clamp(0, lines.length - 1),
              // 当前行占两行高度（正文 + 翻译/折行）。
              slots: math.max(
                1,
                (constraints.maxHeight / _lineHeight).floor() - 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricsHint extends StatelessWidget {
  final String text;

  const _LyricsHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LyricsWindow extends StatelessWidget {
  final List<LyricLine> lines;
  final int active;

  /// 可放下的行数（当前行按一行计）。
  final int slots;

  const _LyricsWindow({
    required this.lines,
    required this.active,
    required this.slots,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final before = math.min(active, (slots - 1) ~/ 3);
    final after = slots - 1 - before;
    final inactiveStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final activeLine = lines[active];
    final translation = activeLine.translation?.trim() ?? '';
    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = active - before; i < active; i++)
            _line(lines[i].text, inactiveStyle),
          SizedBox(
            height: _Lyrics._lineHeight * 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeLine.text.trim(),
                  maxLines: translation.isEmpty ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (translation.isNotEmpty)
                  Text(
                    translation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          for (var i = active + 1; i <= active + after && i < lines.length; i++)
            _line(lines[i].text, inactiveStyle),
        ],
      ),
    );
  }

  Widget _line(String text, TextStyle? style) {
    return SizedBox(
      height: _Lyrics._lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
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
        const SizedBox(width: 20),
        ValueListenableBuilder<PlaybackMode>(
          valueListenable: player.playbackMode,
          builder: (context, mode, _) => _ControlButton(
            icon: switch (mode) {
              PlaybackMode.shuffle => Icons.shuffle_rounded,
              PlaybackMode.loop => Icons.repeat_rounded,
              PlaybackMode.single => Icons.repeat_one_rounded,
            },
            label: switch (mode) {
              PlaybackMode.shuffle => '随机',
              PlaybackMode.loop => '列表循环',
              PlaybackMode.single => '单曲循环',
            },
            onSelect: () => unawaited(player.cyclePlaybackMode()),
          ),
        ),
        const SizedBox(width: 20),
        _ControlButton(
          icon: Icons.queue_music_rounded,
          label: '播放列表',
          onSelect: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '播放列表'),
              builder: (_) => const TvLiteQueuePage(),
            ),
          ),
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

  /// 图标下方的小字说明（模式、播放列表等不常见图标用）。
  final String? label;

  const _ControlButton({
    required this.icon,
    required this.onSelect,
    this.autofocus = false,
    this.large = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return TvLiteFocusable(
      onSelect: onSelect,
      autofocus: autofocus,
      selected: true,
      radius: label == null ? 40 : 16,
      padding: label == null
          ? EdgeInsets.all(large ? 18 : 14)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: label == null
          ? Icon(icon, size: large ? 44 : 34)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
    );
  }
}
