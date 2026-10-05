import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/services/feiniu/api_models.dart';
import 'package:feiniu_music/app/state/settings_layout_state.dart';
import 'package:feiniu_music/app/state/song_state.dart';
import 'package:feiniu_music/components/layout/side_menu.dart';
import 'package:feiniu_music/pages/home/widgets/home_large_layout.dart';
import 'package:feiniu_music/pages/home/widgets/home_hero_banner.dart';
import 'package:feiniu_music/pages/home/widgets/home_shortcut_menu.dart';
import 'package:feiniu_music/pages/home/widgets/home_section_feedback.dart';

void _noop() {}

const _song = SongEntity(
  id: 'test-song',
  title: '很长的歌曲名称用于验证放大后仍然不会覆盖播放按钮',
  artist: '很长的歌手名称',
  durationMs: 123000,
);

Widget _home({Map<HomeSection, Widget> feedback = const {}}) => HomeLargeLayout(
  sectionFeedback: feedback,
  heroSong: _song,
  onPlayRoam: _noop,
  onRefreshRoam: _noop,
  shortcutItems: [
    for (final label in ['歌曲', '歌手', '专辑', '风格'])
      HomeShortcutItem(icon: Icons.music_note, label: label, onTap: _noop),
  ],
  recentSongs: const [_song],
  onPlayRecent: _noop,
  onOpenRecent: _noop,
  onTapRecent: (_) {},
  playlists: const [
    FeiNiuPlaylist(
      guid: 'playlist',
      name: '很长的推荐歌单名称',
      createdAt: 0,
      updatedAt: 0,
    ),
  ],
  onOpenPlaylists: _noop,
  onTapPlaylist: (_) {},
  recentAlbums: const [
    FeiNiuAlbum(guid: 'album', name: '很长的专辑名称', trackCount: 123),
  ],
  onOpenAlbums: _noop,
  onTapAlbum: (_) {},
  recentTracks: const [_song],
  onOpenSongs: _noop,
  onTapTrack: (_) {},
  favoriteSongs: const [_song],
  onOpenFavorite: _noop,
  onTapFavorite: (_) {},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLayoutSettings.resetForTest();
    AppLayoutSettings.tvMode.value = true;
    AppLayoutSettings.tvUiScaleOverride.value = 2.0;
  });
  tearDown(AppLayoutSettings.resetForTest);

  for (final size in [
    const Size(800, 480),
    const Size(1024, 600),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets('200% 车机首页 $size / 字体 $textScale 无布局溢出', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // 侧栏占用的真实宽度与 TabletLayoutHost 一致。
        final railWidth = (size.width * .28)
            .clamp(640.0, 720.0)
            .clamp(0.0, size.width * .45);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(width: railWidth, child: const SideMenu()),
                  Expanded(child: _home()),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final homeScroll = find
            .descendant(
              of: find.byType(HomeLargeLayout),
              matching: find.byType(Scrollable),
            )
            .first;
        for (var i = 0; i < 24; i++) {
          await tester.drag(homeScroll, const Offset(0, -500));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('200% 窄屏首页将歌曲模块换成单栏', (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _home())));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-song-sections')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(HomeLargeLayout),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final sections = tester.widget<Wrap>(
      find.byKey(const ValueKey('home-song-sections')),
    );
    expect(sections.children, hasLength(3));
    final cards = sections.children.cast<SizedBox>().toList();
    expect(cards.first.width, 704);
    expect(tester.takeException(), isNull);
  });
  testWidgets('200% 窄屏漫游文字与操作按钮不重叠且可点击', (tester) async {
    tester.view.physicalSize = const Size(344, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var played = false;
    var refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: HomeHeroBanner(
            song: _song,
            height: 480,
            onPlay: () => played = true,
            onRefresh: () => refreshed = true,
          ),
        ),
      ),
    );
    final titleRect = tester.getRect(find.text(_song.title));
    final playRect = tester.getRect(find.byIcon(Icons.play_arrow_rounded));
    final badgeRect = tester.getRect(find.text('漫游 · 随心听'));
    final refreshRect = tester.getRect(find.byIcon(Icons.refresh_rounded));
    expect(titleRect.overlaps(playRect), isFalse);
    expect(badgeRect.overlaps(refreshRect), isFalse);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(played, isTrue);
    expect(refreshed, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('200% 与系统大字体下模块加载和重试提示无溢出', (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: _home(
              feedback: {
                for (final section in HomeSection.values)
                  section: HomeSectionFeedback(
                    section: section,
                    loading: section == HomeSection.roam,
                    onRetry: _noop,
                  ),
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final homeScroll = find
        .descendant(
          of: find.byType(HomeLargeLayout),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final label in ['我的歌单加载失败', '最新专辑加载失败']) {
      // 首页歌曲区有自己的滚动列表，直接推进外层位置以检查页面各模块。
      final position = tester.state<ScrollableState>(homeScroll).position;
      for (var i = 0; i < 50 && find.text(label).evaluate().isEmpty; i++) {
        position.jumpTo(
          (position.pixels + 400).clamp(0, position.maxScrollExtent),
        );
        await tester.pump();
      }
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    for (var i = 0; i < 24; i++) {
      await tester.drag(homeScroll, const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
