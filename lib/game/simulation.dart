// Port of game js/game/simulation.js — gameplay physics, level, entities, boss.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data.dart';

typedef EventSink = void Function(Map<String, dynamic> event);

class GameState {
  String mode = "idle";
  double time = 0;
  double cameraY = 0;
  double score = 0;
  double coins = 0;
  int combo = 0;
  double comboTimer = 0;
  int floor = 0;
  int areaFloor = 0;
  int areaIndex = 0;
  int laneCount = 3;
  int skinIndex = 0;
  double shake = 0;
  double flash = 0;
  String banner = "";
  double bannerTime = 0;
  Map<String, dynamic> player = {};
  List<Map<String, dynamic>> platforms = [];
  List<Map<String, dynamic>> enemies = [];
  List<Map<String, dynamic>> pickups = [];
  List<Map<String, dynamic>> powerups = [];
  List<Map<String, dynamic>> obstacles = [];
  List<Map<String, dynamic>> projectiles = [];
  List<Map<String, dynamic>> hostileProjectiles = [];
  List<Map<String, dynamic>> effects = [];
  List<Map<String, dynamic>> arsenalEffects = [];
  List<Map<String, dynamic>> bosses = [];
  Map<String, dynamic> boss = {};
  List<Map<String, dynamic>> layouts = [];
  Map<String, double> buffs = {};
  List<Map<String, dynamic>> itemEffects = [];
  double mechanicTimer = 5;
  double lastKillTime = 0;
  double worldScale = 1;
  double worldTime = 0;
  bool mechanicWarned = false;
  // Run statistics for the results screen.
  int kills = 0;
  int maxCombo = 0;
  int bossKills = 0;
  double viewWidth = 390;

  // --- diagnostics for the "character disappears / falls away" bug ---
  int fallFrames = 0;
  double lastLoggedY = 0;
  int landMissCount = 0;
}

double Function() seeded(int seed) {
  int value = seed.toUnsigned(32);
  return () {
    value = (value * 1664525 + 1013904223).toUnsigned(32);
    return value / 4294967296;
  };
}

final _platformThemes = [
  ["normal_wood", "cracked_bamboo", "moving_chain", "spiked_wood"],
  ["normal_wood", "cracked_bamboo", "moving_chain", "spiked_wood"],
  ["normal_wood", "vanishing_spirit", "moving_chain", "spiked_wood"],
  ["normal_wood", "moving_chain", "vanishing_spirit", "ice_bridge"],
  ["fire_grate", "normal_wood", "cracked_bamboo", "trampoline_drums"],
  ["normal_wood", "vanishing_spirit", "cracked_bamboo", "moving_chain"],
  ["moving_chain", "normal_wood", "spiked_wood", "vanishing_spirit"],
  ["vanishing_spirit", "cracked_bamboo", "moving_chain", "spiked_wood"],
  ["ice_bridge", "moving_chain", "vanishing_spirit", "spiked_wood"],
  ["vanishing_spirit", "spiked_wood", "moving_chain", "fire_grate"],
  ["moving_chain", "vanishing_spirit", "spiked_wood", "normal_wood"],
  ["moving_chain", "spiked_wood", "normal_wood", "fire_grate"],
  ["moving_chain", "vanishing_spirit", "ice_bridge", "normal_wood"],
  ["vanishing_spirit", "moving_chain", "normal_wood", "spiked_wood"],
  ["moving_chain", "fire_grate", "spiked_wood", "trampoline_drums"],
  ["vanishing_spirit", "ice_bridge", "moving_chain", "spiked_wood"],
  ["normal_wood", "spiked_wood", "vanishing_spirit", "cracked_bamboo"],
  ["fire_grate", "moving_chain", "spiked_wood", "vanishing_spirit"],
  ["vanishing_spirit", "moving_chain", "ice_bridge", "trampoline_drums"],
  ["vanishing_spirit", "spiked_wood", "fire_grate", "moving_chain"],
];

String platformType(int areaIndex, double roll, int floor) {
  if (floor == 0) return "normal_wood";
  final themed = _platformThemes[areaIndex];
  return themed[math.min(themed.length - 1, (roll * themed.length).floor())];
}

// Small healing drops scattered over the level, separate from the POWERUPS
// rotation (which only rarely rolls the big elixir).
const String healItem = "heal_item";
const double healAmount = 25;

class Simulation {
  final Map<String, double> config;
  final EventSink onEvent;
  final GameState state = GameState();
  final _rand = math.Random();

  Simulation({required this.config, required this.onEvent});

  // Width reserved between the screen edge and the nearest platform edge,
  // and the gap kept between two neighbouring platforms (all in world units).
  static const double _sideMargin = 10.0;
  static const double _laneGap = 8.0;

  // Visual platform width that always fits the available view width, no matter
  // how many lanes there are. Falls back to the hand-tuned design sizes on wide
  // screens where there is room to spare.
  double platformWidth(int laneCount, [double viewWidth = 390]) {
    final design = laneCount >= 8
        ? 44.0
        : laneCount >= 7
            ? 52.0
            : laneCount == 6
                ? 62.0
                : laneCount >= 5
                    ? 82.0
                    : laneCount == 4
                        ? 104.0
                        : 132.0;
    final available = viewWidth - _sideMargin * 2 - (laneCount - 1) * _laneGap;
    final bySpace = laneCount > 0 ? available / laneCount : available;
    return math.min(design, math.max(20.0, bySpace));
  }

  // Center x (world units) of a lane, computed so the whole playfield — every
  // platform including the outermost ones — stays inside the visible width.
  double laneX(double lane, [double viewWidth = 390, int laneCount = 3]) {
    final w = platformWidth(laneCount, viewWidth);
    final total = laneCount * w + (laneCount - 1) * _laneGap;
    final start = (viewWidth - total) / 2 + w / 2;
    return start + lane * (w + _laneGap);
  }

  void addEffect(String type, num lane, num y, [double scale = 1, int? laneCount]) {
    state.effects.add({"type": type, "lane": lane.toDouble(), "laneCount": laneCount ?? state.laneCount, "y": y.toDouble(), "scale": scale, "age": 0.0, "duration": 0.42});
  }

  void addArsenalEffect(String kind, int skinIndex, num lane, num y, [double scale = 1, int? laneCount, double duration = 0.38]) {
    state.arsenalEffects.add({"kind": kind, "skinIndex": skinIndex, "lane": lane.toDouble(), "laneCount": laneCount ?? state.laneCount, "y": y.toDouble(), "scale": scale, "age": 0.0, "duration": duration});
  }

  Map<String, dynamic> makePlatform(Map<String, dynamic> props) {
    return {
      "id": props["id"],
      "areaIndex": props["areaIndex"],
      "floor": props["floor"],
      "lane": props["lane"],
      "laneCount": props["laneCount"],
      "y": props["y"],
      "type": props["type"],
      "alive": true,
      "visible": true,
      "phase": (props["id"] as int) % 13 * 0.47,
      ...Map<String, dynamic>.from(props)
        ..remove("id")
        ..remove("areaIndex")
        ..remove("floor")
        ..remove("lane")
        ..remove("laneCount")
        ..remove("y")
        ..remove("type"),
    };
  }

