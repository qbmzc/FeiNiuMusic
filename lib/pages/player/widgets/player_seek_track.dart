import 'package:flutter/material.dart';

/// 进度条拖动态切换的动画时长。
const Duration playerSeekTrackAnimation = Duration(milliseconds: 160);

/// 进度条滑块：几何上始终按 [preferredRadius] 占位（Slider 轨道两端内缩
/// 依赖滑块的 preferred size，保持不变才能让缓冲条/时间标签对齐），
/// 实际绘制半径 [paintRadius] 可为 0——平时隐藏、拖动时才出现。
class PlayerSeekThumbShape extends SliderComponentShape {
  final double preferredRadius;
  final double paintRadius;

  const PlayerSeekThumbShape({
    required this.preferredRadius,
    required this.paintRadius,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(preferredRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (paintRadius <= 0.01) return;
    final color = sliderTheme.thumbColor ?? Colors.white;
    context.canvas.drawCircle(center, paintRadius, Paint()..color = color);
  }
}
