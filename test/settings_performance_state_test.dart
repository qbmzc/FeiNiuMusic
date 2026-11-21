import 'package:feiniu_music/app/services/device_profile_service.dart';
import 'package:feiniu_music/app/state/settings_state.dart';
import 'package:feiniu_music/pages/player/widgets/player_background.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lowMemProjector = DeviceProfile(
  sdkInt: 28,
  isLowRamDevice: false,
  totalMemBytes: 1 << 30,
  memoryClassMb: 128,
  is64Bit: false,
);

const _phone = DeviceProfile(
  sdkInt: 34,
  isLowRamDevice: false,
  totalMemBytes: 8 << 30,
  memoryClassMb: 512,
  is64Bit: true,
);

Future<void> _load(
  DeviceProfile profile, [
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  AppPerformanceSettings.resetForTest();
  AppPerformanceSettings.profileLoader = () async => profile;
  await AppPerformanceSettings.ensureLoaded();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppPerformanceSettings.resetForTest);

  group('DeviceProfile', () {
    test('1GB 或系统声明低内存判为低内存设备', () {
      expect(_lowMemProjector.isLowMemory, isTrue);
      expect(_lowMemProjector.totalMemLabel, '1.0GB');
      expect(
        DeviceProfile.fromMap(const {
          'isLowRamDevice': true,
          'totalMemBytes': 4 << 30,
        }).isLowMemory,
        isTrue,
      );
    });

    test('大内存手机与查询失败的标准档案不触发', () {
      expect(_phone.isLowMemory, isFalse);
      expect(DeviceProfile.standard.isLowMemory, isFalse);
      expect(DeviceProfile.fromMap(const {}).isLowMemory, isFalse);
    });
  });

  group('AppPerformanceSettings', () {
    test('低内存设备自动开启，普通手机自动关闭', () async {
      await _load(_lowMemProjector);
      expect(AppPerformanceSettings.streamlinedMode.value, isTrue);
      expect(AppPerformanceSettings.isAuto, isTrue);
      expect(AppPerformanceSettings.statusLabel, contains('1.0GB'));

      await _load(_phone);
      expect(AppPerformanceSettings.streamlinedMode.value, isFalse);
    });

    test('手动关闭写入覆盖，切回自动判定值时移除覆盖', () async {
      await _load(_lowMemProjector);
      await AppPerformanceSettings.setStreamlinedMode(false);
      expect(AppPerformanceSettings.streamlinedMode.value, isFalse);
      expect(AppPerformanceSettings.isAuto, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_streamlined_mode_override'), isFalse);

      await AppPerformanceSettings.setStreamlinedMode(true);
      expect(AppPerformanceSettings.isAuto, isTrue);
      expect(prefs.containsKey('setting_streamlined_mode_override'), isFalse);
    });

    test('持久化的手动开启在普通手机上生效', () async {
      await _load(_phone, {'setting_streamlined_mode_override': true});
      expect(AppPerformanceSettings.streamlinedMode.value, isTrue);
      expect(AppPerformanceSettings.statusLabel, '已手动开启');
    });

    test('图片缓存上限随模式切换', () {
      final cache = ImageCache();
      AppPerformanceSettings.streamlinedMode.value = true;
      AppPerformanceSettings.applyImageCacheLimits(cache);
      expect(cache.maximumSizeBytes, 48 << 20);
      expect(cache.maximumSize, 200);

      AppPerformanceSettings.streamlinedMode.value = false;
      AppPerformanceSettings.applyImageCacheLimits(cache);
      expect(cache.maximumSizeBytes, 100 << 20);
      expect(cache.maximumSize, 1000);
    });
  });

  group('流畅模式降级生效值', () {
    setUp(() {
      AppBackgroundSettings.panelBlurEnabled.value = true;
      AppBackgroundSettings.panelBlurStrength.value = 20;
      AppBackgroundSettings.backgroundBlurSigma.value = 16;
      AppGlassSettings.liquidGlassEnabled.value = true;
      AppLayoutSettings.tvMode.value = false;
      PlayerBackgroundSettings.dynamicGradientEnabled.value = true;
      PlayerBackgroundSettings.rotateCover.value = true;
    });

    test('开启后模糊/玻璃/流光/旋转生效值关闭，关闭后恢复且不改写偏好', () {
      expect(AppBackgroundSettings.effectivePanelBlurValue.value, 20);

      AppPerformanceSettings.streamlinedMode.value = true;
      expect(AppBackgroundSettings.effectivePanelBlurValue.value, 0);
      expect(AppBackgroundSettings.effectiveBackgroundBlurSigma, 0);
      expect(AppGlassSettings.effectiveEnabled, isFalse);
      expect(PlayerBackgroundSettings.effectiveDynamicGradient, isFalse);
      expect(PlayerBackgroundSettings.effectiveRotateCover, isFalse);
      expect(AppBackgroundSettings.panelBlurEnabled.value, isTrue);
      expect(AppGlassSettings.liquidGlassEnabled.value, isTrue);

      AppPerformanceSettings.streamlinedMode.value = false;
      expect(AppBackgroundSettings.effectivePanelBlurValue.value, 20);
      expect(AppBackgroundSettings.effectiveBackgroundBlurSigma, 16);
      expect(AppGlassSettings.effectiveEnabled, isTrue);
      expect(PlayerBackgroundSettings.effectiveDynamicGradient, isTrue);
    });

    test('玻璃 effectiveChanges 在流畅模式切换时通知', () {
      var calls = 0;
      void listener() => calls++;
      AppGlassSettings.effectiveChanges.addListener(listener);
      AppPerformanceSettings.streamlinedMode.value = true;
      AppGlassSettings.effectiveChanges.removeListener(listener);
      expect(calls, 1);
    });
  });
}
