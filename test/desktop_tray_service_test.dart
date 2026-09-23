import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:feiniu_music/app/services/desktop_tray_service.dart';
import 'package:feiniu_music/app/state/player_state.dart';
import 'package:feiniu_music/app/state/settings_close_to_tray_state.dart';

const _trayChannel = MethodChannel('tray_manager');
const _windowChannel = MethodChannel('window_manager');
const _nativeChannel = MethodChannel('com.feiniu.music/desktop_tray');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalDebugPrint = debugPrint;
  final trayCalls = <MethodCall>[];
  final windowCalls = <MethodCall>[];
  final calls = <String>[];
  final logs = <String>[];
  String? failingTrayMethod;
  String? failingWindowMethod;
  Completer<void>? menuGate;
  var visible = true;
  var minimized = false;

  List<Map<dynamic, dynamic>> menuItems() {
    final arguments =
        trayCalls.lastWhere((call) => call.method == 'setContextMenu').arguments
            as Map;
    return ((arguments['menu'] as Map)['items'] as List)
        .cast<Map<dynamic, dynamic>>();
  }

  Iterable<bool> preventCloseValues() => windowCalls
      .where((call) => call.method == 'setPreventClose')
      .map((call) => (call.arguments as Map)['isPreventClose'] as bool);

  setUp(() {
    DesktopTrayService.resetForTest();
    SharedPreferences.setMockInitialValues({});
    CloseToTraySettings.resetForTest();
    AppPlayerState.instance.currentSong.value = null;
    AppPlayerState.instance.isPlaying.value = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    trayCalls.clear();
    windowCalls.clear();
    calls.clear();
    logs.clear();
    failingTrayMethod = null;
    failingWindowMethod = null;
    menuGate = null;
    visible = true;
    minimized = false;

    messenger.setMockMethodCallHandler(_trayChannel, (call) async {
      trayCalls.add(call);
      calls.add('tray.${call.method}');
      if (defaultTargetPlatform == TargetPlatform.linux &&
          !{
            'destroy',
            'setIcon',
            'setTitle',
            'setContextMenu',
          }.contains(call.method)) {
        throw MissingPluginException(call.method);
      }
      if (call.method == failingTrayMethod) {
        throw PlatformException(code: 'test_failure', message: call.method);
      }
      if (call.method == 'setContextMenu') await menuGate?.future;
      return null;
    });
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async => true);
    messenger.setMockMethodCallHandler(_windowChannel, (call) async {
      windowCalls.add(call);
      calls.add('window.${call.method}');
      if (call.method == failingWindowMethod &&
          (call.arguments as Map)['isPreventClose'] == true) {
        throw PlatformException(code: 'test_failure', message: call.method);
      }
      switch (call.method) {
        case 'isVisible':
          return visible;
        case 'isMinimized':
          return minimized;
        case 'hide':
          visible = false;
        case 'show':
          visible = true;
        case 'restore':
          minimized = false;
      }
      return null;
    });
  });

  tearDown(() async {
    if (menuGate != null && !menuGate!.isCompleted) menuGate!.complete();
    await pumpEventQueue();
    DesktopTrayService.resetForTest();
    CloseToTraySettings.resetForTest();
    AppPlayerState.instance.isPlaying.value = false;
    messenger.setMockMethodCallHandler(_trayChannel, null);
    messenger.setMockMethodCallHandler(_windowChannel, null);
    messenger.setMockMethodCallHandler(_nativeChannel, null);
    debugPrint = originalDebugPrint;
    debugDefaultTargetPlatformOverride = null;
  });

  test('Linux 使用 PNG，跳过 tooltip 和手动弹出菜单', () async {
    expect(DesktopTrayService.supported, isTrue);
    await DesktopTrayService.init();
    final icon = trayCalls.singleWhere((call) => call.method == 'setIcon');
    expect(
      (icon.arguments['iconPath'] as String).replaceAll('\\', '/'),
      endsWith('assets/icon/app_icon.png'),
    );
    expect(calls, [
      'window.ensureInitialized',
      'tray.setIcon',
      'tray.setContextMenu',
      'window.setPreventClose',
    ]);
    expect(preventCloseValues(), [true]);

    DesktopTrayService.instance.onTrayIconRightMouseDown();
    await pumpEventQueue();
    expect(trayCalls.map((call) => call.method), ['setIcon', 'setContextMenu']);
    expect(logs, isEmpty);
  });

  test('Linux 菜单可恢复隐藏且最小化的主窗口', () async {
    await DesktopTrayService.init();
    final show = menuItems().singleWhere((item) => item['label'] == '显示主窗口');
    expect(show['disabled'], isFalse);
    visible = false;
    minimized = true;
    windowCalls.clear();

    DesktopTrayService.instance.onTrayMenuItemClick(
      MenuItem(key: show['key'] as String),
    );
    await pumpEventQueue();

    expect(windowCalls.map((call) => call.method), [
      'isMinimized',
      'restore',
      'isMinimized',
      'show',
      'focus',
    ]);
    expect(visible, isTrue);
    expect(minimized, isFalse);
  });

  test('菜单完成前不拦截关闭，也不隐藏主窗口', () async {
    menuGate = Completer<void>();
    final initialization = DesktopTrayService.init();
    await pumpEventQueue();
    expect(trayCalls.map((call) => call.method), contains('setContextMenu'));
    expect(preventCloseValues(), isEmpty);

    DesktopTrayService.instance.onWindowClose();
    await pumpEventQueue();
    expect(windowCalls.map((call) => call.method), isNot(contains('hide')));

    menuGate!.complete();
    await initialization;
    expect(preventCloseValues(), [true]);
  });

  test('Windows 保留 ICO、tooltip、单击恢复和右键菜单', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(DesktopTrayService.supported, isTrue);
    await DesktopTrayService.init();
    final icon = trayCalls.singleWhere((call) => call.method == 'setIcon');
    expect(
      (icon.arguments['iconPath'] as String).replaceAll('\\', '/'),
      endsWith('assets/icon/app_icon.ico'),
    );
    expect(calls, [
      'window.ensureInitialized',
      'tray.setIcon',
      'tray.setToolTip',
      'tray.setContextMenu',
      'window.setPreventClose',
    ]);
    expect(
      trayCalls.singleWhere((call) => call.method == 'setToolTip').arguments,
      {'toolTip': '飞牛音乐'},
    );
    expect(menuItems().map((item) => item['key']), [
      'info',
      null,
      'playPause',
      'previous',
      'next',
      null,
      'quit',
    ]);

    visible = false;
    DesktopTrayService.instance.onTrayIconMouseDown();
    DesktopTrayService.instance.onTrayIconRightMouseDown();
    await pumpEventQueue();
    expect(
      windowCalls.map((call) => call.method),
      containsAllInOrder(['isMinimized', 'show', 'focus']),
    );
    expect(trayCalls.last.method, 'popUpContextMenu');
    expect(visible, isTrue);
    expect(logs, isEmpty);
  });

  for (final method in ['setIcon', 'setContextMenu']) {
    test('Linux $method 失败时保持可关闭且不隐藏窗口', () async {
      failingTrayMethod = method;
      await DesktopTrayService.init();
      expect(preventCloseValues(), [false]);
      expect(trayCalls.last.method, 'destroy');
      expect(logs.join('\n'), contains(method));

      DesktopTrayService.instance.onWindowClose();
      await pumpEventQueue();
      expect(windowCalls.map((call) => call.method), isNot(contains('hide')));
      expect(visible, isTrue);
    });
  }

  test('拦截关闭失败时清理托盘并恢复隐藏窗口', () async {
    failingWindowMethod = 'setPreventClose';
    visible = false;
    await DesktopTrayService.init();
    expect(preventCloseValues(), [true, false]);
    expect(trayCalls.last.method, 'destroy');
    expect(visible, isTrue);
    expect(logs.join('\n'), contains('setPreventClose'));

    DesktopTrayService.instance.onWindowClose();
    await pumpEventQueue();
    expect(windowCalls.map((call) => call.method), isNot(contains('hide')));
  });

  test('关闭到托盘后禁用设置，先解除拦截再销毁并显示主窗口', () async {
    await DesktopTrayService.init();
    DesktopTrayService.instance.onWindowClose();
    await pumpEventQueue();
    expect(visible, isFalse);
    calls.clear();

    await CloseToTraySettings.setEnabled(false);
    await pumpEventQueue();
    expect(preventCloseValues(), [true, false]);
    expect(
      calls,
      containsAllInOrder([
        'window.setPreventClose',
        'tray.destroy',
        'window.show',
        'window.focus',
      ]),
    );
    expect(visible, isTrue);
  });

  test('Linux 没有托盘宿主时保留关闭窗口行为', () async {
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async => false);
    await DesktopTrayService.init();
    expect(preventCloseValues(), [false]);
    DesktopTrayService.instance.onWindowClose();
    await pumpEventQueue();
    expect(windowCalls.map((call) => call.method), isNot(contains('hide')));
  });

  test('初始设置关闭时不创建托盘', () async {
    SharedPreferences.setMockInitialValues({'close_to_tray_enabled': false});
    await DesktopTrayService.init();
    expect(trayCalls, isEmpty);
    expect(preventCloseValues(), [false]);
    DesktopTrayService.instance.onWindowClose();
    await pumpEventQueue();
    expect(windowCalls.map((call) => call.method), isNot(contains('hide')));
  });

  test('播放状态变化后仍保留 Linux 恢复入口', () async {
    await DesktopTrayService.init();
    AppPlayerState.instance.isPlaying.value = true;
    await pumpEventQueue();
    expect(
      menuItems().singleWhere((item) => item['key'] == 'playPause')['label'],
      '暂停',
    );
    expect(menuItems().where((item) => item['label'] == '显示主窗口'), hasLength(1));
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.fuchsia,
  ]) {
    test('$platform 不初始化此托盘服务', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(DesktopTrayService.supported, isFalse);
      await DesktopTrayService.init();
      expect(calls, isEmpty);
    });
  }
}
