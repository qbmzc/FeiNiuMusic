import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:feiniu_music/app/services/db/db_helper.dart';
import 'package:feiniu_music/app/services/feiniu/api_client.dart';
import 'package:feiniu_music/app/state/settings_layout_state.dart';
import 'package:feiniu_music/app/utils/api_cache_manager.dart';
import 'package:feiniu_music/pages/home/home_page.dart';

const _albumPath = '/music/api/v1/album/list';

class _Request {
  _Request(this.options, this.handler);
  final RequestOptions options;
  final RequestInterceptorHandler handler;
  bool completed = false;

  void resolve(List<Map<String, dynamic>> rows) {
    if (completed) return;
    completed = true;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'code': 0,
          'data': options.path.endsWith('/roam-start')
              ? {
                  'current': {
                    'roamId': 'roam',
                    'track': {'guid': 'roam', 'title': '漫游歌曲'},
                  },
                }
              : {'list': rows, 'total': rows.length},
        },
      ),
    );
  }

  void fail() {
    completed = true;
    handler.reject(
      DioException.connectionError(requestOptions: options, reason: 'offline'),
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'fast modules render before a slow module; refresh shares in-flight work',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLayoutSettings.resetForTest();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      DbHelper.instance.resetForTest(overridePath: inMemoryDatabasePath);
      await tester.runAsync(() async {
        await DbHelper.instance.database;
      });
      addTearDown(() => DbHelper.instance.resetForTest());
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <_Request>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final request = _Request(options, handler);
            requests.add(request);
            if (options.path.endsWith(_albumPath)) return;
            request.resolve(
              options.path.endsWith('/track/list')
                  ? [
                      {
                        'guid': 'fast',
                        'title': '先返回的歌曲',
                        'album': <String, dynamic>{},
                        'artists': [],
                      },
                    ]
                  : [],
            );
          },
        ),
      );
      FeiNiuApiClient.instance.setDioForTest(dio);
      await FeiNiuApiClient.instance.setAuth('http://nas.test', 'token');
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _pump(tester);
      expect(find.text('先返回的歌曲'), findsOneWidget);
      expect(find.text('最新专辑加载中…'), findsOneWidget);
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final refreshing = refresh.onRefresh();
      await _pump(tester);
      expect(
        requests.where((r) => r.options.path.endsWith(_albumPath)),
        hasLength(1),
      );
      requests
          .singleWhere((r) => r.options.path.endsWith(_albumPath))
          .resolve([]);
      await _pump(tester);
      await refreshing;
      expect(find.text('最新专辑加载中…'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed module retains cached content and retries only that module',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLayoutSettings.resetForTest();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      DbHelper.instance.resetForTest(overridePath: inMemoryDatabasePath);
      await tester.runAsync(() async {
        await DbHelper.instance.database;
        await ApiCacheManager.instance.set(
          scope: 'home',
          key: 'dashboard',
          jsonData: '{"recentAlbums":[{"guid":"cached","name":"缓存专辑"}]}',
        );
      });
      addTearDown(() => DbHelper.instance.resetForTest());
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <_Request>[];
      var albumAttempts = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final request = _Request(options, handler);
            requests.add(request);
            if (options.path.endsWith(_albumPath) && albumAttempts++ == 0) {
              request.fail();
            } else {
              request.resolve(
                options.path.endsWith(_albumPath)
                    ? [
                        {'guid': 'fresh', 'name': '更新后的专辑'},
                      ]
                    : [],
              );
            }
          },
        ),
      );
      FeiNiuApiClient.instance.setDioForTest(dio);
      await FeiNiuApiClient.instance.setAuth('http://nas.test', 'token');
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _pump(tester);
      expect(find.text('缓存专辑'), findsOneWidget);
      expect(find.text('最新专辑加载失败'), findsOneWidget);
      final beforeRetry = requests.length;
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await _pump(tester);
      expect(requests.length, beforeRetry + 1);
      expect(requests.last.options.path, endsWith(_albumPath));
      expect(find.text('更新后的专辑'), findsOneWidget);
      expect(find.text('最新专辑加载失败'), findsNothing);
      final saved = await tester.runAsync(
        () => ApiCacheManager.instance.getPersisted('home', 'dashboard'),
      );
      expect(saved, contains('更新后的专辑'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