  void buildLevel() {
    final random = seeded(23071993);
    // Own stream, so heal drops don't reshuffle the rest of the level.
    final healRandom = seeded(19930723);
    final platforms = <Map<String, dynamic>>[];
    final enemies = <Map<String, dynamic>>[];
    final pickups = <Map<String, dynamic>>[];
    final powerups = <Map<String, dynamic>>[];
    final obstacles = <Map<String, dynamic>>[];
    final bosses = <Map<String, dynamic>>[];
    final layouts = <Map<String, dynamic>>[];
    int globalRow = 0;

    for (final area in AREAS) {
      final startRow = globalRow;
      final startY = START_Y + startRow * FLOOR_SPACING;
      // Random spacing that still guarantees every area gets several.
      var nextHeal = 2 + (healRandom() * 9).floor();
      for (int floor = 0; floor < area.floors; floor += 1) {
        final y = START_Y + globalRow * FLOOR_SPACING;
        // Area 1 eases the player in: its first few floors are gap-free so the
        // opening drop is a single floor, not a long empty shaft.
        final fullRow = floor == 0 || floor % 5 == 0 || (area.index == 0 && floor <= 4);
        final gapCount = fullRow ? 0 : area.lanes >= 7 ? 3 : area.lanes >= 5 ? 2 : 1;
        final blocked = <int>{};
        while (blocked.length < gapCount) blocked.add((random() * area.lanes).floor());

        final rowLanes = <int>[];
        for (int lane = 0; lane < area.lanes; lane += 1) {
          if (blocked.contains(lane)) continue;
          String? type = (area.index == 0 && floor == 0 && lane != (area.lanes / 2).floor())
              ? null
              : platformType(area.index, random(), floor);
          if (type == null) continue;
          final id = area.index * 10000 + floor * 10 + lane;
          platforms.add(makePlatform({"id": id, "areaIndex": area.index, "floor": floor, "lane": lane, "laneCount": area.lanes, "y": y, "type": type}));
          rowLanes.add(lane);

          final enemyChance = math.min(0.88, config["enemyRate"]! + area.index * 0.032);
          if (floor > 1 && random() < enemyChance && type != "spiked_wood") {
            final variant = (random() * area.enemies.length).floor();
            enemies.add({
              "id": "e-${area.index}-$floor-$lane",
              "areaIndex": area.index,
              "laneCount": area.lanes,
              "lane": lane.toDouble(),
              "baseLane": lane.toDouble(),
              "y": y - 6,
              "type": area.enemies[variant],
              "variant": variant,
              "hp": 2 + (area.index / 3).floor() + (variant == 2 ? 1 : 0),
              "maxHp": 2 + (area.index / 3).floor() + (variant == 2 ? 1 : 0),
              "alive": true,
              "age": random() * 3,
              "attackTimer": 1.4 + random() * 2,
              "dir": random() > 0.5 ? 1.0 : -1.0,
              "frozen": 0.0,
              "burn": 0.0,
              "burnDps": 0.0,
            });
          } else if (random() < 0.86) {
            pickups.add({"id": "c-${area.index}-$floor-$lane", "areaIndex": area.index, "laneCount": area.lanes, "lane": lane.toDouble(), "y": y - 55, "type": "gold_coin", "active": true, "bob": random() * 4});
            if (random() < 0.24) {
              pickups.add({"id": "c2-${area.index}-$floor-$lane", "areaIndex": area.index, "laneCount": area.lanes, "lane": lane.toDouble(), "y": y - 91, "type": "gold_coin", "active": true, "bob": random() * 4});
            }
          }
        }

        if (floor > 3 && (floor + area.index * 2) % 9 == 0 && rowLanes.isNotEmpty) {
          final lane = rowLanes[(random() * rowLanes.length).floor()];
          final powerup = POWERUPS[(random() * POWERUPS.length).floor()];
          powerups.add({
            "id": "p-${area.index}-$floor",
            "areaIndex": area.index,
            "laneCount": area.lanes,
            "lane": lane.toDouble(),
            "y": y - 82,
            "type": powerup.type,
            "active": true,
            "bob": random() * 5,
          });
        }

        if (floor >= nextHeal && rowLanes.isNotEmpty) {
          nextHeal = floor + 5 + (healRandom() * 9).floor();
          powerups.add({
            "id": "heal-${area.index}-$floor",
            "areaIndex": area.index,
            "laneCount": area.lanes,
            "lane": rowLanes[(healRandom() * rowLanes.length).floor()].toDouble(),
            "y": y - 68,
            "type": healItem,
            "active": true,
            "bob": healRandom() * 5,
          });
        }

        if (floor > 2 && floor % (area.index >= 3 ? 2 : 3) == 0) {
          final hazardCount = area.index >= 15 && floor % 4 == 0 ? 3 : area.index >= 7 && floor % 4 == 0 ? 2 : 1;
          final used = <int>{};
          for (int h = 0; h < hazardCount; h += 1) {
            int lane = (random() * area.lanes).floor();
            while (used.contains(lane)) lane = (random() * area.lanes).floor();
            used.add(lane);
            obstacles.add({
              "id": "h-${area.index}-$floor-$h",
              "areaIndex": area.index,
              "laneCount": area.lanes,
              "lane": lane.toDouble(),
              "y": y - 44,
              "type": area.hazards[(floor + h) % area.hazards.length],
              "phase": random() * 2.2,
              "period": math.max(2.0, 2.75 - area.index * 0.035),
              "warning": 0.72,
              "activeWindow": 0.72,
              "active": false,
              "telegraph": false,
              "hitCooldown": 0.0,
              "direction": random() > 0.5 ? 1.0 : -1.0,
            });
          }
        }
        globalRow += 1;
      }

      final arenaY = START_Y + globalRow * FLOOR_SPACING;
      for (int lane = 0; lane < area.lanes; lane += 1) {
        platforms.add(makePlatform({
          "id": 900000 + area.index * 10 + lane,
          "areaIndex": area.index,
          "floor": area.floors,
          "lane": lane,
          "laneCount": area.lanes,
          "y": arenaY,
          "type": "normal_wood",
          "arena": true,
        }));
      }
      final bossY = arenaY + 145;
      platforms.add(makePlatform({
        "id": 990000 + area.index,
        "areaIndex": area.index,
        "floor": area.floors + 1,
        "lane": (area.lanes - 1) / 2,
        "laneCount": area.lanes,
        "y": bossY + 7,
        "type": area.index == 8 ? "ice_bridge" : "moving_chain",
        "bossBase": true,
      }));
      final maxHp = config["bossHp"]! + area.index * 10 + (area.index >= 9 ? 18 : 0) + (area.index == AREAS.length - 1 ? 30 : 0);
      bosses.add({
        "areaIndex": area.index,
        "name": area.boss,
        "active": false,
        "defeated": false,
        "laneCount": area.lanes,
        "lane": (area.lanes - 1) / 2,
        "y": bossY,
        "hp": maxHp,
        "maxHp": maxHp,
        "attackTimer": 1.5,
        "dodgeCooldown": 0.0,
        "dodging": 0.0,
        "anim": "idle",
        "animTime": 0.0,
        "arenaY": arenaY,
        "clearTimer": 0.0,
      });
      layouts.add({"areaIndex": area.index, "startY": startY, "arenaY": arenaY, "endY": bossY + 170, "startRow": startRow, "floors": area.floors});
      globalRow += 3;
    }

    state.platforms = platforms;
    state.enemies = enemies;
    state.pickups = pickups;
    state.powerups = powerups;
    state.obstacles = obstacles;
    state.bosses = bosses;
    state.boss = bosses[0];
    state.layouts = layouts;
    indexEntities();
  }

  // Entities bucketed per area. Each frame only the areas around the player
  // (current ±1) are simulated and drawn, so the cost no longer grows with the
  // whole 20-area level (~10k entities).
  List<List<Map<String, dynamic>>> _platformsByArea = [];
  List<List<Map<String, dynamic>>> _enemiesByArea = [];
  List<List<Map<String, dynamic>>> _pickupsByArea = [];
  List<List<Map<String, dynamic>>> _powerupsByArea = [];
  List<List<Map<String, dynamic>>> _obstaclesByArea = [];
  List<Map<String, dynamic>> nearPlatforms = [];
  List<Map<String, dynamic>> nearEnemies = [];
  List<Map<String, dynamic>> nearPickups = [];
  List<Map<String, dynamic>> nearPowerups = [];
  List<Map<String, dynamic>> nearObstacles = [];
  int _nearArea = -1;

  // Rebuilds the per-area buckets; call after replacing an entity list.
  void indexEntities() {
    List<List<Map<String, dynamic>>> bucket(List<Map<String, dynamic>> items) {
      final buckets = List.generate(AREAS.length, (_) => <Map<String, dynamic>>[]);
      for (final item in items) {
        buckets[item["areaIndex"] as int].add(item);
      }
      return buckets;
    }

    _platformsByArea = bucket(state.platforms);
    _enemiesByArea = bucket(state.enemies);
    _pickupsByArea = bucket(state.pickups);
    _powerupsByArea = bucket(state.powerups);
    _obstaclesByArea = bucket(state.obstacles);
    _nearArea = -1;
    _refreshNear();
  }

  void _refreshNear() {
    if (_nearArea == state.areaIndex || _platformsByArea.isEmpty) return;
    _nearArea = state.areaIndex;
    final from = math.max(0, state.areaIndex - 1);
    final to = math.min(AREAS.length - 1, state.areaIndex + 1);
    List<Map<String, dynamic>> window(List<List<Map<String, dynamic>>> buckets) =>
        [for (int i = from; i <= to; i += 1) ...buckets[i]];
    nearPlatforms = window(_platformsByArea);
    nearEnemies = window(_enemiesByArea);
    nearPickups = window(_pickupsByArea);
    nearPowerups = window(_powerupsByArea);
    nearObstacles = window(_obstaclesByArea);
  }

  void reset({int skinIndex = -1}) {
    final si = skinIndex < 0 ? state.skinIndex : skinIndex % SKINS.length;
    state.mode = "idle";
    state.time = 0;
    state.cameraY = 0;
    state.score = 0;
    state.coins = 0;
    state.combo = 0;
    state.comboTimer = 0;
    state.floor = 0;
    state.areaFloor = 0;
    state.areaIndex = 0;
    state.laneCount = AREAS[0].lanes;
    state.skinIndex = si;
    state.shake = 0;
    state.flash = 0;
    state.banner = "AREA 1 · ROOFTOP DOJO";
    state.bannerTime = 2.4;
    state.projectiles = [];
    state.hostileProjectiles = [];
    state.effects = [];
    state.arsenalEffects = [];
    state.itemEffects = [];
    state.buffs = {for (final p in POWERUPS) p.type: 0};
    state.mechanicTimer = 5;
    state.lastKillTime = 0;
    state.worldScale = 1;
    state.worldTime = 0;
    state.mechanicWarned = false;
    state.kills = 0;
    state.maxCombo = 0;
    state.bossKills = 0;
    final hpBonus = [3, 13].contains(state.skinIndex) ? 20 : 0;
    state.player = {
      "lane": (AREAS[0].lanes / 2).floor().toDouble(),
      "targetLane": (AREAS[0].lanes / 2).floor().toDouble(),
      "y": START_Y,
      "vy": 0.0,
      "hp": 100.0 + hpBonus,
      "maxHp": 100.0 + hpBonus,
      "grounded": true,
      "groundTime": 0.0,
      "currentPlatform": 0,
      "invulnerable": 0.0,
      "dashCooldown": 0.0,
      "slashCooldown": 0.0,
      "slowTimer": 0.0,
      "anim": "idle",
      "animTime": 0.0,
      "animUntil": 0.0,
      "facing": 1.0,
      "groundPound": false,
      "lastLandedY": START_Y,
      "shieldReady": state.skinIndex == 9,
      "healTimer": 10.0,
      "skillPower": 1.0,
      "reviveReady": state.skinIndex == 16,
    };
    _lastGapDamageY = START_Y;
    buildLevel();
    // Point currentPlatform at the actual floor-0 platform the ninja starts on
    // (id 0 is invalid), so the grounded branch sees the right surface.
    state.player["currentPlatform"] = state.platforms
        .firstWhere((p) => p["areaIndex"] == 0 && p["floor"] == 0 && p["lane"] == state.player["lane"], orElse: () => <String, dynamic>{})
        ["id"] ?? 0;
  }

