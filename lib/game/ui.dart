// Flutter overlay UI. Follows the structure of game js/game/ui.js (HUD, start,
// pause, shop, end) and adds a main menu, settings, tutorial, announcements and
// a results screen. Sizes follow the CSS container units: cw(4) ≈ 4cqw.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Animation;

import 'data.dart';
import 'fx.dart' show paletteColor, rarityOf;
import 'game.dart';
import 'notifier.dart';
import 'ui_kit.dart';

class _Box {
  final double w;
  final double h;
  const _Box(this.w, this.h);
  double cw(double v) => w * v / 100;
  double ch(double v) => h * v / 100;
  bool get landscape => w >= h;
}

class GameUI extends StatelessWidget {
  final NinjaGame game;
  const GameUI({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    return LayoutBuilder(builder: (context, constraints) {
      final box = _Box(constraints.maxWidth, constraints.maxHeight);
      return ListenableBuilder(
        listenable: n,
        builder: (context, _) => Stack(fit: StackFit.expand, children: [
          if (!n.startVisible && !n.tutorialVisible) SafeArea(child: LayoutBuilder(builder: (context, inner) => _Hud(game: game, box: _Box(inner.maxWidth, inner.maxHeight)))),
          if (!n.startVisible) _Announcer(item: n.announcement, box: box),
          if (!n.startVisible) _Announcer(item: n.toast, box: box),
          if (!n.startVisible) _Announcer(item: n.ultCut, box: box, game: game),
          if (n.startVisible) _MenuScreen(game: game, box: box),
          if (n.pauseVisible) _PauseScreen(game: game, box: box),
          if (n.endVisible) _EndScreen(key: ValueKey(n.endStats), game: game, box: box),
          if (n.shopVisible) _ShopScreen(game: game, box: box),
          if (n.settingsVisible) _SettingsScreen(game: game, box: box),
          if (n.tutorialVisible) _TutorialScreen(game: game, box: box),
        ]),
      );
    });
  }
}

class _Scrim extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  const _Scrim({required this.child, this.colors = const [Color(0xb803040a), Color(0xe003040a)]});

  @override
  Widget build(BuildContext context) => Reveal(
        rise: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)),
            child: SafeArea(child: child),
          ),
        ),
      );
}

// ---------------------------------------------------------------- HUD ---

