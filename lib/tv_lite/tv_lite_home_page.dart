import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services/debug_log_service.dart';
import '../app/services/feiniu/api_client.dart';
import '../app/services/feiniu/api_models.dart';
import '../app/services/feiniu/playlist_service.dart';
import '../app/services/player_service.dart';
import '../app/state/song_state.dart';
import '../components/dialog/debug_log_qr_dialog.dart';
import 'tv_lite_diagnostics.dart';
import 'tv_lite_focusable.dart';
import 'tv_lite_player_page.dart';
import 'tv_lite_playlists.dart';
import 'tv_lite_song_list.dart';

enum _Section {
  recent('最近播放', Icons.history_rounded),
  favorites('我的收藏', Icons.favorite_rounded),
  playlists('歌单', Icons.queue_music_rounded),
  all('全部歌曲', Icons.library_music_rounded);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 精简版首页：左侧导航，右侧当前分区内容。分区在确认键按下时才切换，
/// 焦点经过侧栏不会触发加载。返回键先回到侧栏，焦点已在侧栏时才退出。
class TvLiteHomePage extends StatefulWidget {
  const TvLiteHomePage({super.key});

  @override
  State<TvLiteHomePage> createState() => _TvLiteHomePageState();
}

class _TvLiteHomePageState extends State<TvLiteHomePage> {
  static final FeiNiuApiClient _api = FeiNiuApiClient.instance;

  _Section _section = _Section.recent;

  late final Map<_Section, TvLitePagedSongs> _songs = {
    _Section.recent: TvLitePagedSongs(
      (page, size) => _api.getPlayHistory(page: page, size: size),
    ),
    _Section.favorites: TvLitePagedSongs(
      (page, size) => _api.getFavoriteList(page: page, size: size),
    ),
    _Section.all: TvLitePagedSongs(
      (page, size) => _api.getTrackList(page: page, size: size),
    ),
  };

  Future<List<FeiNiuPlaylist>>? _playlists;

  final Map<_Section, FocusNode> _sectionNodes = {
    for (final section in _Section.values)
      section: FocusNode(debugLabel: 'tv-lite-${section.name}'),
  };

  /// 包住整个侧栏，用 hasFocus 判断焦点是否在侧栏内。
  final FocusNode _railNode = FocusNode(
    debugLabel: 'tv-lite-rail',
    skipTraversal: true,
  );

  @override
  void dispose() {
    for (final controller in _songs.values) {
      controller.dispose();
    }
    for (final node in _sectionNodes.values) {
      node.dispose();
    }
    _railNode.dispose();
    super.dispose();
  }

  void _handleBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_railNode.hasFocus) {
      unawaited(SystemNavigator.pop());
      return;
    }
    _sectionNodes[_section]!.requestFocus();
  }

  void _select(_Section section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  Future<void> _play(List<SongEntity> songs, int index) async {
    unawaited(
      PlayerService.instance.playQueue(List.of(songs), index).catchError((
        Object e,
      ) {
        if (kDebugMode) debugPrint('[TvLite] play failed: $e');
        DebugLogService.instance.add('[TvLite] 播放失败: $e');
      }),
    );
    await _openPlayer();
  }

  Future<void> _openPlayer() {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TvLitePlayerPage()));
  }

  void _openPlaylist(FeiNiuPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvLitePlaylistPage(playlist: playlist, onPlay: _play),
      ),
    );
  }

  void _reloadPlaylists() {
    setState(() {
      _playlists = FeiNiuPlaylistService.instance.getPlaylistList();
    });
  }

  Widget _buildContent() {
    if (_section == _Section.playlists) {
      final playlists = _playlists ??= FeiNiuPlaylistService.instance
          .getPlaylistList();
      return TvLitePlaylistList(
        playlists: playlists,
        onRetry: _reloadPlaylists,
        onOpen: _openPlaylist,
      );
    }
    return TvLiteSongList(
      key: ValueKey(_section),
      controller: _songs[_section]!,
      onPlay: _play,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: Focus(
                  focusNode: _railNode,
                  child: _Rail(
                    current: _section,
                    focusNodes: _sectionNodes,
                    onSelect: _select,
                    onOpenPlayer: _openPlayer,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                      child: Text(
                        _section.label,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final _Section current;
  final Map<_Section, FocusNode> focusNodes;
  final ValueChanged<_Section> onSelect;
  final VoidCallback onOpenPlayer;

  const _Rail({
    required this.current,
    required this.focusNodes,
    required this.onSelect,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 20),
              child: Text('飞牛音乐', style: theme.textTheme.titleLarge),
            ),
            for (final section in _Section.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TvLiteFocusable(
                  focusNode: focusNodes[section],
                  autofocus: section == _Section.recent,
                  selected: section == current,
                  onSelect: () => onSelect(section),
                  child: _RailLabel(icon: section.icon, label: section.label),
                ),
              ),
            const Spacer(),
            _NowPlayingEntry(onOpen: onOpenPlayer),
            const SizedBox(height: 4),
            TvLiteFocusable(
              onSelect: () => _showDiagnostics(context),
              child: const _RailLabel(icon: Icons.speed_rounded, label: '诊断'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RailLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _NowPlayingEntry extends StatelessWidget {
  final VoidCallback onOpen;

  const _NowPlayingEntry({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: PlayerService.instance.currentSong,
      builder: (context, song, _) => TvLiteFocusable(
        onSelect: onOpen,
        child: Row(
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('正在播放', style: theme.textTheme.titleMedium),
                  if (song != null)
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showDiagnostics(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _DiagnosticsDialog(),
  );
}

class _DiagnosticsDialog extends StatelessWidget {
  const _DiagnosticsDialog();

  @override
  Widget build(BuildContext context) {
    final diagnostics = TvLiteDiagnostics.instance;
    final current = diagnostics.snapshot();
    final last = diagnostics.lastPeriod.value;
    return AlertDialog(
      title: const Text('诊断'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本分钟：${current.describe()}'),
            if (last != null) ...[
              const SizedBox(height: 8),
              Text('上一分钟：${last.describe()}'),
            ],
            const SizedBox(height: 12),
            const Text('每分钟自动记一行到日志，扫码即可在手机上查看。'),
          ],
        ),
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: diagnostics.showPerformanceOverlay,
          builder: (context, show, _) => TextButton(
            onPressed: () => diagnostics.showPerformanceOverlay.value = !show,
            child: Text(show ? '关闭帧耗时图' : '显示帧耗时图'),
          ),
        ),
        TextButton(
          onPressed: () => DebugLogQrDialog.show(context),
          child: const Text('扫码看日志'),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
