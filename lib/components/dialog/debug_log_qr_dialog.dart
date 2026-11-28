import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/services/debug_log_share_server.dart';

/// 局域网日志二维码：弹窗打开期间运行 [DebugLogShareServer]，关闭即停止。
class DebugLogQrDialog extends StatefulWidget {
  const DebugLogQrDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const DebugLogQrDialog(),
    );
    DebugLogShareServer.stop();
  }

  @override
  State<DebugLogQrDialog> createState() => _DebugLogQrDialogState();
}

class _DebugLogQrDialogState extends State<DebugLogQrDialog> {
  late final Future<List<String>> _urls = DebugLogShareServer.start();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('手机扫码查看日志'),
      content: SizedBox(
        width: 320,
        child: FutureBuilder<List<String>>(
          future: _urls,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final urls = snapshot.data ?? const <String>[];
            if (snapshot.hasError || urls.isEmpty) {
              return Text(
                '无法启动局域网服务，请确认设备已连接 Wi-Fi。'
                '${snapshot.hasError ? '\n${snapshot.error}' : ''}',
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: urls.first,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                ),
                const SizedBox(height: 12),
                for (final url in urls)
                  SelectableText(
                    url,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                const SizedBox(height: 8),
                Text(
                  '手机需与本机连接同一 Wi-Fi。关闭此窗口后链接失效。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