class _Hud extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _Hud({required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    final b = box;
    final pad = (b.w * 0.022).clamp(8.0, 14.0);
    const barTop = 66.0;
    return Stack(children: [
      const Positioned(
        top: -60,
        left: 0,
        right: 0,
        height: 180,
        child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xd902030a), Color(0x0002030a)])))),
      ),
      const Positioned(
        bottom: -40,
        left: 0,
        right: 0,
        height: 170,
        child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xc002030a), Color(0x0002030a)])))),
      ),
      Positioned(
        top: pad,
        left: pad,
        right: pad,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: IgnorePointer(child: _vitals(n, b))),
          const SizedBox(width: 8),
          IgnorePointer(child: _score(n, b)),
          const SizedBox(width: 8),
          Pressable(onTap: game.pauseGame, child: _pauseButton()),
        ]),
      ),
      Positioned(
        top: pad + barTop,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Column(children: [
            if (n.bossVisible) _bossBar(n, b) else _areaStrip(n, b),
            const SizedBox(height: 5),
            if (!n.bossVisible)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: b.w * 0.72),
                child: Text(n.mechanic, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: inter((b.cw(2.5)).clamp(8.5, 11.0), weight: 800, color: const Color(0xcc9fb4cc), spacing: 0.1)),
              ),
            if (n.buffVisible) ...[
              const SizedBox(height: 5),
              _buffChip(n, b),
            ],
          ]),
        ),
      ),
      if (n.comboVisible) Positioned(top: b.h * 0.27, right: pad, child: IgnorePointer(child: _Combo(combo: n.combo, ratio: n.comboRatio, box: b))),
      if (n.debugVisible)
        Positioned(
          top: b.ch(24),
          left: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xcc000000),
              child: Text(n.debug, style: const TextStyle(color: Color(0xff9effa0), fontSize: 12, fontFamily: "monospace", decoration: TextDecoration.none)),
            ),
          ),
        ),
      if (n.descendHint)
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Pulse(
                builder: (context, t) => Opacity(
                  opacity: 0.55 + 0.45 * t,
                  child: Text("↓  GESER BAWAH UNTUK TURUN", style: inter(11.5, weight: 800, color: const Color(0xffffe6aa), spacing: 0.1).copyWith(shadows: const [Shadow(color: Color(0xff000000), blurRadius: 4)])),
                ),
              ),
            ),
          ),
        ),
      _controls(n, b),
    ]);
  }

  Widget _vitals(GameNotifier n, _Box b) {
    final assets = game.gameAssets;
    const portrait = 52.0;
    final lowHp = n.hpRatio < 0.35;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: portrait,
        height: portrait,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: lowHp ? const Color(0xffff5a5a) : kGold, width: 1.6),
          gradient: const RadialGradient(colors: [Color(0xff3a1520), Color(0xff0b0810)]),
        ),
        child: assets == null
            ? null
            : FutureBuilder<ui.Image?>(
                key: ValueKey(n.skinIndex),
                future: assets.skinPreview(n.skinIndex),
                builder: (context, snap) => snap.data == null
                    ? const SizedBox.shrink()
                    : Transform.scale(scale: 2.1, alignment: const Alignment(0, -0.62), child: RawImage(image: snap.data, fit: BoxFit.cover, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium)),
              ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Stack(alignment: Alignment.center, children: [
              ChipBar(ratio: n.hpRatio, height: 15, colors: lowHp ? const [Color(0xff7c0f22), Color(0xffff4a4a)] : const [Color(0xffb61938), Color(0xfff04f51), Color(0xffffbd52)]),
              Text("${n.hp}/${n.maxHp}", style: inter(9.5, weight: 800, color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const CoinIcon(13),
            const SizedBox(width: 5),
            Flexible(child: Text(formatId(n.coins), maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13, weight: 800, color: const Color(0xffffe2a0)))),
          ]),
        ]),
      ),
    ]);
  }

  Widget _score(GameNotifier n, _Box b) => ConstrainedBox(
        constraints: BoxConstraints(minWidth: 86, maxWidth: math.max(90, b.w * 0.3)),
        child: LacquerPanel(
          corner: 8,
          ornate: false,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("SKOR", style: inter(8.5, weight: 700, color: kMist, spacing: 0.16)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(formatId(n.score), style: trade((b.cw(5.2)).clamp(17.0, 24.0), color: const Color(0xfffff5cf)))),
          ]),
        ),
      );

  Widget _pauseButton() => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xc7090810), border: Border.all(color: kGoldDim)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < 2; i += 1) Container(width: 4, height: 15, margin: const EdgeInsets.symmetric(horizontal: 2), color: kPaper),
        ]),
      );

  Widget _areaStrip(GameNotifier n, _Box b) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: b.w * 0.74),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(n.area, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter((b.cw(3)).clamp(10.5, 13.0), weight: 800, color: const Color(0xffe5edf7), spacing: 0.02).copyWith(shadows: const [Shadow(color: Color(0xcc000000), blurRadius: 4, offset: Offset(0, 1))])),
          const SizedBox(height: 4),
          SizedBox(
            width: b.w * 0.5,
            height: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Color(0x66ffffff)),
                FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: n.floorRatio, child: const ColoredBox(color: kGold)),
              ]),
            ),
          ),
        ]),
      );

  Widget _bossBar(GameNotifier n, _Box b) => Reveal(
        child: SizedBox(
          width: math.min(b.w * 0.86, 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text(n.bossName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: trade(15, color: const Color(0xffffc9c0), shadows: const [Shadow(color: Color(0xff000000), blurRadius: 4)]))),
              for (int i = 1; i <= 3; i += 1)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 4),
                  transform: Matrix4.rotationZ(math.pi / 4),
                  color: i <= n.bossPhase ? const Color(0xffff4a4a) : const Color(0x55ffffff),
                ),
            ]),
            const SizedBox(height: 4),
            ChipBar(ratio: n.bossRatio, height: 11, colors: const [Color(0xffffb23e), Color(0xffcf2f48)]),
          ]),
        ),
      );

  Widget _buffChip(GameNotifier n, _Box b) => Container(
        constraints: BoxConstraints(maxWidth: b.w * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xd1412305), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0x80ffd365))),
        child: Text(n.buff, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter((b.cw(2.5)).clamp(9.0, 11.0), weight: 800, color: const Color(0xffffe19a))),
      );

  Widget _controls(GameNotifier n, _Box b) {
    final narrow = b.w <= 350;
    final size = narrow ? 60.0 : b.cw(18).clamp(62.0, 76.0);
    final side = narrow ? 8.0 : b.cw(3.5).clamp(12.0, 24.0);
    return Positioned(
      left: side,
      right: side,
      bottom: 12,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Pressable(
          onTap: game.dash,
          child: _SkillButton(size: size, box: b, glyph: "術", label: n.skillLabel, cooldown: n.dashCd, cooldownText: n.dashCdText, colors: const [Color(0xc06a4bb0), Color(0xf007060f)], ready: n.dashCdText.isEmpty),
        ),
        const SizedBox(width: 8),
        Expanded(child: Center(child: Pressable(onTap: game.openShop, child: _shopButton(n, narrow)))),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Pressable(
            onTap: game.slash,
            child: _SkillButton(size: size * 0.72, box: b, glyph: "斬", label: "", cooldown: n.slashCd, cooldownText: "", colors: const [Color(0xc0b08a34), Color(0xf00d0a06)]),
          ),
          const SizedBox(height: 8),
          Pressable(
            onTap: () => game.fastFall(true),
            child: _SkillButton(size: size, box: b, glyph: "↓", label: "POUND", colors: const [Color(0xc0b5402a), Color(0xf00d0810)]),
          ),
        ]),
      ]),
    );
  }

  Widget _shopButton(GameNotifier n, bool narrow) => LacquerPanel(
        corner: 7,
        ornate: false,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("TOKO", style: inter(9, weight: 800, color: const Color(0xffffd36b), spacing: 0.16)),
          Text(n.skinName, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(narrow ? 10 : 12, weight: 800, color: const Color(0xfff6e6b8))),
          Text(n.passive, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(9, color: const Color(0xff92b6d6))),
        ]),
      );
}

