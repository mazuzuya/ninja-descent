// Port of game js/game/renderer.js — draws the simulation to a Flutter canvas.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'atlas.dart';
import 'data.dart';
import 'assets.dart';
import 'fx.dart';
import 'simulation.dart';

const double VIEW_HEIGHT = 920;

const Set<String> _tallObstacles = {"fire_wall", "water_jet", "ice_shard", "drowning_chain", "steam_burst", "moon_laser", "solar_jet", "reality_tear", "moon_spear", "cave_collapse", "ember_rain", "red_lantern_drop", "void_column", "sky_hook", "glass_rain", "molten_anvil", "rainbow_rift"};

class Renderer {
  final GameAssets assets;
  final Simulation simulation;
  double effectsIntensity;

  final Fx fx;

  Renderer({required this.assets, required this.simulation, required this.fx, this.effectsIntensity = 1.0});

  double get viewWidth => _viewWidth;

  late final Atlas _platforms = assets.platforms;
  late final Atlas _objects = assets.objects;
  late final Atlas _effects = assets.effects;
  late final List<Atlas> _areaEnemies = assets.areas.map((a) => a.enemies).toList();
  late final List<Atlas> _areaBosses = assets.areas.map((a) => a.boss).toList();
  late final List<SkinAssets> _skins = assets.skins;

  double _viewWidth = 390;
  final ui.Paint _bgPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final ui.Paint _whiteFlash = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..colorFilter = const ui.ColorFilter.mode(ui.Color(0xe6ffffff), ui.BlendMode.srcIn);
  final ui.Paint _ghostPaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..blendMode = ui.BlendMode.plus;
  ui.Rect _lastDst = ui.Rect.zero;
  ui.Rect _lastCrop = ui.Rect.zero;
  // Background cross-fade between areas.
  int _bgArea = 0;
  int _bgFromArea = -1;
  double _bgFade = 1;
  double _lastTime = 0;
  final math.Random _shakeRand = math.Random();

  // Paint alpha modulates image opacity; low filtering matches the browser's
  // default canvas image smoothing.
  ui.Paint get _plain => ui.Paint()..filterQuality = ui.FilterQuality.medium;
  ui.Paint _alpha(double a) => _plain..color = ui.Color.fromRGBO(255, 255, 255, a);
  // "lighter" composite in the JS canvas.
  ui.Paint _additiveAlpha(double a) => _alpha(a)..blendMode = ui.BlendMode.plus;

  // Images are decoded lazily (see GameAssets); a sheet that is still decoding
  // is simply skipped for a frame or two.
  void drawFrameInBox(ui.Canvas canvas, ui.Image? image, Frame? frame, num x, num y, num width, num height, [ui.Paint? paint]) {
    if (frame == null || image == null) return;
    final crop = frame.content;
    final scale = math.min(width.toDouble() / crop.width, height.toDouble() / crop.height);
    final dw = crop.width * scale;
    final dh = crop.height * scale;
    canvas.drawImageRect(image, crop, ui.Rect.fromLTWH(x.toDouble() - dw / 2, y.toDouble() - dh / 2, dw, dh), paint ?? _plain);
  }

  void drawAnchored(ui.Canvas canvas, ui.Image? image, Animation? animation, int index, num x, double feetY, num desiredHeight, [bool flip = false, double alpha = 1, double flash = 0]) {
    if (animation == null || animation.frames.isEmpty || image == null) return;
    final frames = animation.frames;
    final frame = frames[index % frames.length];
    final crop = frame.content;
    final scale = desiredHeight.toDouble() / animation.maxHeight;
    final dx = x.toDouble();
    canvas.save();
    if (flip) {
      canvas.translate(dx * 2, 0);
      canvas.scale(-1, 1);
    }
    final drawX = dx - (frame.anchor.dx - crop.left) * scale;
    final drawY = feetY - (frame.anchor.dy - crop.top) * scale;
    final dst = ui.Rect.fromLTWH(drawX, drawY, crop.width * scale, crop.height * scale);
    canvas.drawImageRect(image, crop, dst, alpha < 1 ? _alpha(alpha) : _plain);
    // Damage flash: repaint the silhouette white on top.
    if (flash > 0) canvas.drawImageRect(image, crop, dst, _whiteFlash);
    _lastDst = dst;
    _lastCrop = crop;
    canvas.restore();
  }

