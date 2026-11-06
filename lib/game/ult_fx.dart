// One procedural "ultimate" per skin, drawn over the arsenal's skill sprite.
// Each cast is pure visuals: the damage already happened in Simulation.dash().
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show HSVColor;

class UltCast {
  final int skin;
  final double x, y; // world space
  final List<ui.Offset> targets; // world space
  final int seed;
  double age = 0;
  UltCast(this.skin, this.x, this.y, this.targets, this.seed);
  double get duration => kUltDurations[skin];
  bool get done => age >= duration;
}

const List<double> kUltDurations = [0.9, 1.0, 1.1, 1.1, 1.2, 1.1, 1.2, 0.9, 1.3, 1.2, 1.2, 1.2, 1.2, 1.3, 1.1, 1.0, 1.3, 1.2, 1.1, 1.3];

// Primary, secondary per skin: shared by shots, muzzle flashes, impacts, ultimates.
const List<(int, int)> kSkinPalette = [
  (0xffb05cff, 0xff4b1e8f), // Shadow Kunoichi
  (0xff38f0ff, 0xff1b6dff), // Cyber Ninja
  (0xffff9a3c, 0xff5ad2ff), // Kitsune
  (0xffff5a2a, 0xffffc23c), // Dragon
  (0xffa8e6ff, 0xff5c8cff), // Ghost Ronin
  (0xff8cffd8, 0xffe8fff6), // Tengu
  (0xffff8fc0, 0xff8dffae), // Sakura
  (0xfffff06a, 0xff8ab4ff), // Thunder Oni
  (0xff8a3cff, 0xffffcf5c), // Shadow Monarch
  (0xffffd65a, 0xfffff3c0), // Golden Buddha
  (0xffff3c5a, 0xffffa0b0), // Crimson Moth
  (0xff4dffa0, 0xffc8ff5a), // Jade Alchemist
  (0xffdfe8ff, 0xffffc8e0), // Moon Rabbit
  (0xff9fc4e8, 0xff5a7fa8), // Iron Beetle
  (0xff6f7dff, 0xffc8d0ff), // Void Sailor
  (0xfff4efe0, 0xffff6a6a), // Paper Doll
  (0xffff8a2a, 0xffffe05a), // Solar Phoenix
  (0xffe8e0c8, 0xff8fff9a), // Bone Oracle
  (0xffff5ad8, 0xff5ad8ff), // Prism Pulse
  (0xffffffff, 0xff9aa0b0), // Origin White
];

ui.Color paletteColor(int skin, {bool secondary = false}) => ui.Color(secondary ? kSkinPalette[skin].$2 : kSkinPalette[skin].$1);

double _out(double t) => 1 - math.pow(1 - t.clamp(0.0, 1.0), 3).toDouble();
double _fade(double t, [double hold = 0.55]) => t < hold ? 1 : (1 - (t - hold) / (1 - hold)).clamp(0.0, 1.0);

final ui.Paint _p = ui.Paint();

ui.Paint _add(ui.Color c, double a, {double width = 0}) {
  _p
    ..shader = null
    ..blendMode = ui.BlendMode.plus
    ..color = c.withValues(alpha: (c.a * a).clamp(0.0, 1.0))
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..style = width > 0 ? ui.PaintingStyle.stroke : ui.PaintingStyle.fill
    ..strokeWidth = width;
  return _p;
}

void _glow(ui.Canvas c, ui.Offset o, double r, ui.Color color, double a) {
  if (r <= 0 || a <= 0) return;
  _p
    ..blendMode = ui.BlendMode.plus
    ..style = ui.PaintingStyle.fill
    ..color = const ui.Color(0xffffffff)
    ..shader = ui.Gradient.radial(o, r, [color.withValues(alpha: a.clamp(0.0, 1.0)), color.withValues(alpha: 0)]);
  c.drawCircle(o, r, _p);
  _p.shader = null;
}

