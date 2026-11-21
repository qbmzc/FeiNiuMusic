import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_glass_state.dart';
import 'settings_performance_state.dart';

class AppBackgroundSettings {
  static const String _prefsBackgroundImagePath =
      'setting_background_image_path';
  static const String _prefsBackgroundMaskOpacity =
      'setting_background_mask_opacity';
  static const String _prefsBackgroundBlurSigma =
      'setting_background_blur_sigma';
  static const String _prefsPageGlowEnabled = 'setting_page_glow_enabled';
  static const String _prefsPanelBlur = 'setting_panel_blur';
  static const String _prefsPanelBlurEnabled = 'setting_panel_blur_enabled';

  static final ValueNotifier<String?> backgroundImagePath = ValueNotifier(null);
  static final ValueNotifier<double> backgroundMaskOpacity = ValueNotifier(
    0.35,
  );
  // 0 = original sharp image, 32 = heavily blurred. Users kept complaining
  // that "透明度=0" still looked hazy — that was this constant-16 blur.
  static final ValueNotifier<double> backgroundBlurSigma = ValueNotifier(16);
  static final ValueNotifier<bool> pageGlowEnabled = ValueNotifier(false);
  /// 面板高斯模糊强度（0 = 无模糊，32 = 最大模糊）
  static final ValueNotifier<double> panelBlurStrength = ValueNotifier(20);
  /// 高斯模糊总开关。关闭后 [panelBlurStrength] 视为 0，各处不渲染模糊。
  static final ValueNotifier<bool> panelBlurEnabled = ValueNotifier(true);

  /// 生效的高斯模糊强度：总开关关闭或流畅模式时恒为 0。
  static double get effectivePanelBlur {
    if (AppPerformanceSettings.streamlinedMode.value) return 0.0;
    return panelBlurEnabled.value ? panelBlurStrength.value : 0.0;
  }

  /// [effectivePanelBlur] 的响应式版本：开关/强度/流畅模式变化时重算。
  /// 面板、导航栏、迷你播放器等统一监听它，不再各自组合两个 notifier。
  static final ValueNotifier<double> effectivePanelBlurValue =
      _DerivedNotifier<double>(() => effectivePanelBlur, [
        panelBlurEnabled,
        panelBlurStrength,
        AppPerformanceSettings.streamlinedMode,
      ]);

  /// 生效的背景图模糊：流畅模式恒为 0（跳过全屏 ImageFiltered）。
  static double get effectiveBackgroundBlurSigma {
    if (AppPerformanceSettings.streamlinedMode.value) return 0.0;
    return backgroundBlurSigma.value;
  }

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    backgroundImagePath.value = prefs.getString(_prefsBackgroundImagePath);
    backgroundMaskOpacity.value =
        (prefs.getDouble(_prefsBackgroundMaskOpacity) ?? 0.5).clamp(0.0, 1.0);
    backgroundBlurSigma.value =
        (prefs.getDouble(_prefsBackgroundBlurSigma) ?? 16).clamp(0.0, 32.0);
    pageGlowEnabled.value = prefs.getBool(_prefsPageGlowEnabled) ?? false;
    panelBlurStrength.value = (prefs.getDouble(_prefsPanelBlur) ?? 20).clamp(0.0, 32.0);
    panelBlurEnabled.value = prefs.getBool(_prefsPanelBlurEnabled) ?? true;
  }

  static Future<void> setBackgroundImagePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_prefsBackgroundImagePath);
      backgroundImagePath.value = null;
      return;
    }
    await prefs.setString(_prefsBackgroundImagePath, path);
    backgroundImagePath.value = path;
  }

  static Future<void> setBackgroundMaskOpacity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    final next = value.clamp(0.0, 1.0);
    await prefs.setDouble(_prefsBackgroundMaskOpacity, next);
    backgroundMaskOpacity.value = next;
  }

  static Future<void> setBackgroundBlurSigma(double value) async {
    final prefs = await SharedPreferences.getInstance();
    final next = value.clamp(0.0, 32.0);
    await prefs.setDouble(_prefsBackgroundBlurSigma, next);
    backgroundBlurSigma.value = next;
  }

  static Future<void> setPageGlowEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPageGlowEnabled, enabled);
    pageGlowEnabled.value = enabled;
  }

  static Future<void> setPanelBlur(double value) async {
    final prefs = await SharedPreferences.getInstance();
    final next = value.clamp(0.0, 32.0);
    await prefs.setDouble(_prefsPanelBlur, next);
    panelBlurStrength.value = next;
  }

  static Future<void> setPanelBlurEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPanelBlurEnabled, enabled);
    panelBlurEnabled.value = enabled;
    // 与液体玻璃互斥：开启高斯模糊时关闭液体玻璃。
    if (enabled) {
      await AppGlassSettings.setLiquidGlassEnabled(false);
    }
  }
}

/// 由若干来源派生的只读 notifier：任一来源变化时重算，值不变不通知。
class _DerivedNotifier<T> extends ValueNotifier<T> {
  _DerivedNotifier(this._compute, List<Listenable> sources)
    : super(_compute()) {
    for (final source in sources) {
      source.addListener(_update);
    }
  }

  final T Function() _compute;

  void _update() {
    value = _compute();
  }
}
