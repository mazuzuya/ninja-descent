import 'package:flutter_test/flutter_test.dart';
import 'package:ninja_descent/game/data.dart';
import 'package:ninja_descent/game/simulation.dart';

// A plain reactive player: shoots often, uses its skill, steers to the safest
// lane of the next row. Guards the difficulty curve: a free skin must get past
// the first boss, and a paid skin must go clearly further.
int furthestArea(int skin) {
  final t = Tweaks.defaults();
  final sim = Simulation(
    config: {"gravity": t.gravity, "enemyRate": t.enemyRate, "bossHp": t.bossHp, "effectsIntensity": 1},
    onEvent: (_) {},
  );
  sim.reset(skinIndex: skin);
  sim.start();
  for (int f = 0; sim.state.mode == "running" && f < 60 * 300; f += 1) {
    final player = sim.state.player;
    final y = (player["y"] as num).toDouble();
    final lane = (player["targetLane"] as num).toDouble();
    if (f % 12 == 0) sim.shoot();
    if (f % 30 == 0) sim.dash();
    if (f % 20 == 0 && player["grounded"] == true) {
      double? next;
      for (final p in sim.nearPlatforms) {
        final py = p["y"] as double;
        if (py > y + 1 && p["alive"] == true && (next == null || py < next)) next = py;
      }
      if (next != null) {
        final row = next;
        double score(int l) {
          var s = -(l - lane).abs() * 0.1;
          var solid = false;
          for (final p in sim.nearPlatforms) {
            if (p["y"] == row && (p["lane"] as num) == l && p["alive"] == true) {
              solid = true;
              if (p["type"] == "spiked_wood") s -= 5;
              if (p["type"] == "fire_grate") s -= 1;
            }
          }
          if (!solid) s -= 2;
          for (final e in sim.nearEnemies) {
            if (e["alive"] == true && ((e["y"] as num) - row).abs() < 60 && ((e["lane"] as num) - l).abs() < 0.6) s -= 4;
          }
          for (final h in sim.nearObstacles) {
            if (((h["y"] as num) - (row - 40)).abs() < 70 && ((h["lane"] as num) - l).abs() < 0.6) s -= 3;
          }
          return s;
        }

        var best = lane.round();
        var bestScore = score(best);
        for (int l = 0; l < sim.state.laneCount; l += 1) {
          final value = score(l);
          if (value > bestScore) {
            bestScore = value;
            best = l;
          }
        }
        if (best > lane + 0.4) sim.move(1);
        if (best < lane - 0.4) sim.move(-1);
      }
    }
    if (f % 40 == 10 && player["grounded"] == true) sim.fastFall();
    sim.update(1 / 60);
  }
  return sim.state.areaIndex + 1;
}

void main() {
  test('a free skin clears the first boss', () {
    final runs = [for (int i = 0; i < 4; i += 1) furthestArea(0)];
    expect(runs.where((area) => area >= 2).length, greaterThanOrEqualTo(3), reason: "areas reached: $runs");
  });

  test('a paid skin outlasts a free one', () {
    int total(int skin) => [for (int i = 0; i < 3; i += 1) furthestArea(skin)].reduce((a, b) => a + b);
    expect(total(9), greaterThan(total(0)));
  });
}