  // Leaves the current platform downward. Landing ignores every row at or
  // above dropFromY; without this the ninja re-lands on the platform it just
  // left on the very next frame (previousY == platform.y).
  void _dropThrough(double vy, {bool safeFall = false}) {
    final player = state.player;
    player["grounded"] = false;
    player["vy"] = vy;
    player["dropFromY"] = (player["y"] as num).toDouble();
    player["safeFall"] = safeFall;
    player["anim"] = "fall";
    player["animTime"] = 0.0;
  }

  void setAnim(String name, double duration) {
    state.player["anim"] = name;
    state.player["animTime"] = 0.0;
    state.player["animUntil"] = duration;
  }

  double _lastGapDamageY = START_Y;

  // Environmental damage eases in: 60% in area 1, the full value from area 9 on.
  double get _hazardRamp => math.min(1.0, 0.6 + state.areaIndex * 0.05);

  void hurt(num amount, [num? lane, num? y]) {
    final player = state.player;
    final double a = amount.toDouble();
    final double ln = (lane ?? player["lane"] as num).toDouble();
    final double yy = (y ?? player["y"] as num).toDouble();
    if (player["invulnerable"] > 0 ||
        state.buffs["bamboo_shield"]! > 0 ||
        state.buffs["shadow_cloak"]! > 0 ||
        state.buffs["celestial_aegis"]! > 0 ||
        state.mode != "running") return;
    if (player["shieldReady"] == true) {
      player["shieldReady"] = false;
      player["invulnerable"] = 1.0;
      addEffect("hit_burst", ln, yy, 1.2);
      onEvent({"type": "shield"});
      return;
    }
    if (state.skinIndex == 4 && _rand.nextDouble() < 0.05) return;
    player["hp"] = math.max(0.0, player["hp"] - a);
    player["invulnerable"] = 1.25;
    state.combo = 0;
    state.shake = 0.75;
    state.flash = 0.35;
    setAnim("hit", 0.42);
    addEffect("hit_burst", ln, yy, 1.15);
    onEvent({"type": "hit", "amount": a, "lane": ln, "y": yy, "laneCount": state.laneCount});
    if (player["hp"] <= 0) die();
  }

  void die() {
    if (state.mode == "gameover") return;
    if (state.player["reviveReady"] == true) {
      state.player["reviveReady"] = false;
      state.player["hp"] = math.max(35.0, state.player["maxHp"] * 0.35);
      state.player["invulnerable"] = 2.5;
      addArsenalEffect("skill", 16, state.player["lane"], state.player["y"] - 40, 1.2, state.laneCount, 0.8);
      onEvent({"type": "revive"});
      return;
    }
    state.mode = "gameover";
    setAnim("death", 2);
    onEvent({"type": "gameover", "score": state.score.floor(), "coins": state.coins, "area": state.areaIndex + 1});
  }

  void defeatEnemy(Map<String, dynamic> enemy) {
    enemy["alive"] = false;
    state.lastKillTime = state.time;
    state.combo = math.max(1, state.combo + 1);
    state.comboTimer = 2.1;
    state.kills += 1;
    state.maxCombo = math.max(state.maxCombo, state.combo);
    // Aggressive play keeps a run alive between area-clear heals.
    state.player["hp"] = math.min(state.player["maxHp"] as num, (state.player["hp"] as num) + 2.0).toDouble();
    final multiplier = math.max(1, state.combo);
    state.score += (250 + enemy["areaIndex"] * 35) * multiplier;
    final coinReward = 8 + multiplier * 2 + (enemy["areaIndex"] / 2).floor();
    state.coins += coinReward;
    addEffect("hit_burst", enemy["lane"], enemy["y"] - 35, 1, enemy["laneCount"]);
    onEvent({"type": "enemyDown", "combo": state.combo, "coinReward": coinReward, "lane": enemy["lane"], "y": enemy["y"], "laneCount": enemy["laneCount"]});
  }

  void start() {
    if (state.mode != "idle") return;
    state.mode = "running";
    state.player["grounded"] = true;
    state.player["anim"] = "idle";
  }

  void move(int direction) {
    if (state.mode != "running") return;
    final player = state.player;
    final speedBonus = state.skinIndex == 0 ? 0.18 : 0.0;
    player["targetLane"] = ((player["targetLane"] as num) + direction).clamp(0, state.laneCount - 1).toDouble();
    player["facing"] = direction < 0 ? -1.0 : 1.0;
    // Sliding while grounded is a short hop: the ninja leaves the platform
    // immediately (negative vy = upward) and arcs back down. This matches the
    // JS original and guarantees the lane settles to an integer before the
    // landing check, so it never slips into the gap between two lanes and
    // falls through the whole run ("ilang / jatuh ke bawah"). Re-jumping only
    // happens while grounded, so swipe-spam can't keep it airborne forever.
    if (player["grounded"] == true) {
      player["grounded"] = false;
      player["dropFromY"] = double.negativeInfinity;
      player["vy"] = -250.0 - (state.skinIndex == 5 ? 35.0 : 0.0);
      player["groundTime"] = -speedBonus;
      setAnim("jump", 0.48);
      onEvent({"type": "jump"});
    } else {
      setAnim("jump", 0.34);
    }
  }

  void fastFall([bool forcePound = false]) {
    if (state.mode != "running") return;
    final platform = state.player["grounded"] == true ? _currentPlatform() : const <String, dynamic>{};
    // The boss arena holds until the boss is down.
    final locked = state.boss["active"] == true && state.boss["defeated"] != true && platform["arena"] == true && platform["areaIndex"] == state.boss["areaIndex"];
    if (locked) return;
    final now = state.time;
    final double = forcePound || now - _lastDownSwipe < 0.34;
    _lastDownSwipe = now;
    // Leaving a cleared arena drops 3 rows into the next area; that fall is part
    // of the level layout, not a missed jump.
    _dropThrough(double ? 780.0 : math.max(520.0, state.player["vy"] + 300.0), safeFall: platform["arena"] == true);
    state.player["groundPound"] = double;
    setAnim("fall", 0.5);
  }

  double _lastDownSwipe = -10;

  void slash() {
    final player = state.player;
    if (state.mode != "running" || player["slashCooldown"] > 0) return;
    player["slashCooldown"] = 2.0;
    setAnim("slash", 0.28);
    addEffect("slash_arc", player["lane"] + player["facing"] * 0.23, player["y"] - 42, 1.15);
    var hit = false;
    for (final enemy in nearEnemies) {
      if (enemy["alive"] != true) continue;
      if ((enemy["lane"] - player["lane"]).abs() < 0.78 && (enemy["y"] - player["y"]).abs() < 110) {
        enemy["hp"] -= 3;
        hit = true;
        if (enemy["hp"] <= 0) defeatEnemy(enemy);
      }
    }
    final boss = state.boss;
    if (boss["active"] == true && boss["defeated"] != true && (boss["dodging"] ?? 0) <= 0 && (boss["y"] - player["y"]).abs() < 190 && (boss["lane"] - player["lane"]).abs() < 1.1) {
      boss["hp"] -= 3;
      boss["anim"] = "hit";
      boss["animTime"] = 0.0;
      hit = true;
    }
    onEvent({"type": "slash", "hit": hit});
  }

