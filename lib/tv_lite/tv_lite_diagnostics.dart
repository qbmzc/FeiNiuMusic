import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app/services/debug_log_service.dart';

/// 一个采样周期内的帧耗时与内存。
@immutable
class TvLiteStats {
  final int frames;
  final int jankyFrames;
  final int worstBuildMs;
  final int worstRasterMs;
  final int rssMb;
  final int maxRssMb;
  final int imageCacheMb;

  const TvLiteStats({
    required this.frames,
    required this.jankyFrames,
    required this.worstBuildMs,
    required this.worstRasterMs,
    required this.rssMb,
    required this.maxRssMb,
    required this.imageCacheMb,
  });

  double get jankPercent => frames == 0 ? 0 : jankyFrames * 100 / frames;

  String describe() {
    final jank = jankPercent.toStringAsFixed(1);
    return '帧 $frames，掉帧 $jankyFrames（$jank%），'
        '最慢构建 ${worstBuildMs}ms / 光栅 ${worstRasterMs}ms；'
        '内存 RSS ${rssMb}MB（峰值 ${maxRssMb}MB），图片缓存 ${imageCacheMb}MB';
  }
}

/// 精简版诊断：统计掉帧（构建或光栅超过一帧预算）与进程内存，每分钟写一行
/// 调试日志。投影上无法接 adb，手机扫码看日志即可判断是否流畅、内存是否
/// 持续上涨。
class TvLiteDiagnostics {
  TvLiteDiagnostics._();

  static final TvLiteDiagnostics instance = TvLiteDiagnostics._();

  static const Duration _interval = Duration(minutes: 1);
  static const int _frameBudgetMicros = 16667;

  /// Flutter 自带的帧耗时图层（遥控器菜单键或诊断页开关）。
  final ValueNotifier<bool> showPerformanceOverlay = ValueNotifier(false);

  /// 最近一个完整周期的统计，诊断页展示用。
  final ValueNotifier<TvLiteStats?> lastPeriod = ValueNotifier(null);

  Timer? _timer;
  int _frames = 0;
  int _janky = 0;
  int _worstBuildMicros = 0;
  int _worstRasterMicros = 0;

  void start() {
    if (_timer != null) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(_interval, (_) => _closePeriod());
    DebugLogService.instance.add('[TvLite] 启动 ${snapshot().describe()}');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// 当前周期（未满一分钟）的即时统计。
  TvLiteStats snapshot() {
    return TvLiteStats(
      frames: _frames,
      jankyFrames: _janky,
      worstBuildMs: _worstBuildMicros ~/ 1000,
      worstRasterMs: _worstRasterMicros ~/ 1000,
      rssMb: ProcessInfo.currentRss >> 20,
      maxRssMb: ProcessInfo.maxRss >> 20,
      imageCacheMb: PaintingBinding.instance.imageCache.currentSizeBytes >> 20,
    );
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      _frames++;
      if (build > _frameBudgetMicros || raster > _frameBudgetMicros) {
        _janky++;
      }
      if (build > _worstBuildMicros) _worstBuildMicros = build;
      if (raster > _worstRasterMicros) _worstRasterMicros = raster;
    }
  }

  void _closePeriod() {
    final stats = snapshot();
    lastPeriod.value = stats;
    DebugLogService.instance.add('[TvLite] ${stats.describe()}');
    _frames = 0;
    _janky = 0;
    _worstBuildMicros = 0;
    _worstRasterMicros = 0;
  }
}
