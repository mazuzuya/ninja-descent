// Orchestrator mirroring game js/game/game.js — wires simulation, renderer,
// audio, events, persistence and the game loop. Built on Flame's Game.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assets.dart';
import 'audio.dart';
import 'data.dart';
import 'fx.dart';
import 'notifier.dart';
import 'renderer.dart';
import 'simulation.dart';

class NinjaGame extends Game {
  final GameNotifier notifier = GameNotifier();
  final Audio audio = Audio();
  final Fx fx = Fx();
  bool _tutorialSeen = false;
  bool _startAfterTutorial = false;
  bool _musicUnlocked = false;

  GameAssets? _assets;
  Simulation? _simulation;
  Renderer? _renderer;
  Persistent persistent = Persistent();
  bool _loaded = false;
  bool _ended = false;
  String _shopReturnMode = "running";
  Timer? _saveTimer;
  ui.Size _size = const ui.Size(390, 844);
  final Tweaks tweaks = Tweaks.defaults();

  GameAssets? get gameAssets => _assets;

  @override
  Future<void> onLoad() async {
    try {
      // The save decides which skin to decode first.
      await SharedPreferences.getInstance().then(_loadPersistent).catchError((_) {});
      await _loadSettings();
      _assets = await preloadGameAssets(skinIndex: persistent.skinIndex);
    } catch (error) {
      notifier.setStart(visible: true, status: "ASET GAGAL DIMUAT · COBA MUAT ULANG", enabled: false);
      // ignore: avoid_print
      print(error);
      return;
    }
    _simulation = Simulation(
      config: {
        "gravity": tweaks.gravity,
        "enemyRate": tweaks.enemyRate,
        "bossHp": tweaks.bossHp,
        "effectsIntensity": tweaks.effectsIntensity,
      },
      onEvent: _onEvent,
    );
    _simulation!.reset(skinIndex: persistent.skinIndex);
    _renderer = Renderer(assets: _assets!, simulation: _simulation!, fx: fx, effectsIntensity: tweaks.effectsIntensity);
    _loaded = true;
    notifier.best = persistent.best;
    notifier.shopFocus = persistent.skinIndex;
    _refreshShop();
    notifier.setStart(visible: true, status: "KETUK UNTUK TURUN", enabled: true);
    notifier.syncFromState(_simulation!.state, SKINS[_simulation!.state.skinIndex]);
  }

