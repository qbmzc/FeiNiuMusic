import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_profile_service.dart';

/// 流畅模式：面向 1GB 内存 / 弱 GPU 的 Android 设备（投影、电视盒子）。
///
/// 开启后强制关闭液体玻璃、高斯模糊、背景图模糊、播放页动态流光等重渲染
/// 效果，收紧图片缓存，跳过高刷切换，并在启动时不加载 libmpv。不会改写
/// 用户已保存的视觉偏好：关闭流畅模式即恢复原样。
///
/// 持久化键不存在时为「自动」：低内存 Android 设备自动开启；用户在设置页
/// 切换后写入显式值。切回与自动判定一致的值时移除键，重新跟随自动判定。
class AppPerformanceSettings {
  static const String _prefsStreamlinedOverride =
      'setting_streamlined_mode_override';

  /// 流畅模式下的图片缓存上限。张数放宽到 200，避免一屏封面占满后
  /// 来回滚动反复解码；内存主要靠字节上限约束。
  static const int streamlinedImageCacheSize = 200;
  static const int streamlinedImageCacheBytes = 48 << 20;

  /// Flutter 默认的图片缓存上限，关闭流畅模式时恢复。
  static const int defaultImageCacheSize = 1000;
  static const int defaultImageCacheBytes = 100 << 20;

  /// 生效值：是否处于流畅模式。
  static final ValueNotifier<bool> streamlinedMode = ValueNotifier(false);

  static DeviceProfile _profile = DeviceProfile.standard;

  /// 测试可替换：读取设备档案。
  @visibleForTesting
  static Future<DeviceProfile> Function() profileLoader =
      DeviceProfileService.instance.load;
  static bool? _override;
  static Future<void>? _loading;

  static DeviceProfile get profile => _profile;

  /// 自动判定结果（不考虑用户覆盖）。
  static bool get autoRecommended => _profile.isLowMemory;

  /// 是否跟随自动判定（用户未手动切换过）。
  static bool get isAuto => _override == null;

  /// 设置页副标题。
  static String get statusLabel {
    if (!isAuto) {
      return streamlinedMode.value ? '已手动开启' : '已手动关闭';
    }
    if (autoRecommended) {
      final mem = _profile.totalMemLabel;
      return mem.isEmpty ? '自动开启：检测到低内存设备' : '自动开启：检测到低内存设备（$mem）';
    }
    return '自动：当前设备无需开启';
  }

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    _profile = await profileLoader();
    final prefs = await SharedPreferences.getInstance();
    _override = prefs.getBool(_prefsStreamlinedOverride);
    _recompute();
  }

  static Future<void> setStreamlinedMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled == autoRecommended) {
      await prefs.remove(_prefsStreamlinedOverride);
      _override = null;
    } else {
      await prefs.setBool(_prefsStreamlinedOverride, enabled);
      _override = enabled;
    }
    _recompute();
  }

  static void _recompute() {
    streamlinedMode.value = _override ?? autoRecommended;
  }

  /// 按当前模式设置图片缓存上限。缩小上限时 [ImageCache] 会立即淘汰超出部分。
  static void applyImageCacheLimits(ImageCache cache) {
    if (streamlinedMode.value) {
      cache
        ..maximumSize = streamlinedImageCacheSize
        ..maximumSizeBytes = streamlinedImageCacheBytes;
    } else {
      cache
        ..maximumSize = defaultImageCacheSize
        ..maximumSizeBytes = defaultImageCacheBytes;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _loading = null;
    _override = null;
    _profile = DeviceProfile.standard;
    profileLoader = DeviceProfileService.instance.load;
    streamlinedMode.value = false;
  }
}
