import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feiniu_music/pages/player/desktop_lyrics_window.dart';

Map<String, Object?> _payload({
  bool karaoke = false,
  String? fontFamily = 'PingFang SC',
}) {
  return {
    'currentLine': '当前歌词',
    'nextLine': '下一句歌词',
    'karaoke': karaoke,
    'progress': 0.4,
    'fontFamily': fontFamily,
    'fontSize': 24.0,
    'textColor': 0xFFFFFFFF,
    'highlightColor': 0xFF59F7E7,
    'backgroundOpacity': 0.64,
  };
}

/// 还原 [Text] 实际生效的样式：MaterialApp 的兜底 [DefaultTextStyle]
/// 与自身 style 合并后的结果。
List<TextStyle> _resolvedStylesOf(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: '未找到歌词文本 $text');
  final styles = <TextStyle>[];
  for (var index = 0; index < finder.evaluate().length; index++) {
    final inherited = DefaultTextStyle.of(
      tester.element(finder.at(index)),
    ).style;
    final own = tester.widget<Text>(finder.at(index)).style;
    styles.add(own == null ? inherited : inherited.merge(own));
  }
  return styles;
}

void main() {
  testWidgets('歌词不继承 MaterialApp 兜底样式的下划线', (tester) async {
    final state = DesktopLyricsWindowState()..update(_payload());

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    for (final text in <String>['当前歌词', '下一句歌词']) {
      for (final style in _resolvedStylesOf(tester, text)) {
        expect(
          style.decoration ?? TextDecoration.none,
          TextDecoration.none,
          reason: '$text 不应带下划线（MaterialApp 兜底样式为 underline）',
        );
        expect(style.decorationStyle, isNot(TextDecorationStyle.double));
      }
    }
  });

  testWidgets('未配置字体时不使用 monospace 兜底字体', (tester) async {
    final state = DesktopLyricsWindowState()
      ..update(_payload(fontFamily: null));

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    for (final style in _resolvedStylesOf(tester, '当前歌词')) {
      expect(style.fontFamily, isNull);
    }
  });

  testWidgets('逐字歌词同样不带下划线', (tester) async {
    final state = DesktopLyricsWindowState()..update(_payload(karaoke: true));

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    for (final text in <String>['当前歌词', '下一句歌词']) {
      for (final style in _resolvedStylesOf(tester, text)) {
        expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
      }
    }
  });

  testWidgets('逐字歌词高亮层与底字完全重合（不出现两份歌词）', (tester) async {
    final state = DesktopLyricsWindowState()..update(_payload(karaoke: true));

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    // 逐字歌词渲染两层：底层整行 + 上层高亮扫光。两层必须叠在同一位置，
    // 否则看起来就是同一句歌词出现在两个地方。
    final finder = find.text('当前歌词');
    expect(finder, findsNWidgets(2), reason: '逐字歌词应渲染底字 + 高亮两层');

    final base = tester.getRect(finder.at(0));
    final highlight = tester.getRect(finder.at(1));
    expect(
      highlight.left,
      closeTo(base.left, 0.5),
      reason: '高亮层左边缘应与底字对齐（当前 left=${highlight.left}, 底字 left=${base.left}）',
    );
    expect(highlight.top, closeTo(base.top, 0.5), reason: '高亮层应与底字同一行');
    expect(highlight.width, closeTo(base.width, 0.5));
  });

  testWidgets('背景透明度和歌词可以在暂停时更新', (tester) async {
    final state = DesktopLyricsWindowState()..update(_payload());
    await tester.pumpWidget(DesktopLyricsWindow(state: state));
    state.update({
      ..._payload(),
      'backgroundOpacity': 0.0,
      'currentLine': '新歌词',
    });
    await tester.pump();
    expect(find.text('新歌词'), findsOneWidget);
    expect(find.text('当前歌词'), findsNothing);
    final background =
        tester
                .widget<Container>(
                  find
                      .byWidgetPredicate(
                        (widget) =>
                            widget is Container &&
                            widget.decoration is BoxDecoration,
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(background.color!.a, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('Linux 自由拖动使用原生移动，锁定后禁止拖动', (tester) async {
    const native = MethodChannel('window_manager');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        native,
        null,
      ),
    );
    final state = DesktopLyricsWindowState()
      ..update({..._payload(), 'position': 'free'});
    await tester.pumpWidget(DesktopLyricsWindow(state: state));
    await tester.drag(find.text('当前歌词'), const Offset(100, 20));
    expect(calls.map((call) => call.method), ['startDragging']);
    state.update({..._payload(), 'position': 'locked'});
    await tester.pump();
    await tester.drag(find.text('当前歌词'), const Offset(100, 20));
    expect(calls, hasLength(1));
    state.update({..._payload(), 'position': 'free'});
    await tester.pump();
    await tester.drag(find.text('当前歌词'), const Offset(100, 20));
    expect(calls.map((call) => call.method), [
      'startDragging',
      'startDragging',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  }, skip: !Platform.isLinux);

  testWidgets('Linux 窗口初始化和锁定不调用不支持的插件接口', (tester) async {
    const manager = MethodChannel('window_manager');
    const native = MethodChannel(
      'com.feiniu.music/desktop_lyrics_window/native',
    );
    const screen = MethodChannel('dev.leanflutter.plugins/screen_retriever');
    const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
    const channel = WindowMethodChannel(
      'com.feiniu.music/desktop_lyrics_window',
    );
    final managerCalls = <MethodCall>[];
    final nativeCalls = <MethodCall>[];
    final bridgeCalls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      managerCalls.add(call);
      if (call.method == 'setHasShadow' ||
          call.method == 'setIgnoreMouseEvents') {
        throw MissingPluginException(call.method);
      }
      if (call.method.startsWith('is')) return false;
      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': 760.0, 'height': 112.0};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      nativeCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(bridge, (call) async {
      bridgeCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(screen, (call) async {
      const display = {
        'id': 'test',
        'size': {'width': 1280.0, 'height': 720.0},
        'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      };
      return switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => {
          'displays': [display],
        },
        'getCursorScreenPoint' => {'dx': 0.0, 'dy': 0.0},
        _ => null,
      };
    });
    addTearDown(() async {
      await channel.setMethodCallHandler(null);
      for (final value in [manager, native, bridge, screen]) {
        messenger.setMockMethodCallHandler(value, null);
      }
    });
    await runDesktopLyricsWindow(WindowController.fromWindowId('test'));
    await tester.pump();
    expect(bridgeCalls.last.arguments['method'], 'ready');
    expect(managerCalls.map((call) => call.method), contains('setAsFrameless'));
    expect(nativeCalls.single.method, 'setIgnoreMouseEvents');
    expect(nativeCalls.single.arguments, false);

    Future<void> send(String method, Object? arguments) async {
      const codec = StandardMethodCodec();
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        bridge.name,
        codec.encodeMethodCall(
          MethodCall('methodCall', {
            'channel': channel.name,
            'method': method,
            'arguments': arguments,
          }),
        ),
        (reply) {
          try {
            codec.decodeEnvelope(reply!);
            done.complete();
          } catch (error, stack) {
            done.completeError(error, stack);
          }
        },
      );
      await done.future;
    }

    await send('setState', _payload());
    await send('position', {'mode': 'locked', 'x': 10.0, 'y': 20.0});
    await send('show', null);
    await tester.pump();
    expect(find.text('当前歌词'), findsOneWidget);
    expect(nativeCalls.map((call) => call.method), [
      'setIgnoreMouseEvents',
      'setIgnoreMouseEvents',
      'showPassive',
    ]);
    expect(nativeCalls[1].arguments, true);
    final count = managerCalls
        .where((call) => call.method == 'setBounds')
        .length;
    await send('position', {'mode': 'locked', 'x': 10.0, 'y': 20.0});
    expect(
      managerCalls.where((call) => call.method == 'setBounds'),
      hasLength(count),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isLinux);
}
