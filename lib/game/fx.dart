// Visual-only "juice" layered over the simulation: particles, floating numbers,
// shockwaves, afterimages, hit-stop and slow motion. Nothing here feeds back
// into gameplay rules except the time scale game.dart applies to the sim.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'data.dart';
import 'simulation.dart';
import 'ult_fx.dart';

export 'ult_fx.dart' show paletteColor, kSkinPalette;

enum PShape { circle, streak, petal, shard }

class _Particle {
  double x = 0, y = 0, vx = 0, vy = 0, life = 0, maxLife = 1, size = 1, gravity = 0, rot = 0, vrot = 0, drag = 0;
  int color = 0xffffffff;
  PShape shape = PShape.circle;
  bool additive = false;
}

class _Floater {
  final ui.Paragraph text;
  final double width;
  double x, y, age = 0;
  final double life;
  _Floater(this.text, this.width, this.x, this.y, this.life);
}

class _Ring {
  double x, y, age = 0;
  final double life, radius;
  final int color;
  _Ring(this.x, this.y, this.life, this.radius, this.color);
}

class Ghost {
  final ui.Image image;
  final ui.Rect src;
  final ui.Rect dst; // world space (y includes the camera)
  final bool flip;
  final double centerX;
  double age = 0;
  Ghost(this.image, this.src, this.dst, this.flip, this.centerX);
}

class AmbientStyle {
  final PShape shape;
  final int colorA, colorB, count;
  final double size, vx, vy;
  final bool additive;
  const AmbientStyle(this.shape, this.colorA, this.colorB, this.count, this.size, this.vx, this.vy, {this.additive = true});
}

// One atmosphere per area, in AREAS order.
const List<AmbientStyle> kAmbient = [
  AmbientStyle(PShape.circle, 0x889fc8ff, 0x55e7f1ff, 20, 1.8, 6, -10), // Rooftop Dojo: moon dust
  AmbientStyle(PShape.petal, 0xcc6fae4a, 0xcc9ac265, 16, 4.0, 22, 34, additive: false), // Bamboo: leaves
  AmbientStyle(PShape.shard, 0xcc7ff0ff, 0x99c79bff, 18, 2.6, 2, -8), // Crystal: glints
  AmbientStyle(PShape.circle, 0x7799e0ff, 0x55c8f2ff, 18, 3.0, 3, -38), // Flooded: bubbles
  AmbientStyle(PShape.circle, 0xddff8a2e, 0xccffc14d, 30, 2.0, 8, -70), // Fire: embers
  AmbientStyle(PShape.circle, 0x6698ffd0, 0x44c8ffe5, 14, 3.4, 9, -14), // Village: ghost motes
  AmbientStyle(PShape.circle, 0xbbff5a3c, 0x99ffb347, 18, 2.0, 12, -26), // Market: lantern sparks
  AmbientStyle(PShape.streak, 0x55e9e4f5, 0x33ffffff, 12, 1.0, 10, 22), // Nest: drifting silk
  AmbientStyle(PShape.circle, 0xeeffffff, 0xbbd9efff, 34, 2.2, -28, 62, additive: false), // Peak: snow
  AmbientStyle(PShape.circle, 0xaa9a5cff, 0x77542bd6, 22, 2.4, 0, -30), // Abyss: void motes
  AmbientStyle(PShape.streak, 0x668fc6ff, 0x44cfe6ff, 30, 1.0, -36, 520), // Storm: rain
  AmbientStyle(PShape.shard, 0xccffb95c, 0x99d98a2b, 20, 2.0, 16, 60), // Clockwork: brass sparks
  AmbientStyle(PShape.circle, 0x6670f0e0, 0x4499fff0, 18, 3.2, -4, -34), // Torii: bubbles
  AmbientStyle(PShape.circle, 0x7796ffb4, 0x55b8ffd0, 16, 3.0, 12, -18), // Grave sea: souls
  AmbientStyle(PShape.streak, 0x44ffffff, 0x33ffd9c2, 16, 1.2, -240, 14), // Skyship: wind
  AmbientStyle(PShape.shard, 0xbbe2e8ff, 0x88a8c4ff, 20, 3.0, 5, 24), // Mirror: glass
  AmbientStyle(PShape.petal, 0xdde0324a, 0xccff6b7d, 22, 3.4, 26, 40, additive: false), // Blood moon: petals
  AmbientStyle(PShape.circle, 0xeeffd24d, 0xccff8a2e, 30, 1.9, -6, -86), // Forge: sparks
  AmbientStyle(PShape.shard, 0xbbf5dc8a, 0x77ffffff, 16, 2.2, 0, -6), // Citadel: suspended time
  AmbientStyle(PShape.circle, 0xbbff7bd5, 0xbb7bd5ff, 26, 2.4, 14, -22), // Origin: spectrum ink
];

