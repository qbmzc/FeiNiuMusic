import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'debug_log_service.dart';
import 'login_pair_server.dart';

/// 局域网查看调试日志：投影/电视等无法导出文件的设备上，手机扫码即可在
/// 浏览器里查看并复制日志。
///
/// URL 形如 `http://<ip>:<port>/l/<token>`，token 为随机 32 位 hex，URL 即
/// 密钥；只在「版本信息」页的二维码弹窗打开期间运行。
class DebugLogShareServer {
  DebugLogShareServer._();

  static HttpServer? _server;
  static String? _token;
  static List<String>? _urls;

  /// 启动服务（幂等），返回局域网 URL 列表。
  static Future<List<String>> start() async {
    final existing = _urls;
    if (_server != null && existing != null) return List.of(existing);
    _token = _generateToken();
    final server = await shelf_io.serve(
      handleRequest,
      InternetAddress.anyIPv4,
      0,
    );
    _server = server;
    final addresses = await LoginPairServer.localIpv4s();
    final urls = [
      for (final ip in addresses) 'http://$ip:${server.port}/l/$_token',
    ];
    _urls = urls;
    return List.of(urls);
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
    _token = null;
    _urls = null;
  }

  /// 测试可直接调用：校验 token 后返回包含全部日志的网页。
  static Response handleRequest(Request request) {
    final path = request.url.pathSegments;
    if (request.method != 'GET' ||
        path.length != 2 ||
        path[0] != 'l' ||
        _token == null ||
        path[1] != _token) {
      return Response.notFound('Not found');
    }
    return Response.ok(
      renderPage(DebugLogService.instance.exportText()),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }

  static String renderPage(String logs) {
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(logs);
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>飞牛音乐 · 调试日志</title>
<style>
  body { font-family: -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
         margin: 0; padding: 16px; background: #f4f5f7; color: #1f2937; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  p { font-size: 13px; color: #6b7280; margin: 0 0 12px; }
  button { padding: 10px 16px; font-size: 15px; border: 0; border-radius: 10px;
           background: #3b82f6; color: #fff; margin: 0 8px 12px 0; }
  textarea { width: 100%; box-sizing: border-box; height: 75vh; font-size: 12px;
             font-family: ui-monospace, Menlo, monospace; border-radius: 10px;
             border: 1px solid #d1d5db; padding: 10px; }
</style>
</head>
<body>
<h1>飞牛音乐 · 调试日志</h1>
<p>按时间从旧到新排列。点「全选」后复制，发给开发者即可。刷新页面可获取最新日志。</p>
<button onclick="selectAll()">全选</button>
<button onclick="location.reload()">刷新</button>
<textarea id="log" readonly>$escaped</textarea>
<script>
  function selectAll() {
    var el = document.getElementById('log');
    el.focus();
    el.select();
    el.setSelectionRange(0, el.value.length);
    try { document.execCommand('copy'); } catch (e) {}
  }
</script>
</body>
</html>
''';
  }

  static String _generateToken() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }
}