void _bolt(ui.Canvas c, ui.Offset a, ui.Offset b, math.Random r, ui.Color color, double width, double alpha) {
  final path = ui.Path()..moveTo(a.dx, a.dy);
  const steps = 7;
  final normal = ui.Offset(-(b.dy - a.dy), b.dx - a.dx) / math.max(1.0, (b - a).distance);
  for (int i = 1; i < steps; i += 1) {
    final p = ui.Offset.lerp(a, b, i / steps)! + normal * ((r.nextDouble() - 0.5) * 34);
    path.lineTo(p.dx, p.dy);
  }
  path.lineTo(b.dx, b.dy);
  c.drawPath(path, _add(color, alpha * 0.45, width: width * 3));
  c.drawPath(path, _add(const ui.Color(0xffffffff), alpha, width: width));
}

void _polygon(ui.Canvas c, ui.Offset o, double r, int sides, double rot, ui.Paint paint) {
  final path = ui.Path();
  for (int i = 0; i <= sides; i += 1) {
    final a = rot + i / sides * math.pi * 2;
    final p = o + ui.Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  c.drawPath(path, paint);
}

// Screen-space dim behind the actors while an ultimate plays.
void renderUltVeil(ui.Canvas c, UltCast u, double w, double h) {
  final t = u.age / u.duration;
  final strength = u.skin == 8 ? 0.72 : u.skin == 19 ? 0.6 : 0.34;
  final a = strength * math.min(1.0, t * 8) * _fade(t, 0.45);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = ui.Color.fromRGBO(4, 3, 12, a));
}

