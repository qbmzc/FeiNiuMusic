import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feiniu_music/pages/player/desktop_lyrics_window.dart';

Map<String, Object?> _payload({
  bool karaoke = false,
  String? fontFamily = 'PingFang SC',
  String position = 'free',
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
    'position': position,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('直接点击歌词窗口的小锁即可请求锁定', (tester) async {
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final state = DesktopLyricsWindowState()..update(_payload());
    bool? requestedLock;

    await tester.pumpWidget(
      DesktopLyricsWindow(
        state: state,
        onLockChanged: (locked) async {
          requestedLock = locked;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('desktop-lyrics-lock')));
    await tester.pump();

    expect(requestedLock, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('忽略旧透明度配置，歌词始终没有背景或边框', (tester) async {
    final state = DesktopLyricsWindowState()
      ..update({..._payload(), 'backgroundOpacity': 0.9});

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    final gesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('desktop-lyrics-drag-area')),
    );
    final container = gesture.child! as Container;
    expect(container.color, isNull);
    expect(container.decoration, isNull);
    expect(find.byTooltip('锁定歌词位置'), findsOneWidget);
  });

  testWidgets('锁定后不接收拖动手势且可以找到解锁按钮', (tester) async {
    final state = DesktopLyricsWindowState()
      ..update(_payload(position: 'locked'));

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    final gesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('desktop-lyrics-drag-area')),
    );
    expect(gesture.onPanStart, isNull);
    expect(gesture.onPanUpdate, isNull);
    expect(gesture.onPanEnd, isNull);
    expect(find.byTooltip('解锁歌词'), findsOneWidget);
  });

  testWidgets('只有自由拖动模式接收拖动手势', (tester) async {
    final state = DesktopLyricsWindowState()
      ..update(_payload(position: 'free'));

    await tester.pumpWidget(DesktopLyricsWindow(state: state));

    final gesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('desktop-lyrics-drag-area')),
    );
    expect(gesture.onPanStart, isNotNull);
    expect(gesture.onPanUpdate, isNotNull);
    expect(gesture.onPanEnd, isNotNull);
  });
}
