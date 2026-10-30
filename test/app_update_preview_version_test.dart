import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:feiniu_music/app/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
