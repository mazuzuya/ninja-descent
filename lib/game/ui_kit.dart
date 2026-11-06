// Shared visual language: black lacquer panels, gold hairlines, vermilion ink.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Animation;
import 'package:flutter/scheduler.dart';

import 'atlas.dart';

const kGold = Color(0xffe0bd6a);
const kGoldDim = Color(0x66e0bd6a);
const kVermilion = Color(0xffc8232c);
const kPaper = Color(0xfff4e6c5);
const kMist = Color(0xff9fb0c5);
const kLacquerTop = Color(0xf2171019);
const kLacquerBottom = Color(0xfa08070e);

TextStyle inter(double size, {double weight = 500, Color color = kPaper, double spacing = 0}) => TextStyle(
      fontFamily: "Inter",
      fontSize: size,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: [ui.FontVariation.weight(weight)],
      color: color,
      letterSpacing: spacing * size,
      height: 1.2,
      decoration: TextDecoration.none,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

TextStyle trade(double size, {Color color = kPaper, List<Shadow>? shadows}) =>
    TextStyle(fontFamily: "TradeWinds", fontSize: size, color: color, height: 1.05, shadows: shadows, decoration: TextDecoration.none);

Path cutCorners(Rect r, double c) => Path()
  ..moveTo(r.left + c, r.top)
  ..lineTo(r.right - c, r.top)
  ..lineTo(r.right, r.top + c)
  ..lineTo(r.right, r.bottom - c)
  ..lineTo(r.right - c, r.bottom)
  ..lineTo(r.left + c, r.bottom)
  ..lineTo(r.left, r.bottom - c)
  ..lineTo(r.left, r.top + c)
  ..close();

class _PanelPainter extends CustomPainter {
  final double corner;
  final Color accent;
  final List<Color> fill;
  final bool ornate;
  _PanelPainter(this.corner, this.accent, this.fill, this.ornate);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = cutCorners(rect, corner);
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill).createShader(rect));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent);
    if (!ornate) return;
    canvas.drawPath(cutCorners(rect.deflate(4), math.max(0, corner - 2)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = accent.withValues(alpha: 0.28));
    final dot = Paint()..color = accent;
    for (final c in [Offset(corner * 0.5, corner * 0.5), Offset(size.width - corner * 0.5, corner * 0.5), Offset(corner * 0.5, size.height - corner * 0.5), Offset(size.width - corner * 0.5, size.height - corner * 0.5)]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRect(const Rect.fromLTWH(-1.6, -1.6, 3.2, 3.2), dot);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PanelPainter old) => old.corner != corner || old.accent != accent || old.ornate != ornate;
}

class LacquerPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double corner;
  final Color accent;
  final bool ornate;
  final List<Color> fill;
  const LacquerPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.corner = 12, this.accent = kGoldDim, this.ornate = true, this.fill = const [kLacquerTop, kLacquerBottom]});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PanelPainter(corner, accent, fill, ornate),
        child: Padding(padding: padding, child: child),
      );
}

// `button:active` feedback, a little stronger than the CSS.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const Pressable({super.key, required this.onTap, required this.child});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapUp: widget.onTap == null ? null : (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? 0.95 : 1, duration: const Duration(milliseconds: 70), curve: Curves.easeOut, child: widget.child),
      );
}

class InkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double height;
  final double fontSize;
  final bool expand;
  const InkButton({super.key, required this.label, required this.onTap, this.primary = true, this.height = 50, this.fontSize = 15, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: inter(fontSize, weight: 800, spacing: 0.08, color: enabled ? const Color(0xfffff3d4) : const Color(0x88fff3d4)));
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: LacquerPanel(
          corner: 9,
          ornate: false,
          accent: enabled ? (primary ? kGold : kGoldDim) : const Color(0x33e0bd6a),
          fill: !enabled
              ? const [Color(0xcc1a1a22), Color(0xcc101016)]
              : primary
                  ? const [Color(0xffa81e2a), Color(0xff5c0e18)]
                  : const [Color(0xee1d1a26), Color(0xee0c0b12)],
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Center(widthFactor: 1, child: text),
        ),
      ),
    );
  }
}

// A sumi-e brush stroke with rough ends; `reveal` wipes it in from the left.
class BrushBand extends StatelessWidget {
  final Color color;
  final double reveal;
  final Widget? child;
  const BrushBand({super.key, required this.color, this.reveal = 1, this.child});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BrushPainter(color, reveal), child: child);
}

class _BrushPainter extends CustomPainter {
  final Color color;
  final double reveal;
  _BrushPainter(this.color, this.reveal);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, -20, size.width * reveal, size.height + 40));
    final r = math.Random(7);
    final w = size.width, h = size.height;
    final top = <Offset>[], bottom = <Offset>[];
    const steps = 26;
    for (int i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final taper = math.min(1.0, math.min(t, 1 - t) * 7);
      final inset = h * 0.5 * (1 - taper);
      top.add(Offset(t * w, inset + r.nextDouble() * h * 0.06));
      bottom.add(Offset(t * w, h - inset - r.nextDouble() * h * 0.06));
    }
    final path = Path()..moveTo(top.first.dx, top.first.dy);
    for (final p in top) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in bottom.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    // Dry-brush streaks that break up the ends.
    final streak = Paint()
      ..color = color.withValues(alpha: color.a * 0.65)
      ..strokeWidth = 1.2;
    for (int i = 0; i < 16; i += 1) {
      final y = h * (0.12 + r.nextDouble() * 0.76);
      final len = w * (0.04 + r.nextDouble() * 0.08);
      canvas.drawLine(Offset(w - len * 0.2, y), Offset(w + len * 0.45, y), streak);
      canvas.drawLine(Offset(-len * 0.45, y), Offset(len * 0.2, y), streak);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrushPainter old) => old.color != color || old.reveal != reveal;
}

