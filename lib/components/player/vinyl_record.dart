import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 大尺寸黑胶唱片（播放页 / 外观预览）。
///
/// 拆成两层：[VinylRecordDisc] 是会旋转的唱片本体（黑胶 + 纹路 + 封面标签），
/// [VinylRecordGloss] 是固定不动的高光与中心轴。旋转时高光不动、纹路与封面
/// 在其下转动，才有真实唱片的光泽流动感。迷你播放器的 44px 小唱片见
/// `vinyl_disc.dart`，两者视觉语言一致。
class VinylRecord {
  const VinylRecord._();

  /// 封面标签占唱片直径的比例：保留足够大的封面，外圈露出一圈黑胶纹路。
  static const double labelRatio = 0.76;

  static double labelSize(double size) => size * labelRatio;
}

/// 唱片本体：黑胶底 + 纹路 + 圆形封面标签。整体可被外层旋转。
class VinylRecordDisc extends StatelessWidget {
  final double size;

  /// 封面标签内容（按 [VinylRecord.labelSize] 布局，这里负责圆形裁切）。
  final Widget label;

  /// 封面主色：给黑胶底色带一丝同色系的暗调，避免纯黑显得突兀。
  final Color? tint;

  const VinylRecordDisc({
    super.key,
    required this.size,
    required this.label,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final labelSize = VinylRecord.labelSize(size);
    // 独立图层：旋转时只改变图层变换，不重新录制纹路与封面。
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _VinylGroovePainter(tint: tint)),
            ),
            SizedBox(
              width: labelSize,
              height: labelSize,
              child: ClipOval(child: label),
            ),
          ],
        ),
      ),
    );
  }
}

/// 固定层：外圈扇形高光 + 中心轴孔。不随唱片旋转。
class VinylRecordGloss extends StatelessWidget {
  final double size;

  const VinylRecordGloss({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final spindle = (size * 0.045).clamp(4.0, 18.0);
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _VinylSheenPainter()),
            ),
            Container(
              width: spindle,
              height: spindle,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xff111215),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.38),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  final Color? tint;

  const _VinylGroovePainter({this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = tint;
    final inner = base == null
        ? const Color(0xff17181b)
        : Color.lerp(base, const Color(0xff101113), 0.84)!;
    final outer = base == null
        ? const Color(0xff0b0b0d)
        : Color.lerp(base, const Color(0xff08080a), 0.92)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [inner, outer]).createShader(rect),
    );

    final labelRadius = radius * VinylRecord.labelRatio;
    final grooveStart = labelRadius + radius * 0.025;
    final grooveEnd = radius * 0.975;
    final step = math.max(1.6, radius * 0.012);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    var i = 0;
    for (var r = grooveStart; r < grooveEnd; r += step, i++) {
      groove.color = Colors.white.withValues(alpha: i.isEven ? 0.055 : 0.022);
      canvas.drawCircle(center, r, groove);
    }

    // 曲目间隔：两条稍宽的暗带，让纹路有层次而不是均匀的细线。
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.008)
      ..color = Colors.black.withValues(alpha: 0.45);
    for (final t in const [0.38, 0.7]) {
      canvas.drawCircle(
        center,
        grooveStart + (grooveEnd - grooveStart) * t,
        gap,
      );
    }

    // 外缘细高光与标签边缘暗环，勾出唱片轮廓。
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      center,
      labelRadius + 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.012)
        ..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_VinylGroovePainter oldDelegate) {
    return oldDelegate.tint != tint;
  }
}

class _VinylSheenPainter extends CustomPainter {
  const _VinylSheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // 只在黑胶外圈画高光，封面标签保持干净不发灰。
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(rect)
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: radius * VinylRecord.labelRatio,
        ),
      );
    final sheen = SweepGradient(
      transform: const GradientRotation(-math.pi / 4),
      stops: const [0, 0.08, 0.18, 0.5, 0.58, 0.68, 1],
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.16),
        Colors.transparent,
        Colors.transparent,
        Colors.white.withValues(alpha: 0.09),
        Colors.transparent,
        Colors.transparent,
      ],
    );
    canvas.drawPath(ring, Paint()..shader = sheen.createShader(rect));
  }

  @override
  bool shouldRepaint(_VinylSheenPainter oldDelegate) => false;
}

/// 唱片旋转的惯性模型：速度按指数趋近目标速度，v(t) = vt + (v0 - vt)·e^(-kt)。
///
/// 起转时从当前速度平滑加速到匀速；停转时（目标 0）缓缓减速停下。
class VinylSpinSimulation extends Simulation {
  final double start;
  final double initialVelocity;
  final double targetVelocity;
  final double rate;

  VinylSpinSimulation({
    required this.start,
    required this.initialVelocity,
    required this.targetVelocity,
    required this.rate,
  });

  @override
  double x(double time) {
    final decay = 1 - math.exp(-rate * time);
    return start +
        targetVelocity * time +
        (initialVelocity - targetVelocity) * decay / rate;
  }

  @override
  double dx(double time) {
    return targetVelocity +
        (initialVelocity - targetVelocity) * math.exp(-rate * time);
  }

  @override
  bool isDone(double time) {
    return targetVelocity == 0 && dx(time).abs() < 1e-4;
  }
}