  Future<void> _loadPersistent(SharedPreferences prefs) async {
    final saved = prefs.getString("ninja_descent_save");
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        if (data["version"] == 2) {
          persistent = Persistent(
            best: _clampInt(data["best"]),
            coins: _clampInt(data["coins"]),
            skinIndex: _clampInt(data["skinIndex"], max: SKINS.length - 1),
            unlocked: _sanitizeUnlocked(data["unlocked"]),
          );
        } else if (data["version"] == 1) {
          final oldSkin = _clampInt(data["skinIndex"], max: 9);
          persistent = Persistent(
            best: _clampInt(data["best"]),
            coins: _clampInt(data["coins"]),
            skinIndex: oldSkin,
            unlocked: [0, 1, 2, oldSkin],
          );
        }
      } catch (_) {}
    }
    if (!persistent.unlocked.contains(persistent.skinIndex)) persistent.skinIndex = 0;
  }

  List<int> _sanitizeUnlocked(dynamic raw) {
    if (raw is! List) return [0, 1, 2];
    final set = <int>{0, 1, 2};
    for (final v in raw) {
      if (v is int && v >= 0 && v < SKINS.length) set.add(v);
    }
    return set.toList();
  }

  // Scores and coins are unbounded in the JS (Number.MAX_SAFE_INTEGER).
  int _clampInt(dynamic v, {int max = 9007199254740991}) => (v is num && v.isFinite ? v.floor() : 0).clamp(0, max);

  Future<void> _loadSettings() async {
    var sfx = true, music = true, haptics = true, low = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString("ninja_descent_settings");
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        sfx = data["sfx"] != false;
        music = data["music"] != false;
        haptics = data["haptics"] != false;
        low = data["low"] == true;
        _tutorialSeen = data["tutorialSeen"] == true;
      }
    } catch (_) {}
    _applySettings(sfx: sfx, music: music, haptics: haptics, low: low);
  }

  void _applySettings({required bool sfx, required bool music, required bool haptics, required bool low}) {
    audio.sfxEnabled = sfx;
    audio.musicEnabled = music;
    audio.hapticsEnabled = haptics;
    fx.lowEffects = low;
    notifier.applySettings(sfx: sfx, music: music, haptics: haptics, low: low);
  }

  void updateSettings({bool? sfx, bool? music, bool? haptics, bool? low}) {
    _applySettings(
      sfx: sfx ?? notifier.sfxOn,
      music: music ?? notifier.musicOn,
      haptics: haptics ?? notifier.hapticsOn,
      low: low ?? notifier.lowEffects,
    );
    uiTap();
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("ninja_descent_settings", json.encode({"sfx": notifier.sfxOn, "music": notifier.musicOn, "haptics": notifier.hapticsOn, "low": notifier.lowEffects, "tutorialSeen": _tutorialSeen}));
    } catch (_) {}
  }

  // Immediately writes progress (app going to the background).
  Future<void> flushSave() async {
    _saveTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("ninja_descent_save", json.encode(persistent.toJson()));
    } catch (_) {}
  }

  void uiTap() {
    _musicUnlocked = true;
    audio.uiTap();
  }

  void _saveStateSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("ninja_descent_save", json.encode(persistent.toJson()));
      } catch (_) {}
    });
  }

  double _laneX(num lane, int laneCount) => _simulation!.laneX(lane.toDouble(), _renderer?.viewWidth ?? 390, laneCount);

  void _onEvent(Map<String, dynamic> event) {
    if (_simulation == null || _assets == null) return;
    final type = event["type"];
    final state = _simulation!.state;
    fx.onEvent(event, _laneX, state);
    switch (type) {
      case "jump":
        audio.jump();
        break;
      case "shoot":
        audio.shoot(event["charged"] == true);
        break;
      case "slash":
        audio.slash();
        break;
      case "land":
        if (event["pound"] == true) {
          audio.pound();
        } else if ((event["speed"] as num) > 180) {
          audio.land();
        }
        break;
      case "hit":
      case "enemyDown":
      case "platformBreak":
        audio.hit();
        break;
      case "bossHit":
        audio.bossHit();
        break;
      case "coin":
        audio.coin(event["combo"] ?? 1);
        break;
      case "heal":
        audio.heal();
        audio.haptic();
        break;
      case "powerup":
        audio.victory();
        notifier.announce("powerup", event["name"], kPowerupInfo[event["item"]] ?? "");
        break;
      case "area":
        final index = event["areaIndex"] as int;
        notifier.announce("area", "AREA ${index + 1}", AREAS[index].name);
        break;
      case "boss":
        audio.bossAppear();
        notifier.announce("boss", AREAS[event["areaIndex"] as int].boss, "PENJAGA AREA");
        break;
      case "areaClear":
        audio.areaClear();
        notifier.announce("clear", "AREA ${(event["areaIndex"] as int) + 1} TERSAPU", "+${formatId(event["coinReward"] as num)} KOIN");
        break;
      case "dash":
        audio.dash();
        final skin = SKINS[state.skinIndex];
        notifier.announce("ult", skin.skill, skin.name, skin: state.skinIndex);
        break;
      case "bossDodge":
        audio.dash();
        break;
      case "gameover":
        audio.gameOver();
        _showEnd("TERTELAN JURANG", event["score"] as num, false, event["area"] ?? 20);
        break;
      case "victory":
        audio.victory();
        _showEnd("EMPEROR OF NOTHING TUMBANG", event["score"] as num, true, 20);
        break;
      case "skin":
        persistent.skinIndex = event["skinIndex"];
        _saveStateSoon();
        break;
    }
    if (event["coinReward"] is num && (event["coinReward"] as num) > 0) {
      persistent.coins += (event["coinReward"] as num).floor();
      _refreshShop();
      _saveStateSoon();
    }
    if (const ["hit", "dash", "enemyDown", "bossHit"].contains(type)) {
      audio.haptic(strong: type == "hit");
    }
  }

  void _showEnd(String title, num rawScore, bool victory, int area) {
    if (_ended) return;
    _ended = true;
    final state = _simulation!.state;
    final previousBest = persistent.best;
    persistent.best = math.max(persistent.best, rawScore.floor());
    persistent.skinIndex = state.skinIndex;
    _saveStateSoon();
    // Let the death / victory animation play before the overlay, like the JS.
    Future.delayed(Duration(milliseconds: victory ? 1500 : 850), () {
      if (!_ended) return;
      // The event fires mid-frame; the sim tallies the frame's final score after
      // it, so read the settled value to match what the HUD last showed.
      final score = math.max(state.score.floor(), rawScore.floor());
      persistent.best = math.max(persistent.best, score);
      notifier.best = persistent.best;
      _saveStateSoon();
      notifier.setEnd(
        visible: true,
        title: title,
        stats: EndStats(
          score: score,
          best: persistent.best,
          area: area,
          floor: state.areaFloor,
          kills: state.kills,
          maxCombo: state.maxCombo,
          coins: state.coins.floor(),
          bossKills: state.bossKills,
          newBest: score > previousBest,
          victory: victory,
        ),
      );
    });
  }

  void _refreshShop([String message = ""]) {
    if (_simulation == null) return;
    notifier.setShopData(
      balance: persistent.coins,
      selected: _simulation!.state.skinIndex,
      unlocked: persistent.unlocked,
      message: message.isNotEmpty ? message : null,
    );
  }

  // ---- Control methods used by UI ----
  void startGame() {
    if (_simulation == null || _simulation!.state.mode != "idle") return;
    uiTap();
    notifier.setStart(visible: false);
    if (!_tutorialSeen) {
      _startAfterTutorial = true;
      notifier.setTutorial(true);
      return;
    }
    _beginRun();
  }

  void _beginRun() {
    _simulation!.start();
    notifier.announce("area", "AREA 1", AREAS[0].name);
    audio.unlock();
  }

  void showTutorial() {
    uiTap();
    _startAfterTutorial = false;
    notifier.setTutorial(true);
  }

  void closeTutorial() {
    uiTap();
    notifier.setTutorial(false);
    _tutorialSeen = true;
    _saveSettings();
    if (_startAfterTutorial) {
      _startAfterTutorial = false;
      _beginRun();
    }
  }

  void openSettings() {
    uiTap();
    notifier.setSettings(true);
  }

  void closeSettings() {
    uiTap();
    notifier.setSettings(false);
  }

  void pauseGame() {
    if (_simulation == null || _simulation!.state.mode != "running") return;
    uiTap();
    _simulation!.state.mode = "paused";
    notifier.setPause(true);
  }

  void resumeGame() {
    if (_simulation == null || _simulation!.state.mode != "paused") return;
    uiTap();
    _simulation!.state.mode = "running";
    notifier.setPause(false);
  }

  // App sent to the background: never keep playing behind the user's back.
  void onAppBackgrounded() {
    audio.holdMusic(true);
    flushSave();
    if (_simulation?.state.mode == "running") {
      _simulation!.state.mode = "paused";
      notifier.setPause(true);
    }
  }

  void onAppForegrounded() => audio.holdMusic(false);

  // Android back: closes the top layer, pauses a run, and only leaves the app
  // from the main menu. Returns false when the app should exit.
  bool handleBack() {
    final n = notifier;
    if (n.tutorialVisible) {
      closeTutorial();
    } else if (n.settingsVisible) {
      closeSettings();
    } else if (n.shopVisible) {
      closeShop();
    } else if (n.endVisible) {
      backToMenu();
    } else if (n.pauseVisible) {
      resumeGame();
    } else if (n.startVisible) {
      return false;
    } else {
      pauseGame();
    }
    return true;
  }

  void retryGame() {
    if (_simulation == null) return;
    uiTap();
    _ended = false;
    fx.reset();
    notifier.setEnd(visible: false);
    notifier.setPause(false);
    notifier.clearAnnouncements();
    _simulation!.reset(skinIndex: _simulation!.state.skinIndex);
    _beginRun();
  }

  void backToMenu() {
    if (_simulation == null) return;
    uiTap();
    _ended = false;
    fx.reset();
    notifier.setEnd(visible: false);
    notifier.setPause(false);
    notifier.clearAnnouncements();
    _simulation!.reset(skinIndex: _simulation!.state.skinIndex);
    notifier.setStart(visible: true);
  }

  void openShop() {
    if (_simulation == null || _assets == null) return;
    _shopReturnMode = _simulation!.state.mode == "running" ? "running" : _simulation!.state.mode;
    if (_simulation!.state.mode == "running") _simulation!.state.mode = "paused";
    uiTap();
    _refreshShop();
    notifier.shopFocus = _simulation!.state.skinIndex;
    notifier.setShop(visible: true);
  }

  void closeShop() {
    uiTap();
    notifier.setShop(visible: false);
    if (_simulation?.state.mode == "paused" && _shopReturnMode == "running") {
      _simulation!.state.mode = "running";
    }
  }

  // Testing aid: the shop's coin icon tops the wallet up. Turn this off before
  // releasing the game.
  static const bool testCoinsEnabled = true;

  void grantTestCoins() {
    if (!testCoinsEnabled) return;
    persistent.coins = math.max(persistent.coins, 9999);
    audio.uiBuy();
    _refreshShop("Koin uji: ${formatId(persistent.coins)}");
    _saveStateSoon();
  }

  Future<void> buySkin(int index) async {
    if (_simulation == null || _assets == null) return;
    final owned = persistent.unlocked.contains(index);
    if (!owned) {
      final cost = SKINS[index].cost;
      if (persistent.coins < cost) {
        _refreshShop("Kurang ${formatId(cost - persistent.coins)} koin untuk ${SKINS[index].name}.");
        return;
      }
      persistent.coins -= cost;
      persistent.unlocked.add(index);
      audio.uiBuy();
    } else {
      uiTap();
    }
    persistent.skinIndex = index;
    // Decode the new skin before wearing it so the ninja never blinks out.
    await _assets!.ensureSkin(index);
    _simulation!.setSkin(index);
    _refreshShop(owned ? "${SKINS[index].name} dipakai." : "${SKINS[index].name} dibeli dan dipakai.");
    _saveStateSoon();
  }

  Future<void> startAreaTest(int index) async {
    if (_simulation == null || _assets == null) return;
    notifier.setShop(visible: true, message: "Memuat Area ${index + 1}…");
    await _assets!.ensureArea(index);
    uiTap();
    fx.reset();
    _ended = false;
    notifier.setEnd(visible: false);
    notifier.setPause(false);
    notifier.setShop(visible: false);
    notifier.setStart(visible: false);
    _simulation!.startAtArea(index);
    notifier.announce("area", "AREA ${index + 1}", AREAS[index].name);
    notifier.setShopData(
      balance: persistent.coins,
      selected: _simulation!.state.skinIndex,
      unlocked: persistent.unlocked,
      message: "Area ${index + 1} · ${AREAS[index].name}",
    );
  }

  // ---- Input actions ----
  void move(int direction) => _simulation?.move(direction);
  void shoot([bool charged = false]) => _simulation?.shoot(charged);
  void slash() => _simulation?.slash();
  void fastFall([bool forcePound = false]) => _simulation?.fastFall(forcePound);
  void dash() => _simulation?.dash();
  void setCharging(bool value) => fx.charging = value;

  // Test shortcuts, compiled out unless built with --dart-define=NINJA_DEV=true.
  static const bool devTools = bool.fromEnvironment("NINJA_DEV");

  void devJump({bool toBoss = false}) {
    final sim = _simulation;
    if (!devTools || sim == null || sim.state.mode != "running") return;
    final state = sim.state;
    final layout = toBoss ? state.layouts[state.areaIndex] : state.layouts[math.min(state.areaIndex + 1, state.layouts.length - 1)];
    final y = ((toBoss ? layout["arenaY"] : layout["startY"]) as num).toDouble() - 40;
    state.player["y"] = y;
    state.player["lastLandedY"] = y;
    state.player["grounded"] = false;
    state.player["vy"] = 120.0;
    state.player["lane"] = (state.player["lane"] as num).roundToDouble();
    state.player["targetLane"] = state.player["lane"];
    state.cameraY = y - 350;
  }

  Future<void> devNextSkin() async {
    if (!devTools || _simulation == null || _assets == null) return;
    final next = (_simulation!.state.skinIndex + 1) % SKINS.length;
    await _assets!.ensureSkin(next);
    _simulation!.setSkin(next);
  }

  void devHeal() {
    if (!devTools || _simulation == null) return;
    _simulation!.state.player["hp"] = _simulation!.state.player["maxHp"];
    _simulation!.state.buffs["celestial_aegis"] = 600;
  }

  @override
  void update(double dt) {
    if (!_loaded || _simulation == null) return;
    final capped = dt.clamp(0.0, 0.034);
    final state = _simulation!.state;
    // JS skips the simulation entirely while paused (shop / pause overlay).
    if (state.mode != "paused") {
      _simulation!.update(fx.scaleDt(capped));
      fx.update(capped, _simulation!, _renderer?.viewWidth ?? 390, VIEW_HEIGHT, _laneX);
    }

    if (_musicUnlocked) {
      final bossFight = state.boss["active"] == true && state.boss["defeated"] != true;
      audio.playMusic(state.mode == "gameover" ? null : bossFight ? "music_boss" : "music_descent");
    }

    // Keep the sheets around the player decoded and free the rest.
    _assetTimer -= dt;
    if (_assetTimer <= 0) {
      _assetTimer = 0.5;
      _assets!.prefetch(
        areaIndex: state.areaIndex,
        skinIndex: state.skinIndex,
        chain: const [7, 13, 17, 19].contains(state.skinIndex),
        revive: state.player["reviveReady"] == true,
      );
      _assets!.sweep();
    }

    // The HUD is Flutter widgets; ~15 updates a second reads as live while
    // keeping widget rebuilds off most frames.
    _hudTimer -= dt;
    if (_hudTimer <= 0) {
      _hudTimer = 1 / 15;
      notifier.syncFromState(state, SKINS[state.skinIndex]);
      if (notifier.debugVisible) _updateDebug();
    }
  }

  double _assetTimer = 0;
  double _hudTimer = 0;

  void _updateDebug() {
    final s = _simulation!.state;
    final p = s.player;
    notifier.setDebug(
      "mode=${s.mode} area=${s.areaIndex}\n"
      "y=${p["y"].toStringAsFixed(0)} vy=${p["vy"].toStringAsFixed(0)}\n"
      "lane=${p["lane"].toStringAsFixed(2)} target=${p["targetLane"].toStringAsFixed(2)}\n"
      "grounded=${p["grounded"]} gp=${p["groundPound"]}\n"
      "cam=${s.cameraY.toStringAsFixed(0)} hp=${(p["hp"] as num).toStringAsFixed(0)}\n"
      "plat=${s.platforms.length} fall=${s.fallFrames} miss=${s.landMissCount}",
    );
  }

  void toggleDebug() => notifier.toggleDebug();

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = ui.Size(size.x, size.y);
  }

  @override
  void onRemove() {
    _saveTimer?.cancel();
    audio.dispose();
    super.onRemove();
  }

  @override
  void render(ui.Canvas canvas) {
    if (!_loaded || _renderer == null) return;
    _renderer!.render(canvas, _size);
  }
}