// Red hanko seal.
class Hanko extends StatelessWidget {
  final String text;
  final double size;
  final double angle;
  const Hanko(this.text, {super.key, this.size = 44, this.angle = -0.09});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kVermilion,
            borderRadius: BorderRadius.circular(size * 0.14),
            border: Border.all(color: const Color(0xffff8a7a), width: 1),
            boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: FittedBox(
            child: Padding(
              padding: EdgeInsets.all(size * 0.08),
              child: Text(text, style: TextStyle(fontSize: size * 0.62, color: const Color(0xfffff0e0), fontWeight: FontWeight.w700, height: 1, decoration: TextDecoration.none)),
            ),
          ),
        ),
      );
}

class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon(this.size, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xff6e3d0c)),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xfffff0a7), Color(0xffc77b16)]),
        ),
      );
}

// Bar whose fill snaps quickly and whose pale "chip" drains after it, so a big
// hit reads at a glance.
class ChipBar extends StatelessWidget {
  final double ratio;
  final double height;
  final List<Color> colors;
  final Color track;
  const ChipBar({super.key, required this.ratio, required this.height, required this.colors, this.track = const Color(0xcc05060c)});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    Widget bar(double value, Decoration decoration) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(decoration: decoration),
        );
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: track, borderRadius: radius, border: Border.all(color: kGoldDim)),
      child: Stack(fit: StackFit.expand, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: ratio),
          duration: const Duration(milliseconds: 620),
          curve: const Interval(0.3, 1, curve: Curves.easeOut),
          builder: (context, value, _) => bar(value, const BoxDecoration(color: Color(0xddfff0d8))),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(end: ratio),
          duration: const Duration(milliseconds: 110),
          builder: (context, value, _) => bar(value, BoxDecoration(gradient: LinearGradient(colors: colors))),
        ),
      ]),
    );
  }
}

// Plays one sprite animation from an atlas. The atlas decodes on first draw and
// is released again by GameAssets.sweep once nothing draws it.
class SkinSprite extends StatefulWidget {
  final Atlas atlas;
  final String animation;
  final double fps;
  final Alignment alignment;
  const SkinSprite({super.key, required this.atlas, this.animation = "idle", this.fps = 3.3, this.alignment = Alignment.bottomCenter});

  @override
  State<SkinSprite> createState() => _SkinSpriteState();
}

class _SkinSpriteState extends State<SkinSprite> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMilliseconds / 1000)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _SpritePainter(widget.atlas, widget.animation, widget.fps, widget.alignment, _time), size: Size.infinite));
}

class _SpritePainter extends CustomPainter {
  final Atlas atlas;
  final String animation;
  final double fps;
  final Alignment alignment;
  final ValueNotifier<double> time;
  _SpritePainter(this.atlas, this.animation, this.fps, this.alignment, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final image = atlas.image;
    final anim = atlas.anim(animation);
    if (image == null || anim == null || anim.frames.isEmpty) return;
    final frame = anim.frames[(time.value * fps).floor() % anim.frames.length];
    final crop = frame.content;
    final scale = math.min(size.width / crop.width, size.height / anim.maxHeight);
    final w = crop.width * scale, h = crop.height * scale;
    final x = (size.width - w) * (alignment.x + 1) / 2;
    final y = (size.height - h) * (alignment.y + 1) / 2;
    canvas.drawImageRect(image, crop, Rect.fromLTWH(x, y, w, h), Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_SpritePainter old) => old.atlas != atlas || old.animation != animation;
}

// Loops a 0→1 value, for ready-glows and breathing elements.
class Pulse extends StatefulWidget {
  final Duration period;
  final Widget Function(BuildContext context, double t) builder;
  const Pulse({super.key, this.period = const Duration(milliseconds: 1400), required this.builder});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, math.sin(_c.value * 2 * math.pi) * 0.5 + 0.5));
}

// Fade + small rise when a screen appears.
class Reveal extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double rise;
  const Reveal({super.key, required this.child, this.duration = const Duration(milliseconds: 260), this.rise = 14});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: child)),
      );
}

// conic-gradient cooldown wipe.
class CooldownSweep extends CustomPainter {
  final double ratio;
  CooldownSweep(this.ratio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(Offset.zero & size, -math.pi / 2, ratio.clamp(0.0, 1.0) * 2 * math.pi, true, Paint()..color = const Color(0xd102040a));
  }

  @override
  bool shouldRepaint(CooldownSweep old) => old.ratio != ratio;
}
