import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPlatformService {
  AndroidPlatformService._();

  static final AndroidPlatformService instance = AndroidPlatformService._();

  static const MethodChannel _channel = MethodChannel(
    'com.feiniu.music/downloads',
  );

  int? _sdkInt;

  Future<int> sdkInt() async {
    if (!Platform.isAndroid) return 0;
    final cached = _sdkInt;
    if (cached != null) return cached;
    try {
      final value = await _channel.invokeMethod<int>('getAndroidSdkInt');
      _sdkInt = value ?? 0;
    } catch (_) {
      _sdkInt = 0;
    }
    return _sdkInt!;
  }

  /// 取出上一次进程异常退出的报告（Java 崩溃堆栈、logcat 中的致命日志；
  /// Android 11+ 另含系统记录的退出原因），读取后原生侧即清除。非 Android 或无记录返回 null。
  Future<String?> takeLastExitReport() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeLastExitReport');
    } catch (_) {
      return null;
    }
  }

  /// 本应用的系统日志（logcat）：`launch` 为本次启动时保存的快照（含上一
  /// 进程结束前的日志），`current` 为当前最新日志。非 Android 返回 null。
  Future<({String? launch, String? current})?> readLogcat() async {
    if (!Platform.isAndroid) return null;
    try {
      final map = await _channel.invokeMapMethod<String, String?>('readLogcat');
      if (map == null) return null;
      return (launch: map['launch'], current: map['current']);
    } catch (_) {
      return null;
    }
  }

  Future<bool> supportsNotificationCustomActions() async {
    if (!Platform.isAndroid) return true;
    final sdk = await sdkInt();
    if (sdk == 0) return false;
    // Media-style notification custom actions are supported on old Android
    // versions too. Low-version devices may show fewer actions depending on
    // the system UI/OEM skin, but the feature itself is available.
    return sdk >= 21;
  }
}