class _Combo extends StatelessWidget {
  final int combo;
  final double ratio;
  final _Box box;
  const _Combo({required this.combo, required this.ratio, required this.box});

  @override
  Widget build(BuildContext context) {
    final hot = combo >= 8;
    return TweenAnimationBuilder<double>(
      key: ValueKey(combo),
      tween: Tween(begin: 1.4, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, alignment: Alignment.centerRight, child: child),
      child: Transform.rotate(
        angle: -0.05,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text("x$combo", style: trade((box.cw(8)).clamp(26.0, 40.0), color: hot ? const Color(0xffffd65a) : const Color(0xfffff2d3), shadows: const [Shadow(color: Color(0xffa1122c), offset: Offset(0, 3))])),
          Text("COMBO", style: inter(9, weight: 800, color: const Color(0xffff9aa6), spacing: 0.24)),
          const SizedBox(height: 3),
          SizedBox(
            width: 58,
            height: 3,
            child: FractionallySizedBox(alignment: Alignment.centerRight, widthFactor: ratio, child: const ColoredBox(color: Color(0xffef4667))),
          ),
        ]),
      ),
    );
  }
}

class _SkillButton extends StatelessWidget {
  final double size;
  final _Box box;
  final String glyph;
  final String label;
  final double cooldown;
  final String cooldownText;
  final List<Color> colors;
  final bool ready;
  const _SkillButton({required this.size, required this.box, required this.glyph, required this.label, required this.colors, this.cooldown = 0, this.cooldownText = "", this.ready = false});

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xb3d3bd85), width: 1.6),
        gradient: RadialGradient(center: const Alignment(-0.3, -0.5), radius: 0.9, colors: colors),
        boxShadow: const [BoxShadow(color: Color(0xcc000000), offset: Offset(0, 3), blurRadius: 3)],
      ),
      child: ClipOval(
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(glyph, style: TextStyle(fontSize: size * (label.isEmpty ? 0.46 : 0.38), height: 1, color: const Color(0xfff5ecd6), decoration: TextDecoration.none)),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size * 0.115, weight: 800, color: const Color(0xffc5d0de))),
              ],
            ]),
          ),
          if (cooldown > 0)
            CustomPaint(
              painter: CooldownSweep(cooldown),
              child: Center(child: Text(cooldownText, style: inter(size * 0.3, weight: 800, color: Colors.white))),
            ),
        ]),
      ),
    );
    if (!ready) return body;
    return Pulse(
      builder: (context, t) => DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color.fromRGBO(170, 130, 255, 0.25 + 0.4 * t), blurRadius: 8 + 10 * t, spreadRadius: 1)]),
        child: body,
      ),
    );
  }
}

// -------------------------------------------------------- announcements ---

class _Announcer extends StatefulWidget {
  final Announcement? item;
  final _Box box;
  final NinjaGame? game;
  const _Announcer({required this.item, required this.box, this.game});

  @override
  State<_Announcer> createState() => _AnnouncerState();
}

