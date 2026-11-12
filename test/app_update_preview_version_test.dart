import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:feiniu_music/app/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview checks fork releases and compares numeric sequence', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.uri.host, 'api.github.com');
          expect(options.uri.path, '/repos/qbmzc/FeiNiuMusic/releases');
          handler.resolve(Response(
            requestOptions: options,
            data: [
              {'tag_name': 'v1.7.1-preview.9'},
              {'tag_name': 'v1.7.1-preview.11', 'draft': true},
              {'tag_name': 'v9.0.0'},
              {
                'tag_name': 'v1.7.1-preview.10',
                'html_url': 'https://github.com/qbmzc/FeiNiuMusic/releases/tag/v1.7.1-preview.10',
              },
            ],
          ));
        },
      ),
    );
    final service = AppUpdateService.forTest(dio);
    final update = await service.checkLatest('1.7.1-preview.9');
    expect(update.hasUpdate, isTrue);
    expect(update.latestVersion, '1.7.1-preview.10');
    expect(update.releaseUrl, contains('/qbmzc/'));
    expect((await service.checkLatest('1.7.1-preview.10')).hasUpdate, isFalse);
    expect((await service.checkLatest('1.7.1-preview.12')).hasUpdate, isFalse);
    expect((await service.checkLatest('1.7.2-preview.1')).hasUpdate, isFalse);
    dio.close();
  });

  test('stable builds continue checking upstream stable releases', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.uri.path, '/repos/kuilei0926/FeiNiuMusic/releases/latest');
          handler.resolve(Response(
            requestOptions: options,
            data: {'tag_name': 'v1.7.2'},
          ));
        },
      ),
    );
    final service = AppUpdateService.forTest(dio);
    expect((await service.checkLatest('1.7.1')).hasUpdate, isTrue);
    expect((await service.checkLatest('1.7.2')).hasUpdate, isFalse);
    dio.close();
  });

  test(
    'version display uses the build-time preview label when provided',
    () async {
      PackageInfo.setMockInitialValues(
        appName: '飞牛音乐',
        packageName: 'com.feiniu.music',
        version: '1.6.9',
        buildNumber: '2',
        buildSignature: '',
      );
      const previewVersion = String.fromEnvironment('APP_PREVIEW_VERSION');
      expect(
        await AppUpdateService.instance.currentVersion(),
        previewVersion.isEmpty ? '1.6.9' : previewVersion,
      );
    },
  );
}
