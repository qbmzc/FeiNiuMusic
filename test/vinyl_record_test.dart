import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feiniu_music/components/player/vinyl_record.dart';

void main() {
  group('VinylSpinSimulation', () {
    test('spins up smoothly from rest to the target speed', () {
      final sim = VinylSpinSimulation(
        start: 0,
        initialVelocity: 0,
        targetVelocity: 0.05,
        rate: 2.6,
      );

      expect(sim.x(0), 0);
      expect(sim.dx(0), 0);
      expect(sim.dx(0.3), inExclusiveRange(0, 0.05));
      expect(sim.dx(2), closeTo(0.05, 0.001));
      expect(sim.isDone(60), isFalse);
      // Position keeps increasing and stays continuous.
      expect(sim.x(0.5), lessThan(sim.x(1)));
    });

    test('coasts to a stop instead of freezing when paused', () {
      final sim = VinylSpinSimulation(
        start: 0.4,
        initialVelocity: 0.05,
        targetVelocity: 0,
        rate: 1.6,
      );

      expect(sim.x(0), closeTo(0.4, 1e-9));
      expect(sim.dx(0), 0.05);
      expect(sim.dx(0.5), inExclusiveRange(0, 0.05));
      expect(sim.isDone(0.5), isFalse);
      expect(sim.isDone(5), isTrue);
      // Total coast distance is v0 / k turns, a small natural run-out.
      expect(sim.x(10), closeTo(0.4 + 0.05 / 1.6, 1e-4));
    });
  });

  testWidgets('vinyl record renders the label at the configured ratio', (
    tester,
  ) async {
    const key = Key('label');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              VinylRecordDisc(
                size: 300,
                tint: Color(0xFF2E6BD8),
                label: ColoredBox(key: key, color: Color(0xFFFF0000)),
              ),
              VinylRecordGloss(size: 300),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(key)), const Size(228, 228));
    expect(tester.getSize(find.byType(VinylRecordDisc)), const Size(300, 300));
  });
}