class _AnnouncerState extends State<_Announcer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  Duration _durationFor(String kind) => switch (kind) { "ult" => const Duration(milliseconds: 950), "boss" => const Duration(milliseconds: 2400), "powerup" => const Duration(milliseconds: 1700), _ => const Duration(milliseconds: 2100) };

  void _play() {
    final item = widget.item;
    if (item == null) {
      _c.stop();
      _c.value = 0;
      return;
    }
    _c.duration = _durationFor(item.kind);
    _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(_Announcer old) {
    super.didUpdateWidget(old);
    if (old.item?.id != widget.item?.id) _play();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (!_c.isAnimating) return const SizedBox.shrink();
            final seconds = _c.value * _c.duration!.inMilliseconds / 1000;
            final total = _c.duration!.inMilliseconds / 1000;
            final wipe = Curves.easeOutCubic.transform((seconds / 0.26).clamp(0.0, 1.0));
            final fade = (total - seconds) < 0.3 ? (total - seconds) / 0.3 : 1.0;
            final textIn = Curves.easeOutBack.transform(((seconds - 0.1) / 0.3).clamp(0.0, 1.0));
            return Opacity(opacity: fade.clamp(0.0, 1.0), child: item.kind == "ult" ? _ultCut(item, seconds, total) : item.kind == "powerup" ? _toast(item, wipe, textIn) : _banner(item, wipe, textIn));
          },
        ),
      ),
    );
  }

  Widget _banner(Announcement item, double wipe, double textIn) {
    final b = widget.box;
    final boss = item.kind == "boss";
    final clear = item.kind == "clear";
    final color = boss ? const Color(0xf08f0f1f) : clear ? const Color(0xf0a67b1e) : const Color(0xf00b0a12);
    final titleSize = (b.cw(boss ? 7.6 : 9)).clamp(22.0, 44.0);
    return Align(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: b.w,
        height: titleSize * 2.9,
        child: BrushBand(
          color: color,
          reveal: wipe,
          child: Center(
            child: Opacity(
              opacity: textIn.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(-22 * (1 - textIn), 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (boss) Text("⚠  ${item.subtitle}  ⚠", style: inter(10.5, weight: 800, color: const Color(0xffffc9c0), spacing: 0.24)),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(item.title.toUpperCase(), maxLines: 1, style: trade(titleSize, color: const Color(0xfffff3d4), shadows: const [Shadow(color: Color(0xcc000000), offset: Offset(0, 2))]))),
                    if (!boss) Text(item.subtitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(11.5, weight: 800, color: clear ? const Color(0xfffff0b9) : kGold, spacing: 0.22)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Character cut-in: slides across, holds, leaves the other way.
  Widget _ultCut(Announcement item, double seconds, double total) {
    final b = widget.box;
    final inT = Curves.easeOutCubic.transform((seconds / 0.16).clamp(0.0, 1.0));
    final outT = Curves.easeInCubic.transform(((seconds - total + 0.2) / 0.2).clamp(0.0, 1.0));
    final color = paletteColor(item.skin, secondary: true);
    final accent = paletteColor(item.skin);
    final assets = widget.game?.gameAssets;
    final height = (b.cw(30)).clamp(96.0, 140.0);
    return Align(
      alignment: const Alignment(0, 0.42),
      child: Transform.translate(
        offset: Offset(-b.w * (1 - inT) + b.w * outT, 0),
        child: Transform.rotate(
          angle: -0.05,
          child: SizedBox(
            width: b.w * 1.1,
            height: height,
            child: BrushBand(
              color: Color.lerp(const Color(0xf00a0812), color, 0.5)!,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: b.w * 0.08),
                child: Row(children: [
                  SizedBox(
                    width: height,
                    height: height,
                    child: assets == null
                        ? null
                        : FutureBuilder<ui.Image?>(
                            future: assets.skinPreview(item.skin),
                            builder: (context, snap) => snap.data == null ? const SizedBox.shrink() : RawImage(image: snap.data, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.subtitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(10.5, weight: 800, color: accent, spacing: 0.2)),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(item.title, maxLines: 1, style: trade((b.cw(8)).clamp(24.0, 40.0), color: const Color(0xfffff6e0), shadows: [Shadow(color: accent, blurRadius: 14)]))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toast(Announcement item, double wipe, double textIn) {
    final b = widget.box;
    return Align(
      alignment: const Alignment(0, 0.3),
      child: Transform.scale(
        scale: 0.8 + 0.2 * textIn,
        child: Opacity(
          opacity: wipe,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: b.w * 0.8),
            child: LacquerPanel(
              corner: 8,
              accent: kGold,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: trade(18, color: const Color(0xffffe6aa))),
                if (item.subtitle.isNotEmpty) Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(11, color: const Color(0xffd5dde8))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ main menu ---

class _MenuScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _MenuScreen({required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    final b = box;
    final assets = game.gameAssets;
    final titleSize = (b.landscape ? b.ch(9) : b.cw(11)).clamp(28.0, 56.0);
    final skin = SKINS[n.selectedSkin];
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xe603040c), Color(0x9903040c), Color(0xf503040c)], stops: [0, 0.45, 1])),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Column(children: [
            if (n.startEnabled)
              Row(children: [
                _stat("TERBAIK", formatId(n.best)),
                const Spacer(),
                Row(children: [const CoinIcon(16), const SizedBox(width: 6), Text(formatId(n.shopBalance), style: inter(16, weight: 800, color: const Color(0xffffe2a0)))]),
              ]),
            const Spacer(flex: 2),
            Reveal(
              duration: const Duration(milliseconds: 600),
              rise: 26,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xfffff7dc), Color(0xffe9bf66), Color(0xffb07a2a)], stops: [0, 0.55, 1]).createShader(r),
                    child: Text("NINJA\nDESCENT", textAlign: TextAlign.center, style: trade(titleSize, color: Colors.white, shadows: const [Shadow(color: Color(0xff26070b), offset: Offset(0, 4))])),
                  ),
                  Positioned(right: -titleSize * 0.42, top: -titleSize * 0.2, child: Hanko("忍", size: titleSize * 0.72)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: titleSize * 5.2,
                  height: titleSize * 0.72,
                  child: BrushBand(
                    color: const Color(0xee8f0f1f),
                    child: Center(child: Text("ABYSS BAZAAR", style: inter((titleSize * 0.27).clamp(10.0, 15.0), weight: 800, color: const Color(0xfffff0e0), spacing: 0.3))),
                  ),
                ),
              ]),
            ),
            const Spacer(),
            Expanded(
              flex: 9,
              child: Stack(alignment: Alignment.bottomCenter, children: [
                // Blood moon behind the hero.
                Positioned.fill(child: Pulse(period: const Duration(milliseconds: 5200), builder: (context, t) => CustomPaint(painter: _MoonPainter(t)))),
                if (assets != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: SkinSprite(key: ValueKey(n.selectedSkin), atlas: assets.skins[n.selectedSkin].motion)),
              ]),
            ),
            const SizedBox(height: 8),
            if (n.startEnabled) ...[
              Text(skin.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: trade(19, color: const Color(0xffffe6aa))),
              const SizedBox(height: 2),
              Text("${skin.weapon} · ${skin.skill}", maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(11, color: kMist)),
              const SizedBox(height: 14),
              Reveal(
                duration: const Duration(milliseconds: 500),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Pulse(
                      builder: (context, t) => DecoratedBox(
                        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(220, 50, 50, 0.16 + 0.26 * t), blurRadius: 14 + 12 * t)]),
                        child: InkButton(label: "MULAI TURUN", height: 58, fontSize: 18, expand: true, onTap: game.startGame),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: InkButton(label: "TOKO", primary: false, onTap: game.openShop)),
                      const SizedBox(width: 10),
                      Expanded(child: InkButton(label: "PENGATURAN", primary: false, fontSize: 13, onTap: game.openSettings)),
                    ]),
                  ]),
                ),
              ),
            ] else ...[
              _loading(n, b),
              const SizedBox(height: 40),
            ],
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: inter(9, weight: 800, color: kMist, spacing: 0.18)),
        Text(value, style: trade(18, color: const Color(0xfffff5cf))),
      ]);

  Widget _loading(GameNotifier n, _Box b) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(n.startStatus, textAlign: TextAlign.center, style: inter(13, weight: 700, color: const Color(0xffd8dde6), spacing: 0.08)),
        const SizedBox(height: 10),
        SizedBox(
          width: b.w * 0.5,
          child: const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(minHeight: 3, color: kGold, backgroundColor: Color(0x33ffffff)),
          ),
        ),
      ]);
}

