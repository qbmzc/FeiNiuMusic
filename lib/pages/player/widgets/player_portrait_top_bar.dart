import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';
import 'cast_button.dart';
import 'player_typography.dart';

/// 经典竖屏播放页顶栏：下拉指示条 + 投屏按钮。
///
/// 歌名在封面页位于封面下方；横滑到歌词页时，顶栏中间的紧凑歌名随
/// [pageController] 的滑动进度渐显，保证歌词页仍有歌曲上下文。
class PlayerPortraitTopBar extends StatelessWidget {
  final Signal<SongEntity?> songSignal;
  final PageController pageController;

  const PlayerPortraitTopBar({
    super.key,
    required this.songSignal,
    required this.pageController,
  });

  /// 两侧预留宽度：左侧给桌面端浮层返回按钮，右侧给投屏按钮，标题保持居中。
  static const double _sideSlot = 56;

  double _pageProgress() {
    if (!pageController.hasClients) return 0;
    final position = pageController.position;
    if (!position.hasContentDimensions || !position.hasPixels) return 0;
    return (pageController.page ?? 0).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: _sideSlot),
                Expanded(
                  child: AnimatedBuilder(
                    animation: pageController,
                    builder: (context, _) {
                      final progress = _pageProgress();
                      // 封面页（progress≈0）不构建紧凑标题，避免与封面下方
                      // 的完整标题重复出现在语义树/测试查找中。
                      if (progress < 0.01) return const SizedBox.shrink();
                      return Opacity(
                        opacity: progress,
                        child: _CompactTitle(songSignal: songSignal),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: _sideSlot,
                  child: Center(child: CastButton(songSignal: songSignal)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTitle extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const _CompactTitle({required this.songSignal});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
        final title = song?.title.trim().isNotEmpty == true
            ? song!.title.trim()
            : '未知歌曲';
        final artist = song?.artistDisplayName.isNotEmpty == true
            ? song!.artistDisplayName
            : '未知歌手';
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PlayerTypography.title(
                scheme,
              ).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PlayerTypography.subtitle(scheme).copyWith(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
