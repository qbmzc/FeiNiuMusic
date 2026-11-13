import 'package:flutter/material.dart';

/// 播放页统一的文字层级：标题 / 副标题 / 辅助信息。
///
/// 经典、海报、横屏布局共用，避免各处各写一套字号字重。
class PlayerTypography {
  const PlayerTypography._();

  static TextStyle title(ColorScheme scheme) {
    return TextStyle(
      color: scheme.onSurface,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.2,
    );
  }

  static TextStyle subtitle(ColorScheme scheme) {
    return TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.65),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  /// 进度时间等数字标签：等宽数字，避免每秒跳动时文字宽度抖动。
  static TextStyle time(ColorScheme scheme) {
    return TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle meta(ColorScheme scheme) {
    return TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.62),
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      height: 1.35,
      letterSpacing: 0.3,
    );
  }
}