  void shoot([bool charged = false]) {
    if (state.mode != "running") return;
    final player = state.player;
    setAnim("shoot", 0.3);
    var targetLane = player["lane"] + player["facing"] * 0.25;
    if (state.boss["active"] == true && state.boss["defeated"] != true) {
      targetLane = state.boss["lane"];
    } else {
      final target = nearEnemies
          .where((e) => e["alive"] == true && e["y"] > player["y"] - 20 && e["y"] < player["y"] + 420)
          .toList()
        ..sort((a, b) => (a["y"] as double).compareTo(b["y"] as double));
      if (target.isNotEmpty) targetLane = target.first["lane"];
    }
    final profiles = [
      {"speed": 570.0, "damage": 1.1, "pierce": 1, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 760.0, "damage": 1.2, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 520.0, "damage": 1.45, "pierce": 1, "burn": 2.2, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 510.0, "damage": 2.0, "pierce": 1, "blast": 0.75, "burn": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 610.0, "damage": 1.35, "pierce": 3, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 730.0, "damage": 1.1, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 3, "spread": 0.32},
      {"speed": 570.0, "damage": 1.05, "pierce": 1, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.35, "radius": 0.32, "count": 2, "spread": 0.22},
      {"speed": 630.0, "damage": 1.45, "pierce": 1, "burn": 0.0, "blast": 0.0, "chain": charged ? 4 : 2, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 590.0, "damage": 1.85, "pierce": 3, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 460.0, "damage": 1.25, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.48, "count": 1, "spread": 0.2},
      {"speed": 620.0, "damage": 1.25, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.45, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 560.0, "damage": 1.2, "pierce": 2, "burn": 3.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 510.0, "damage": 1.9, "pierce": 1, "blast": 0.85, "burn": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 660.0, "damage": 1.55, "pierce": 4, "blast": 0.0, "burn": 0.0, "chain": 1, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 570.0, "damage": 1.45, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.44, "count": 1, "spread": 0.2},
      {"speed": 680.0, "damage": 1.05, "pierce": 1, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 3, "spread": 0.28},
      {"speed": 650.0, "damage": 1.5, "pierce": 2, "burn": 1.4, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 600.0, "damage": 1.7, "pierce": 2, "blast": 0.0, "burn": 0.0, "chain": 2, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
      {"speed": 550.0, "damage": 1.35, "pierce": 2, "burn": 0.0, "blast": 0.0, "chain": 0, "heal": 0.0, "radius": 0.58, "count": 1, "spread": 0.2},
      {"speed": 710.0, "damage": 2.15, "pierce": 4, "blast": 0.0, "burn": 0.0, "chain": 2, "heal": 0.0, "radius": 0.32, "count": 1, "spread": 0.2},
    ];
    final profile = profiles[state.skinIndex];
    final count = (profile["count"] as int) + (state.buffs["storm_scroll"]! > 0 ? 2 : 0) + (state.buffs["clone_charm"]! > 0 ? 1 : 0);
    for (int i = 0; i < count; i += 1) {
      final spread = count == 1 ? 0.0 : (i - (count - 1) / 2) * (profile["spread"] as double);
      state.projectiles.add({
        "lane": player["lane"],
        "laneCount": state.laneCount,
        "laneVelocity": (targetLane - player["lane"]) * 2.2 + spread,
        "y": player["y"] - 55,
        "vy": (profile["speed"] as double) + (charged ? 90.0 : 0),
        "damage": (profile["damage"] as double) * (charged ? 3.2 : 1) * (state.buffs["dragon_orb"]! > 0 ? 1.75 : 1),
        "pierce": (profile["pierce"] as int) + (charged ? 2 : 0),
        "charged": charged,
        "skinIndex": state.skinIndex,
        "age": i * 0.04,
        "rotation": 0.0,
        "hitIds": <String>[],
        "burn": profile["burn"],
        "blast": profile["blast"],
        "chain": profile["chain"],
        "heal": profile["heal"],
        "radius": profile["radius"],
      });
    }
    onEvent({"type": "shoot", "charged": charged});
  }

  final List<int> _dashCooldowns = [8, 9, 10, 11, 9, 9, 12, 11, 13, 14, 10, 11, 12, 13, 11, 10, 16, 13, 12, 17];

  void dash() {
    final player = state.player;
    final cooldownMax = _dashCooldowns[state.skinIndex];
    if (state.mode != "running" || player["dashCooldown"] > 0) return;
    final visible = nearEnemies.where((e) => e["alive"] == true && e["y"] > state.cameraY - 60 && e["y"] < state.cameraY + 820).toList();
    final boss = state.boss["active"] == true && state.boss["defeated"] != true ? state.boss : null;
    final applyDamage = (Map<String, dynamic> e, double dmg) {
      e["hp"] -= dmg;
      if (e["hp"] <= 0) defeatEnemy(e);
    };
    switch (state.skinIndex) {
      case 0:
        final target = [...visible]..sort((a, b) => ((a["y"] as double) - (player["y"] as double)).abs().compareTo(((b["y"] as double) - (player["y"] as double)).abs()));
        if (target.isNotEmpty) {
          final t = target.first;
          player["lane"] = t["lane"];
          player["targetLane"] = t["lane"];
          player["y"] = t["y"] - 10;
          applyDamage(t, 4);
        } else {
          player["targetLane"] = player["targetLane"] >= state.laneCount - 1 ? 0.0 : player["targetLane"] + 1.0;
        }
        break;
      case 1:
        for (final e in visible) applyDamage(e, 4);
        if (boss != null) boss["hp"] -= 5;
        break;
      case 2:
        for (final e in visible) { e["burn"] = 4.0; e["burnDps"] = 2.2; e["hp"] -= 2; }
        if (boss != null) boss["hp"] -= 5;
        break;
      case 3:
        for (final e in visible.where((e) => e["y"] >= player["y"] - 30)) applyDamage(e, 6);
        if (boss != null) boss["hp"] -= 7;
        break;
      case 4:
        player["invulnerable"] = 2.4;
        for (final e in visible) applyDamage(e, 3);
        if (boss != null) boss["hp"] -= 4;
        break;
      case 5:
        for (final e in visible) { applyDamage(e, 4); e["lane"] = math.max(0.0, math.min((e["laneCount"] as int) - 1.0, e["lane"] + (e["dir"] > 0 ? 0.7 : -0.7))); }
        if (boss != null) boss["hp"] -= 5;
        break;
      case 6:
        player["hp"] = math.min(player["maxHp"], player["hp"] + 22.0);
        for (final e in visible) applyDamage(e, 2);
        break;
      case 7:
        for (final e in visible.take(7)) applyDamage(e, 5);
        if (boss != null) boss["hp"] -= 7;
        break;
      case 8:
        for (final e in visible) applyDamage(e, 6);
        if (boss != null) boss["hp"] -= 9;
        break;
      case 9:
        player["shieldReady"] = true;
        player["invulnerable"] = 2.2;
        player["hp"] = math.min(player["maxHp"], player["hp"] + 14.0);
        if (boss != null) boss["hp"] -= 3;
        break;
      case 10:
        for (final e in visible) { applyDamage(e, 3.5); player["hp"] = math.min(player["maxHp"], player["hp"] + 1.2); }
        if (boss != null) { boss["hp"] -= 5; player["hp"] = math.min(player["maxHp"], player["hp"] + 5.0); }
        break;
      case 11:
        for (final e in visible) { e["burn"] = 6.0; e["burnDps"] = 2.8; e["hp"] -= 2; }
        if (boss != null) boss["hp"] -= 6;
        break;
      case 12:
        for (final e in visible) applyDamage(e, 5.5);
        if (boss != null) boss["hp"] -= 7;
        break;
      case 13:
        player["invulnerable"] = 3.4;
        for (final e in visible) applyDamage(e, 4);
        if (boss != null) boss["hp"] -= 5;
        break;
      case 14:
        for (final e in visible) { e["lane"] += (player["lane"] - e["lane"]) * 0.8; applyDamage(e, 3.5); }
        if (boss != null) { boss["lane"] += (player["lane"] - boss["lane"]) * 0.5; boss["hp"] -= 5; }
        break;
      case 15:
        for (final e in visible) applyDamage(e, 4.5);
        if (boss != null) boss["hp"] -= 6;
        break;
      case 16:
        player["reviveReady"] = true;
        player["hp"] = math.min(player["maxHp"], player["hp"] + 12.0);
        for (final e in visible) applyDamage(e, 5);
        if (boss != null) boss["hp"] -= 7;
        break;
      case 17:
        for (final e in visible) { e["frozen"] = 3.0; applyDamage(e, 5); }
        if (boss != null) { boss["attackTimer"] += 2; boss["hp"] -= 7; }
        break;
      case 18:
        for (final e in visible) applyDamage(e, 6);
        if (boss != null) boss["hp"] -= 8;
        break;
      default:
        player["hp"] = math.min(player["maxHp"], player["hp"] + 25.0);
        player["invulnerable"] = 2.5;
        for (final e in visible) applyDamage(e, 8);
        if (boss != null) boss["hp"] -= 11;
    }
    player["dashCooldown"] = cooldownMax.toDouble();
    player["invulnerable"] = math.max(player["invulnerable"], 0.55);
    setAnim("dash", 0.24);
    addArsenalEffect("skill", state.skinIndex, player["lane"], player["y"] - 45, state.skinIndex == 3 ? 1.5 : 1.25, state.laneCount, 0.72);
    _sanitizeLane();
    onEvent({
      "type": "dash",
      "skill": SKINS[state.skinIndex].skill,
      "targets": [
        for (final enemy in visible) [enemy["lane"], enemy["y"], enemy["laneCount"]],
        if (boss != null) [boss["lane"], boss["y"], boss["laneCount"]],
      ],
    });
  }

  void cycleSkin() {
    state.skinIndex = (state.skinIndex + 1) % SKINS.length;
    final ratio = state.player["hp"] / state.player["maxHp"];
    state.player["maxHp"] = 100.0 + (state.skinIndex == 3 ? 20 : 0);
    state.player["hp"] = math.max(1.0, state.player["maxHp"] * ratio);
    if (state.skinIndex == 9) state.player["shieldReady"] = true;
    onEvent({"type": "skin", "skinIndex": state.skinIndex});
  }

  void setSkin(int index) {
    if (index < 0 || index >= SKINS.length) return;
    final ratio = state.player["hp"] / state.player["maxHp"];
    state.skinIndex = index;
    state.player["maxHp"] = 100.0 + ([3, 13].contains(index) ? 20 : 0);
    state.player["hp"] = math.max(1.0, state.player["maxHp"] * ratio);
    state.player["shieldReady"] = index == 9;
    state.player["reviveReady"] = index == 16;
    state.player["dashCooldown"] = 0.0;
    onEvent({"type": "skin", "skinIndex": index});
  }

  void updateArea() {
    int nextArea = state.areaIndex;
    for (final layout in state.layouts) {
      if (state.player["y"] >= layout["startY"] - 20) nextArea = layout["areaIndex"];
    }
    if (nextArea != state.areaIndex) {
      final oldCount = state.laneCount;
      state.areaIndex = nextArea;
      state.laneCount = AREAS[nextArea].lanes;
      final ratio = oldCount > 1 ? state.player["lane"] / (oldCount - 1) : 0.5;
      state.player["lane"] = ratio * (state.laneCount - 1);
      state.player["targetLane"] = (state.player["lane"] as num).round().toDouble();
      state.banner = "AREA ${nextArea + 1} · ${AREAS[nextArea].name.toUpperCase()}";
      state.bannerTime = 2.6;
      state.mechanicTimer = 5;
      state.mechanicWarned = false;
      onEvent({"type": "area", "areaIndex": nextArea});
    }
    final layout = state.layouts[state.areaIndex];
    state.areaFloor = math.max(0, math.min(AREAS[state.areaIndex].floors, ((state.player["y"] - layout["startY"]) / FLOOR_SPACING).floor() + 1));
  }

  void updatePlatforms() {
    for (final platform in nearPlatforms) {
      if (platform["type"] == "vanishing_spirit") platform["visible"] = math.sin(state.worldTime * math.pi + platform["phase"]) > -0.2;
      if (platform["type"] == "moving_chain") {
        final amplitude = platform["areaIndex"] == 11 ? 0.34 : 0.16;
        platform["laneOffset"] = math.sin(state.worldTime * 1.7 + platform["phase"]) * amplitude;
      }
      final breakAt = (platform["breakAt"] as num?) ?? 0;
      if (breakAt > 0 && state.time >= breakAt) {
        platform["alive"] = false;
        platform["breakAt"] = 0.0;
        addEffect("platform_break", platform["lane"], platform["y"] + 8, 1.1, platform["laneCount"]);
        if (state.player["currentPlatform"] == platform["id"] && state.player["grounded"] == true) {
          _dropThrough(platform["pounded"] == true ? 760.0 : 180.0);
        }
        onEvent({"type": "platformBreak"});
      }
    }
  }

  void land(Map<String, dynamic> platform) {
    final player = state.player;
    final landingSpeed = player["vy"];
    final wasPound = player["groundPound"] == true;
    player["y"] = platform["y"];
    player["vy"] = 0.0;
    player["grounded"] = true;
    player["groundTime"] = 0.0;
    player["currentPlatform"] = platform["id"];
    player["lastLandedY"] = platform["y"];
    player["groundPound"] = false;
    player["dropFromY"] = double.negativeInfinity;
    player["safeFall"] = false;
    player["anim"] = "idle";
    player["animTime"] = 0.0;
    final impact = math.min(1.4, 0.65 + landingSpeed.abs() / 800);
    addEffect("hit_burst", player["lane"], platform["y"] - 4, impact * 0.45, platform["laneCount"]);
    onEvent({"type": "land", "lane": player["lane"], "y": platform["y"], "laneCount": platform["laneCount"], "speed": landingSpeed, "pound": wasPound});
    if (platform["type"] == "spiked_wood") hurt(20 * _hazardRamp, player["lane"], player["y"]);
    if (platform["type"] == "trampoline_drums") {
      _dropThrough(630.0);
      setAnim("fall", 0.5);
    }
    if ((platform["type"] == "cracked_bamboo" || wasPound) && platform["arena"] != true) {
      platform["pounded"] = wasPound;
      platform["breakAt"] = state.time + 0.28;
    }
    if (platform["arena"] == true) {
      final boss = state.bosses[platform["areaIndex"]];
      if (boss["defeated"] != true) {
        state.boss = boss;
        boss["active"] = true;
        boss["anim"] = "idle";
        boss["animTime"] = 0.0;
        state.banner = boss["name"].toUpperCase();
        state.bannerTime = 2.0;
        onEvent({"type": "boss", "areaIndex": platform["areaIndex"]});
      }
    }
  }

  // Keep player["lane"] / targetLane inside the valid [0, laneCount-1] range.
  // A corrupted (huge / NaN) lane pushed the ninja millions of px off-screen
  // (the "character ilang" bug) and once corrupted it spread to enemies and
  // dash-teleports. This is the safety net; it also logs the first corruption
  // so we can still trace where the bad value originates.
  bool _laneFixLogged = false;
  void _sanitizeLane() {
    final maxLane = (state.laneCount - 1).toDouble();
    final lane = state.player["lane"];
    final target = state.player["targetLane"];
    final bad = (lane is! num || lane.isNaN || lane.isInfinite || lane < -1 || lane > state.laneCount + 1) ||
        (target is! num || target.isNaN || target.isInfinite || target < -1 || target > state.laneCount + 1);
    if (bad) {
      if (!_laneFixLogged) {
        _laneFixLogged = true;
        debugPrint("[DEBUG laneFix] FIRST corruption: lane=$lane target=$target area=${state.areaIndex} skin=${state.skinIndex}");
      }
      state.player["lane"] = maxLane / 2;
      state.player["targetLane"] = maxLane / 2;
    } else {
      state.player["lane"] = lane.toDouble().clamp(0.0, maxLane);
      state.player["targetLane"] = target.toDouble().clamp(0.0, maxLane);
    }
  }

  Map<String, dynamic> _currentPlatform() => nearPlatforms.firstWhere((p) => p["id"] == state.player["currentPlatform"], orElse: () => <String, dynamic>{});

  bool _supports(Map<String, dynamic> p) =>
      p["alive"] == true && p["visible"] == true && p["bossBase"] != true && (((p["lane"] as num) + ((p["laneOffset"] as num?) ?? 0)) - (state.player["lane"] as num)).abs() <= 0.5;

  // The ninja only descends when the player says so, so it must still fall when
  // the ground goes away: a spirit platform fading out, or wind, ice and
  // currents pushing it off the edge. Sliding onto a neighbour keeps it standing.
  void _checkFooting(Map<String, dynamic> platform) {
    if (platform.isNotEmpty && _supports(platform)) return;
    final y = state.player["y"];
    for (final p in nearPlatforms) {
      if (p["y"] == y && _supports(p)) {
        state.player["currentPlatform"] = p["id"];
        return;
      }
    }
    _dropThrough(60.0);
  }

  void updatePlayer(double dt) {
    final player = state.player;
    _sanitizeLane();
    player["animTime"] += dt;
    player["invulnerable"] = math.max(0.0, player["invulnerable"] - dt);
    player["dashCooldown"] = math.max(0.0, player["dashCooldown"] - dt);
    player["slashCooldown"] = math.max(0.0, player["slashCooldown"] - dt);
    player["slowTimer"] = math.max(0.0, player["slowTimer"] - dt);
    final laneSpeed = player["slowTimer"] > 0 ? 4.2 : state.areaIndex == 3 ? 6.2 : 10.0;
    player["lane"] += (player["targetLane"] - player["lane"]) * math.min(1.0, dt * laneSpeed);
    _sanitizeLane();
    if (player["animUntil"] > 0) {
      player["animUntil"] -= dt;
      if (player["animUntil"] <= 0 && player["grounded"] != true) player["anim"] = "fall";
      else if (player["animUntil"] <= 0) player["anim"] = "idle";
    }

    if (state.skinIndex == 6) {
      player["healTimer"] -= dt;
      if (player["healTimer"] <= 0) {
        player["healTimer"] = 10.0;
        player["hp"] = math.min(player["maxHp"], player["hp"] + 5.0);
      }
    }
    if (state.buffs["spirit_lantern"]! > 0) player["hp"] = math.min(player["maxHp"], player["hp"] + dt * 3.5);

    if (player["grounded"] == true) {
      player["groundTime"] += dt;
      final platform = _currentPlatform();
      if (platform["type"] == "ice_bridge") player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, player["targetLane"] + player["facing"] * dt * 0.7));
      if (platform["type"] == "fire_grate" && player["groundTime"] > 0.75) hurt(14 * _hazardRamp);
      _checkFooting(platform);
      return;
    }

