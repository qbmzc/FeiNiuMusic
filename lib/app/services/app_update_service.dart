import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String? releaseName;
  final String? releaseUrl;
  final String? releaseNotes;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseName,
    this.releaseUrl,
    this.releaseNotes,
  });
}

class AppUpdateService {
  AppUpdateService._()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  @visibleForTesting
  AppUpdateService.forTest(this._dio);

  static final AppUpdateService instance = AppUpdateService._();

  static const _previewVersion = String.fromEnvironment('APP_PREVIEW_VERSION');
  static const String releasePageUrl = _previewVersion != ''
      ? 'https://github.com/qbmzc/FeiNiuMusic/releases'
      : 'https://github.com/kuilei0926/FeiNiuMusic/releases/latest';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/kuilei0926/FeiNiuMusic/releases/latest';

  final Dio _dio;

  String? _cachedVersion;

  /// Preview builds include their sequence number; stable builds use the
  /// platform release version without the internal build number.
  Future<String> currentVersion() async {
    const previewVersion = String.fromEnvironment('APP_PREVIEW_VERSION');
    if (previewVersion.isNotEmpty) return previewVersion;
    final cached = _cachedVersion;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      _cachedVersion = v.isEmpty ? '0.0.0' : v;
      return _cachedVersion!;
    } catch (_) {
      return _cachedVersion ?? '0.0.0';
    }
  }

  Future<AppUpdateInfo> checkLatest(String currentVersion) async {
    try {
      final preview = _previewVersion.isNotEmpty ||
          currentVersion.contains('-preview.');
      final response = await _dio.get(
        preview
            ? 'https://api.github.com/repos/qbmzc/FeiNiuMusic/releases?per_page=100'
            : latestReleaseApiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'FeiNiuMusic',
          },
        ),
      );
      final data = preview
          ? _latestPreview(response.data as List<dynamic>)
          : response.data as Map<String, dynamic>?;
      if (data == null) {
        return AppUpdateInfo(latestVersion: currentVersion, hasUpdate: false);
      }

      final tagName = (data['tag_name'] as String? ?? '').trim();
      final latestName = tagName.startsWith('v') || tagName.startsWith('V')
          ? tagName.substring(1)
          : tagName;
      final releaseName = data['name'] as String?;
      final body = data['body'] as String?;
      final htmlUrl = data['html_url'] as String?;

      final hasUpdate = _compareVersions(latestName, currentVersion) > 0;
      return AppUpdateInfo(
        latestVersion: latestName,
        hasUpdate: hasUpdate,
        releaseName: releaseName,
        releaseUrl: htmlUrl ?? releasePageUrl,
        releaseNotes: body,
      );
    } catch (e) {
      return AppUpdateInfo(latestVersion: currentVersion, hasUpdate: false);
    }
  }

  Map<String, dynamic>? _latestPreview(List<dynamic> releases) {
    Map<String, dynamic>? latest;
    final previewTag = RegExp(r'^[vV]?\d+\.\d+\.\d+-preview\.\d+$');
    for (final entry in releases.cast<Map<String, dynamic>>()) {
      final tag = entry['tag_name'] as String? ?? '';
      if (entry['draft'] == true || !previewTag.hasMatch(tag)) continue;
      if (latest == null ||
          _compareVersions(tag, latest['tag_name'] as String) > 0) {
        latest = entry;
      }
    }
    return latest;
  }

  String _normalizeVersion(String version) {
    final value = version.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }
    return value;
  }

  int _compareVersions(String a, String b) {
    List<int> release(String v) {
      var s = _normalizeVersion(v);
      final cut = s.indexOf(RegExp(r'[+\-]'));
      if (cut >= 0) s = s.substring(0, cut);
      return s.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }

    final left = release(a);
    final right = release(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    final previewSuffix = RegExp(r'-preview\.(\d+)(?:\+.*)?$');
    final leftPreview = previewSuffix.firstMatch(a);
    final rightPreview = previewSuffix.firstMatch(b);
    if (leftPreview != null && rightPreview != null) {
      return int.parse(leftPreview.group(1)!).compareTo(
        int.parse(rightPreview.group(1)!),
      );
    }
    return 0;
  }
}