class _MoonPainter extends CustomPainter {
  final double breath;
  _MoonPainter(this.breath);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) * 0.4 + breath * 4;
    final center = Offset(size.width / 2, size.height * 0.5);
    canvas.drawCircle(center, radius * 1.5, Paint()..shader = RadialGradient(colors: [Color.fromRGBO(200, 30, 50, 0.3 + 0.14 * breath), const Color(0x00c81e32)]).createShader(Rect.fromCircle(center: center, radius: radius * 1.5)));
    canvas.drawCircle(center, radius, Paint()..shader = const RadialGradient(colors: [Color(0xffd13b3b), Color(0xff8c1423)]).createShader(Rect.fromCircle(center: center, radius: radius)));
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.breath != breath;
}

// ---------------------------------------------------------- pause / misc ---

class _PauseScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _PauseScreen({required this.game, required this.box});

  @override
  Widget build(BuildContext context) => _Scrim(
        child: Center(
          child: Reveal(
            child: SizedBox(
              width: math.min(box.w * 0.82, 360),
              child: LacquerPanel(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Hanko("止", size: 40),
                  const SizedBox(height: 12),
                  Text("DIAM DALAM BAYANGAN", textAlign: TextAlign.center, style: trade((box.cw(5.4)).clamp(18.0, 26.0), color: const Color(0xffefe0ba))),
                  const SizedBox(height: 20),
                  InkButton(label: "LANJUT", expand: true, onTap: game.resumeGame),
                  const SizedBox(height: 10),
                  InkButton(label: "ULANGI RUN", primary: false, expand: true, onTap: game.retryGame),
                  const SizedBox(height: 10),
                  InkButton(label: "PENGATURAN", primary: false, expand: true, onTap: game.openSettings),
                  const SizedBox(height: 10),
                  InkButton(label: "MENU UTAMA", primary: false, expand: true, onTap: game.backToMenu),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _SettingsScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _SettingsScreen({required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    return _Scrim(
      child: Center(
        child: Reveal(
          child: SizedBox(
            width: math.min(box.w * 0.86, 380),
            child: LacquerPanel(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("PENGATURAN", style: trade(24, color: const Color(0xffffe6aa))),
                const SizedBox(height: 14),
                _Toggle(label: "Efek Suara", value: n.sfxOn, onChanged: (v) => game.updateSettings(sfx: v)),
                _Toggle(label: "Musik", value: n.musicOn, onChanged: (v) => game.updateSettings(music: v)),
                _Toggle(label: "Getar", value: n.hapticsOn, onChanged: (v) => game.updateSettings(haptics: v)),
                _Toggle(label: "Mode Hemat Efek", hint: "Lebih ringan untuk HP lama, tanpa guncangan layar", value: n.lowEffects, onChanged: (v) => game.updateSettings(low: v)),
                const SizedBox(height: 14),
                InkButton(label: "CARA MAIN", primary: false, expand: true, onTap: game.showTutorial),
                const SizedBox(height: 10),
                InkButton(label: "TUTUP", expand: true, onTap: game.closeSettings),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.label, required this.value, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: inter(14, weight: 700)),
                if (hint != null) Text(hint!, style: inter(10, color: kMist)),
              ]),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 46,
              height: 26,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(color: value ? const Color(0xff8f1a26) : const Color(0xff1b1b24), borderRadius: BorderRadius.circular(13), border: Border.all(color: value ? kGold : kGoldDim)),
              child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: value ? const Color(0xfffff0c8) : const Color(0xff7e8391))),
            ),
          ]),
        ),
      );
}

class _TutorialScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _TutorialScreen({required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    Widget row(String glyph, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xff1a1420), border: Border.all(color: kGoldDim), borderRadius: BorderRadius.circular(6)),
              child: Text(glyph, style: const TextStyle(fontSize: 18, color: kPaper, height: 1, decoration: TextDecoration.none)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: inter(13, weight: 800, color: const Color(0xffffe6aa))),
                Text(text, style: inter(11.5, color: const Color(0xffc6d0dc))),
              ]),
            ),
          ]),
        );
    return _Scrim(
      child: Center(
        child: Reveal(
          child: SizedBox(
            width: math.min(box.w * 0.9, 400),
            child: LacquerPanel(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("JALAN NINJA", style: trade(24, color: const Color(0xffffe6aa))),
                const SizedBox(height: 4),
                Text("Kamu yang menentukan kapan turun. Pilih platform yang aman.", textAlign: TextAlign.center, style: inter(11.5, color: kMist)),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      row("↔", "GESER KIRI / KANAN", "Pindah lajur, hindari duri & jebakan"),
                      row("●", "KETUK / TAHAN", "Tembak. Tahan lalu lepas: tembakan kuat"),
                      row("斬", "GESER ATAS", "Tebasan jarak dekat"),
                      row("↓", "GESER BAWAH", "Turun satu lantai. Dua kali: pound pemecah lantai"),
                      row("術", "TOMBOL JURUS", "Jurus khas tiap skin, ada waktu tunggu"),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                InkButton(label: "SIAP", expand: true, onTap: game.closeTutorial),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- results ---

class _EndScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _EndScreen({super.key, required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    final stats = n.endStats;
    final b = box;
    if (stats == null) return const SizedBox.shrink();
    final accent = stats.victory ? const Color(0xfff2c457) : const Color(0xffff6470);
    Widget cell(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: trade(19, color: const Color(0xfffff0d0))),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(8.5, weight: 800, color: kMist, spacing: 0.12)),
          ]),
        );
    return _Scrim(
      colors: const [Color(0x8c0c0206), Color(0xeb040208)],
      child: Center(
        child: Reveal(
          duration: const Duration(milliseconds: 420),
          rise: 30,
          child: SizedBox(
            width: math.min(b.w * 0.88, 400),
            child: LacquerPanel(
              accent: accent.withValues(alpha: 0.6),
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: double.infinity,
                  height: 16,
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Text(stats.victory ? "KEMENANGAN" : "RUN BERAKHIR", style: inter(10.5, weight: 800, color: kMist, spacing: 0.3)),
                    if (stats.newBest)
                      Positioned(
                        right: -2,
                        top: -10,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 2.4, end: 1),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInCubic,
                          builder: (context, s, child) => Transform.scale(scale: s, child: child),
                          child: const Hanko("新", size: 38, angle: 0.2),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(n.endTitle, textAlign: TextAlign.center, style: trade((b.cw(7)).clamp(22.0, 32.0), color: accent)),
                const SizedBox(height: 16),
                Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text("SKOR", style: inter(10, weight: 800, color: kMist, spacing: 0.22)),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: stats.score.toDouble()),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(formatId(v), style: trade((b.cw(11)).clamp(34.0, 50.0), color: const Color(0xfffff0b9))),
                    ),
                  ]),
                ]),
                const SizedBox(height: 4),
                Text(stats.newBest ? "REKOR BARU!" : "TERBAIK ${formatId(stats.best)}", style: inter(11.5, weight: 800, color: stats.newBest ? const Color(0xffffd65a) : kMist, spacing: 0.08)),
                const SizedBox(height: 16),
                Container(height: 1, color: kGoldDim),
                const SizedBox(height: 12),
                Row(children: [cell("AREA", "${stats.area}/20"), cell("LANTAI", "${stats.floor}"), cell("MUSUH", formatId(stats.kills))]),
                const SizedBox(height: 12),
                Row(children: [cell("COMBO", "x${stats.maxCombo}"), cell("BOSS", "${stats.bossKills}"), cell("KOIN", "+${formatId(stats.coins)}")]),
                const SizedBox(height: 18),
                InkButton(label: stats.victory ? "TURUN LAGI" : "COBA LAGI", height: 54, fontSize: 17, expand: true, onTap: game.retryGame),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: InkButton(label: "TOKO", primary: false, onTap: game.openShop)),
                  const SizedBox(width: 10),
                  Expanded(child: InkButton(label: "MENU", primary: false, onTap: game.backToMenu)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- shop ---

class _ShopScreen extends StatelessWidget {
  final NinjaGame game;
  final _Box box;
  const _ShopScreen({required this.game, required this.box});

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    final b = box;
    return Reveal(
      rise: 0,
      child: ColoredBox(
        color: const Color(0xf201030a),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              _header(n, b),
              const SizedBox(height: 8),
              _hero(n, b),
              const SizedBox(height: 8),
              Expanded(child: _grid(n, b)),
              const SizedBox(height: 8),
              _footer(n, b),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(GameNotifier n, _Box b) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("ABYSS BAZAAR", maxLines: 1, overflow: TextOverflow.ellipsis, style: trade((b.cw(5.6)).clamp(17.0, 25.0), color: const Color(0xffffe6aa))),
            Text("20 WUJUD · 20 JURUS", style: inter(9, weight: 700, color: const Color(0xff99adc5), spacing: 0.14)),
          ]),
        ),
        Pressable(
          onTap: NinjaGame.testCoinsEnabled ? game.grantTestCoins : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xb8060911), border: Border.all(color: kGoldDim), borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const CoinIcon(18),
              const SizedBox(width: 6),
              Text(formatId(n.shopBalance), style: inter(14, weight: 800, color: const Color(0xffffe099))),
              if (NinjaGame.testCoinsEnabled) ...[
                const SizedBox(width: 5),
                Text("+", style: inter(16, weight: 800, color: kGold)),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Pressable(
          onTap: game.closeShop,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xbd050810), border: Border.all(color: kGoldDim)),
            child: Text("×", style: inter(24, color: const Color(0xfff3e6c4))),
          ),
        ),
      ]);

  Widget _hero(GameNotifier n, _Box b) {
    final index = n.shopFocus.clamp(0, SKINS.length - 1);
    final skin = SKINS[index];
    final rarity = rarityOf(skin);
    final rarityColor = Color(rarity.color);
    final owned = n.unlocked.contains(index);
    final worn = n.selectedSkin == index;
    final assets = game.gameAssets;
    final affordable = n.shopBalance >= skin.cost;
    return SizedBox(
      height: (b.ch(25)).clamp(150.0, 214.0),
      child: LacquerPanel(
        accent: rarityColor.withValues(alpha: 0.7),
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          SizedBox(
            width: b.cw(30).clamp(96.0, 150.0),
            child: Stack(alignment: Alignment.bottomCenter, children: [
              Center(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [rarityColor.withValues(alpha: 0.32), rarityColor.withValues(alpha: 0)])))),
              if (assets != null) SkinSprite(key: ValueKey("hero$index"), atlas: assets.skins[index].motion),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rarity.label, style: inter(9, weight: 800, color: rarityColor, spacing: 0.2)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(skin.name, maxLines: 1, style: trade(20, color: const Color(0xfffff0d0)))),
              const SizedBox(height: 5),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _spec("PASIF", skin.passive),
                    _spec("SENJATA", skin.weapon),
                    _spec("JURUS", skin.skill),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              InkButton(
                label: worn ? "DIPAKAI" : owned ? "PAKAI" : "BELI · ${formatId(skin.cost)}",
                height: 40,
                fontSize: 13,
                expand: true,
                primary: !worn && (owned || affordable),
                onTap: worn ? null : () => game.buySkin(index),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _spec(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 56, child: Text(label, style: inter(8.5, weight: 800, color: kMist, spacing: 0.1))),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(11.5, weight: 700, color: const Color(0xffe7edf5)))),
        ]),
      );

  Widget _grid(GameNotifier n, _Box b) => GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: b.landscape ? 6 : 3, mainAxisSpacing: 6, crossAxisSpacing: 6, mainAxisExtent: 118),
        itemCount: SKINS.length,
        itemBuilder: (context, i) => _ShopCard(game: game, index: i),
      );

  Widget _footer(GameNotifier n, _Box b) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(n.shopMessage, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: inter(10.5, color: const Color(0xffa9b9cc))),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(color: const Color(0xff10121c), border: Border.all(color: kGoldDim), borderRadius: BorderRadius.circular(6)),
              child: Material(
                type: MaterialType.transparency,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: n.areaTestIndex,
                    isExpanded: true,
                    dropdownColor: const Color(0xff10121c),
                    iconEnabledColor: kPaper,
                    style: inter(12.5, weight: 600, color: const Color(0xfff2e7ca)),
                    items: [
                      for (int i = 0; i < AREAS.length; i++) DropdownMenuItem(value: i, child: Text("Area ${i + 1} · ${AREAS[i].name}", maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (v != null) n.setAreaTestIndex(v);
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkButton(label: "MULAI TES", primary: false, height: 44, fontSize: 12, onTap: () => game.startAreaTest(n.areaTestIndex)),
        ]),
      ]);
}

