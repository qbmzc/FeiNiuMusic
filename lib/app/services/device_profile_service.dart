import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备性能档案（仅 Android 有真实数据，其余平台为 [DeviceProfile.standard]）。
@immutable
class DeviceProfile {
  /// 总内存不超过该值视为低内存设备（1.5GiB，主要命中 1GB 投影/盒子）。
  static const int lowMemoryThresholdBytes = 1536 << 20;

  final int sdkInt;
  final bool isLowRamDevice;
  final int totalMemBytes;
  final int memoryClassMb;
  final bool is64Bit;

  const DeviceProfile({
    required this.sdkInt,
    required this.isLowRamDevice,
    required this.totalMemBytes,
    required this.memoryClassMb,
    required this.is64Bit,
  });

  /// 查询失败或非 Android：按标准设备处理，不触发任何降级。
  static const DeviceProfile standard = DeviceProfile(
    sdkInt: 0,
    isLowRamDevice: false,
    totalMemBytes: 0,
    memoryClassMb: 0,
    is64Bit: true,
  );

  factory DeviceProfile.fromMap(Map<Object?, Object?> map) {
    int readInt(String key) => (map[key] as num?)?.toInt() ?? 0;
    return DeviceProfile(
      sdkInt: readInt('sdkInt'),
      isLowRamDevice: map['isLowRamDevice'] == true,
      totalMemBytes: readInt('totalMemBytes'),
      memoryClassMb: readInt('memoryClassMb'),
      is64Bit: map['is64Bit'] != false,
    );
  }

  /// 系统声明低内存，或总内存不超过 [lowMemoryThresholdBytes]。
  bool get isLowMemory =>
      isLowRamDevice ||
      (totalMemBytes > 0 && totalMemBytes <= lowMemoryThresholdBytes);

  /// 如「1.0GB」，总内存未知时为空串。
  String get totalMemLabel {
    if (totalMemBytes <= 0) return '';
    return '${(totalMemBytes / (1 << 30)).toStringAsFixed(1)}GB';
  }

  @override
  String toString() =>
      'DeviceProfile(sdk=$sdkInt, lowRam=$isLowRamDevice, '
      'totalMem=$totalMemLabel, memoryClass=${memoryClassMb}MB, '
      '64bit=$is64Bit)';
}

/// 通过 `com.feiniu.music/tv` 通道查询 [DeviceProfile]，结果缓存。
class DeviceProfileService {
  DeviceProfileService._();

  static final DeviceProfileService instance = DeviceProfileService._();

  static const MethodChannel _channel = MethodChannel('com.feiniu.music/tv');

  Future<DeviceProfile>? _loading;

  Future<DeviceProfile> load() => _loading ??= _query();

  Future<DeviceProfile> _query() async {
    if (!Platform.isAndroid) return DeviceProfile.standard;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'getDeviceProfile',
      );
      if (map == null) return DeviceProfile.standard;
      final profile = DeviceProfile.fromMap(map);
      if (kDebugMode) debugPrint('[DeviceProfile] $profile');
      return profile;
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceProfile] query failed: $e');
      return DeviceProfile.standard;
    }
  }
}
