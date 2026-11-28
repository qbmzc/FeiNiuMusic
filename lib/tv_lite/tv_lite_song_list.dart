import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/services/debug_log_service.dart';
import '../app/services/feiniu/api_models.dart';
import '../app/services/feiniu/track_service.dart';
import '../app/state/song_state.dart';
import 'tv_lite_focusable.dart';
import 'tv_lite_widgets.dart';

typedef TvLiteTrackPageLoader =
    Future<FeiNiuPageData<FeiNiuTrack>> Function(int page, int size);

/// 分页歌曲数据：首屏加载一页，列表滚到末尾附近再拉下一页。
class TvLitePagedSongs extends ChangeNotifier {
  TvLitePagedSongs(this._loader, {this.pageSize = 100});

  final TvLiteTrackPageLoader _loader;
  final int pageSize;

  List<SongEntity> _songs = const [];
  int _total = 0;
  int _page = 0;
  bool _loadedOnce = false;
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  List<SongEntity> get songs => _songs;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  Object? get error => _error;
  bool get hasMore => !_loadedOnce || _songs.length < _total;

  Future<void> ensureLoaded() async {
    if (_loadedOnce || _loading) return;
    await _loadNext();
  }

  Future<void> loadMore() async {
    if (_loading || !hasMore || _error != null) return;
    await _loadNext();
  }

  Future<void> retry() async {
    if (_loading) return;
    _error = null;
    await _loadNext();
  }

  Future<void> _loadNext() async {
    _loading = true;
    _notify();
    try {
      final data = await _loader(_page + 1, pageSize);
      final mapped = data.list
          .map(FeiNiuTrackService.instance.trackToSongEntity)
          .toList();
      _page++;
      _songs = [..._songs, ...mapped];
      // 服务器 total 偶尔与实际条数不符：拿到空页就视为到底，避免无限请求。
      _total = mapped.isEmpty ? _songs.length : data.total;
      _loadedOnce = true;
      _error = null;
    } catch (e) {
      _error = e;
      if (kDebugMode) debugPrint('[TvLite] load songs failed: $e');
      DebugLogService.instance.add('[TvLite] 歌曲加载失败: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 歌曲列表：固定行高 + 按需构建，遥控器上下键逐行移动。
class TvLiteSongList extends StatefulWidget {
  final TvLitePagedSongs controller;
  final void Function(List<SongEntity> songs, int index) onPlay;

  /// 独立页面进入时让第一行自动获得焦点；首页由侧栏持有初始焦点。
  final bool autofocusFirst;

  const TvLiteSongList({
    super.key,
    required this.controller,
    required this.onPlay,
    this.autofocusFirst = false,
  });

  @override
  State<TvLiteSongList> createState() => _TvLiteSongListState();
}

class _TvLiteSongListState extends State<TvLiteSongList> {
  static const int _prefetchDistance = 10;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.ensureLoaded());
  }

  @override
  void didUpdateWidget(TvLiteSongList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      unawaited(widget.controller.ensureLoaded());
    }
  }

  void _maybeLoadMore(int index) {
    final c = widget.controller;
    if (index < c.songs.length - _prefetchDistance) return;
    if (!c.hasMore || c.loading || c.error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final songs = c.songs;
        if (songs.isEmpty) {
          if (c.error != null) {
            return TvLiteMessage(
              text: '加载失败',
              actionLabel: '重试',
              onAction: c.retry,
            );
          }
          if (!c.loadedOnce || c.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return const TvLiteMessage(text: '这里还没有歌曲');
        }
        final showFooter = c.hasMore || c.error != null;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 24, 24),
          itemExtent: TvLiteSongRow.extent,
          itemCount: songs.length + (showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= songs.length) return _Footer(controller: c);
            _maybeLoadMore(index);
            return TvLiteSongRow(
              song: songs[index],
              index: index,
              autofocus: widget.autofocusFirst && index == 0,
              onSelect: () => widget.onPlay(songs, index),
            );
          },
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  final TvLitePagedSongs controller;

  const _Footer({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.error != null) {
      return Center(
        child: TvLiteFocusable(
          onSelect: controller.retry,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: const Text('加载失败，按确认键重试'),
        ),
      );
    }
    return Center(
      child: Text(
        controller.loading ? '正在加载…' : '',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class TvLiteSongRow extends StatelessWidget {
  static const double extent = 68;

  final SongEntity song;
  final int index;
  final VoidCallback onSelect;
  final bool autofocus;

  /// 常亮底色，播放列表里标出正在播放的歌。
  final bool selected;

  const TvLiteSongRow({
    super.key,
    required this.song,
    required this.index,
    required this.onSelect,
    this.autofocus = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final durationMs = song.durationMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TvLiteFocusable(
        onSelect: onSelect,
        autofocus: autofocus,
        selected: selected,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
            const SizedBox(width: 8),
            TvLiteCover(
              coverId: song.coverId,
              updatedAt: song.updatedAt,
              size: 48,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    song.artistDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            if (durationMs != null && durationMs > 0) ...[
              const SizedBox(width: 16),
              Text(
                formatTvLiteDuration(Duration(milliseconds: durationMs)),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