void renderUlt(ui.Canvas c, UltCast u, double w, double h, double cameraY) {
  final t = (u.age / u.duration).clamp(0.0, 1.0);
  final o = ui.Offset(u.x, u.y - cameraY);
  final a = paletteColor(u.skin);
  final b = paletteColor(u.skin, secondary: true);
  final f = _fade(t);
  final r = math.Random(u.seed);
  final targets = [for (final p in u.targets) p.translate(0, -cameraY)];
  const tau = math.pi * 2;

  switch (u.skin) {
    case 0: // UMBRA FAN: a fan of crescent blades sweeping out
      for (int i = 0; i < 9; i += 1) {
        final angle = (i - 4) * 0.42 + math.pi / 2 + t * 1.2;
        final dist = _out(t * 1.2) * h * 0.55;
        final p = o + ui.Offset(math.cos(angle), math.sin(angle)) * dist;
        c.save();
        c.translate(p.dx, p.dy);
        c.rotate(angle + t * 14);
        final blade = ui.Path()
          ..moveTo(-26, 0)
          ..quadraticBezierTo(0, -26, 26, 0)
          ..quadraticBezierTo(0, -11, -26, 0);
        c.drawPath(blade, _add(a, f));
        c.restore();
        c.drawLine(o, p, _add(b, f * 0.3, width: 2));
      }
      _glow(c, o, 120 * _out(t * 3), a, 0.6 * f);
    case 1: // NEON GRID: scanning lattice, target locks
      final reach = _out(t * 1.6) * h;
      for (double x = (u.x % 48); x < w; x += 48) {
        c.drawLine(ui.Offset(x, o.dy - reach), ui.Offset(x, o.dy + reach), _add(a, f * 0.34, width: 1.2));
      }
      for (double y = -((cameraY - u.y) % 48); y < h; y += 48) {
        if ((y - o.dy).abs() < reach) c.drawLine(ui.Offset(0, y), ui.Offset(w, y), _add(a, f * 0.34, width: 1.2));
      }
      final scan = o.dy + (t * 2 % 1 - 0.5) * h;
      c.drawLine(ui.Offset(0, scan), ui.Offset(w, scan), _add(const ui.Color(0xffffffff), f * 0.8, width: 2.5));
      for (final p in targets) {
        final s = 34 - 12 * _out(t * 3);
        c.drawRect(ui.Rect.fromCenter(center: p.translate(0, -38), width: s * 2, height: s * 2), _add(b, f, width: 2));
        c.drawLine(o, p.translate(0, -38), _add(a, f * 0.5, width: 1.4));
      }
    case 2: // NINE-TAIL: nine foxfire tails lash outward
      for (int i = 0; i < 9; i += 1) {
        final angle = i / 9 * tau + t * 1.6;
        final len = _out(t * 1.8) * 210;
        final tip = o + ui.Offset(math.cos(angle), math.sin(angle)) * len;
        final bend = o + ui.Offset(math.cos(angle + 0.9 + math.sin(t * 12 + i)), math.sin(angle + 0.9 + math.sin(t * 12 + i))) * len * 0.55;
        c.drawPath(ui.Path()..moveTo(o.dx, o.dy)..quadraticBezierTo(bend.dx, bend.dy, tip.dx, tip.dy), _add(a, f * 0.8, width: 7 * (1 - t) + 2));
        _glow(c, tip, 30, i.isEven ? a : b, f);
        _glow(c, tip, 9, const ui.Color(0xffffffff), f);
      }
    case 3: // DRAGON BREATH: a roaring cone of fire downward
      for (int i = 0; i < 70; i += 1) {
        final phase = (t * 1.6 + r.nextDouble()) % 1;
        final spread = (r.nextDouble() - 0.5) * 1.15;
        final dist = phase * h * 0.75;
        final p = o + ui.Offset(math.sin(spread) * dist, math.cos(spread) * dist);
        final size = 10 + phase * 42;
        _glow(c, p, size, phase < 0.35 ? b : a, f * (1 - phase) * 0.75);
      }
      _glow(c, o, 90, b, f);
    case 4: // SOUL MARCH: ghosts rise up every column of the screen
      for (int i = 0; i < 16; i += 1) {
        final x = (i + 0.5) / 16 * w + (r.nextDouble() - 0.5) * 18;
        final y = h + 40 - ((t * 1.1 + r.nextDouble() * 0.5) % 1.2) * (h + 120);
        final sway = math.sin(t * 9 + i) * 10;
        final body = ui.Path()
          ..addOval(ui.Rect.fromCenter(center: ui.Offset(x + sway, y), width: 26, height: 34))
          ..moveTo(x + sway - 12, y + 8)
          ..quadraticBezierTo(x + sway, y + 70, x + sway + 12, y + 8);
        c.drawPath(body, _add(a, f * 0.42));
        _glow(c, ui.Offset(x + sway, y), 34, b, f * 0.4);
      }
    case 5: // CYCLONE: feathers spiral in a widening vortex
      for (int i = 0; i < 46; i += 1) {
        final k = i / 46;
        final angle = k * tau * 3 + t * 15;
        final dist = (24 + k * 220) * _out(t * 1.5);
        final p = o + ui.Offset(math.cos(angle), math.sin(angle) * 0.72) * dist;
        c.save();
        c.translate(p.dx, p.dy);
        c.rotate(angle + math.pi / 2);
        c.drawOval(const ui.Rect.fromLTWH(-13, -3, 26, 6), _add(i.isEven ? a : b, f * 0.85));
        c.restore();
      }
      for (int i = 1; i <= 3; i += 1) {
        c.drawOval(ui.Rect.fromCenter(center: o, width: 150.0 * i * _out(t * 2), height: 74.0 * i * _out(t * 2)), _add(a, f * 0.25, width: 2));
      }
    case 6: // BLOOM: a great flower opens, healing motes rise
      final open = _out(t * 1.7);
      for (int layer = 0; layer < 2; layer += 1) {
        for (int i = 0; i < 12; i += 1) {
          final angle = i / 12 * tau + layer * 0.26 + t * 0.7;
          c.save();
          c.translate(o.dx, o.dy);
          c.rotate(angle);
          final length = (layer == 0 ? 170 : 104) * open;
          c.drawOval(ui.Rect.fromLTWH(10, -length * 0.16, length, length * 0.32), _add(layer == 0 ? a : const ui.Color(0xffffd0e4), f * 0.55));
          c.restore();
        }
      }
      for (int i = 0; i < 24; i += 1) {
        final y = o.dy + 60 - ((t + r.nextDouble()) % 1) * 240;
        _glow(c, ui.Offset(o.dx + (r.nextDouble() - 0.5) * 170, y), 9, b, f);
      }
    case 7: // RAIJIN CHAIN: lightning leaps between every enemy
      final flick = math.Random(u.seed + (t * 22).floor());
      var from = o;
      for (final p in targets.take(7)) {
        final to = p.translate(0, -38);
        _bolt(c, from, to, flick, a, 2.4, f);
        _glow(c, to, 46, a, f);
        from = to;
      }
      if (targets.isEmpty) {
        for (int i = 0; i < 5; i += 1) {
          _bolt(c, o, ui.Offset(flick.nextDouble() * w, o.dy + 80 + flick.nextDouble() * 300), flick, a, 2.4, f);
        }
      }
      _bolt(c, ui.Offset(o.dx, -10), o, flick, b, 3.5, f);
      _glow(c, o, 100, a, f * 0.8);
    case 8: // ECLIPSE: a black sun and its burning corona
      final center = ui.Offset(w / 2, h * 0.42);
      final radius = _out(t * 2) * 120;
      for (int i = 0; i < 40; i += 1) {
        final angle = i / 40 * tau + t * 0.8;
        final len = radius + 26 + r.nextDouble() * 90 * f;
        c.drawLine(center + ui.Offset(math.cos(angle), math.sin(angle)) * radius, center + ui.Offset(math.cos(angle), math.sin(angle)) * len, _add(i.isEven ? b : a, f * 0.75, width: 2.4));
      }
      _glow(c, center, radius * 1.9, b, f * 0.7);
      c.drawCircle(center, radius, ui.Paint()..color = ui.Color.fromRGBO(2, 0, 8, f));
      c.drawCircle(center, radius, _add(b, f, width: 3));
    case 9: // DHARMA: bell waves and a golden mandala
      for (int i = 0; i < 4; i += 1) {
        final wave = ((t * 1.5 - i * 0.14)).clamp(0.0, 1.0);
        c.drawCircle(o, _out(wave) * h * 0.6, _add(a, (1 - wave) * 0.9, width: 5 * (1 - wave) + 1));
      }
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(t * 1.4);
      final mandala = _out(t * 2) * 150;
      for (int i = 0; i < 16; i += 1) {
        c.rotate(tau / 16);
        c.drawLine(ui.Offset(mandala * 0.3, 0), ui.Offset(mandala, 0), _add(b, f * 0.8, width: 1.6));
        c.drawCircle(ui.Offset(mandala, 0), 5, _add(a, f));
        c.drawOval(ui.Rect.fromLTWH(mandala * 0.42, -7, mandala * 0.32, 14), _add(a, f * 0.4));
      }
      c.restore();
      _glow(c, o, 110, b, f * 0.7);
    case 10: // SCARLET COCOON: silk threads wind inward, moth wings spread
      final wing = _out(t * 1.6);
      for (final side in const [-1.0, 1.0]) {
        c.drawPath(
          ui.Path()
            ..moveTo(o.dx, o.dy)
            ..cubicTo(o.dx + side * 150 * wing, o.dy - 190 * wing, o.dx + side * 240 * wing, o.dy - 40 * wing, o.dx + side * 120 * wing, o.dy + 20)
            ..cubicTo(o.dx + side * 170 * wing, o.dy + 90 * wing, o.dx + side * 60 * wing, o.dy + 120 * wing, o.dx, o.dy + 10),
          _add(a, f * 0.42),
        );
      }
      for (int i = 0; i < 26; i += 1) {
        final angle = i / 26 * tau * 2 + t * 8;
        final radius = 170 * (1 - _out(t * 1.2)) + 30 + i * 1.5;
        final p = o + ui.Offset(math.cos(angle), math.sin(angle) * 1.25) * radius;
        final q = o + ui.Offset(math.cos(angle + 0.6), math.sin(angle + 0.6) * 1.25) * radius;
        c.drawLine(p, q, _add(b, f * 0.8, width: 1.3));
      }
    case 11: // TRANSMUTE: a turning hexagram, poison boiling off targets
      final radius = _out(t * 2) * 165;
      c.drawCircle(o, radius, _add(a, f * 0.8, width: 2.4));
      c.drawCircle(o, radius * 0.86, _add(b, f * 0.5, width: 1));
      _polygon(c, o, radius * 0.86, 3, t * 2, _add(a, f * 0.85, width: 2));
      _polygon(c, o, radius * 0.86, 3, t * 2 + math.pi, _add(a, f * 0.85, width: 2));
      _glow(c, o, radius, a, f * 0.28);
      for (final p in targets) {
        for (int i = 0; i < 6; i += 1) {
          final rise = (t * 1.5 + i / 6) % 1;
          c.drawCircle(p.translate((i - 2.5) * 11, -rise * 96), 3.0 + i % 3 * 2, _add(i.isEven ? a : b, f * (1 - rise)));
        }
      }
    case 12: // MOONFALL: the moon comes down
      final impact = math.min(1.0, t / 0.42);
      final moon = ui.Offset(o.dx, -130 + (o.dy + 130) * impact * impact);
      if (t < 0.42) {
        _glow(c, moon, 190, a, 0.65);
        c.drawCircle(moon, 92, ui.Paint()..shader = ui.Gradient.radial(moon.translate(-24, -24), 120, const [ui.Color(0xfffdfdff), ui.Color(0xffb4bfd8)]));
        for (int i = 0; i < 6; i += 1) {
          c.drawCircle(moon + ui.Offset(math.cos(i * 1.9), math.sin(i * 1.9)) * (24 + i * 9), 6.0 + i * 1.6, ui.Paint()..color = const ui.Color(0x668f9ab8));
        }
      } else {
        final blast = (t - 0.42) / 0.58;
        c.drawCircle(o, _out(blast) * h * 0.62, _add(a, 1 - blast, width: 16 * (1 - blast) + 1));
        c.drawCircle(o, _out(blast) * h * 0.4, _add(b, 1 - blast, width: 7 * (1 - blast) + 1));
        _glow(c, o, 240 * (1 - blast * 0.5), a, 1 - blast);
      }
    case 13: // FORTRESS: an iron honeycomb dome locks in
      final grow = _out(t * 1.8);
      const size = 34.0;
      for (int q = -5; q <= 5; q += 1) {
        for (int k = -5; k <= 5; k += 1) {
          final p = ui.Offset((q + k * 0.5) * size * 1.74, k * size * 1.5);
          final dist = p.distance;
          if (dist > 175 * grow) continue;
          final lit = (math.sin(t * 16 - dist * 0.04) + 1) / 2;
          _polygon(c, o.translate(0, -30) + p, size * 0.92, 6, math.pi / 6, _add(a, f * (0.28 + 0.55 * lit), width: 2));
        }
      }
      _glow(c, o.translate(0, -30), 190 * grow, b, f * 0.45);
    case 14: // EVENTIDE NET: a star net snaps enemies toward the sailor
      final pull = _out(t * 1.4);
      final nodes = [for (final p in targets) ui.Offset.lerp(p.translate(0, -38), o, pull * 0.8)!];
      for (int i = 0; i < 18; i += 1) {
        final angle = i / 18 * tau + t;
        final p = o + ui.Offset(math.cos(angle), math.sin(angle)) * 260 * (1 - pull * 0.55);
        c.drawLine(o, p, _add(a, f * 0.42, width: 1.2));
        final next = o + ui.Offset(math.cos(angle + tau / 18), math.sin(angle + tau / 18)) * 260 * (1 - pull * 0.55);
        c.drawLine(p, next, _add(b, f * 0.5, width: 1.2));
        c.drawCircle(p, 3, _add(const ui.Color(0xffffffff), f));
      }
      for (final p in nodes) {
        c.drawLine(o, p, _add(b, f, width: 2));
        _glow(c, p, 24, a, f);
      }
    case 15: // 1000 CLONES: a blizzard of paper darts across the screen
      for (int i = 0; i < 90; i += 1) {
        final fromLeft = r.nextBool();
        final y = r.nextDouble() * h;
        final speed = 0.8 + r.nextDouble();
        final x = ((t * speed * 1.6 + r.nextDouble()) % 1) * (w + 120) - 60;
        final px = fromLeft ? x : w - x;
        final dart = ui.Path()
          ..moveTo(px + (fromLeft ? 16 : -16), y)
          ..lineTo(px - (fromLeft ? 12 : -12), y - 5)
          ..lineTo(px - (fromLeft ? 6 : -6), y)
          ..lineTo(px - (fromLeft ? 12 : -12), y + 5)
          ..close();
        c.drawPath(dart, _add(i % 7 == 0 ? b : a, f * 0.9));
      }
    case 16: // REBIRTH NOVA: phoenix wings, then the nova
      final spread = _out(t * 1.7);
      for (final side in const [-1.0, 1.0]) {
        for (int i = 0; i < 9; i += 1) {
          final k = i / 8;
          final angle = -0.25 - k * 1.2;
          final tip = o + ui.Offset(side * math.cos(angle), math.sin(angle)) * (120 + (1 - (k - 0.5).abs() * 2) * 110) * spread;
          c.drawLine(o, tip, _add(i.isEven ? a : b, f * 0.75, width: 9 * (1 - k * 0.5)));
          _glow(c, tip, 24, b, f * 0.8);
        }
      }
      final nova = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
      c.drawCircle(o, _out(nova) * h * 0.55, _add(b, (1 - nova) * (nova > 0 ? 1 : 0), width: 12 * (1 - nova) + 1));
      _glow(c, o, 130, a, f * 0.75);
    case 17: // FATE CAGE: bone bars slam down around each fated enemy
      final slam = _out(t * 3);
      final cages = targets.isEmpty ? [o] : targets.take(9).toList();
      for (final p in cages) {
        for (int i = -2; i <= 2; i += 1) {
          final x = p.dx + i * 15;
          final top = p.dy - 90 - (1 - slam) * 300;
          c.drawLine(ui.Offset(x, top), ui.Offset(x, top + 96), _add(a, f, width: 3.4));
        }
        c.drawLine(ui.Offset(p.dx - 38, p.dy + 6 - (1 - slam) * 300), ui.Offset(p.dx + 38, p.dy + 6 - (1 - slam) * 300), _add(a, f, width: 3));
        _glow(c, p.translate(0, -40), 44, b, f * 0.45);
      }
      c.drawCircle(o, 130 * slam, _add(b, f * 0.7, width: 1.6));
      _polygon(c, o, 130 * slam, 7, t * 3, _add(b, f * 0.6, width: 1.2));
    case 18: // RESONANCE: spectrum waves pulse through the screen
      for (int i = 0; i < 7; i += 1) {
        final wave = (t * 1.6 - i * 0.09).clamp(0.0, 1.0);
        if (wave <= 0 || wave >= 1) continue;
        final color = HSVColor.fromAHSV(1, (i * 52 + t * 260) % 360, 0.75, 1).toColor();
        c.drawCircle(o, _out(wave) * h * 0.75, _add(color, (1 - wave) * 0.85, width: 8 * (1 - wave) + 1.5));
      }
      for (int i = 0; i < 22; i += 1) {
        final x = i / 21 * w;
        final bar = (math.sin(t * 26 + i * 0.9).abs()) * 80 * f;
        c.drawLine(ui.Offset(x, o.dy - bar), ui.Offset(x, o.dy + bar), _add(i.isEven ? a : b, f * 0.55, width: 3));
      }
    default: // ORIGIN RESET: ink bursts, then everything wipes to white
      for (int i = 0; i < 26; i += 1) {
        final angle = r.nextDouble() * tau;
        final dist = (40 + r.nextDouble() * 320) * _out(t * 2.4);
        final p = o + ui.Offset(math.cos(angle), math.sin(angle)) * dist;
        c.drawCircle(p, 6 + r.nextDouble() * 28, ui.Paint()..color = ui.Color.fromRGBO(4, 4, 8, f * 0.92));
      }
      final wipe = ((t - 0.3) / 0.45).clamp(0.0, 1.0);
      c.drawCircle(o, _out(wipe) * h * 1.15, _add(const ui.Color(0xffffffff), (1 - wipe) * (wipe > 0 ? 0.95 : 0)));
      c.drawCircle(o, _out(wipe) * h * 1.15, _add(const ui.Color(0xffffffff), (1 - wipe), width: 5));
      for (int i = 0; i < 12; i += 1) {
        final angle = i / 12 * tau + t;
        c.drawLine(o, o + ui.Offset(math.cos(angle), math.sin(angle)) * h * _out(t * 1.5), _add(b, f * 0.5, width: 1));
      }
  }
  _p.blendMode = ui.BlendMode.srcOver;
}
