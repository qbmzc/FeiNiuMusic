import 'package:flutter/material.dart';

import '../app/services/feiniu/api_client.dart';
import '../app/services/feiniu/api_models.dart';
import '../app/state/song_state.dart';
import 'tv_lite_focusable.dart';
import 'tv_lite_song_list.dart';
import 'tv_lite_widgets.dart';

/// 歌单列表（一次取全部，歌单数量通常不多）。
class TvLitePlaylistList extends StatelessWidget {
  final Future<List<FeiNiuPlaylist>> playlists;
  final VoidCallback onRetry;
  final ValueChanged<FeiNiuPlaylist> onOpen;

  const TvLitePlaylistList({
    super.key,
    required this.playlists,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FeiNiuPlaylist>>(
      future: playlists,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return TvLiteMessage(
            text: '加载失败',
            actionLabel: '重试',
            onAction: onRetry,
          );
        }
        final items = snapshot.data ?? const <FeiNiuPlaylist>[];
        if (items.isEmpty) return const TvLiteMessage(text: '还没有歌单');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 24, 24),
          itemExtent: TvLiteSongRow.extent,
          itemCount: items.length,
          itemBuilder: (context, index) =>
              _PlaylistRow(playlist: items[index], onOpen: onOpen),
        );
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final FeiNiuPlaylist playlist;
  final ValueChanged<FeiNiuPlaylist> onOpen;

  const _PlaylistRow({required this.playlist, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TvLiteFocusable(
        onSelect: () => onOpen(playlist),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            TvLiteCover(
              coverId: playlist.coverId,
              updatedAt: playlist.updatedAt,
              size: 48,
              fallbackIcon: Icons.queue_music_rounded,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '${playlist.trackCount} 首',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个歌单的歌曲页。
class TvLitePlaylistPage extends StatefulWidget {
  final FeiNiuPlaylist playlist;
  final void Function(List<SongEntity> songs, int index) onPlay;

  const TvLitePlaylistPage({
    super.key,
    required this.playlist,
    required this.onPlay,
  });

  @override
  State<TvLitePlaylistPage> createState() => _TvLitePlaylistPageState();
}

class _TvLitePlaylistPageState extends State<TvLitePlaylistPage> {
  late final TvLitePagedSongs _songs = TvLitePagedSongs(
    (page, size) => FeiNiuApiClient.instance.getPlaylistTracks(
      playlistGUID: widget.playlist.guid,
      page: page,
      size: size,
    ),
  );

  @override
  void dispose() {
    _songs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
              child: Text(
                widget.playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TvLiteSongList(
                  controller: _songs,
                  onPlay: widget.onPlay,
                  autofocusFirst: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
