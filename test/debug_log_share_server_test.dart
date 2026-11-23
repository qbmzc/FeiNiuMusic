import 'package:feiniu_music/app/services/debug_log_service.dart';
import 'package:feiniu_music/app/services/debug_log_share_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DebugLogService.instance.resetForTest();
    await DebugLogService.instance.setEnabled(true);
  });

  tearDown(() {
    DebugLogShareServer.stop();
    DebugLogService.instance.resetForTest();
  });

  test('仅凭正确 token 返回日志网页，内容做 HTML 转义', () async {
    DebugLogService.instance.add('[PlayerService] <script>boom</script>');
    final urls = await DebugLogShareServer.start();
    final token = Uri.parse(
      urls.isEmpty ? 'http://127.0.0.1/l/x' : urls.first,
    ).pathSegments.last;

    final wrong = await DebugLogShareServer.handleRequest(
      Request('GET', Uri.parse('http://localhost/l/deadbeef')),
    );
    expect(wrong.statusCode, 404);

    if (urls.isEmpty) return; // 测试机无局域网地址时只校验拒绝路径
    final ok = await DebugLogShareServer.handleRequest(
      Request('GET', Uri.parse('http://localhost/l/$token')),
    );
    expect(ok.statusCode, 200);
    final body = await ok.readAsString();
    expect(body, contains('&lt;script&gt;boom&lt;/script&gt;'));
    expect(body, isNot(contains('<script>boom')));
  });

  test('系统日志分区同样转义，空内容不输出分区', () {
    final page = DebugLogShareServer.renderPage(
      'app',
      launchLogcat: 'F libc    : Fatal signal 11 <x>',
      currentLogcat: '  ',
    );
    expect(page, contains('Fatal signal 11 &lt;x&gt;'));
    expect(page, contains('id="launch"'));
    expect(page, isNot(contains('id="current"')));
  });

  test('停止后旧链接失效', () async {
    final urls = await DebugLogShareServer.start();
    DebugLogShareServer.stop();
    if (urls.isEmpty) return;
    final token = Uri.parse(urls.first).pathSegments.last;
    final res = await DebugLogShareServer.handleRequest(
      Request('GET', Uri.parse('http://localhost/l/$token')),
    );
    expect(res.statusCode, 404);
  });
}
