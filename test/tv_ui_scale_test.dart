import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/state/settings_layout_state.dart';
import 'package:feiniu_music/app/tv/tv_layout.dart';
import 'package:feiniu_music/app/tv/tv_ui_scale.dart';
import 'package:feiniu_music/pages/settings/app_appearance_settings_page.dart';
import 'package:feiniu_music/pages/settings/settings_page.dart';

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => TvUiScale(child: child!),
      home: home,
    );

Widget _withSidebar(Widget page) => LayoutBuilder(
  builder: (context, constraints) {
    final width = constraints.maxWidth;
    final sidebarWidth = (width * .28)
        .clamp(320.0, 360.0)
        .clamp(0.0, width * .45);
    return Row(
      children: [
        SizedBox(width: sidebarWidth),
        Expanded(child: page),
      ],
    );
  },
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLayoutSettings.resetForTest();
    await AppLayoutSettings.ensureLoaded();
    await AppLayoutSettings.setForceTvMode(true);
    await AppLayoutSettings.setTvUiScaleOverride(2);
  });
  tearDown(AppLayoutSettings.resetForTest);

  testWidgets('scales the viewport once and preserves system text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext scaledContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            viewPadding: const EdgeInsets.only(top: 24),
            viewInsets: const EdgeInsets.only(bottom: 300),
            systemGestureInsets: const EdgeInsets.only(left: 20),
            textScaler: TextScaler.linear(1.5),
          ),
          child: TvUiScale(child: child!),
        ),
        home: TvUiScale(
          child: Builder(
            builder: (context) {
              scaledContext = context;
              return const Center(
                child: SizedBox(key: ValueKey('box'), width: 40, height: 40),
              );
            },
          ),
        ),
      ),
    );
    final media = MediaQuery.of(scaledContext);
    expect(media.size, const Size(960, 540));
    expect(media.devicePixelRatio, 2);
    expect(media.padding.top, 12);
    expect(media.viewPadding.top, 12);
    expect(media.viewInsets.bottom, 150);
    expect(media.systemGestureInsets.left, 10);
    expect(media.textScaler.scale(16), 24);
    expect(TvLayout.uiScale(scaledContext), 1);
    expect(TvLayout.configuredUiScale(scaledContext), 2);
    expect(TvLayout.recommendedUiScale(scaledContext), 1.3);
    expect(
      tester.getRect(find.byKey(const ValueKey('box'))).size,
      const Size(80, 80),
    );
  });

  testWidgets('changing scale or TV mode preserves routes and control state', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var checked = false;
    await tester.pumpWidget(
      _app(const Scaffold(body: Text('home')), navigatorKey: navigatorKey),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: Switch(
                value: checked,
                onChanged: (value) => setState(() => checked = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(checked, isTrue);
    for (final scale in [0.8, 1.0, 1.5, 2.0]) {
      AppLayoutSettings.tvUiScaleOverride.value = scale;
      await tester.pump();
      expect(navigatorKey.currentState!.canPop(), isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        MediaQuery.sizeOf(tester.element(find.byType(Switch))),
        const Size(800, 600) / scale,
      );
    }
    AppLayoutSettings.tvMode.value = false;
    await tester.pump();
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(Switch))),
      const Size(800, 600),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final rootNavigator in [false, true]) {
    testWidgets(
      'dialogs and sheets scale with nested/root navigator $rootNavigator',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late BuildContext pageContext;
        await tester.pumpWidget(
          _app(
            Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) {
                  pageContext = context;
                  return const Scaffold(body: Text('page'));
                },
              ),
            ),
          ),
        );
        var tapped = false;
        final button = SizedBox(
          key: const ValueKey('overlay-button'),
          width: 80,
          height: 40,
          child: TextButton(
            onPressed: () => tapped = true,
            child: const Text('确认'),
          ),
        );
        showDialog<void>(
          context: pageContext,
          useRootNavigator: rootNavigator,
          builder: (_) => Dialog(
            child: Center(widthFactor: 1, heightFactor: 1, child: button),
          ),
        );
        await tester.pumpAndSettle();
        final overlay = find.byKey(const ValueKey('overlay-button'));
        expect(tester.getRect(overlay).size, const Size(160, 80));
        await tester.tap(overlay);
        expect(tapped, isTrue);
        Navigator.of(pageContext, rootNavigator: rootNavigator).pop();
        await tester.pumpAndSettle();
        tapped = false;
        showModalBottomSheet<void>(
          context: pageContext,
          useRootNavigator: rootNavigator,
          builder: (_) => SizedBox(height: 100, child: Center(child: button)),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(overlay).size, const Size(160, 80));
        await tester.tap(overlay);
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(800, 480),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('settings remains scrollable at 200% on $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_withSidebar(const SettingsPage())));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        MediaQuery.sizeOf(tester.element(find.byType(SettingsPage))),
        size / 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'appearance settings fits beside the sidebar at 200% on $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(_withSidebar(const AppAppearanceSettingsPage())),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final list = find.byType(ListView).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final textScale in [1.0, 1.5]) {
    testWidgets(
      'library grids reduce columns in a scaled viewport with font $textScale',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1280);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: TvUiScale(child: child!),
            ),
            home: Builder(
              builder: (context) => GridView.builder(
                gridDelegate: TvLayout.gridDelegate(
                  context,
                  columns: 6,
                  mainAxisSpacing: 12,
                  childAspectRatio: .84,
                ),
                itemCount: 12,
                itemBuilder: (_, index) =>
                    Center(child: Text('专辑 $index', key: ValueKey(index))),
              ),
            ),
          ),
        );
        final first = tester.getCenter(find.byKey(const ValueKey(0)));
        final second = tester.getCenter(find.byKey(const ValueKey(1)));
        if (textScale == 1) {
          expect(first.dy, second.dy);
          expect(
            tester.getCenter(find.byKey(const ValueKey(2))).dy,
            greaterThan(first.dy),
          );
        } else {
          expect(second.dy, greaterThan(first.dy));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