class Fx {
  // "Hemat" effects mode halves particle work and removes screen shake.
  bool lowEffects = false;

  final List<_Particle> _particles = [];
  final List<_Particle> _pool = [];
  final List<_Floater> _floaters = [];
  final List<_Ring> _rings = [];
  final List<_Particle> _ambient = [];
  final List<Ghost> ghosts = [];
  final List<UltCast> ults = [];
  int _trailTick = 0;
  final math.Random _r = math.Random();
  final Map<String, ui.Paragraph> _textCache = {};
  final ui.Paint _paint = ui.Paint();

  static const int _maxParticles = 240;

  double hitStop = 0;
  double slowMo = 0;
  double whiteFlash = 0;
  double kickY = 0;
  double letterbox = 0;
  double deathFade = 0;
  double chargeTime = 0;
  bool charging = false;
  double _ghostTimer = 0;
  double _speedTimer = 0;
  int _ambientArea = -1;
  double _lastCameraY = 0;

  // What the sim should advance by this frame.
  double scaleDt(double dt) {
    if (hitStop > 0) {
      hitStop -= dt;
      return 0;
    }
    if (slowMo > 0) {
      slowMo -= dt;
      return dt * 0.28;
    }
    return dt;
  }

  void reset() {
    _pool.addAll(_particles);
    _particles.clear();
    _floaters.clear();
    _rings.clear();
    ghosts.clear();
    ults.clear();
    hitStop = slowMo = whiteFlash = kickY = letterbox = deathFade = chargeTime = 0;
    charging = false;
  }

  _Particle? _spawn() {
    if (_particles.length >= (lowEffects ? _maxParticles ~/ 2 : _maxParticles)) return null;
    final p = _pool.isNotEmpty ? _pool.removeLast() : _Particle();
    _particles.add(p);
    return p;
  }

  double _rand(double a, double b) => a + _r.nextDouble() * (b - a);

  void burst(double x, double y, int count, int color, {double speed = 180, double size = 3, double life = 0.5, double gravity = 320, PShape shape = PShape.circle, bool additive = true, double spread = math.pi * 2, double angle = 0, double drag = 0}) {
    final n = lowEffects ? (count / 2).ceil() : count;
    for (int i = 0; i < n; i += 1) {
      final p = _spawn();
      if (p == null) return;
      final a = angle + (_r.nextDouble() - 0.5) * spread;
      final v = speed * _rand(0.35, 1);
      p
        ..x = x
        ..y = y
        ..vx = math.cos(a) * v
        ..vy = math.sin(a) * v
        ..maxLife = _rand(life * 0.6, life)
        ..size = _rand(size * 0.6, size * 1.2)
        ..gravity = gravity
        ..rot = _r.nextDouble() * math.pi
        ..vrot = _rand(-8, 8)
        ..drag = drag
        ..color = color
        ..shape = shape
        ..additive = additive;
      p.life = p.maxLife;
    }
  }

  void ring(double x, double y, double radius, int color, {double life = 0.4}) => _rings.add(_Ring(x, y, life, radius, color));