    final previousY = player["y"];
    final areaGravity = config["gravity"]! * (state.areaIndex == 3 ? 0.78 : 1 + state.areaIndex * 0.018);
    player["vy"] = math.min(920.0, player["vy"] + areaGravity * dt);
    player["y"] += player["vy"] * dt;

    if (player["vy"] > 0) {
      final dropFromY = (player["dropFromY"] as num?)?.toDouble() ?? double.negativeInfinity;
      final candidates = nearPlatforms.where((p) => p["alive"] == true && p["visible"] == true && p["bossBase"] != true && previousY <= p["y"] && player["y"] >= p["y"] && p["y"] > dropFromY + 0.5).toList()
        ..sort((a, b) => (a["y"] as double).compareTo(b["y"] as double));
      if (candidates.isNotEmpty) {
        // Only look at the first row the ninja crosses this frame, then snap
        // to the NEAREST platform in that row. The old code required the lane
        // to be within 0.43 of a platform, so a fractional lane mid-slide (e.g.
        // 1.5) slipped past BOTH neighbouring platforms and the ninja fell
        // through the whole run ("ilang / jatuh ke bawah") on a left/right
        // swipe. Snapping to the closest platform keeps gaps deadly (a lane
        // with no platform nearby still drops you) but never lets a swipe
        // teleport you into the void.
        final topY = candidates.first["y"] as double;
        Map<String, dynamic>? best;
        double bestDist = double.infinity;
        for (final p in candidates) {
          if (((p["y"] as double) - topY).abs() > 1.0) break;
          final dist = ((p["lane"] + (p["laneOffset"] ?? 0)) - player["lane"]).abs();
          if (dist < bestDist) {
            bestDist = dist;
            best = p;
          }
        }
        if (best != null && bestDist <= 0.5) {
          land(best);
        } else {
          state.landMissCount += 1;
        }
      }
    }

