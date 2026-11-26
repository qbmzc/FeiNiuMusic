import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/services/player_service.dart';
import '../app/state/song_state.dart';
import 'tv_lite_song_list.dart';
import 'tv_lite_widgets.dart';

/// 当前播放队列。打开时焦点落在正在播放的歌上，确认键跳到所选歌曲并回到
/// 播放页。
class TvLiteQueuePage extends StatelessWidget {
  const TvLiteQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('播放列表', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Expanded(
                child: ValueListenableBuilder<List<SongEntity>>(
                  valueListenable: PlayerService.instance.queue,
                  builder: (context, queue, _) => queue.isEmpty
                      ? const TvLiteMessage(text: '播放列表是空的')
                      : _QueueList(queue: queue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueList extends StatefulWidget {
  final List<SongEntity> queue;

  const _QueueList({required this.queue});

  @override
  State<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<_QueueList> {
  /// 正在播放的歌上方留几行，打开时不贴在顶部。
  static const int _rowsAbove = 3;

  late final int _initialIndex = PlayerService.instance.currentIndex.value;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset:
        math.max(0, _initialIndex - _rowsAbove) * TvLiteSongRow.extent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _play(int index) {
    unawaited(PlayerService.instance.skipToIndex(index));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    return ValueListenableBuilder<int>(
      valueListenable: PlayerService.instance.currentIndex,
      builder: (context, current, _) => ListView.builder(
        controller: _scroll,
        itemExtent: TvLiteSongRow.extent,
        itemCount: queue.length,
        itemBuilder: (context, index) => TvLiteSongRow(
          song: queue[index],
          index: index,
          selected: index == current,
          autofocus:
              index == _initialIndex ||
              (_initialIndex < 0 || _initialIndex >= queue.length) &&
                  index == 0,
          onSelect: () => _play(index),
        ),
      ),
    );
  }
}
