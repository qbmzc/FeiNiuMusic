import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/settings_state.dart';
import 'player_service.dart';

/// Windows / Linux 系统托盘服务。
///
/// - 托盘创建成功后拦截关闭按钮：设置开启时隐藏到托盘而不是退出应用；
/// - 托盘菜单提供歌曲信息、播放控制和退出，随播放状态实时刷新；
/// - Windows 单击托盘图标恢复主窗口，Linux 通过菜单恢复。
///
/// macOS 由原生 NSStatusItem 承担（MacosStatusBarService + 原生改动），
/// 本服务不处理（window_manager 在 macOS 会劫持窗口 delegate，与原生
/// windowShouldClose 冲突，故 macOS 走原生实现）。
class DesktopTrayService with WindowListener, TrayListener {
  DesktopTrayService._();

  static final DesktopTrayService instance = DesktopTrayService._();

  static bool get supported =>
      !kIsWeb && (_isWindows || defaultTargetPlatform == TargetPlatform.linux);

  static bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  // Windows 的 LoadImage 需要 ICO，Linux 的 AppIndicator 使用 PNG。
  static String get _iconAsset =>
      _isWindows ? 'assets/icon/app_icon.ico' : 'assets/icon/app_icon.png';

  static const String _kShow = 'show';
  static const String _kInfo = 'info';
  static const String _kPlayPause = 'playPause';
  static const String _kPrevious = 'previous';
  static const String _kNext = 'next';
  static const String _kQuit = 'quit';

  bool _started = false;
  bool _trayReady = false;
  bool _closeToTrayReady = false;

  static Future<void> init() async {
    if (!supported || instance._started) return;
    instance._started = true;

    try {
      await CloseToTraySettings.ensureLoaded();
      await WindowManager.instance.ensureInitialized();
      WindowManager.instance.addListener(instance);
      TrayManager.instance.addListener(instance);

      CloseToTraySettings.enabled.addListener(instance._onSettingChanged);
      AppPlayerState.instance.isPlaying.addListener(instance._refreshMenu);
      AppPlayerState.instance.currentSong.addListener(instance._refreshMenu);

      await instance._applySetting(CloseToTraySettings.enabled.value);
    } catch (error, stackTrace) {
      instance._removeListeners();
      instance._started = false;
      await instance._recoverFromTrayFailure(error, stackTrace);
    }
  }

  void _removeListeners() {
    WindowManager.instance.removeListener(this);
    TrayManager.instance.removeListener(this);
    CloseToTraySettings.enabled.removeListener(_onSettingChanged);
    AppPlayerState.instance.isPlaying.removeListener(_refreshMenu);
    AppPlayerState.instance.currentSong.removeListener(_refreshMenu);
  }

  @visibleForTesting
  static void resetForTest() {
    instance._removeListeners();
    instance._started = false;
    instance._trayReady = false;
    instance._closeToTrayReady = false;
  }

  Future<void> _onSettingChanged() async {
    await _applySetting(CloseToTraySettings.enabled.value);
  }

  Future<void> _applySetting(bool enabled) async {
    try {
      if (enabled) {
        await _ensureTray();
        _closeToTrayReady =
            _isWindows ||
            await const MethodChannel(
                  'com.feiniu.music/desktop_tray',
                ).invokeMethod<bool>('hasStatusNotifierHost') ==
                true;
        await WindowManager.instance.setPreventClose(_closeToTrayReady);
      } else {
        _closeToTrayReady = false;
        await WindowManager.instance.setPreventClose(false);
        await _destroyTray();
        // 关闭设置时恢复隐藏窗口，避免无托盘也找不到主窗口。
        if (!await WindowManager.instance.isVisible()) {
          await _showMainWindow();
        }
      }
    } catch (error, stackTrace) {
      await _recoverFromTrayFailure(error, stackTrace);
    }
  }

  Future<void> _ensureTray() async {
    if (_trayReady) return;
    await TrayManager.instance.setIcon(_iconAsset);
    if (_isWindows) {
      await TrayManager.instance.setToolTip('飞牛音乐');
    }
    await TrayManager.instance.setContextMenu(_buildMenu());
    _trayReady = true;
  }

  Future<void> _destroyTray() async {
    if (!_trayReady) return;
    _trayReady = false;
    await TrayManager.instance.destroy();
  }

  Future<void> _recoverFromTrayFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    _logFailure(error, stackTrace);
    _trayReady = false;
    _closeToTrayReady = false;
    try {
      await WindowManager.instance.setPreventClose(false);
    } catch (error, stackTrace) {
      _logFailure(error, stackTrace);
    }
    try {
      // setIcon 成功但菜单失败时，也清理尚未就绪的托盘。
      await TrayManager.instance.destroy();
    } catch (error, stackTrace) {
      _logFailure(error, stackTrace);
    }
    try {
      if (!await WindowManager.instance.isVisible()) {
        await _showMainWindow();
      }
    } catch (error, stackTrace) {
      _logFailure(error, stackTrace);
    }
  }

  static void _logFailure(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('DesktopTrayService: $error\n$stackTrace');
    }
  }

  Future<void> _refreshMenu() async {
    if (!_trayReady) return;
    try {
      // tray_manager 无增量更新：每次全量重建菜单。
      await TrayManager.instance.setContextMenu(_buildMenu());
    } catch (error, stackTrace) {
      await _recoverFromTrayFailure(error, stackTrace);
    }
  }

  Menu _buildMenu() {
    final state = AppPlayerState.instance;
    final song = state.currentSong.value;
    final isPlaying = state.isPlaying.value;
    final title = song?.title.trim() ?? '';
    final artist = song?.artistDisplayName.trim() ?? '';
    final info = song == null
        ? '飞牛音乐'
        : '${isPlaying ? '正在播放' : '已暂停'}：$title'
              '${artist.isEmpty ? '' : ' — $artist'}';

    return Menu(
      items: [
        MenuItem(key: _kInfo, label: info, disabled: true),
        MenuItem.separator(),
        if (defaultTargetPlatform == TargetPlatform.linux)
          MenuItem(key: _kShow, label: '显示主窗口'),
        MenuItem(key: _kPlayPause, label: isPlaying ? '暂停' : '播放'),
        MenuItem(key: _kPrevious, label: '上一首'),
        MenuItem(key: _kNext, label: '下一首'),
        MenuItem.separator(),
        MenuItem(key: _kQuit, label: '退出'),
      ],
    );
  }

  // ---- WindowListener ----

  @override
  void onWindowClose() async {
    // 托盘未就绪时不隐藏窗口，保留原生关闭行为。
    if (_closeToTrayReady && CloseToTraySettings.enabled.value) {
      await WindowManager.instance.hide();
    }
  }

  // ---- TrayListener ----

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kShow:
        unawaited(_showMainWindow());
      case _kPlayPause:
        unawaited(PlayerService.instance.togglePlayPause());
      case _kPrevious:
        unawaited(PlayerService.instance.previous());
      case _kNext:
        unawaited(PlayerService.instance.next());
      case _kQuit:
        unawaited(_quit());
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 单击/双击托盘图标：恢复并聚焦主窗口。
    unawaited(_showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows 原生不自动弹出菜单，Linux 不支持此方法。
    if (_isWindows) {
      unawaited(TrayManager.instance.popUpContextMenu());
    }
  }

  Future<void> _showMainWindow() async {
    if (await WindowManager.instance.isMinimized()) {
      await WindowManager.instance.restore();
    }
    await WindowManager.instance.show();
    await WindowManager.instance.focus();
  }

  Future<void> _quit() async {
    await _destroyTray();
    await WindowManager.instance.destroy();
  }
}
