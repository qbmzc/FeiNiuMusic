import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/navigator_key.dart';
import '../app/services/feiniu/auth_service.dart';
import '../pages/login/login_page.dart';
import 'tv_lite_diagnostics.dart';
import 'tv_lite_home_page.dart';
import 'tv_lite_widgets.dart';

class _TogglePerformanceOverlayIntent extends Intent {
  const _TogglePerformanceOverlayIntent();
}

/// 投影/电视精简版根组件（`--dart-define=TV_LITE=true` 构建时由 main 启动）。
///
/// 固定深色主题，不取动态色、不包液体玻璃；页面切换无过渡动画；焦点高亮
/// 始终显示。登录复用手机版登录页（TV 布局自带扫码配对）。
class TvLiteApp extends StatefulWidget {
  const TvLiteApp({super.key});

  @override
  State<TvLiteApp> createState() => _TvLiteAppState();
}

class _TvLiteAppState extends State<TvLiteApp> {
  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _NoTransitionsBuilder(),
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    TvLiteDiagnostics.instance.start();
  }

  @override
  void dispose() {
    TvLiteDiagnostics.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = TvLiteDiagnostics.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: diagnostics.showPerformanceOverlay,
      builder: (context, showOverlay, _) => MaterialApp(
        title: '飞牛音乐',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: _theme,
        showPerformanceOverlay: showOverlay,
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.contextMenu):
              const _TogglePerformanceOverlayIntent(),
        },
        actions: <Type, Action<Intent>>{
          ...WidgetsApp.defaultActions,
          _TogglePerformanceOverlayIntent:
              CallbackAction<_TogglePerformanceOverlayIntent>(
                onInvoke: (_) {
                  diagnostics.showPerformanceOverlay.value =
                      !diagnostics.showPerformanceOverlay.value;
                  return null;
                },
              ),
        },
        home: const _TvLiteGate(),
        // 复用的手机版页面（如登录页「管理账号」）可能按路由名跳转，精简版
        // 没有这些页面，给出提示而不是抛异常。
        onUnknownRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const _UnsupportedPage(),
        ),
      ),
    );
  }
}

class _TvLiteGate extends StatelessWidget {
  const _TvLiteGate();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (context, loggedIn, _) =>
          loggedIn ? const TvLiteHomePage() : const LoginPage(),
    );
  }
}

class _UnsupportedPage extends StatelessWidget {
  const _UnsupportedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TvLiteMessage(
        text: '精简版暂不支持该功能，请在手机上操作',
        actionLabel: '返回',
        onAction: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
