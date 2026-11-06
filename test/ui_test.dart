import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninja_descent/game/game.dart';
import 'package:ninja_descent/game/notifier.dart';
import 'package:ninja_descent/game/ui.dart';
import 'package:ninja_descent/main.dart';

const _sizes = [Size(320, 568), Size(360, 640), Size(390, 844), Size(430, 932), Size(820, 1180)];

Future<NinjaGame> _pumpUi(WidgetTester t, Size size, void Function(GameNotifier n) setup) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final game = NinjaGame();
  game.notifier.startEnabled = true;
  game.notifier.startVisible = false;
  setup(game.notifier);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: GameUI(game: game))));
  await t.pump(const Duration(milliseconds: 500));
  return game;
}

void main() {
  final endStats = const EndStats(score: 1234567, best: 7654321, area: 20, floor: 58, kills: 1234, maxCombo: 99, coins: 45678, bossKills: 20, newBest: true, victory: true);
  final screens = <String, void Function(GameNotifier)>{
    "menu": (n) => n.startVisible = true,
    "menu loading": (n) {
      n.startVisible = true;
      n.startEnabled = false;
    },
    "hud": (n) {
      n.score = 123456789;
      n.coins = 123456;
      n.buffVisible = true;
      n.buff = "KEBAL CELESTIAL · 5";
      n.comboVisible = true;
      n.combo = 88;
      n.area = "AREA 12/20 · Clockwork Shogunate · 40/45";
      n.mechanic = "MEKANIK · REALITY SHUFFLE";
      n.skinName = "Shadow Kunoichi";
      n.skillLabel = "SCARLET COCOON";
      n.passive = "Crescent Star";
      n.dashCd = 0.5;
      n.dashCdText = "9";
    },
    "descend hint": (n) => n.descendHint = true,
    "ultimate cut-in": (n) => n.announce("ult", "SCARLET COCOON", "Crimson Moth", skin: 10),
    "boss hud": (n) {
      n.bossVisible = true;
      n.bossName = "Gashadokuro Gardener";
      n.bossRatio = 0.4;
    },
    "announcement": (n) => n.announce("boss", "Amaterasu Automaton", "PENJAGA AREA"),
    "toast": (n) => n.announce("powerup", "KEBAL CELESTIAL", "Tembus serangan 6 detik"),
    "pause": (n) => n.pauseVisible = true,
    "settings": (n) => n.settingsVisible = true,
    "tutorial": (n) => n.tutorialVisible = true,
    "shop": (n) => n.shopVisible = true,
    "results": (n) {
      n.endVisible = true;
      n.endTitle = "EMPEROR OF NOTHING TUMBANG";
      n.endStats = endStats;
    },
  };

  for (final size in _sizes) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} fits ${size.width.toInt()}x${size.height.toInt()}', (t) async {
        await _pumpUi(t, size, entry.value);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('keyboard reaches the game even though GameWidget takes focus', (t) async {
    await t.pumpWidget(const MyApp());
    await t.pump(const Duration(milliseconds: 100));
    final game = t.widget<GameUI>(find.byType(GameUI)).game;
    expect(game.notifier.debugVisible, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.backquote);
    await t.pump();
    expect(game.notifier.debugVisible, isTrue);
  });

  testWidgets('the shop coin icon tops the wallet up to 9999 for testing', (t) async {
    final game = await _pumpUi(t, const Size(390, 844), (n) => n.shopVisible = true);
    game.persistent.coins = 12;
    await t.tap(find.text("+"));
    await t.pump(const Duration(milliseconds: 100));
    expect(game.persistent.coins, 9999);
    game.persistent.coins = 20000;
    game.grantTestCoins();
    expect(game.persistent.coins, 20000);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('back closes the top layer and only exits from the menu', (t) async {
    final game = await _pumpUi(t, const Size(390, 844), (n) => n.shopVisible = true);
    final n = game.notifier;
    expect(game.handleBack(), isTrue);
    expect(n.shopVisible, isFalse);
    n.setSettings(true);
    expect(game.handleBack(), isTrue);
    expect(n.settingsVisible, isFalse);
    n.setStart(visible: true);
    expect(game.handleBack(), isFalse);
    await t.pump(const Duration(seconds: 1));
  });

  test('formatId uses Indonesian thousands separators', () {
    expect(formatId(0), "0");
    expect(formatId(999), "999");
    expect(formatId(1000), "1.000");
    expect(formatId(1234567.9), "1.234.567");
  });
}