class _ShopCard extends StatelessWidget {
  final NinjaGame game;
  final int index;
  const _ShopCard({required this.game, required this.index});

  // CSS `filter: saturate(.35) brightness(.62)` for locked skins.
  static const double _s = 0.35;
  static const double _b = 0.62;
  static const ColorFilter _lockedFilter = ColorFilter.matrix([
    _b * (0.213 + 0.787 * _s), _b * (0.715 - 0.715 * _s), _b * (0.072 - 0.072 * _s), 0, 0,
    _b * (0.213 - 0.213 * _s), _b * (0.715 + 0.285 * _s), _b * (0.072 - 0.072 * _s), 0, 0,
    _b * (0.213 - 0.213 * _s), _b * (0.715 - 0.715 * _s), _b * (0.072 + 0.928 * _s), 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final n = game.notifier;
    final owned = n.unlocked.contains(index);
    final worn = n.selectedSkin == index;
    final focused = n.shopFocus == index;
    final skin = SKINS[index];
    final rarity = Color(rarityOf(skin).color);
    final assets = game.gameAssets;
    return Pressable(
      onTap: () {
        game.uiTap();
        n.setShopFocus(index);
      },
      child: LacquerPanel(
        corner: 7,
        ornate: false,
        accent: focused ? kGold : rarity.withValues(alpha: 0.36),
        fill: focused ? const [Color(0xf22a1c22), Color(0xf5100c12)] : const [Color(0xeb171a26), Color(0xf5070912)],
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
        child: Column(children: [
          Expanded(
            child: assets == null
                ? const SizedBox.expand()
                : FutureBuilder<ui.Image?>(
                    future: assets.skinPreview(index),
                    builder: (context, snapshot) {
                      final image = snapshot.data;
                      if (image == null) {
                        return const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0x66e0bd6a))));
                      }
                      final preview = RawImage(image: image, fit: BoxFit.contain, alignment: Alignment.bottomCenter, filterQuality: FilterQuality.medium);
                      return owned ? preview : ColorFiltered(colorFilter: _lockedFilter, child: preview);
                    },
                  ),
          ),
          const SizedBox(height: 3),
          Text(skin.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(10, weight: 800, color: const Color(0xfff4e6c5))),
          const SizedBox(height: 2),
          if (worn)
            Text("DIPAKAI", style: inter(9, weight: 800, color: const Color(0xffffe095)))
          else if (owned)
            Text("DIMILIKI", style: inter(9, weight: 800, color: const Color(0xff79d7b1)))
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const CoinIcon(9),
              const SizedBox(width: 3),
              Text(formatId(skin.cost), style: inter(9, weight: 800, color: const Color(0xfff1bd4e))),
            ]),
        ]),
      ),
    );
  }
}
