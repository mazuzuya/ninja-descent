import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ninja_descent/game/data.dart';
import 'package:ninja_descent/game/simulation.dart';

Simulation makeSim(List<Map<String, dynamic>> events) {
  final tweaks = Tweaks.defaults();
  return Simulation(
    config: {
      "gravity": tweaks.gravity,
      "enemyRate": tweaks.enemyRate,
      "bossHp": tweaks.bossHp,
      "effectsIntensity": tweaks.effectsIntensity,
    },
    onEvent: events.add,
  );
}

void step(Simulation sim, double seconds) {
  for (double t = 0; t < seconds; t += 1 / 60) {
    sim.update(1 / 60);
  }
}

void main() {
  test('arrow auto aim hits a nearby enemy in the next lane', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.start();
    final player = sim.state.player;
    final enemy = sim.nearEnemies.first;
    for (final other in sim.nearEnemies) {
      other["alive"] = false;
    }
    enemy["alive"] = true;
    enemy["lane"] = (player["lane"] as double) == 0 ? 1.0 : (player["lane"] as double) - 1.0;
    enemy["y"] = (player["y"] as double) + 40;
    enemy["hp"] = 20.0;
    sim.state.boss["active"] = false;

    sim.shoot();
    expect(sim.state.projectiles.single["laneVelocity"].abs(), greaterThan(2));
    for (int i = 0; i < 30; i += 1) {
      sim.updateProjectiles(1 / 60);
    }
    expect(enemy["hp"], lessThan(20));
  });

  test('swiping past the edge lane keeps the lane a double and the run alive', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.start();
    for (int i = 0; i < 6; i += 1) {
      sim.move(1);
      step(sim, 0.05);
    }
    expect(sim.state.player["targetLane"], isA<double>());
    expect(sim.state.player["targetLane"], sim.state.laneCount - 1.0);
    final y = sim.state.player["y"] as double;
    step(sim, 2);
    expect(sim.state.player["y"] as double, greaterThan(y));
  });

  test('a broken platform breaks exactly once', () {
    final events = <Map<String, dynamic>>[];
    final sim = makeSim(events);
    sim.reset(skinIndex: 0);
    sim.start();
    final platform = sim.state.platforms.firstWhere((p) => p["floor"] == 3);
    platform["breakAt"] = sim.state.time + 0.1;
    step(sim, 1);
    expect(events.where((e) => e["type"] == "platformBreak").length, 1);
    expect(platform["alive"], isFalse);
  });

  test('fast fall and area changes never store ints in float fields', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.startAtArea(0);
    sim.fastFall(true);
    // Jump straight to the start of area 2 so updateArea re-maps the lane.
    sim.state.player["y"] = (sim.state.layouts[1]["startY"] as double) - 10;
    sim.state.player["grounded"] = false;
    sim.state.player["vy"] = 400.0;
    step(sim, 0.5);
    expect(sim.state.areaIndex, greaterThanOrEqualTo(1));
    expect(sim.state.player["targetLane"], isA<double>());
    expect(sim.state.player["vy"], isA<double>());
  });

  test('the player stays on the boss arena while the boss is alive', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 9); // shield skin: survives a few boss shots
    sim.startAtArea(0);
    final arena = sim.state.platforms.firstWhere((p) => p["arena"] == true && p["areaIndex"] == 0 && p["lane"] == 1);
    sim.state.player["y"] = (arena["y"] as double) - 30;
    sim.state.player["lane"] = 1.0;
    sim.state.player["targetLane"] = 1.0;
    sim.state.player["grounded"] = false;
    sim.state.player["vy"] = 200.0;
    sim.state.boss["maxHp"] = 1e9;
    sim.state.boss["hp"] = 1e9;
    step(sim, 0.3);
    expect(sim.state.boss["active"], isTrue);
    sim.state.buffs["celestial_aegis"] = 100;
    step(sim, 4);
    expect(sim.state.player["y"], arena["y"]);
    expect(sim.state.player["grounded"], isTrue);
  });

  test('chain projectiles hit at most `chain` extra enemies', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 7);
    sim.start();
    final y = sim.state.player["y"] as double;
    sim.state.enemies = [
      for (int i = 0; i < 6; i += 1)
        {
          "id": "t$i", "areaIndex": 0, "laneCount": 4, "lane": i == 0 ? 1.0 : 3.0, "baseLane": 3.0,
          "y": y + 400, "type": "shadow_footsoldier", "variant": 0, "hp": 100.0, "maxHp": 100.0,
          "alive": true, "age": 0.0, "attackTimer": 99.0, "dir": 1.0, "frozen": 99.0, "burn": 0.0, "burnDps": 0.0,
        },
    ];
    sim.indexEntities(); // the sim reads enemies through the near-area window
    sim.state.projectiles = [
      {
        "lane": 1.0, "laneCount": 4, "laneVelocity": 0.0, "y": y + 362, "vy": 0.0, "damage": 10.0, "pierce": 1,
        "charged": false, "skinIndex": 7, "age": 0.0, "rotation": 0.0, "hitIds": <String>[],
        "burn": 0.0, "blast": 0.0, "chain": 2, "heal": 0.0, "radius": 0.32,
      },
    ];
    sim.updateProjectiles(1 / 60);
    final damaged = sim.state.enemies.where((e) => (e["hp"] as num) < 100).length;
    expect(damaged, 3); // direct hit + 2 chained
  });

  test('a long random run across every area never throws', () {
    final rand = math.Random(1);
    for (int area = 0; area < AREAS.length; area += 1) {
      final sim = makeSim([]);
      sim.reset(skinIndex: area % SKINS.length);
      sim.startAtArea(area);
      for (int frame = 0; frame < 60 * 20; frame += 1) {
        if (sim.state.mode != "running") break;
        if (frame % 9 == 0) {
          switch (rand.nextInt(6)) {
            case 0: sim.move(-1);
            case 1: sim.move(1);
            case 2: sim.shoot(rand.nextBool());
            case 3: sim.slash();
            case 4: sim.dash();
            default: sim.fastFall(rand.nextBool());
          }
        }
        sim.update(1 / 60);
        final lane = sim.state.player["lane"] as double;
        expect(lane.isFinite && lane >= 0 && lane <= sim.state.laneCount - 1, isTrue);
      }
    }
  });

  test('an idle ninja stays put; swiping down descends exactly one row', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.start();
    sim.state.buffs["celestial_aegis"] = 1e9;
    // Clear area 1's wind mechanic out of the way: it may push the ninja off.
    sim.state.mechanicTimer = 1e9;
    final y = sim.state.player["y"] as double;
    step(sim, 10);
    expect(sim.state.player["y"], y);
    expect(sim.state.player["grounded"], isTrue);
    sim.fastFall();
    step(sim, 0.5);
    expect(sim.state.player["y"], y + FLOOR_SPACING);
    expect(sim.state.player["grounded"], isTrue);
  });

  test('the ninja falls when its platform vanishes or it is pushed off the edge', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.start();
    sim.state.mechanicTimer = 1e9;
    final y = sim.state.player["y"] as double;
    final start = sim.state.platforms.firstWhere((p) => p["id"] == sim.state.player["currentPlatform"]);
    start["alive"] = false;
    step(sim, 0.6);
    expect(sim.state.player["y"] as double, greaterThan(y));

    // Floor 1 of area 1 is a full row: drifting sideways slides onto the neighbour.
    final row = sim.state.player["y"];
    sim.state.player["targetLane"] = 0.0;
    step(sim, 1);
    expect(sim.state.player["y"], row);
    expect(sim.state.player["grounded"], isTrue);
  });

  test('swiping down or pounding cannot leave the arena while the boss lives', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.startAtArea(0);
    final arena = sim.state.platforms.firstWhere((p) => p["arena"] == true && p["areaIndex"] == 0 && p["lane"] == 1);
    sim.state.player["y"] = (arena["y"] as double) - 30;
    sim.state.player["lane"] = 1.0;
    sim.state.player["targetLane"] = 1.0;
    sim.state.player["grounded"] = false;
    sim.state.player["vy"] = 200.0;
    sim.state.player["groundPound"] = true;
    sim.state.buffs["celestial_aegis"] = 1e9;
    sim.state.boss["maxHp"] = 1e9;
    sim.state.boss["hp"] = 1e9;
    step(sim, 0.3);
    expect(sim.state.boss["active"], isTrue);
    sim.fastFall();
    sim.fastFall(true);
    step(sim, 2);
    expect(sim.state.player["y"], arena["y"]);
    expect(arena["alive"], isTrue);
  });

  test('heal items are scattered through every area, heal once, and wait at full HP', () {
    final events = <Map<String, dynamic>>[];
    final sim = makeSim(events);
    sim.reset(skinIndex: 0);
    for (int area = 0; area < AREAS.length; area += 1) {
      expect(sim.state.powerups.where((p) => p["type"] == healItem && p["areaIndex"] == area).length, greaterThanOrEqualTo(1), reason: "area $area");
    }
    sim.start();
    sim.state.mechanicTimer = 1e9;
    final player = sim.state.player;
    final item = sim.state.powerups.firstWhere((p) => p["type"] == healItem);
    sim.state.powerups.remove(item);
    item
      ..["lane"] = player["lane"]
      ..["y"] = (player["y"] as double) - 38;
    sim.state.powerups = [item];
    sim.indexEntities();

    step(sim, 0.1);
    expect(item["active"], isTrue, reason: "full HP should not consume it");

    player["hp"] = 50.0;
    step(sim, 0.1);
    expect(item["active"], isFalse);
    expect(player["hp"], 50.0 + healAmount);
    expect(events.where((e) => e["type"] == "heal").length, 1);

    player["hp"] = 90.0;
    item["active"] = true;
    step(sim, 0.1);
    expect(player["hp"], player["maxHp"], reason: "never heals past max");
  });

  test('a cleared boss arena drops into the next area without gap damage', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.startAtArea(0);
    final arena = sim.state.platforms.firstWhere((p) => p["arena"] == true && p["areaIndex"] == 0 && p["lane"] == 1);
    sim.state.player["y"] = (arena["y"] as double) - 30;
    sim.state.player["lane"] = 1.0;
    sim.state.player["targetLane"] = 1.0;
    sim.state.player["grounded"] = false;
    sim.state.player["vy"] = 200.0;
    step(sim, 0.3);
    sim.state.boss["hp"] = 0.0;
    sim.state.hostileProjectiles = [];
    step(sim, 0.1);
    final hp = sim.state.player["hp"] as double;
    sim.nearEnemies.clear();
    sim.nearObstacles.clear();
    final startArea = sim.state.areaIndex;
    sim.fastFall();
    while (sim.state.areaIndex == startArea && sim.state.time < 30) {
      sim.state.hostileProjectiles = [];
      sim.update(1 / 60);
    }
    expect(sim.state.areaIndex, 1);
    expect(sim.state.player["hp"] as double, greaterThanOrEqualTo(hp));
  });

  test('run statistics count kills and the best combo', () {
    final sim = makeSim([]);
    sim.reset(skinIndex: 0);
    sim.start();
    final enemies = sim.nearEnemies.take(3).toList();
    for (final enemy in enemies) {
      sim.defeatEnemy(enemy);
    }
    expect(sim.state.kills, 3);
    expect(sim.state.maxCombo, 3);
    sim.reset(skinIndex: 0);
    expect(sim.state.kills, 0);
  });

  test('environmental damage eases in from 60% and reaches the JS value by area 9', () {
    final damage = <double>[];
    for (final area in [0, 8]) {
      final events = <Map<String, dynamic>>[];
      final sim = makeSim(events);
      sim.reset(skinIndex: 0);
      sim.startAtArea(area);
      final spikes = sim.state.platforms.firstWhere((p) => p["areaIndex"] == area && p["type"] == "spiked_wood");
      sim.land(spikes);
      damage.add((events.firstWhere((e) => e["type"] == "hit")["amount"] as num).toDouble());
    }
    expect(damage[0], closeTo(12, 0.001));
    expect(damage[1], closeTo(20, 0.001));
  });
}
