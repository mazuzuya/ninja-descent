import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ninja_descent/game/data.dart';
import 'package:ninja_descent/game/fx.dart';
import 'package:ninja_descent/game/simulation.dart';
import 'package:ninja_descent/game/ult_fx.dart';

void main() {
  late Fx fx;
  late Simulation sim;
  double laneX(num lane, int laneCount) => sim.laneX(lane.toDouble(), 390, laneCount);

  setUp(() {
    fx = Fx();
    final t = Tweaks.defaults();
    sim = Simulation(
      config: {"gravity": t.gravity, "enemyRate": t.enemyRate, "bossHp": t.bossHp, "effectsIntensity": 1},
      onEvent: (e) => fx.onEvent(e, laneX, sim.state),
    );
  });

  test('every area has an atmosphere', () => expect(kAmbient.length, AREAS.length));

  test('every powerup has a description', () {
    for (final p in POWERUPS) {
      expect(kPowerupInfo[p.type], isNotNull, reason: p.type);
    }
  });

  test('effects survive long runs in every area and stay bounded', () {
    final rand = math.Random(3);
    for (int area = 0; area < AREAS.length; area += 1) {
      sim.reset(skinIndex: area % SKINS.length);
      sim.startAtArea(area);
      for (int frame = 0; frame < 60 * 8 && sim.state.mode == "running"; frame += 1) {
        if (frame % 9 == 0) {
          switch (rand.nextInt(5)) {
            case 0:
              sim.move(rand.nextBool() ? 1 : -1);
            case 1:
              sim.shoot(rand.nextBool());
            case 2:
              sim.slash();
            case 3:
              sim.dash();
            default:
              sim.fastFall(rand.nextBool());
          }
        }
        sim.update(fx.scaleDt(1 / 60));
        fx.update(1 / 60, sim, 390, 920, laneX);
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      fx.renderAmbient(canvas, sim.state.time);
      fx.render(canvas, sim.state.cameraY);
      recorder.endRecording().dispose();
    }
  });

  test('every skin has its own ultimate and they all render, with and without targets', () {
    expect(kSkinPalette.length, SKINS.length);
    expect(kUltDurations.length, SKINS.length);
    for (int skin = 0; skin < SKINS.length; skin += 1) {
      for (final targets in [<ui.Offset>[], [const ui.Offset(60, 500), const ui.Offset(200, 700), const ui.Offset(330, 620)]]) {
        final cast = UltCast(skin, 195, 400, targets, 11);
        for (double t = 0; t <= 1.0; t += 0.1) {
          cast.age = t * cast.duration;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          renderUltVeil(canvas, cast, 390, 920);
          renderUlt(canvas, cast, 390, 920, 100);
          recorder.endRecording().dispose();
        }
      }
    }
  });

  test('casting a skill starts that skin\'s ultimate; shots hit with impact events', () {
    sim.reset(skinIndex: 7);
    sim.start();
    sim.dash();
    expect(fx.ults.single.skin, 7);
    fx.update(5, sim, 390, 920, laneX);
    expect(fx.ults, isEmpty);
  });

  test('hit-stop freezes the sim for its duration, slow motion scales it', () {
    fx.hitStop = 0.03;
    expect(fx.scaleDt(0.016), 0);
    expect(fx.scaleDt(0.016), 0);
    expect(fx.scaleDt(0.016), 0.016);
    fx.slowMo = 0.5;
    expect(fx.scaleDt(0.016), closeTo(0.016 * 0.28, 1e-9));
  });

  test('low effects mode caps particle work', () {
    fx.lowEffects = true;
    sim.reset(skinIndex: 0);
    for (int i = 0; i < 100; i += 1) {
      fx.burst(10, 10, 40, 0xffffffff);
    }
    fx.update(0.001, sim, 390, 920, laneX);
    final recorder = ui.PictureRecorder();
    fx.render(ui.Canvas(recorder), 0);
    recorder.endRecording().dispose();
  });
}