  void floatText(String text, double x, double y, int color, {double size = 22, double life = 0.8}) {
    if (_floaters.length > 40) return;
    final key = "$text|$color|$size";
    final paragraph = _textCache[key] ??= _layoutText(text, color, size);
    if (_textCache.length > 96) _textCache.clear();
    _floaters.add(_Floater(paragraph, paragraph.maxIntrinsicWidth, x, y, life));
  }

  ui.Paragraph _layoutText(String text, int color, double size) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: "TradeWinds", fontSize: size, textAlign: ui.TextAlign.center))
      ..pushStyle(ui.TextStyle(color: ui.Color(color), shadows: const [ui.Shadow(color: ui.Color(0xe6000000), offset: ui.Offset(0, 2), blurRadius: 2)]))
      ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 200));
  }

  // Sim events → effects. laneX maps a lane to world x with the current layout.
  void onEvent(Map<String, dynamic> e, double Function(num lane, int laneCount) laneX, GameState state) {
    final type = e["type"];
    double x() => laneX(e["lane"] as num, e["laneCount"] as int);
    final y = (e["y"] as num?)?.toDouble() ?? 0;
    switch (type) {
      case "enemyDown":
        burst(x(), y - 40, 12, 0xffffd9a0, speed: 260, size: 3.2, life: 0.55);
        burst(x(), y - 40, 8, 0xdd16121f, speed: 120, size: 7, life: 0.6, gravity: -40, additive: false, drag: 2);
        ring(x(), y - 40, 58, 0xccffe2b0, life: 0.28);
        hitStop = math.max(hitStop, 0.03);
      case "hit":
        burst(x(), y, 14, 0xffff4a4a, speed: 300, size: 3.2, life: 0.45);
        floatText("-${(e["amount"] as num).round()}", x(), y - 30, 0xffff6470, size: 28);
        hitStop = math.max(hitStop, 0.06);
      case "land":
        final speed = (e["speed"] as num).toDouble();
        if (e["pound"] == true) {
          ring(x(), y, 120, 0xddfff0c0, life: 0.34);
          burst(x(), y, 22, 0xffffe2a0, speed: 340, size: 3.4, life: 0.5, angle: -math.pi / 2, spread: math.pi * 1.1);
          kickY = 12;
        } else if (speed > 180) {
          final n = (speed / 110).round().clamp(3, 8);
          burst(x(), y - 2, n, 0x66d9d2c0, speed: 100, size: 5, life: 0.34, gravity: -30, additive: false, angle: -math.pi / 2, spread: math.pi * 1.2, drag: 3);
          kickY = math.max(kickY, math.min(5, speed / 170));
        }
      case "coin":
        burst(x(), y, 6, 0xffffd65a, speed: 150, size: 2.2, life: 0.4, gravity: 200);
        floatText("+${e["coinReward"]}", x(), y - 8, 0xffffe08a, size: 15, life: 0.55);
      case "powerup":
        final px = laneX(state.player["lane"] as num, state.laneCount);
        final py = (state.player["y"] as num).toDouble() - 42;
        ring(px, py, 130, 0xeefff0a7, life: 0.5);
        burst(px, py, 24, 0xfffff0a7, speed: 300, size: 2.8, life: 0.6, gravity: 0, drag: 2);
      case "heal":
        ring(x(), y, 70, 0xcc7dffa0, life: 0.4);
        burst(x(), y, 14, 0xff9dffb8, speed: 170, size: 2.6, life: 0.6, gravity: -120, drag: 1.5);
        floatText("+${(e["amount"] as num).round()}", x(), y - 12, 0xff8dffae, size: 24);
      case "dash":
        final skin = state.skinIndex;
        final px = laneX(state.player["lane"] as num, state.laneCount);
        final py = (state.player["y"] as num).toDouble() - 45;
        final palette = kSkinPalette[skin];
        ring(px, py, 170, palette.$1, life: 0.42);
        burst(px, py, 26, palette.$1, speed: 460, size: 2.4, life: 0.42, gravity: 0, shape: PShape.streak, drag: 3);
        ults.add(UltCast(skin, px, py, [
          for (final t in (e["targets"] as List? ?? const []))
            ui.Offset(laneX(t[0] as num, t[2] as int), (t[1] as num).toDouble()),
        ], _r.nextInt(1 << 30)));
        slowMo = math.max(slowMo, 0.22);
        whiteFlash = math.max(whiteFlash, 0.14);
      case "shoot":
        final skin = state.skinIndex;
        final charged = e["charged"] == true;
        final px = laneX(state.player["lane"] as num, state.laneCount);
        final py = (state.player["y"] as num).toDouble() - 55;
        final color = kSkinPalette[skin].$1;
        ring(px, py, charged ? 74 : 30, color, life: charged ? 0.3 : 0.16);
        burst(px, py, charged ? 18 : 6, color, speed: charged ? 300 : 170, size: charged ? 2.8 : 2, life: charged ? 0.34 : 0.2, gravity: 0, angle: math.pi / 2, spread: 1.5, shape: PShape.streak);
        if (charged) kickY = 5;
      case "impact":
        final skin = e["skinIndex"] as int;
        final charged = e["charged"] == true;
        final palette = kSkinPalette[skin];
        burst(x(), y, charged ? 20 : 9, palette.$1, speed: charged ? 340 : 210, size: 2.6, life: 0.36, gravity: 120);
        burst(x(), y, charged ? 8 : 3, palette.$2, speed: 130, size: 4, life: 0.26, gravity: 0, drag: 3);
        ring(x(), y, charged ? 74 : 38, palette.$1, life: 0.22);
        if (charged) hitStop = math.max(hitStop, 0.045);
      case "shield":
      case "revive":
        final px = laneX(state.player["lane"] as num, state.laneCount);
        final py = (state.player["y"] as num).toDouble() - 42;
        ring(px, py, 150, 0xeeffd65a, life: 0.5);
        if (type == "revive") whiteFlash = 0.5;
      case "boss":
        letterbox = 2.4;
      case "areaClear":
      case "victory":
        final boss = state.boss;
        final bx = laneX(boss["lane"] as num, boss["laneCount"] as int);
        final by = (boss["y"] as num).toDouble() - 70;
        burst(bx, by, 44, 0xffffe2a0, speed: 520, size: 3.6, life: 1.0, gravity: 220);
        burst(bx, by, 26, 0xee16121f, speed: 240, size: 11, life: 0.9, gravity: -30, additive: false, drag: 2);
        ring(bx, by, 300, 0xffffffff, life: 0.6);
        slowMo = 0.8;
        whiteFlash = 0.55;
        letterbox = 0;
      case "gameover":
        slowMo = 0.6;
        deathFade = 0.0001;
    }
  }

  // Generic damage feedback: compares HP to last frame, so every damage source
  // (shots, slash, skills, burn) gets the same flash and number.
  void _trackDamage(Simulation sim, double Function(num lane, int laneCount) laneX) {
    final state = sim.state;
    for (final enemy in sim.nearEnemies) {
      if (enemy["alive"] != true) continue;
      final y = (enemy["y"] as num).toDouble();
      if (y < state.cameraY - 120 || y > state.cameraY + 1040) continue;
      final hp = (enemy["hp"] as num).toDouble();
      final last = (enemy["_hp"] as double?) ?? hp;
      if (last - hp >= 0.5) {
        enemy["_flash"] = 0.11;
        final damage = last - hp;
        floatText(damage.round().clamp(1, 9999).toString(), laneX(enemy["lane"] as num, enemy["laneCount"] as int) + _rand(-10, 10), y - 74, damage >= 5 ? 0xffffd65a : 0xfffff5e0, size: damage >= 5 ? 28 : 20);
        enemy["_hp"] = hp;
      } else if (hp > last) {
        enemy["_hp"] = hp;
      } else {
        enemy["_hp"] = last;
      }
      final flash = (enemy["_flash"] as double?) ?? 0;
      if (flash > 0) enemy["_flash"] = flash - 1 / 60;
    }
    final boss = state.boss;
    if (boss["active"] == true && boss["defeated"] != true) {
      final hp = (boss["hp"] as num).toDouble();
      final last = (boss["_hp"] as double?) ?? hp;
      if (last - hp >= 0.5) {
        boss["_flash"] = 0.11;
        final bx = laneX(boss["lane"] as num, boss["laneCount"] as int);
        final by = (boss["y"] as num).toDouble() - 110;
        final damage = last - hp;
        floatText(damage.round().clamp(1, 9999).toString(), bx + _rand(-24, 24), by, damage >= 5 ? 0xffffd65a : 0xfffff5e0, size: damage >= 5 ? 34 : 24);
        burst(bx, by + 40, 8, 0xffffb35c, speed: 240, size: 2.6, life: 0.36);
        kickY = math.max(kickY, 3);
        boss["_hp"] = hp;
      }
      final flash = (boss["_flash"] as double?) ?? 0;
      if (flash > 0) boss["_flash"] = flash - 1 / 60;
    }
  }

  void update(double dt, Simulation sim, double viewWidth, double viewHeight, double Function(num lane, int laneCount) laneX) {
    final state = sim.state;
    whiteFlash = math.max(0, whiteFlash - dt * 2.4);
    kickY = math.max(0, kickY - dt * 46);
    letterbox = math.max(0, letterbox - dt);
    if (deathFade > 0) deathFade = math.min(1, deathFade + dt * 1.1);
    chargeTime = charging ? chargeTime + dt : 0;
    if (state.mode == "running") _trackDamage(sim, laneX);

    for (int i = _particles.length - 1; i >= 0; i -= 1) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
        _pool.add(p);
        continue;
      }
      if (p.drag > 0) {
        final k = math.max(0.0, 1 - p.drag * dt);
        p.vx *= k;
        p.vy *= k;
      }
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vrot * dt;
    }
    for (int i = _floaters.length - 1; i >= 0; i -= 1) {
      final f = _floaters[i];
      f.age += dt;
      f.y -= (70 - f.age * 60) * dt;
      if (f.age >= f.life) _floaters.removeAt(i);
    }
    for (int i = _rings.length - 1; i >= 0; i -= 1) {
      _rings[i].age += dt;
      if (_rings[i].age >= _rings[i].life) _rings.removeAt(i);
    }

    // Afterimages while dropping fast or dashing, skill speed-lines.
    final player = state.player;
    final vy = (player["vy"] as num).toDouble();
    final dashing = player["anim"] == "dash";
    for (int i = ghosts.length - 1; i >= 0; i -= 1) {
      ghosts[i].age += dt;
      if (ghosts[i].age > 0.26) ghosts.removeAt(i);
    }
    _ghostTimer -= dt;
    wantGhost = state.mode == "running" && (vy > 430 || dashing) && _ghostTimer <= 0 && !lowEffects;
    if (wantGhost) _ghostTimer = 0.035;

    _speedTimer -= dt;
    if (state.mode == "running" && vy > 560 && _speedTimer <= 0 && !lowEffects) {
      _speedTimer = 0.03;
      final p = _spawn();
      if (p != null) {
        p
          ..x = _r.nextDouble() * viewWidth
          ..y = state.cameraY + viewHeight + 20
          ..vx = 0
          ..vy = -1250
          ..maxLife = 0.5
          ..life = 0.5
          ..size = 1.2
          ..gravity = 0
          ..drag = 0
          ..rot = 0
          ..vrot = 0
          ..color = 0x44ffffff
          ..shape = PShape.streak
          ..additive = true;
      }
    }

    for (int i = ults.length - 1; i >= 0; i -= 1) {
      ults[i].age += dt;
      if (ults[i].done) ults.removeAt(i);
    }

    // Shots shed sparks in their owner's colours.
    _trailTick += 1;
    if (_trailTick.isEven || !lowEffects) {
      for (final shot in state.projectiles) {
        final charged = shot["charged"] == true;
        if (!charged && _trailTick % 2 == 1) continue;
        final palette = kSkinPalette[shot["skinIndex"] as int];
        final p = _spawn();
        if (p == null) break;
        p
          ..x = laneX(shot["lane"] as num, shot["laneCount"] as int) + _rand(-5, 5)
          ..y = (shot["y"] as num).toDouble() - 8
          ..vx = _rand(-30, 30)
          ..vy = -_rand(20, 90)
          ..maxLife = charged ? 0.42 : 0.28
          ..size = charged ? _rand(1.8, 3.4) : _rand(1.2, 2.2)
          ..gravity = 0
          ..drag = 0
          ..rot = 0
          ..vrot = 0
          ..color = _r.nextInt(3) == 0 ? palette.$2 : palette.$1
          ..shape = PShape.circle
          ..additive = true;
        p.life = p.maxLife;
      }
    }

    _updateAmbient(dt, state, viewWidth, viewHeight);
    _lastCameraY = state.cameraY;
  }

  bool wantGhost = false;

  void _updateAmbient(double dt, GameState state, double w, double h) {
    final style = kAmbient[state.areaIndex % kAmbient.length];
    final target = lowEffects ? style.count ~/ 2 : style.count;
    if (_ambientArea != state.areaIndex) {
      _ambientArea = state.areaIndex;
      _ambient.clear();
    }
    while (_ambient.length < target) {
      final p = _Particle();
      _seedAmbient(p, style, w, h);
      p.y = _r.nextDouble() * h;
      _ambient.add(p);
    }
    // Parallax: motes lag the camera while the ninja falls.
    final parallax = (state.cameraY - _lastCameraY) * 0.45;
    for (final p in _ambient) {
      p.x += p.vx * dt;
      p.y += p.vy * dt - parallax;
      p.rot += p.vrot * dt;
      p.life += dt;
      if (p.y < -30) {
        p.y = h + 20;
        p.x = _r.nextDouble() * w;
      } else if (p.y > h + 30) {
        p.y = -20;
        p.x = _r.nextDouble() * w;
      }
      if (p.x < -30) p.x = w + 20;
      if (p.x > w + 30) p.x = -20;
    }
  }

  void _seedAmbient(_Particle p, AmbientStyle s, double w, double h) {
    final depth = _rand(0.55, 1.2);
    p
      ..x = _r.nextDouble() * w
      ..y = s.vy < 0 ? h + 10 : -10
      ..vx = (s.vx + _rand(-8, 8)) * depth
      ..vy = s.vy * depth + _rand(-4, 4)
      ..size = s.size * depth
      ..rot = _r.nextDouble() * math.pi * 2
      ..vrot = _rand(-2, 2)
      ..life = _r.nextDouble() * 6
      ..color = _r.nextBool() ? s.colorA : s.colorB
      ..shape = s.shape
      ..additive = s.additive;
  }

  void _drawParticle(ui.Canvas c, _Particle p, double x, double y, double alpha) {
    final color = ui.Color(p.color);
    _paint
      ..blendMode = p.additive ? ui.BlendMode.plus : ui.BlendMode.srcOver
      ..color = color.withValues(alpha: color.a * alpha)
      ..style = ui.PaintingStyle.fill
      ..strokeWidth = p.size;
    switch (p.shape) {
      case PShape.circle:
        c.drawCircle(ui.Offset(x, y), p.size, _paint);
      case PShape.streak:
        final speed = math.sqrt(p.vx * p.vx + p.vy * p.vy);
        final k = speed < 1 ? 0.0 : math.min(46.0, speed * 0.05) / speed;
        c.drawLine(ui.Offset(x, y), ui.Offset(x - p.vx * k, y - p.vy * k), _paint);
      case PShape.petal:
        c.save();
        c.translate(x, y);
        c.rotate(p.rot);
        c.drawOval(ui.Rect.fromCenter(center: ui.Offset.zero, width: p.size * 2.2, height: p.size), _paint);
        c.restore();
      case PShape.shard:
        c.save();
        c.translate(x, y);
        c.rotate(p.rot);
        c.drawRect(ui.Rect.fromCenter(center: ui.Offset.zero, width: p.size * 1.4, height: p.size * 1.4), _paint);
        c.restore();
    }
  }

  void renderUltVeils(ui.Canvas c, double w, double h) {
    for (final u in ults) {
      renderUltVeil(c, u, w, h);
    }
  }

  void renderUlts(ui.Canvas c, double w, double h, double cameraY) {
    for (final u in ults) {
      renderUlt(c, u, w, h, cameraY);
    }
  }

  // Behind the actors, in screen space.
  void renderAmbient(ui.Canvas c, double time) {
    for (final p in _ambient) {
      final twinkle = 0.65 + 0.35 * math.sin(p.life * 2.2);
      _drawParticle(c, p, p.x, p.y, twinkle);
    }
    _paint.blendMode = ui.BlendMode.srcOver;
  }

  // Over the actors, world space translated by the camera.
  void render(ui.Canvas c, double cameraY) {
    for (final r in _rings) {
      final t = r.age / r.life;
      final color = ui.Color(r.color);
      _paint
        ..blendMode = ui.BlendMode.plus
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 7 * (1 - t) + 0.5
        ..color = color.withValues(alpha: color.a * (1 - t));
      c.drawCircle(ui.Offset(r.x, r.y - cameraY), r.radius * (1 - (1 - t) * (1 - t)), _paint);
    }
    _paint.style = ui.PaintingStyle.fill;
    for (final p in _particles) {
      _drawParticle(c, p, p.x, p.y - cameraY, (p.life / p.maxLife).clamp(0.0, 1.0));
    }
    _paint.blendMode = ui.BlendMode.srcOver;
    for (final f in _floaters) {
      final t = f.age / f.life;
      final scale = t < 0.14 ? 0.6 + (t / 0.14) * 0.6 : 1.2 - math.min(0.2, (t - 0.14) * 1.2);
      c.save();
      c.translate(f.x, f.y - cameraY);
      c.scale(scale);
      final opacity = t > 0.65 ? 1 - (t - 0.65) / 0.35 : 1.0;
      if (opacity < 1) {
        c.saveLayer(null, ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, opacity));
      }
      c.drawParagraph(f.text, const ui.Offset(-100, -14));
      if (opacity < 1) c.restore();
      c.restore();
    }
  }
}

