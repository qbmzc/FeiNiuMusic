import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/services/feiniu/api_client.dart';
import 'tv_lite_focusable.dart';

/// 精简版封面：按显示尺寸向服务器请求小图，无加载转圈、无淡入动画。
///
/// 手机端 ArtworkWidget 统一请求 800px 并在加载时转圈；在低端投影上整屏
/// 缩略图同时解码大图 + 多个转圈动画会持续掉帧。
class TvLiteCover extends StatelessWidget {
  final String? coverId;
  final int? updatedAt;
  final double size;
  final double radius;
  final IconData fallbackIcon;

  const TvLiteCover({
    super.key,
    required this.coverId,
    required this.size,
    this.updatedAt,
    this.radius = 8,
    this.fallbackIcon = Icons.music_note_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        fallbackIcon,
        size: size * 0.45,
        color: scheme.onSurfaceVariant,
      ),
    );
    final id = coverId;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixels = (size * dpr).round();
    final Widget image;
    if (id == null || id.isEmpty) {
      image = placeholder;
    } else {
      image = CachedNetworkImage(
        imageUrl: FeiNiuApiClient.instance.coverUrl(
          id,
          size: _requestSize(pixels),
          updatedAt: updatedAt,
        ),
        httpHeaders: FeiNiuApiClient.imageAuthHeaders(),
        width: size,
        height: size,
        memCacheWidth: pixels,
        memCacheHeight: pixels,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  /// 归档到少数几档，同一封面在不同位置复用同一份磁盘缓存。
  static int _requestSize(int pixels) {
    if (pixels <= 160) return 160;
    if (pixels <= 400) return 400;
    return FeiNiuApiClient.coverRequestSize;
  }
}

/// 居中提示（空列表 / 加载失败），可带一个重试按钮。
class TvLiteMessage extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const TvLiteMessage({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            TvLiteFocusable(
              onSelect: onAction,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Text(actionLabel!, style: theme.textTheme.titleMedium),
            ),
          ],
        ],
      ),
    );
  }
}

String formatTvLiteDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