  int frameIndex(double time, double speed, int count, [bool once = false]) {
    final index = (time * speed).floor();
    return once ? math.min(count - 1, index) : index % count;
  }

  double laneX(num lane, [int laneCount = 3]) => simulation.laneX(lane.toDouble(), _viewWidth, laneCount);

  void _drawBackgroundImage(ui.Canvas canvas, GameState state, ui.Image image, ui.Paint paint) {
    final tileHeight = math.max(VIEW_HEIGHT, _viewWidth * (image.height / image.width));
    final scroll = state.cameraY * 0.13;
    final offset = -(scroll % tileHeight);
    final firstTile = (scroll / tileHeight).floor() - 1;
    final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    int tile = firstTile;
    for (double y = offset - tileHeight; y < VIEW_HEIGHT + tileHeight; y += tileHeight) {
      // Every other tile is mirrored so its edge meets the same pixels as its
      // neighbour: the art doesn't tile, and repeating it shows a hard seam.
      if (tile.isOdd) {
        canvas.save();
        canvas.translate(0, y * 2 + tileHeight);
        canvas.scale(1, -1);
        canvas.drawImageRect(image, src, ui.Rect.fromLTWH(0, y, _viewWidth, tileHeight), paint);
        canvas.restore();
      } else {
        canvas.drawImageRect(image, src, ui.Rect.fromLTWH(0, y, _viewWidth, tileHeight), paint);
      }
      tile += 1;
    }
  }

