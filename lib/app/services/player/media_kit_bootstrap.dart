import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// media_kit（libmpv）初始化入口，保证只执行一次。
///
/// 默认在启动时调用；流畅模式下的 Android 启动时跳过，由 MediaKitEngine
/// 在首次创建原生 Player 前调用，MP3/AAC/FLAC（走 ExoPlayer）不会加载 libmpv。
class MediaKitBootstrap {
  MediaKitBootstrap._();

  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      debugPrint('MediaKit.ensureInitialized failed: $e');
    }
  }
}
