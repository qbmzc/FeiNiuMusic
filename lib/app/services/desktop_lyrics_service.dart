import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as fl;

import '../state/settings_desktop_lyrics_state.dart';
import 'lyrics/lyrics_service.dart';
import 'player_service.dart';

const desktopLyricsWindowArgument = 'desktopLyrics';
const desktopLyricsWindowChannel = 'com.feiniu.music/desktop_lyrics_window';

/// 跨平台桌面歌词服务。
///
/// macOS、Windows、Linux 共用 Flutter 第二窗口和同一套歌词渲染；平台原生
/// runner 只负责让第二窗口可创建，避免三端各维护一套字体/颜色绘制代码。
class DesktopLyricsService {
  static const _channel = WindowMethodChannel(
    desktopLyricsWindowChannel,
    mode: ChannelMode.bidirectional,
  );

  static bool _started = false;
  static bool _windowReady = false;
  static bool _creating = false;
  static bool _syncQueued = false;
  static bool _syncing = false;
  static bool _visible = false;
  static Map<String, Object?>? _lastPayload;
  static Map<String, Object?>? _lastPosition;
  static WindowController? _window;

  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static Future<void> init() async {
    if (!supported || _started) return;
    await DesktopLyricsSettings.ensureLoaded();
    _started = true;
    await _channel.setMethodCallHandler((call) async {
      if (call.method == 'ready') {
        _windowReady = true;
        _visible = false;
        _lastPayload = null;
        _lastPosition = null;
        _queueSync();
      } else if (call.method == 'draggedPosition' && call.arguments is Map) {
        final arguments = Map<String, Object?>.from(call.arguments as Map);
        final x = (arguments['x'] as num?)?.toDouble();
        final y = (arguments['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          await DesktopLyricsSettings.setLockedPosition(x, y);
          _queueSync();
        }
      }
      return null;
    });
    for (final notifier in <Listenable>[
      DesktopLyricsSettings.enabled,
      DesktopLyricsSettings.fontFamily,
      DesktopLyricsSettings.fontSize,
      DesktopLyricsSettings.textColor,
      DesktopLyricsSettings.highlightColor,
      DesktopLyricsSettings.backgroundOpacity,
      DesktopLyricsSettings.position,
      LyricsService.instance.currentLineText,
      LyricsService.instance.controller.activeIndexNotifiter,
      LyricsService.instance.controller.lyricNotifier,
      PlayerService.instance.currentSong,
      PlayerService.instance.position,
    ]) {
      notifier.addListener(_queueSync);
    }
    onWindowsChanged.listen((_) async {
      final window = _window;
      if (window == null) return;
      try {
        final windows = await WindowController.getAll();
        if (_window == window &&
            !windows.any(
              (candidate) => candidate.windowId == window.windowId,
            )) {
          _window = null;
          _windowReady = false;
          _queueSync();
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('desktop lyrics window lookup failed: $error');
        }
      }
    });
    _queueSync();
  }

  @visibleForTesting
  static double progressForLine({
    required fl.LyricLine line,
    required Duration position,
    Duration? nextLineStart,
  }) {
    final lineEnd =
        line.end ?? nextLineStart ?? line.start + const Duration(seconds: 3);
    if (position <= line.start) return 0;
    if (position >= lineEnd) return 1;
    final words = line.words;
    if (words == null || words.isEmpty) {
      final durationMs = (lineEnd - line.start).inMilliseconds;
      if (durationMs <= 0) return 0;
      return ((position - line.start).inMilliseconds / durationMs).clamp(
        0.0,
        1.0,
      );
    }
    final totalUnits = words.fold<int>(
      0,
      (sum, word) => sum + word.text.runes.length,
    );
    if (totalUnits == 0) return 0;
    var completedUnits = 0.0;
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final wordEnd =
          word.end ??
          (index + 1 < words.length ? words[index + 1].start : lineEnd);
      if (position >= wordEnd) {
        completedUnits += word.text.runes.length;
        continue;
      }
      if (position <= word.start) break;
      final durationMs = (wordEnd - word.start).inMilliseconds;
      if (durationMs > 0) {
        completedUnits +=
            word.text.runes.length *
            ((position - word.start).inMilliseconds / durationMs).clamp(
              0.0,
              1.0,
            );
      }
      break;
    }
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }

  @visibleForTesting
  static Map<String, Object?>? buildPayload({
    required bool enabled,
    required String? title,
    required List<fl.LyricLine> lines,
    required int activeIndex,
    required Duration position,
  }) {
    if (!enabled || title == null || title.trim().isEmpty) return null;
    if (lines.isEmpty) {
      return const {
        'currentLine': '暂无歌词',
        'nextLine': '',
        'progress': 0.0,
        'karaoke': false,
      };
    }
    if (activeIndex < 0 || activeIndex >= lines.length) {
      activeIndex = lines.lastIndexWhere((line) => line.start <= position);
      if (activeIndex < 0) activeIndex = 0;
    }
    final current = lines[activeIndex];
    final next = activeIndex + 1 < lines.length ? lines[activeIndex + 1] : null;
    return {
      'currentLine': current.text.trim(),
      'nextLine': next?.text.trim() ?? '',
      'progress': progressForLine(
        line: current,
        position: position,
        nextLineStart: next?.start,
      ),
      // 只有原始歌词带逐字时间轴时才启用扫光；普通 LRC 保持整行固定。
      'karaoke': current.words?.isNotEmpty == true,
    };
  }

  static void _queueSync() {
    _syncQueued = true;
    if (_syncing) return;
    _syncing = true;
    scheduleMicrotask(() async {
      try {
        while (_syncQueued) {
          _syncQueued = false;
          try {
            await _sync();
          } catch (error) {
            _lastPayload = null;
            _lastPosition = null;
            _visible = false;
            if (kDebugMode) debugPrint('desktop lyrics sync failed: $error');
          }
        }
      } finally {
        _syncing = false;
      }
    });
  }

  static Future<void> _send(String method, [Object? arguments]) => _channel
      .invokeMethod<void>(method, arguments)
      .timeout(const Duration(seconds: 2));

  static Future<void> _sync() async {
    final player = PlayerService.instance;
    final lyrics = LyricsService.instance;
    final payload = buildPayload(
      enabled: DesktopLyricsSettings.enabled.value,
      title: player.currentSong.value?.title,
      lines: lyrics.controller.lyricNotifier.value?.lines ?? const [],
      activeIndex: lyrics.controller.activeIndexNotifiter.value,
      position: player.position.value,
    );
    if (payload == null) {
      if (_windowReady && _visible) {
        await _send('hide');
        _visible = false;
      }
      return;
    }
    await _ensureWindow();
    if (!_windowReady) return;
    final state = <String, Object?>{
      ...payload,
      'fontFamily': DesktopLyricsSettings.fontFamily.value,
      'fontSize': DesktopLyricsSettings.fontSize.value,
      'textColor': DesktopLyricsSettings.textColor.value,
      'highlightColor': DesktopLyricsSettings.highlightColor.value,
      'backgroundOpacity': DesktopLyricsSettings.backgroundOpacity.value,
      'position': DesktopLyricsSettings.position.value,
    };
    if (!mapEquals(state, _lastPayload)) {
      await _send('setState', state);
      _lastPayload = state;
    }
    final position = <String, Object?>{
      'mode': DesktopLyricsSettings.position.value,
      'x': DesktopLyricsSettings.lockedPositionX,
      'y': DesktopLyricsSettings.lockedPositionY,
    };
    if (!mapEquals(position, _lastPosition)) {
      await _send('position', position);
      _lastPosition = position;
    }
    if (!_visible) {
      await _send('show');
      _visible = true;
    }
  }

  static Future<void> _ensureWindow() async {
    if (_window != null || _creating) return;
    _creating = true;
    try {
      _window = await WindowController.create(
        const WindowConfiguration(
          arguments: desktopLyricsWindowArgument,
          hiddenAtLaunch: true,
        ),
      );
    } catch (_) {
      _window = null;
    } finally {
      _creating = false;
    }
  }

  /// 供启动入口识别第二窗口，避免重复初始化登录、播放器和数据库。
  static bool isDesktopLyricsWindow(String arguments) {
    if (arguments == desktopLyricsWindowArgument) return true;
    try {
      return jsonDecode(arguments)['type'] == desktopLyricsWindowArgument;
    } catch (_) {
      return false;
    }
  }
}