// Short pickup descriptions for the powerup popup.
const Map<String, String> kPowerupInfo = {
  "bamboo_shield": "Kebal selama 9 detik",
  "shadow_cloak": "Tembus serangan 6 detik",
  "time_hourglass": "Dunia melambat 7 detik",
  "coin_magnet": "Koin tertarik 14 detik",
  "phoenix_heart": "+55 HP & satu kali bangkit",
  "storm_scroll": "+2 tembakan 9 detik",
  "moon_seal": "Musuh & jebakan membeku",
  "dragon_orb": "Damage +75% selama 10 detik",
  "healing_elixir": "Pulihkan 60 HP",
  "celestial_aegis": "Kebal selama 5 detik",
  "spirit_lantern": "Regen HP 12 detik",
  "clone_charm": "+1 tembakan 10 detik",
};

// Rarity tiers derive from a skin's price.
class Rarity {
  final String label;
  final int color;
  const Rarity(this.label, this.color);
}

Rarity rarityOf(Skin skin) {
  if (skin.cost == 0) return const Rarity("BIASA", 0xff9fb4cc);
  if (skin.cost <= 1100) return const Rarity("LANGKA", 0xff6fc3ff);
  if (skin.cost <= 3100) return const Rarity("EPIK", 0xffc48bff);
  return const Rarity("LEGENDA", 0xffffc85a);
}
