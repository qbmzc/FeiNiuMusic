import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'package:feiniu_music/app/state/song_state.dart';
import 'package:feiniu_music/pages/player/widgets/player_background.dart';
import 'package:feiniu_music/pages/player/widgets/player_portrait_top_bar.dart';
import 'package:feiniu_music/pages/player/widgets/player_seek_track.dart';

void main() {
  group('dominantColorFromPixels', () {
    test(
      'keeps a real cover color when two hues would average to mud',
      () async {
        const red = 0xFFD8312A;
        const blue = 0xFF2A4FD8;
        final pixels = [...List.filled(550, red), ...List.filled(450, blue)];

        final color = (await dominantColorFromPixels(pixels))!;
        final hsl = HSLColor.fromColor(color);

        // 平均色会是低饱和的灰紫；量化打分应返回其中一个真实色块。
        expect(hsl.saturation, greaterThan(0.6));
        expect(
          hsl.hue < 20 || hsl.hue > 340 || (hsl.hue > 215 && hsl.hue < 245),
          isTrue,
          reason: 'hue=${hsl.hue}',
        );
      },
    );

    test('prefers a vivid accent over a neutral gray majority', () async {
      final pixels = [
        ...List.filled(800, 0xFF7F7F7F),
        ...List.filled(200, 0xFF1E5BFF),
      ];

      final color = (await dominantColorFromPixels(pixels))!;
      final hsl = HSLColor.fromColor(color);

      expect(hsl.hue, inInclusiveRange(210, 240));
      expect(hsl.saturation, greaterThan(0.6));
    });

    test('falls back to the average for grayscale covers', () async {
      final pixels = [
        ...List.filled(500, 0xFF202020),
        ...List.filled(500, 0xFFE0E0E0),
      ];

      final color = await dominantColorFromPixels(pixels);

      expect(color, const Color(0xFF808080));
    });

    test('returns null when no pixels are available', () async {
      expect(await dominantColorFromPixels(const []), isNull);
    });
  });

  test('player cover defaults favour a calm rounded-square look', () async {
    SharedPreferences.setMockInitialValues({});
    PlayerBackgroundSettings.resetForTest();
    await PlayerBackgroundSettings.ensureLoaded();

    expect(
      PlayerBackgroundSettings.hueShift.value,
      PlayerBackgroundSettings.defaultHueShift,
    );
    expect(PlayerBackgroundSettings.defaultHueShift, lessThanOrEqualTo(40));
    expect(PlayerBackgroundSettings.roundCover.value, isFalse);
    expect(PlayerBackgroundSettings.rotateCover.value, isFalse);
  });

  test('stored cover preferences still win over the new defaults', () async {
    SharedPreferences.setMockInitialValues({
      'gradient_hue_shift': 120.0,
      'player_round_cover': true,
      'player_rotate_cover': true,
    });
    PlayerBackgroundSettings.resetForTest();
    await PlayerBackgroundSettings.ensureLoaded();

    expect(PlayerBackgroundSettings.hueShift.value, 120.0);
    expect(PlayerBackgroundSettings.roundCover.value, isTrue);
    expect(PlayerBackgroundSettings.rotateCover.value, isTrue);
  });

  test('hidden seek thumb keeps its geometry so track insets stay aligned', () {
    const hidden = PlayerSeekThumbShape(preferredRadius: 6, paintRadius: 0);
    const shown = PlayerSeekThumbShape(preferredRadius: 6, paintRadius: 7);

    expect(hidden.getPreferredSize(true, false), const Size(12, 12));
    expect(
      shown.getPreferredSize(true, false),
      hidden.getPreferredSize(true, false),
    );
  });

  testWidgets('portrait top bar reveals the song title on the lyrics page', (
    tester,
  ) async {
    final song = signal<SongEntity?>(
      const SongEntity(id: 's1', title: 'Night Drive', artist: 'Lumen'),
    );
    final controller = PageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerPortraitTopBar(
                songSignal: song,
                pageController: controller,
              ),
              Expanded(
                child: PageView(
                  controller: controller,
                  children: const [SizedBox.expand(), SizedBox.expand()],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Night Drive'), findsNothing);

    controller.jumpToPage(1);
    await tester.pump();

    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('Lumen'), findsOneWidget);
  });
}