  void drawBackground(ui.Canvas canvas, GameState state) {
    if (_bgArea != state.areaIndex) {
      _bgFromArea = _bgArea;
      _bgArea = state.areaIndex;
      _bgFade = 0;
    }
    _bgFade = math.min(1, _bgFade + (state.time - _lastTime).abs() / 1.1);
    _lastTime = state.time;
    if (_bgFade >= 1) _bgFromArea = -1;
    final image = assets.areas[state.areaIndex].background.image;
    final from = _bgFromArea >= 0 ? assets.areas[_bgFromArea].background.image : null;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, _viewWidth, VIEW_HEIGHT), ui.Paint()..color = const ui.Color(0xff050914));
    if (from != null) _drawBackgroundImage(canvas, state, from, _bgPaint);
    if (image != null) {
      _drawBackgroundImage(canvas, state, image, _bgFade >= 1 ? _bgPaint : _alpha(_bgFade));
    }
    final shade = ui.Gradient.linear(const ui.Offset(0, 0), const ui.Offset(0, VIEW_HEIGHT), const [ui.Color(0x14040916), ui.Color(0x2e030713), ui.Color(0x8c02040c)], [0.0, 0.55, 1.0]);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, _viewWidth, VIEW_HEIGHT), ui.Paint()..shader = shade);

    final star = ui.Paint()..color = const ui.Color(0x098bcdff);
    for (int i = 0; i < 7; i += 1) {
      final y = (((i * 147 - state.cameraY * 0.28) % 900 + 900) % 900) - 50;
      canvas.drawRect(ui.Rect.fromLTWH(0, y, _viewWidth, 2.0), star);
    }
  }

  void drawPlatforms(ui.Canvas canvas, GameState state) {
    for (final platform in simulation.nearPlatforms) {
      if (platform["alive"] != true || platform["visible"] != true) continue;
      final y = (platform["y"] as num).toDouble() - state.cameraY;
      if (y < -90 || y > VIEW_HEIGHT + 100) continue;
      final x = laneX(platform["lane"] + (platform["laneOffset"] ?? 0), platform["laneCount"]);
      final baseWidth = simulation.platformWidth(platform["laneCount"], _viewWidth);
      final width = platform["arena"] == true
          ? baseWidth + 8
          : platform["bossBase"] == true
              ? baseWidth * 1.5
              : baseWidth;
      final alpha = platform["type"] == "vanishing_spirit" ? 0.72 : 1.0;
      drawFrameInBox(canvas, _platforms.image, _platforms[platform["type"]], x, y + 13, width, 72, alpha < 1 ? _alpha(alpha) : null);
      if (((platform["breakAt"] as num?) ?? 0) > 0) {
        final pulse = 0.5 + math.sin(state.time * 35) * 0.35;
        canvas.drawRect(ui.Rect.fromLTWH(x - width * 0.35, y - 3, width * 0.7, 3), ui.Paint()..color = ui.Color.fromRGBO(255, 98, 62, pulse));
      }
    }
  }

  void drawPickups(ui.Canvas canvas, GameState state) {
    for (final pickup in simulation.nearPickups) {
      if (pickup["active"] != true) continue;
      final y = (pickup["y"] as num).toDouble() - state.cameraY + math.sin(pickup["bob"] as double) * 5;
      if (y < -60 || y > VIEW_HEIGHT + 60) continue;
      final frame = _objects[pickup["type"]];
      final image = _objects.image;
      if (frame == null || image == null) continue;
      // Coins spin on their vertical axis.
      final scale = math.min(30 / frame.content.width, 36 / frame.content.height);
      final w = frame.content.width * scale * (0.3 + 0.7 * math.cos(pickup["bob"] as double).abs());
      final h = frame.content.height * scale;
      canvas.drawImageRect(image, frame.content, ui.Rect.fromCenter(center: ui.Offset(laneX(pickup["lane"], pickup["laneCount"]), y), width: w, height: h), _plain);
    }
  }

  void drawPowerups(ui.Canvas canvas, GameState state) {
    for (final pickup in simulation.nearPowerups) {
      if (pickup["active"] != true) continue;
      final y = (pickup["y"] as num).toDouble() - state.cameraY + math.sin(pickup["bob"] as double) * 7;
      if (y < -70 || y > VIEW_HEIGHT + 70) continue;
      final x = laneX(pickup["lane"], pickup["laneCount"]);
      final pulse = 1 + 0.16 * math.sin(state.time * 5 + (pickup["bob"] as double));
      final radius = 40 * pulse;
      final heal = pickup["type"] == healItem;
      final halo = ui.Gradient.radial(ui.Offset(x, y), radius, heal ? const [ui.Color(0x8c7dffa0), ui.Color(0x0032d070)] : const [ui.Color(0x8cffef9c), ui.Color(0x00ffbe46)]);
      canvas.drawCircle(ui.Offset(x, y), radius, ui.Paint()..shader = halo..blendMode = ui.BlendMode.plus);
      final art = heal ? "healing_elixir" : pickup["type"] as String;
      final frame = assets.powerups[art] ?? assets.powerupsB[art];
      final image = assets.powerups.frames.containsKey(art) ? assets.powerups.image : assets.powerupsB.image;
      drawFrameInBox(canvas, image, frame, x, y, heal ? 30 : 36, heal ? 36 : 42);
    }
  }

  ui.Image? powerEffectImage(String name) {
    if (assets.powerupEffectsA.animations.containsKey(name)) return assets.powerupEffectsA.image;
    if (assets.powerupEffectsB.animations.containsKey(name)) return assets.powerupEffectsB.image;
    return assets.powerupEffectsC.image;
  }

  List<Frame>? powerEffectFrames(String name) =>
      assets.powerupEffectsA.anim(name)?.frames ?? assets.powerupEffectsB.anim(name)?.frames ?? assets.powerupEffectsC.anim(name)?.frames;

  // Active buffs sit behind the ninja, softer than the JS's on-top glow, which
  // hid the character for the whole duration of a buff.
  void drawBuffAuras(ui.Canvas canvas, GameState state) {
    final playerX = laneX(state.player["lane"], state.laneCount);
    final playerY = (state.player["y"] as num).toDouble() - state.cameraY - 42;
    final active = POWERUPS.where((p) => state.buffs[p.type]! > 0).toList()
      ..sort((a, b) => state.buffs[b.type]!.compareTo(state.buffs[a.type]!));
    for (final item in active.take(2)) {
      final frames = powerEffectFrames(item.effect);
      if (frames == null) continue;
      final index = frameIndex(state.time, 6, frames.length);
      final additive = !["shadow_phase", "shield_aura"].contains(item.effect);
      final paint = additive ? _additiveAlpha(0.5) : _alpha(0.6);
      drawFrameInBox(canvas, powerEffectImage(item.effect), frames[index], playerX, playerY, 124, 124, paint);
    }
  }

  void drawPowerupEffects(ui.Canvas canvas, GameState state) {
    for (final effect in state.itemEffects) {
      final frames = powerEffectFrames(effect["effect"]);
      if (frames == null) continue;
      final progress = effect["age"] / effect["duration"];
      final index = math.min(frames.length - 1, (progress * frames.length).floor());
      final additive = effect["effect"] == "shadow_phase" ? false : true;
      final alpha1 = (1 - progress * 0.25).clamp(0.0, 1.0).toDouble();
      final paint = additive ? _additiveAlpha(alpha1) : _alpha(alpha1);
      drawFrameInBox(canvas, powerEffectImage(effect["effect"]), frames[index], laneX(effect["lane"], effect["laneCount"]), (effect["y"] as num).toDouble() - state.cameraY, 170, 170, paint);
    }
  }

  Frame? obstacleFrame(String type) => assets.obstacleAtlas(type)?[type];

  ui.Image? obstacleImage(String type) => assets.obstacleAtlas(type)?.image;

  void drawObstacles(ui.Canvas canvas, GameState state) {
    for (final obstacle in simulation.nearObstacles) {
      final y = (obstacle["y"] as num).toDouble() - state.cameraY;
      if (y < -110 || y > VIEW_HEIGHT + 110) continue;
      final x = laneX(obstacle["lane"] + (obstacle["laneOffset"] ?? 0), obstacle["laneCount"]);
      final pulse = 0.55 + math.sin(state.time * 12 + obstacle["phase"]) * 0.25;
      final ptAlpha = obstacle["active"] == true ? 1.0 : obstacle["telegraph"] == true ? pulse : 0.22;
      final imgPaint = ptAlpha < 1 ? _alpha(ptAlpha) : _plain;
      if (obstacle["telegraph"] == true && obstacle["active"] != true) {
        canvas.drawCircle(ui.Offset(x, y), 31, ui.Paint()..color = ui.Color.fromRGBO(255, 197, 71, pulse)..style = ui.PaintingStyle.stroke..strokeWidth = 3);
      }
      final tall = _tallObstacles.contains(obstacle["type"]);
      final narrow = obstacle["laneCount"] >= 8 ? 0.64 : obstacle["laneCount"] >= 7 ? 0.72 : obstacle["laneCount"] == 6 ? 0.82 : 1.0;
      drawFrameInBox(canvas, obstacleImage(obstacle["type"]), obstacleFrame(obstacle["type"]), x, y, (tall ? 58 : 74) * narrow, (tall ? 122 : 84) * narrow, imgPaint);
    }
  }

  void drawEnemies(ui.Canvas canvas, GameState state) {
    for (final enemy in simulation.nearEnemies) {
      if (enemy["alive"] != true) continue;
      final y = (enemy["y"] as num).toDouble() - state.cameraY;
      if (y < -120 || y > VIEW_HEIGHT + 120) continue;
      final animation = _areaEnemies[enemy["areaIndex"]].anim(enemy["type"]);
      if (animation == null) continue;
      final bob = enemy["variant"] == 2 ? math.sin(enemy["age"] * 4) * 7 : 0;
      final index = frameIndex(enemy["age"], 5.5 + enemy["areaIndex"] * 0.16, animation.frames.length);
      final actorScale = enemy["laneCount"] >= 8 ? 0.6 : enemy["laneCount"] >= 7 ? 0.68 : enemy["laneCount"] == 6 ? 0.78 : 1.0;
      final height = (enemy["variant"] == 2 ? 84 : 92) * actorScale;
      drawAnchored(canvas, assets.areas[enemy["areaIndex"]].enemies.image, animation, index, laneX(enemy["lane"], enemy["laneCount"]), y + bob, height, enemy["dir"] > 0, 1, ((enemy["_flash"] as double?) ?? 0));
      if (enemy["hp"] > 1) {
        canvas.drawRect(ui.Rect.fromLTWH(laneX(enemy["lane"], enemy["laneCount"]) - 23, y - 98, 46.0, 5.0), ui.Paint()..color = const ui.Color(0xc7070a14));
        canvas.drawRect(ui.Rect.fromLTWH(laneX(enemy["lane"], enemy["laneCount"]) - 22, y - 97, 44.0 * math.min(1.0, (enemy["hp"] as num).toDouble() / (enemy["maxHp"] as num).toDouble()), 3.0), ui.Paint()..color = const ui.Color(0xffe64d52));
      }
    }
  }

  void drawBoss(ui.Canvas canvas, GameState state) {
    final boss = state.boss;
    if (boss["active"] != true) return;
    if (boss["defeated"] == true && boss["animTime"] > 1.6) return;
    final animationName = boss["defeated"] == true ? "death" : boss["anim"];
    final bossAnimations = _areaBosses[boss["areaIndex"]];
    final animation = bossAnimations.anim(animationName) ?? bossAnimations.anim("idle");
    if (animation == null) return;
    final index = frameIndex(boss["animTime"], animationName == "attack" ? 7 : 5, animation.frames.length, boss["defeated"] == true);
    final height = boss["laneCount"] >= 8 ? 122.0 : boss["laneCount"] >= 7 ? 132.0 : boss["laneCount"] == 6 ? 138.0 : boss["areaIndex"] == 6 ? 150.0 : boss["areaIndex"] == 8 ? 158.0 : 142.0;
    final bossX = laneX(boss["lane"], boss["laneCount"]);
    final bossY = (boss["y"] as num).toDouble() - state.cameraY;
    if (boss["defeated"] != true) {
      final auraRadius = height * (0.82 + 0.06 * math.sin(state.time * 4));
      final center = ui.Offset(bossX, bossY - height * 0.5);
      canvas.drawCircle(center, auraRadius, ui.Paint()..shader = ui.Gradient.radial(center, auraRadius, const [ui.Color(0x66c8232c), ui.Color(0x00c8232c)]));
    }
    drawAnchored(canvas, assets.areas[boss["areaIndex"]].boss.image, animation, index, bossX, bossY, height, false, boss["dodging"] > 0 ? 0.72 : 1.0, ((boss["_flash"] as double?) ?? 0));
  }

  // Energy streak and glow behind a shot, in its owner's colours.
  void _drawShotTrail(ui.Canvas canvas, Map<String, dynamic> shot, double x, double y) {
    final charged = shot["charged"] == true;
    final skin = shot["skinIndex"] as int;
    final primary = paletteColor(skin);
    final secondary = paletteColor(skin, secondary: true);
    final laneCount = shot["laneCount"] as int;
    final spacing = laneX(1, laneCount) - laneX(0, laneCount);
    final vx = (shot["laneVelocity"] as num).toDouble() * spacing;
    final vy = (shot["vy"] as num).toDouble();
    final speed = math.max(1.0, math.sqrt(vx * vx + vy * vy));
    final length = charged ? 120.0 : 62.0;
    final head = ui.Offset(x, y);
    final tail = head - ui.Offset(vx, vy) / speed * length;
    final core = charged ? 13.0 : 6.5;
    canvas.drawLine(head, tail, ui.Paint()
      ..blendMode = ui.BlendMode.plus
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = core * 2.2
      ..shader = ui.Gradient.linear(head, tail, [secondary.withValues(alpha: 0.55), secondary.withValues(alpha: 0)]));
    canvas.drawLine(head, tail, ui.Paint()
      ..blendMode = ui.BlendMode.plus
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = core
      ..shader = ui.Gradient.linear(head, tail, [primary, primary.withValues(alpha: 0)]));
    final radius = charged ? 58.0 : 30.0;
    canvas.drawCircle(head, radius, ui.Paint()
      ..blendMode = ui.BlendMode.plus
      ..shader = ui.Gradient.radial(head, radius, [primary.withValues(alpha: 0.65), primary.withValues(alpha: 0)]));
  }

  void drawProjectiles(ui.Canvas canvas, GameState state) {
    for (final projectile in state.projectiles) {
      final x = laneX(projectile["lane"], projectile["laneCount"]);
      final y = (projectile["y"] as num).toDouble() - state.cameraY;
      final arsenal = _skins[projectile["skinIndex"]].arsenal.anim("projectile")?.frames;
      if (arsenal == null) continue;
      _drawShotTrail(canvas, projectile, x, y);
      final index = frameIndex(projectile["age"], projectile["charged"] == true ? 14 : 10, arsenal.length);
      final size = (projectile["charged"] == true ? 54.0 : projectile["skinIndex"] == 9 ? 46.0 : 34.0) * (projectile["laneCount"] >= 7 ? 0.8 : 1.0);
      drawFrameInBox(canvas, _skins[projectile["skinIndex"]].arsenal.image, arsenal[index], x, y, size, size);
    }
    for (final projectile in state.hostileProjectiles) {
      final x = laneX(projectile["lane"], projectile["laneCount"]);
      final y = (projectile["y"] as num).toDouble() - state.cameraY;
      final halo = ui.Gradient.radial(ui.Offset(x, y), 28, const [ui.Color(0x70ffae37), ui.Color(0x00ff5a1e)]);
      canvas.drawRect(ui.Rect.fromLTWH(x - 30, y - 30, 60.0, 60.0), ui.Paint()..shader = halo);
      final frame = obstacleFrame(projectile["art"]);
      if (frame != null) {
        drawFrameInBox(canvas, obstacleImage(projectile["art"]), frame, x, y, 35, 42);
      } else {
        drawFrameInBox(canvas, _objects.image, _objects["fire_orb"], x, y, 34, 34);
      }
    }
  }

  void drawArsenalEffects(ui.Canvas canvas, GameState state) {
    for (final effect in state.arsenalEffects) {
      final frames = _skins[effect["skinIndex"]].arsenal.anim(effect["kind"])?.frames;
      if (frames == null) continue;
      final progress = effect["age"] / effect["duration"];
      final index = math.min(frames.length - 1, (progress * frames.length).floor());
      final size = (effect["kind"] == "skill" ? 205.0 : 92.0) * (effect["scale"] as num).toDouble() * (effect["laneCount"] >= 7 ? 0.82 : 1.0);
      final additive = !(effect["skinIndex"] == 0 || effect["skinIndex"] == 4 || effect["skinIndex"] == 8);
      final alpha2 = (1 - progress * 0.2).clamp(0.0, 1.0).toDouble();
      final paint = additive ? _additiveAlpha(alpha2) : _alpha(alpha2);
      drawFrameInBox(canvas, _skins[effect["skinIndex"]].arsenal.image, frames[index], laneX(effect["lane"], effect["laneCount"]), (effect["y"] as num).toDouble() - state.cameraY, size, size, paint);
    }
  }

  void drawEffects(ui.Canvas canvas, GameState state) {
    for (final effect in state.effects) {
      final frames = _effects.anim(effect["type"])?.frames;
      if (frames == null) continue;
      final progress = effect["age"] / effect["duration"];
      final index = math.min(frames.length - 1, (progress * frames.length).floor());
      final x = laneX(effect["lane"], effect["laneCount"]);
      final y = (effect["y"] as num).toDouble() - state.cameraY;
      final additive = effect["type"] != "shadow_smoke";
      final alpha3 = (1 - progress * 0.45).clamp(0.0, 1.0).toDouble();
      final paint = additive ? _additiveAlpha(alpha3) : _alpha(alpha3);
      drawFrameInBox(canvas, _effects.image, frames[index], x, y, 110.0 * (effect["scale"] as num).toDouble() * effectsIntensity, 110.0 * (effect["scale"] as num).toDouble() * effectsIntensity, paint);
    }
  }

  void drawPlayer(ui.Canvas canvas, GameState state) {
    final player = state.player;
    final selected = _skins[state.skinIndex];
    final statusNames = {"dash", "hit", "death", "victory"};
    String name = player["anim"];
    if (state.mode == "idle") name = "idle";
    if (state.mode == "victory") name = "victory";
    if (state.mode == "gameover") name = "death";
    final useStatus = statusNames.contains(name);
    // Pick the atlas that actually owns the frames so the image and the
    // frames always come from the same sheet (otherwise the sprite renders
    // from the wrong region and vanishes — e.g. the "hit" anim when sliding
    // into an enemy).
    Atlas atlas = useStatus ? selected.status : selected.motion;
    Animation? animation = atlas.anim(name);
    if (animation == null) {
      atlas = selected.motion;
      animation = atlas.anim("idle");
    }
    final frames = animation?.frames;
    final once = !["idle", "walk", "fall"].contains(name);
    final speeds = {"idle": 3.3, "walk": 7.0, "jump": 8.0, "fall": 5.0, "shoot": 12.5, "slash": 15.0, "dash": 18.0, "hit": 10.0, "death": 3.3, "victory": 2.2};
    final index = frames == null ? 0 : frameIndex(player["animTime"], speeds[name] ?? 6.0, frames.length, once);
    final alpha = state.buffs["shadow_cloak"]! > 0
        ? 0.48
        : player["invulnerable"] > 0 && (player["invulnerable"] * 14).floor() % 2 == 1
            ? 0.55
            : 1.0;
    final feetY = (player["y"] as num).toDouble() - state.cameraY;
    final playerHeight = state.laneCount >= 8 ? 58.0 : state.laneCount >= 7 ? 66.0 : state.laneCount == 6 ? 76.0 : 94.0;
    final px = laneX(player["lane"], state.laneCount);

    // Ground contact shadow.
    if (player["grounded"] == true) {
      canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(px, feetY + 2), width: playerHeight * 0.62, height: 9), ui.Paint()..color = const ui.Color(0x73000000));
    }
    // Afterimages trail behind fast drops and dashes.
    for (final ghost in fx.ghosts) {
      final t = 1 - ghost.age / 0.26;
      _ghostPaint.colorFilter = ui.ColorFilter.mode(ui.Color.fromRGBO(120, 150, 255, 0.34 * t), ui.BlendMode.srcIn);
      final dst = ghost.dst.shift(ui.Offset(0, -state.cameraY));
      if (ghost.flip) {
        canvas.save();
        canvas.translate(ghost.centerX * 2, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawImageRect(ghost.image, ghost.src, dst, _ghostPaint);
      if (ghost.flip) canvas.restore();
    }
    if (fx.chargeTime > 0.14 && state.mode == "running") {
      final ready = fx.chargeTime >= 0.36;
      final center = ui.Offset(px, feetY - playerHeight * 0.55);
      final radius = (ready ? 50.0 : 26 + 60 * fx.chargeTime) + (ready ? 4 * math.sin(state.time * 30) : 0);
      canvas.drawCircle(center, radius, ui.Paint()..blendMode = ui.BlendMode.plus..shader = ui.Gradient.radial(center, radius, ready ? const [ui.Color(0xccfff0a7), ui.Color(0x00ff9d3c)] : const [ui.Color(0x66ffd9a0), ui.Color(0x00ff9d3c)]));
    }

    if (frames == null) {
      // Safety net: the ninja must never disappear — draw a placeholder.
      canvas.drawRect(ui.Rect.fromLTWH(px - 22, feetY - playerHeight, 44, playerHeight), ui.Paint()..color = const ui.Color(0xfff4e6c5));
    } else {
      try {
        drawAnchored(canvas, atlas.image, animation, index, px, feetY, playerHeight, player["facing"] < 0, alpha);
        final image = atlas.image;
        if (fx.wantGhost && image != null) {
          fx.ghosts.add(Ghost(image, _lastCrop, _lastDst.shift(ui.Offset(0, state.cameraY)), player["facing"] < 0, px));
        }
      } catch (e) {
        canvas.drawRect(ui.Rect.fromLTWH(px - 22, feetY - playerHeight, 44, playerHeight), ui.Paint()..color = const ui.Color(0xfff4e6c5));
        // ignore: avoid_print
        print("drawPlayer error: $e name=$name useStatus=$useStatus");
      }
    }

    if (player["shieldReady"] == true) {
      final x = laneX(player["lane"], state.laneCount);
      final y = feetY - 47;
      final shield = ui.Gradient.radial(ui.Offset(x, y), 62, const [ui.Color(0x00f8d75b), ui.Color(0x14f8d75b), ui.Color(0x7cf8d75b)], [0.0, 0.6, 1.0]);
      canvas.drawCircle(ui.Offset(x, y), 60, ui.Paint()..shader = shield);
    }
  }

  void render(ui.Canvas canvas, ui.Size size) {
    // Guard against zero/negative size (e.g. before first layout or on resize)
    // which would make _viewWidth NaN and push every sprite off-screen.
    if (size.height > 0 && size.width > 0) {
      _viewWidth = VIEW_HEIGHT * (size.width / size.height);
      simulation.setViewport(_viewWidth);
    }
    final state = simulation.state;
    final scale = size.height / VIEW_HEIGHT;
    canvas.save();
    canvas.scale(scale, scale);
    final shake = state.shake > 0 && !fx.lowEffects ? state.shake * 9 : 0.0;
    final kick = fx.lowEffects ? 0.0 : fx.kickY;
    canvas.translate((_shakeRand.nextDouble() - 0.5) * shake, (_shakeRand.nextDouble() - 0.5) * shake + kick);

    drawBackground(canvas, state);
    fx.renderAmbient(canvas, state.time);
    fx.renderUltVeils(canvas, _viewWidth, VIEW_HEIGHT);
    drawPlatforms(canvas, state);
    drawPickups(canvas, state);
    drawPowerups(canvas, state);
    drawObstacles(canvas, state);
    drawEnemies(canvas, state);
    drawBoss(canvas, state);
    drawProjectiles(canvas, state);
    drawBuffAuras(canvas, state);
    drawPlayer(canvas, state);
    drawPowerupEffects(canvas, state);
    fx.renderUlts(canvas, _viewWidth, VIEW_HEIGHT, state.cameraY);
    drawArsenalEffects(canvas, state);
    drawEffects(canvas, state);
    fx.render(canvas, state.cameraY);
    canvas.restore();

    // Screen-space grade: vignette, low-HP pulse, letterbox, flashes.
    final screen = ui.Offset.zero & size;
    final center = size.center(ui.Offset.zero);
    final far = size.longestSide * 0.72;
    canvas.drawRect(screen, ui.Paint()..shader = ui.Gradient.radial(center, far, const [ui.Color(0x00000000), ui.Color(0x00000000), ui.Color(0x8c02030a)], const [0.0, 0.55, 1.0]));

    final hpRatio = ((state.player["hp"] as num) / (state.player["maxHp"] as num)).toDouble();
    if (hpRatio < 0.35 && state.mode == "running") {
      final beat = 0.5 + 0.5 * math.sin(state.time * (hpRatio < 0.18 ? 9 : 5.5));
      final alpha = (0.22 + 0.3 * beat) * (1 - hpRatio / 0.35 * 0.55);
      canvas.drawRect(screen, ui.Paint()..shader = ui.Gradient.radial(center, far, [const ui.Color(0x00c8232c), const ui.Color(0x00c8232c), ui.Color.fromRGBO(200, 20, 40, alpha)], const [0.0, 0.5, 1.0]));
    }

    if (fx.letterbox > 0) {
      final t = math.min(1.0, math.min(fx.letterbox, 2.4 - fx.letterbox) / 0.3);
      final bar = size.height * 0.085 * t;
      final black = ui.Paint()..color = const ui.Color(0xf2000000);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, bar), black);
      canvas.drawRect(ui.Rect.fromLTWH(0, size.height - bar, size.width, bar), black);
    }
    if (state.flash > 0) {
      canvas.drawRect(screen, ui.Paint()..color = ui.Color.fromRGBO(255, 73, 73, (state.flash * 0.25).clamp(0.0, 1.0)));
    }
    if (fx.whiteFlash > 0) {
      canvas.drawRect(screen, ui.Paint()..color = ui.Color.fromRGBO(255, 248, 225, fx.whiteFlash.clamp(0.0, 1.0)));
    }
    if (fx.deathFade > 0) {
      canvas.drawRect(screen, ui.Paint()..color = ui.Color.fromRGBO(16, 2, 6, fx.deathFade * 0.62));
    }
  }
}
