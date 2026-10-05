import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/feiniu/api_client.dart';
import 'package:feiniu_music/app/state/settings_layout_state.dart';
import 'package:feiniu_music/pages/search/search_page.dart';

class _Request {
  _Request(this.options, this.handler);
  final RequestOptions options;
  final RequestInterceptorHandler handler;

  void complete({String? title}) => handler.resolve(
    Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'code': 0,
        'data': {
          'list': [
            if (title != null && options.path.endsWith('/track'))
              {
                'guid': title,
                'title': title,
                'album': <String, dynamic>{},
                'artists': [],
              },
          ],
          'total': title == null ? 0 : 1,
        },
      },
    ),
  );
}

Future<void> _pumpRequests(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  late List<_Request> requests;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLayoutSettings.resetForTest();
    requests = [];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(_Request(options, handler));
        },
      ),
    );
    FeiNiuApiClient.instance.setDioForTest(dio);
    await FeiNiuApiClient.instance.setAuth('http://nas.test', 'token');
  });
  tearDown(() => AppLayoutSettings.resetForTest());

  Future<void> openSearch(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: SearchPage()));

  testWidgets('rapid typing sends only the final query after 300ms', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 299));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpRequests(tester);
    expect(requests, hasLength(3));
    expect(
      requests.map((r) => r.options.queryParameters['q']),
      everyElement('ab'),
    );
    for (final request in requests) {
      request.complete(title: 'new result');
    }
    await _pumpRequests(tester);
    expect(find.text('new result'), findsOneWidget);
  });

  testWidgets('clearing cancels all requests and ignores late results', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpRequests(tester);
    expect(requests, hasLength(3));
    final oldRequests = [...requests];
    await tester.tap(find.byIcon(Icons.clear));
    await _pumpRequests(tester);
    expect(
      oldRequests.map((r) => r.options.cancelToken?.isCancelled),
      everyElement(true),
    );
    for (final request in oldRequests) {
      request.complete(title: 'stale result');
    }
    await _pumpRequests(tester);
    expect(find.text('stale result'), findsNothing);
    expect(find.text('请输入关键字进行搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing cancels immediately, before the next debounce expires', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpRequests(tester);
    final oldRequests = [...requests];
    await tester.enterText(find.byType(TextField), 'new');
    expect(oldRequests, hasLength(3));
    expect(
      oldRequests.map((r) => r.options.cancelToken?.isCancelled),
      everyElement(true),
    );
    for (final request in oldRequests) {
      request.complete(title: 'stale result');
    }
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpRequests(tester);
    for (final request in requests.skip(3)) {
      request.complete(title: 'latest result');
    }
    await _pumpRequests(tester);
    expect(find.text('stale result'), findsNothing);
    expect(find.text('latest result'), findsOneWidget);
  });

  testWidgets('submit bypasses debounce without a second delayed request', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'query');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpRequests(tester);
    expect(requests, hasLength(3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, hasLength(3));
    for (final request in requests) {
      request.complete();
    }
    await _pumpRequests(tester);
  });

  testWidgets('leaving search cancels active requests and a pending debounce', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'active');
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpRequests(tester);
    await tester.pumpWidget(const SizedBox());
    expect(
      requests.map((r) => r.options.cancelToken?.isCancelled),
      everyElement(true),
    );
    for (final request in requests) {
      request.complete();
    }
    await _pumpRequests(tester);
    requests.clear();
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'pending');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