    if (player["safeFall"] != true && player["y"] - player["lastLandedY"] > 260 && player["y"] - _lastGapDamageY > 185) {
      _lastGapDamageY = player["y"];
      hurt(14 + (state.areaIndex / 3).floor() * 2, player["lane"], player["y"]);
    }
  }

  void updatePickups(double dt) {
    for (final pickup in nearPickups) {
      if (pickup["active"] != true) continue;
      pickup["bob"] += dt * 3;
      final magnet = state.buffs["coin_magnet"]! > 0;
      if ((pickup["lane"] - state.player["lane"]).abs() < (magnet ? 2.6 : 0.36) &&
          (pickup["y"] - (state.player["y"] - 40)).abs() < (magnet ? 260 : 48)) {
        pickup["active"] = false;
        final coinReward = 10 + pickup["areaIndex"] * 2;
        state.coins += coinReward;
        state.score += 100 + pickup["areaIndex"] * 20;
        addEffect("coin_spark", pickup["lane"], pickup["y"], 0.8, pickup["laneCount"]);
        onEvent({"type": "coin", "combo": state.combo, "coinReward": coinReward, "lane": pickup["lane"], "y": pickup["y"], "laneCount": pickup["laneCount"]});
      }
    }
  }

  void activatePowerup(String type) {
    final definition = POWERUPS.firstWhere((p) => p.type == type);
    state.buffs[type] = math.max(state.buffs[type] ?? 0, definition.duration);
    if (type == "bamboo_shield") state.player["invulnerable"] = math.max(state.player["invulnerable"], 0.35);
    if (type == "phoenix_heart") {
      state.player["hp"] = math.min(state.player["maxHp"], state.player["hp"] + 55.0);
      state.player["reviveReady"] = true;
    }
    if (type == "healing_elixir") state.player["hp"] = math.min(state.player["maxHp"], state.player["hp"] + 60.0);
    if (type == "celestial_aegis") state.player["invulnerable"] = math.max(state.player["invulnerable"], 0.25);
    if (type == "moon_seal") {
      for (final e in nearEnemies) {
        if (e["alive"] == true && (e["y"] - state.player["y"]).abs() < 520) e["frozen"] = math.max(e["frozen"] ?? 0.0, 4.0);
      }
    }
    state.itemEffects.add({"effect": definition.effect, "lane": state.player["lane"], "laneCount": state.laneCount, "y": state.player["y"] - 42, "age": 0.0, "duration": type == "phoenix_heart" ? 1.2 : 0.8});
    state.banner = definition.name;
    state.bannerTime = 1.2;
    onEvent({"type": "powerup", "item": type, "name": definition.name});
  }

  void updatePowerups(double dt) {
    for (final pickup in nearPowerups) {
      if (pickup["active"] != true) continue;
      pickup["bob"] += dt * 2.7;
      if ((pickup["lane"] - state.player["lane"]).abs() < 0.42 && (pickup["y"] - (state.player["y"] - 38)).abs() < 55) {
        if (pickup["type"] == healItem) {
          // Left in place at full HP so it isn't wasted.
          final player = state.player;
          if ((player["hp"] as num) >= (player["maxHp"] as num)) continue;
          pickup["active"] = false;
          player["hp"] = math.min((player["maxHp"] as num).toDouble(), (player["hp"] as num) + healAmount);
          onEvent({"type": "heal", "amount": healAmount, "lane": pickup["lane"], "y": pickup["y"], "laneCount": pickup["laneCount"]});
          continue;
        }
        pickup["active"] = false;
        activatePowerup(pickup["type"]);
      }
    }
  }

  void updateBuffs(double dt) {
    for (final item in POWERUPS) state.buffs[item.type] = math.max(0.0, (state.buffs[item.type] ?? 0) - dt);
    for (final effect in state.itemEffects) effect["age"] += dt;
    state.itemEffects = state.itemEffects.where((e) => e["age"] < e["duration"]).toList();
  }

  void addMechanicShot(String art, double lane, [double damage = 18, double speed = -300]) {
    state.hostileProjectiles.add({
      "lane": lane,
      "laneCount": state.laneCount,
      "laneVelocity": 0.0,
      "y": state.player["y"] + 280,
      "vy": speed,
      "rotation": 0.0,
      "art": art,
      "damage": damage,
    });
  }

  double updateAreaMechanic(double dt) {
    final areaIndex = state.areaIndex;
    var worldScale = state.buffs["time_hourglass"]! > 0 ? 0.5 : 1.0;
    if (areaIndex == 17) worldScale *= 1.16;
    if (areaIndex == 18) worldScale *= math.sin(state.time * 0.8) > 0 ? 1.3 : 0.58;

    state.mechanicTimer -= dt;
    if (state.mechanicTimer < 0.75 && !state.mechanicWarned) {
      state.mechanicWarned = true;
      state.banner = AREAS[areaIndex].mechanic;
      state.bannerTime = 0.75;
    }
    if (state.mechanicTimer > 0) return worldScale;

    final player = state.player;
    final direction = _rand.nextDouble() > 0.5 ? 1.0 : -1.0;
    switch (areaIndex) {
      case 0:
        player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, player["targetLane"] + direction * 0.65));
        break;
      case 1:
        final p = nearPlatforms.firstWhere((p) => p["alive"] == true && p["areaIndex"] == areaIndex && p["y"] > player["y"] && p["y"] < player["y"] + 420, orElse: () => <String, dynamic>{});
        if (p.isNotEmpty) { p["type"] = "cracked_bamboo"; p["breakAt"] = state.time + 1.6; }
        break;
      case 2:
        addMechanicShot("crystal_laser", player["lane"].round().toDouble(), 18, -330);
        break;
      case 3:
        player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, player["targetLane"] + direction));
        break;
      case 4:
        if (player["grounded"] == true) hurt(9, player["lane"], player["y"]);
        break;
      case 5:
        if (state.time - state.lastKillTime > 7) { player["slowTimer"] = 1.5; hurt(6, player["lane"], player["y"]); }
        break;
      case 6:
        for (final e in nearEnemies) { if (e["alive"] == true && (e["y"] - player["y"]).abs() < 420) e["lane"] = math.max(0.0, math.min(e["laneCount"] - 1.0, e["lane"] + direction)); }
        break;
      case 7:
        player["slowTimer"] = math.max(player["slowTimer"], 1.8);
        break;
      case 8:
        player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, player["targetLane"] + direction * 1.2));
        break;
      case 9:
        addMechanicShot("void_column", player["lane"].round().toDouble(), 22, -270);
        break;
      case 10:
        addMechanicShot("lightning_gate", player["lane"].round().toDouble(), 21, -360);
        break;
      case 11:
        state.shake = math.max(state.shake, 0.35);
        break;
      case 12:
        player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, player["targetLane"] + direction * 1.4));
        break;
      case 13:
        for (final coin in nearPickups) { if (coin["active"] == true && (coin["y"] - player["y"]).abs() < 500) coin["lane"] = math.max(0.0, math.min(coin["laneCount"] - 1.0, coin["lane"] + direction * 0.6)); }
        break;
      case 14:
        final safe = (_rand.nextDouble() * state.laneCount).floor();
        for (int lane = 0; lane < state.laneCount; lane += 1) {
          if (lane != safe && lane % 2 == 0) addMechanicShot("cannon_volley", lane.toDouble(), 22, -320);
        }
        break;
      case 15:
        player["targetLane"] = state.laneCount - 1 - player["targetLane"];
        break;
      case 16:
        for (final e in nearEnemies) { if (e["alive"] == true && (e["y"] - player["y"]).abs() < 520) e["hp"] = math.min(e["maxHp"], e["hp"] + 1.5); }
        break;
      case 17:
        addMechanicShot("forge_beam", player["lane"].round().toDouble(), 25, -350);
        break;
      case 18:
        player["slowTimer"] = math.max(player["slowTimer"], 0.8);
        break;
      default:
        player["targetLane"] = _rand.nextDouble() > 0.5 ? state.laneCount - 1 - player["targetLane"] : (_rand.nextDouble() * state.laneCount).floor().toDouble();
    }

    final cadence = [6.0, 6.0, 6.5, 5.8, 6.0, 5.5, 6.0, 5.0, 5.2, 5.5, 4.8, 5.3, 5.0, 5.2, 5.5, 5.6, 5.2, 4.8, 4.5, 4.2];
    state.mechanicTimer = cadence[areaIndex];
    state.mechanicWarned = false;
    return worldScale;
  }

  void spawnEnemyShot(Map<String, dynamic> enemy) {
    state.hostileProjectiles.add({
      "lane": enemy["lane"],
      "laneCount": enemy["laneCount"],
      "laneVelocity": (state.player["lane"] - enemy["lane"]) * 0.16,
      "y": enemy["y"] - 52,
      "vy": -235 - enemy["areaIndex"] * 8,
      "rotation": 0.0,
      "art": AREAS[enemy["areaIndex"]].hazards[1],
      "damage": 12 + (enemy["areaIndex"] / 2).floor(),
    });
  }

  void updateEnemies(double dt) {
    for (final enemy in nearEnemies) {
      if (enemy["alive"] != true) continue;
      enemy["age"] += dt;
      enemy["attackTimer"] -= dt;
      if (enemy["frozen"] > 0) {
        enemy["frozen"] = (enemy["frozen"] ?? 0) - dt;
        continue;
      }
      if (enemy["burn"] > 0) {
        enemy["burn"] = (enemy["burn"] ?? 0) - dt;
        enemy["hp"] = (enemy["hp"] ?? 0) - ((enemy["burnDps"] ?? 1.5) as num).toDouble() * dt;
        if (enemy["hp"] <= 0) { defeatEnemy(enemy); continue; }
      }
      if (enemy["variant"] == 0) enemy["lane"] = enemy["baseLane"] + math.sin(enemy["age"] * (1.3 + enemy["areaIndex"] * 0.05)) * 0.12;
      else if (enemy["variant"] == 2) {
        enemy["lane"] += ((state.player["lane"] as num).toDouble() - (enemy["lane"] as num).toDouble()).sign * dt * (0.12 + (enemy["areaIndex"] as num).toDouble() * 0.012);
        enemy["y"] += math.sin(enemy["age"] * 3) * dt * 9;
      }
      if (enemy["variant"] == 1 && enemy["attackTimer"] <= 0 && enemy["y"] > state.cameraY - 40 && enemy["y"] < state.cameraY + 760) {
        enemy["attackTimer"] = math.max(1.15, 2.7 - enemy["areaIndex"] * 0.12);
        spawnEnemyShot(enemy);
      }
      if ((enemy["lane"] - state.player["lane"]).abs() < 0.32 && (enemy["y"] - state.player["y"]).abs() < 54) {
        hurt(14 + (enemy["areaIndex"] as num).toDouble(), enemy["lane"], enemy["y"] - 35);
      }
    }
  }

  void updateObstacles(double dt) {
    for (final obstacle in nearObstacles) {
      obstacle["hitCooldown"] = math.max(0.0, obstacle["hitCooldown"] - dt);
      final cycle = (state.worldTime + obstacle["phase"]) % obstacle["period"];
      obstacle["telegraph"] = cycle < obstacle["warning"];
      obstacle["active"] = cycle >= obstacle["warning"] && cycle < obstacle["warning"] + obstacle["activeWindow"];
      obstacle["laneOffset"] = ["pendulum_blade", "magma_chain", "razor_awning", "sky_hook"].contains(obstacle["type"])
          ? math.sin(state.worldTime * 4 + obstacle["phase"]) * 0.45
          : 0.0;
      if (state.buffs["moon_seal"]! > 0) {
        obstacle["active"] = false;
        obstacle["telegraph"] = false;
        continue;
      }
      if (obstacle["type"] == "poison_mist") obstacle["active"] = cycle > 0.35;

      final near = (obstacle["y"] - (state.player["y"] - 36)).abs() < 62;
      if (near && obstacle["active"] == true && ["snow_gust", "soul_tide", "flood_gate", "blizzard_wall", "ink_wave"].contains(obstacle["type"])) {
        state.player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, state.player["targetLane"] + obstacle["direction"] * dt * 1.4));
      }
      if (near && obstacle["active"] == true && ["current_vortex", "web_hook", "coral_tentacle", "grave_anchor", "blood_root"].contains(obstacle["type"])) {
        state.player["targetLane"] += (obstacle["lane"] - state.player["targetLane"]) * dt * 1.8;
      }
      if (!near || obstacle["active"] != true) continue;
      final laneHit = (obstacle["lane"] + (obstacle["laneOffset"] ?? 0) - state.player["lane"]).abs() < 0.36;
      if (!laneHit) continue;
      if (["sticky_web", "time_freeze_rune", "venom_web", "grave_scream", "brood_wave", "thunder_drum", "stasis_bubble"].contains(obstacle["type"])) {
        state.player["slowTimer"] = 1.4;
        if (obstacle["hitCooldown"] <= 0) { hurt(8, obstacle["lane"], obstacle["y"]); obstacle["hitCooldown"] = 1.2; }
      } else if (["rewind_gate", "clock_bomb", "time_slice"].contains(obstacle["type"]) && obstacle["hitCooldown"] <= 0) {
        state.player["vy"] = -260.0;
        obstacle["hitCooldown"] = 1.5;
      } else if (["reflection_gate", "mirror_clone"].contains(obstacle["type"]) && obstacle["hitCooldown"] <= 0) {
        state.player["targetLane"] = state.laneCount - 1 - state.player["targetLane"];
        obstacle["hitCooldown"] = 1.5;
      } else if (["reality_tear", "abyss_eye", "rainbow_rift"].contains(obstacle["type"]) && obstacle["hitCooldown"] <= 0) {
        state.player["targetLane"] = (_rand.nextDouble() * state.laneCount).floor().toDouble();
        hurt(24, obstacle["lane"], obstacle["y"]);
        obstacle["hitCooldown"] = 1.5;
      } else if (obstacle["hitCooldown"] <= 0) {
        hurt((16 + ((obstacle["areaIndex"] as num).toDouble() / 2).floor() * 2) * _hazardRamp, obstacle["lane"], obstacle["y"]);
        obstacle["hitCooldown"] = 1.3;
      }
    }
  }

  bool bossDodges(Map<String, dynamic> projectile, Map<String, dynamic> boss) {
    if (boss["dodgeCooldown"] > 0 || boss["dodging"] > 0 || projectile["dodgedBoss"] == true) return false;
    final chance = (0.18 + boss["areaIndex"] * 0.025) * (projectile["charged"] == true ? 0.35 : 1);
    if (_rand.nextDouble() >= chance) return false;
    final options = <double>[];
    for (int lane = 0; lane < boss["laneCount"]; lane += 1) {
      if ((lane - boss["lane"]).abs() > 0.6) options.add(lane.toDouble());
    }
    boss["lane"] = options.isNotEmpty ? options[(_rand.nextDouble() * options.length).floor()] : boss["lane"];
    boss["anim"] = "dodge";
    boss["animTime"] = 0.0;
    boss["dodging"] = 0.42;
    boss["dodgeCooldown"] = math.max(0.7, 1.65 - boss["areaIndex"] * 0.06);
    projectile["dodgedBoss"] = true;
    state.banner = "DODGE!";
    state.bannerTime = 0.45;
    onEvent({"type": "bossDodge"});
    return true;
  }

  void updateProjectiles(double dt, [double hostileDt = -1]) {
    final hDt = hostileDt < 0 ? dt : hostileDt;
    for (final projectile in state.projectiles) {
      projectile["y"] += projectile["vy"] * dt;
      projectile["lane"] += projectile["laneVelocity"] * dt;
      projectile["age"] += dt;
      projectile["rotation"] += dt * 15;
      for (final enemy in nearEnemies) {
        if (enemy["alive"] != true || projectile["pierce"] <= 0 || (projectile["hitIds"] as List).contains(enemy["id"])) continue;
        if ((projectile["lane"] - enemy["lane"]).abs() < projectile["radius"] && (projectile["y"] - (enemy["y"] - 38)).abs() < 42) {
          (projectile["hitIds"] as List).add(enemy["id"]);
          enemy["hp"] -= projectile["damage"];
          if (projectile["burn"] > 0) { enemy["burn"] = math.max(enemy["burn"] ?? 0.0, projectile["burn"]); enemy["burnDps"] = 1.8 + projectile["damage"] * 0.3; }
          projectile["pierce"] -= 1;
          addEffect("hit_burst", enemy["lane"], enemy["y"] - 35, 0.75, enemy["laneCount"]);
          onEvent({"type": "impact", "skinIndex": projectile["skinIndex"], "charged": projectile["charged"], "lane": enemy["lane"], "y": enemy["y"] - 38, "laneCount": enemy["laneCount"]});
          addArsenalEffect("impact", projectile["skinIndex"], enemy["lane"], enemy["y"] - 38, projectile["charged"] == true ? 1.05 : 0.7, enemy["laneCount"]);
          if (projectile["heal"] > 0) state.player["hp"] = math.min(state.player["maxHp"], state.player["hp"] + projectile["heal"]);
          if (projectile["blast"] > 0) {
            for (final nearby in nearEnemies) {
              if (nearby["alive"] != true || nearby["id"] == enemy["id"]) continue;
              if ((nearby["y"] - enemy["y"]).abs() < 130 && (nearby["lane"] - enemy["lane"]).abs() < 1.2) {
                nearby["hp"] -= projectile["damage"] * projectile["blast"];
                if (nearby["hp"] <= 0) defeatEnemy(nearby);
              }
            }
          }
          if (projectile["chain"] > 0) {
            final chained = nearEnemies.where((n) => n["alive"] == true && n["id"] != enemy["id"] && (n["y"] - enemy["y"]).abs() < 220).toList()
              ..sort((a, b) => ((a["lane"] - enemy["lane"]).abs()).compareTo((b["lane"] - enemy["lane"]).abs()));
            for (final nearby in chained.take(projectile["chain"] as int)) {
              nearby["hp"] -= projectile["damage"] * 0.62;
              addArsenalEffect("impact", 7, nearby["lane"], nearby["y"] - 38, 0.55, nearby["laneCount"]);
              if (nearby["hp"] <= 0) defeatEnemy(nearby);
            }
          }
          if (enemy["hp"] <= 0) defeatEnemy(enemy);
        }
      }
      final boss = state.boss;
      if (boss["active"] == true && boss["defeated"] != true && projectile["pierce"] > 0 &&
          (projectile["lane"] - boss["lane"]).abs() < 0.48 && (projectile["y"] - (boss["y"] - 62)).abs() < 70) {
        if (bossDodges(projectile, boss)) continue;
        if (boss["dodging"] > 0) continue;
        var damage = projectile["damage"];
        if (state.skinIndex == 8) damage *= 1.25;
        boss["hp"] -= damage;
        boss["anim"] = "hit";
        boss["animTime"] = 0.0;
        projectile["pierce"] = 0;
        addEffect("hit_burst", boss["lane"], boss["y"] - 70, 1.2, boss["laneCount"]);
        onEvent({"type": "impact", "skinIndex": projectile["skinIndex"], "charged": projectile["charged"], "lane": boss["lane"], "y": boss["y"] - 65, "laneCount": boss["laneCount"]});
        addArsenalEffect("impact", projectile["skinIndex"], boss["lane"], boss["y"] - 65, projectile["charged"] == true ? 1.3 : 0.9, boss["laneCount"]);
        onEvent({"type": "bossHit"});
      }
    }
    state.projectiles = state.projectiles.where((p) => p["pierce"] > 0 && p["y"] < state.cameraY + 940).toList();

    for (final projectile in state.hostileProjectiles) {
      projectile["y"] += projectile["vy"] * hDt;
      projectile["lane"] += projectile["laneVelocity"] * hDt;
      projectile["rotation"] += hDt * 5;
      if ((projectile["lane"] - state.player["lane"]).abs() < 0.34 && (projectile["y"] - (state.player["y"] - 42)).abs() < 42) {
        projectile["dead"] = true;
        hurt(projectile["damage"] ?? 18, projectile["lane"], projectile["y"]);
      }
    }
    state.hostileProjectiles = state.hostileProjectiles.where((p) => p["dead"] != true && p["y"] > state.cameraY - 120).toList();
  }

  void bossAttack(Map<String, dynamic> boss, int phase) {
    final areaIndex = boss["areaIndex"];
    if ([2, 5, 9].contains(areaIndex)) {
      final options = <double>[];
      for (int lane = 0; lane < boss["laneCount"]; lane += 1) {
        if ((lane - boss["lane"]).abs() > 0.6) options.add(lane.toDouble());
      }
      boss["lane"] = options.isNotEmpty ? options[(_rand.nextDouble() * options.length).floor()] : boss["lane"];
    }
    final extra = areaIndex >= 9 ? 2 : areaIndex >= 6 ? 1 : 0;
    final count = math.min(boss["laneCount"], phase + extra);
    for (int i = 0; i < count; i += 1) {
      final spread = count == 1 ? 0.0 : (i - (count - 1) / 2) * 0.55;
      state.hostileProjectiles.add({
        "lane": boss["lane"] + spread,
        "laneCount": boss["laneCount"],
        "laneVelocity": (state.player["lane"] - boss["lane"]) * (0.12 + areaIndex * 0.012),
        "y": boss["y"] - 78,
        "vy": -285 - phase * 28 - areaIndex * 5,
        "rotation": 0.0,
        "art": AREAS[areaIndex].hazards[(phase + i) % AREAS[areaIndex].hazards.length],
        "damage": 16 + areaIndex + phase * 2,
      });
    }
    if (areaIndex == 8) state.player["targetLane"] = math.max(0.0, math.min(state.laneCount - 1.0, state.player["targetLane"] + (_rand.nextDouble() > 0.5 ? 1 : -1) * 0.6));
    if (areaIndex >= 9 && phase >= 2) {
      final obstacle = <String, dynamic>{
        "id": "boss-h-${state.time}",
        "areaIndex": areaIndex,
        "laneCount": boss["laneCount"],
        "lane": state.player["lane"].round().toDouble(),
        "y": state.player["y"] - 35,
        "type": AREAS[areaIndex].hazards[(_rand.nextDouble() * AREAS[areaIndex].hazards.length).floor()],
        "phase": 0.0,
        "period": 1.8,
        "warning": 0.8,
        "activeWindow": 0.45,
        "active": false,
        "telegraph": true,
        "hitCooldown": 0.0,
        "direction": 1.0,
      };
      state.obstacles.add(obstacle);
      _obstaclesByArea[areaIndex].add(obstacle);
      if (areaIndex >= _nearArea - 1 && areaIndex <= _nearArea + 1) nearObstacles.add(obstacle);
    }
  }

  void updateBoss(double dt) {
    final boss = state.boss;
    if (boss["active"] != true) return;
    boss["animTime"] += dt;
    boss["dodging"] = math.max(0.0, boss["dodging"] - dt);
    boss["dodgeCooldown"] = math.max(0.0, boss["dodgeCooldown"] - dt);

    if (boss["defeated"] == true) {
      boss["clearTimer"] -= dt;
      if (boss["clearTimer"] <= 0) boss["active"] = false;
      return;
    }
    if (["hit", "dodge"].contains(boss["anim"]) && boss["animTime"] > 0.42) {
      boss["anim"] = "idle";
      boss["animTime"] = 0.0;
    }
    if (boss["hp"] <= 0) {
      boss["hp"] = 0;
      boss["defeated"] = true;
      boss["anim"] = "death";
      boss["animTime"] = 0.0;
      boss["clearTimer"] = 1.5;
      state.bossKills += 1;
      state.score += 5000 + boss["areaIndex"] * 1800;
      final bossCoins = 100 + boss["areaIndex"] * 25;
      state.coins += bossCoins;
      final stageReward = 180 + boss["areaIndex"] * 45;
      state.coins += stageReward;
      state.player["hp"] = math.min(state.player["maxHp"], state.player["hp"] + 16.0);
      state.player["anim"] = "victory";
      state.player["animTime"] = 0.0;
      state.effects.add({"type": "boss_warning", "lane": boss["lane"], "laneCount": boss["laneCount"], "y": boss["y"] - 80, "scale": 2.0, "age": 0.0, "duration": 1.2});
      if (boss["areaIndex"] == AREAS.length - 1) {
        state.mode = "victory";
        onEvent({"type": "victory", "score": state.score.floor(), "coins": state.coins, "coinReward": stageReward + bossCoins});
      } else {
        state.banner = "AREA ${boss["areaIndex"] + 1} CLEAR";
        state.bannerTime = 2.0;
        onEvent({"type": "areaClear", "areaIndex": boss["areaIndex"], "score": state.score.floor(), "coinReward": stageReward + bossCoins});
      }
      return;
    }
    boss["attackTimer"] -= dt;
    if (boss["attackTimer"] <= 0) {
      final ratio = boss["hp"] / boss["maxHp"];
      final phase = ratio < 0.3 ? 3 : ratio < 0.6 ? 2 : 1;
      boss["attackTimer"] = math.max(0.85, 2.35 - phase * 0.28 - boss["areaIndex"] * 0.055);
      boss["anim"] = "attack";
      boss["animTime"] = 0.0;
      bossAttack(boss, phase);
      addEffect("boss_warning", state.player["lane"], state.player["y"] - 25, 1.1);
      onEvent({"type": "bossAttack", "phase": phase});
    }
    if (boss["anim"] == "attack" && boss["animTime"] > 0.58) {
      boss["anim"] = "idle";
      boss["animTime"] = 0.0;
    }
  }

  void update(double dt) {
    state.time += dt;
    state.shake = math.max(0.0, state.shake - dt * 2.5);
    state.flash = math.max(0.0, state.flash - dt * 2.5);
    state.bannerTime = math.max(0.0, state.bannerTime - dt);
    for (final effect in state.effects) effect["age"] += dt;
    state.effects = state.effects.where((e) => e["age"] < e["duration"]).toList();
    for (final effect in state.arsenalEffects) effect["age"] += dt;
    state.arsenalEffects = state.arsenalEffects.where((e) => e["age"] < e["duration"]).toList();

    if (state.mode != "running") {
      state.player["animTime"] += dt;
      if (state.boss["animTime"] != null) state.boss["animTime"] += dt;
      return;
    }

    if (state.combo > 0) {
      state.comboTimer -= dt;
      if (state.comboTimer <= 0) state.combo = 0;
    }
    updateArea();
    _refreshNear();
    updateBuffs(dt);
    state.worldScale = updateAreaMechanic(dt);
    final worldDt = dt * state.worldScale;
    state.worldTime += worldDt;
    updatePlatforms();
    updatePlayer(dt);
    updatePickups(dt);
    updatePowerups(dt);
    updateEnemies(worldDt);
    updateObstacles(worldDt);
    updateProjectiles(dt, worldDt);
    updateBoss(worldDt);

    // --- diagnostics: warn if the ninja keeps falling without ever landing ---
    if (state.player["grounded"] != true && (state.player["vy"] as num) > 0) {
      state.fallFrames += 1;
      if (state.fallFrames == 90) {
        debugPrint("[DEBUG falling] >1.5s airborne & descending: "
            "lane=${state.player["lane"].toStringAsFixed(2)} "
            "y=${state.player["y"].toStringAsFixed(0)} "
            "vy=${state.player["vy"].toStringAsFixed(0)} "
            "cameraY=${state.cameraY.toStringAsFixed(0)} "
            "grounded=${state.player["grounded"]}");
      }
    } else {
      state.fallFrames = 0;
    }

    state.floor = math.max(state.floor, ((state.player["y"] - START_Y + FLOOR_SPACING * 0.45) / FLOOR_SPACING).floor());
    state.score = math.max(state.score, math.max(0.0, state.player["y"] - START_Y) * 5 + state.coins * 10);
    final cameraTarget = state.boss["active"] == true && state.boss["defeated"] != true ? state.boss["arenaY"] - 340 : math.max(0.0, state.player["y"] - 350);
    state.cameraY += (cameraTarget - state.cameraY) * math.min(1.0, dt * 5);
    // Keep the ninja on screen even during fast falls / leaps so it can
    // never shoot off the top or bottom of the view.
    final minCam = state.player["y"] - 820.0;
    final maxCam = state.player["y"] - 100.0;
    state.cameraY = state.cameraY.clamp(math.min(minCam, maxCam), math.max(minCam, maxCam));
  }

  void setViewport(double width) {
    state.viewWidth = width;
  }

  void startAtArea(int areaIndex) {
    final target = math.max(0, math.min(AREAS.length - 1, areaIndex));
    final skinIndex = state.skinIndex;
    reset(skinIndex: skinIndex);
    final layout = state.layouts[target];
    state.areaIndex = target;
    state.laneCount = AREAS[target].lanes;
    state.player["lane"] = (state.laneCount / 2).floor().toDouble();
    state.player["targetLane"] = state.player["lane"];
    state.player["y"] = layout["startY"];
    state.player["lastLandedY"] = layout["startY"];
    final platform = state.platforms.firstWhere((p) => p["areaIndex"] == target && p["floor"] == 0 && p["lane"] == state.player["lane"], orElse: () => <String, dynamic>{});
    state.player["currentPlatform"] = platform["id"] ?? 0;
    state.player["grounded"] = true;
    state.cameraY = math.max(0.0, layout["startY"] - 350);
    state.boss = state.bosses[target];
    _refreshNear();
    state.banner = "AREA TEST ${target + 1} · ${AREAS[target].name.toUpperCase()}";
    state.bannerTime = 2.5;
    state.mode = "running";
  }
}
