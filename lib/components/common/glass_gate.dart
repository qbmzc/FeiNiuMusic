import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';

/// 液体玻璃双分支门控。
///
/// 单一事实来源：[AppGlassSettings.effectiveEnabled]（开关开启且非 TV、
/// 非流畅模式）。开启时渲染 [glass]（液体玻璃变体），否则渲染 [original]
/// （原有 BackdropFilter/实色方案）——任一来源变化即时原位切换，无需重启。
class GlassGate extends StatelessWidget {
  /// 现有组件（纯回退路径，保持字节级不变）。
  final Widget original;

  /// 液体玻璃变体。
  final Widget glass;

  const GlassGate({super.key, required this.original, required this.glass});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppGlassSettings.effectiveChanges,
      builder: (context, _) {
        return AppGlassSettings.effectiveEnabled ? glass : original;
      },
    );
  }
}
