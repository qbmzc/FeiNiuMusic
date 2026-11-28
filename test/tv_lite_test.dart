import 'package:feiniu_music/app/services/feiniu/api_models.dart';
import 'package:feiniu_music/app/services/lyrics/lyrics_service.dart';
import 'package:feiniu_music/app/services/player_service.dart';
import 'package:feiniu_music/app/state/song_state.dart';
import 'package:feiniu_music/tv_lite/tv_lite_focusable.dart';
import 'package:feiniu_music/tv_lite/tv_lite_player_page.dart';
import 'package:feiniu_music/tv_lite/tv_lite_queue_page.dart';
import 'package:feiniu_music/tv_lite/tv_lite_song_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FeiNiuTrack _track(int i) => FeiNiuTrack.fromJson({
  'guid': 'g$i',
  'title': 'Song $i',
  'createdAt': 0,
  'updatedAt': 0,
  'artists': [
    {'guid': 'a$i', 'name': 'Artist $i'},
  ],
});

/// 模拟服务端分页：共 [total] 首，按 page/size 切片。
TvLiteTrackPageLoader _pagedLoader(int total, {List<int>? calls}) {
  return (page, size) async {
    calls?.add(page);
    final start = (page - 1) * size;
    final end = (start + size).clamp(0, total);
    final list = [for (var i = start; i < end; i++) _track(i)];
    return FeiNiuPageData(list: list, total: total);
  };
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('TvLitePagedSongs', () {
    test('loads pages until total is reached', () async {
      final calls = <int>[];
      final songs = TvLitePagedSongs(
        _pagedLoader(5, calls: calls),
        pageSize: 2,
      );
      await songs.ensureLoaded();
      expect(songs.songs.map((s) => s.title), ['Song 0', 'Song 1']);
      expect(songs.hasMore, isTrue);

      await songs.loadMore();
      await songs.loadMore();
      expect(songs.songs, hasLength(5));
      expect(songs.hasMore, isFalse);

      await songs.loadMore();
      expect(calls, [1, 2, 3]);
      songs.dispose();
    });

    test('stops at an empty page even if total is overstated', () async {
      final songs = TvLitePagedSongs((page, size) async {
        final list = page == 1 ? [_track(0)] : <FeiNiuTrack>[];
        return FeiNiuPageData(list: list, total: 50);
      }, pageSize: 1);
      await songs.ensureLoaded();
      await songs.loadMore();
      expect(songs.songs, hasLength(1));
      expect(songs.hasMore, isFalse);
      songs.dispose();
    });

    test('keeps loaded songs on failure and resumes on retry', () async {
      var fail = false;
      final songs = TvLitePagedSongs((page, size) async {
        if (fail) throw Exception('offline');
        return FeiNiuPageData(list: [_track(page)], total: 3);
      }, pageSize: 1);
      await songs.ensureLoaded();
      fail = true;
      await songs.loadMore();
      expect(songs.error, isNotNull);
      expect(songs.songs, hasLength(1));

      await songs.loadMore();
      expect(songs.songs, hasLength(1), reason: 'loadMore waits for retry');

      fail = false;
      await songs.retry();
      expect(songs.error, isNull);
      expect(songs.songs.map((s) => s.title), ['Song 1', 'Song 2']);
      songs.dispose();
    });
  });

  group('TvLiteFocusable', () {
    testWidgets('remote select key triggers onSelect', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          TvLiteFocusable(
            autofocus: true,
            onSelect: () => selected++,
            child: const Text('item'),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 2);
    });
  });

  group('TvLiteSongList', () {
    testWidgets('arrow down moves focus and select plays that row', (
      tester,
    ) async {
      final songs = TvLitePagedSongs(_pagedLoader(30), pageSize: 30);
      List<SongEntity>? playedQueue;
      int? playedIndex;
      await tester.pumpWidget(
        _host(
          TvLiteSongList(
            controller: songs,
            autofocusFirst: true,
            onPlay: (queue, index) {
              playedQueue = queue;
              playedIndex = index;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Song 0'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);

      expect(playedIndex, 2);
      expect(playedQueue, hasLength(30));
      songs.dispose();
    });

    testWidgets('requests the next page near the end of the list', (
      tester,
    ) async {
      final calls = <int>[];
      final songs = TvLitePagedSongs(
        _pagedLoader(400, calls: calls),
        pageSize: 12,
      );
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(TvLiteSongList(controller: songs, onPlay: (_, _) {})),
      );
      await tester.pumpAndSettle();

      // 首页 12 行填不满 1080 高的屏幕，会继续拉页直到末尾离可见区足够远，
      // 但不会把 400 首一次拉完。
      expect(calls.length, greaterThan(1));
      expect(calls, List.generate(calls.length, (i) => i + 1));
      expect(songs.hasMore, isTrue);
      expect(songs.songs.length, lessThan(100));
      songs.dispose();
    });
  });

  group('TvLitePlayerPage', () {
    testWidgets('fits a 960x540 screen with lyrics and five controls', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final player = PlayerService.instance;
      final lyrics = LyricsService.instance.controller;
      player.currentSong.value = SongEntity(
        id: 'tv-lite-song',
        title: '细雨',
        artist: '[]',
        album: '{}',
        format: 'mp3',
        durationMs: 200000,
      );
      addTearDown(() => player.currentSong.value = null);
      await tester.pump();
      lyrics.lyricNotifier.value = LyricModel(
        lines: [
          for (var i = 0; i < 20; i++)
            LyricLine(
              start: Duration(seconds: i * 5),
              text: '第 $i 行',
              translation: i == 4 ? 'line $i' : null,
            ),
        ],
      );
      lyrics.activeIndexNotifiter.value = 4;
      addTearDown(() => lyrics.lyricNotifier.value = null);

      await tester.pumpWidget(const MaterialApp(home: TvLitePlayerPage()));

      expect(tester.takeException(), isNull);
      expect(find.text('第 3 行'), findsOneWidget);
      expect(find.text('第 4 行'), findsOneWidget);
      expect(find.text('line 4'), findsOneWidget);
      expect(find.text('第 5 行'), findsOneWidget);
      expect(find.text('第 2 行'), findsNothing);
      expect(find.text('播放列表'), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });
  });

  group('TvLiteQueuePage', () {
    testWidgets('opens focused on the playing song', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final player = PlayerService.instance;
      player.queue.value = [
        for (var i = 0; i < 40; i++)
          SongEntity(
            id: 'q$i',
            title: 'Queue $i',
            artist: '[]',
            album: '{}',
            format: 'mp3',
          ),
      ];
      player.currentIndex.value = 25;
      addTearDown(() {
        player.queue.value = const [];
        player.currentIndex.value = -1;
      });

      await tester.pumpWidget(const MaterialApp(home: TvLiteQueuePage()));
      await tester.pump();

      final row = find.text('Queue 25');
      expect(row, findsOneWidget);
      expect(Focus.of(tester.element(row)).hasPrimaryFocus, isTrue);
      expect(find.text('Queue 0'), findsNothing);
    });
  });
}
