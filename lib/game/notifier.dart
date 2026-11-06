// Bridges simulation state to Flutter UI (mirrors game js/game/ui.js updateHUD).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'data.dart';
import 'simulation.dart';

// toLocaleString("id-ID") for integers: 12345 -> "12.345".
String formatId(num value) {
  final n = value.floor();
  final digits = n.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

class Persistent {
  int version = 2;
  int best = 0;
  int coins = 0;
  int skinIndex = 0;
  List<int> unlocked = [0, 1, 2];

  Persistent({this.best = 0, this.coins = 0, this.skinIndex = 0, this.unlocked = const [0, 1, 2]});

  Map<String, dynamic> toJson() => {
        "version": version,
        "best": best,
        "coins": coins,
        "skinIndex": skinIndex,
        "unlocked": unlocked,
      };

  factory Persistent.fromJson(Map<String, dynamic> json) => Persistent(
        best: json["best"] ?? 0,
        coins: json["coins"] ?? 0,
        skinIndex: json["skinIndex"] ?? 0,
        unlocked: List<int>.from(json["unlocked"] ?? [0, 1, 2]),
      );
}

// A timed popup driven by the UI's announcer.
class Announcement {
  final int id;
  final String kind; // area | boss | clear | powerup
  final String title;
  final String subtitle;
  final int skin;
  const Announcement(this.id, this.kind, this.title, this.subtitle, {this.skin = 0});
}

class EndStats {
  final int score, best, area, floor, kills, maxCombo, coins, bossKills;
  final bool newBest, victory;
  const EndStats({required this.score, required this.best, required this.area, required this.floor, required this.kills, required this.maxCombo, required this.coins, required this.bossKills, required this.newBest, required this.victory});
}

class GameNotifier extends ChangeNotifier {
  // HUD
  int coins = 0;
  int score = 0;
  String area = "";
  String mechanic = "";
  String buff = "";
  bool buffVisible = false;
  int combo = 0;
  bool comboVisible = false;
  double comboRatio = 0;
  double hpRatio = 1;
  int hp = 100;
  int maxHp = 100;
  double floorRatio = 0;
  double dashCd = 0;
  String dashCdText = "";
  double slashCd = 0;
  String skinName = "";
  String skillLabel = "";
  String passive = "";
  int skinIndex = 0;
  int areaIndex = 0;
  bool bossVisible = false;
  String bossName = "";
  double bossRatio = 1;
  int bossPhase = 1;
  bool running = false;
  bool descendHint = false;

  // overlays
  bool startVisible = true;
  String startStatus = "MENYIAPKAN BAYANGAN…";
  bool startEnabled = false;
  bool pauseVisible = false;
  bool shopVisible = false;
  bool settingsVisible = false;
  bool tutorialVisible = false;
  bool endVisible = false;
  String endTitle = "";
  EndStats? endStats;

  Announcement? announcement;
  Announcement? toast;
  Announcement? ultCut;
  int _announceId = 0;

  // persistent summary shown on the menu
  int best = 0;

  // settings
  bool sfxOn = true;
  bool musicOn = true;
  bool hapticsOn = true;
  bool lowEffects = false;

  // shop
  int shopBalance = 0;
  int selectedSkin = 0;
  int shopFocus = 0;
  List<int> unlocked = [0, 1, 2];
  String shopMessage = "Kalahkan musuh dan boss untuk mendapat koin.";
  int areaTestIndex = 0;

  // debug overlay (toggle with the ` key)
  bool debugVisible = false;
  String debug = "";

  void toggleDebug() {
    debugVisible = !debugVisible;
    _notify();
  }

  void setDebug(String value) {
    debug = value;
    _notify();
  }

  int _signature = 0;

  // Called ~15 times a second; only notifies when something visible changed.
  void syncFromState(GameState state, Skin skin) {
    final areaDef = AREAS[state.areaIndex];
    final bossActive = state.boss["active"] == true && state.boss["defeated"] != true;
    final String nextArea = state.bannerTime > 0
        ? state.banner
        : "AREA ${state.areaIndex + 1}/20 · ${areaDef.name} · ${state.areaFloor}/${areaDef.floors}";
    final buffDef = POWERUPS.where((p) => state.buffs[p.type]! > 0).firstOrNull;
    final cd = math.max(0.0, (state.player["dashCooldown"] as num).toDouble());
    final hpValue = (state.player["hp"] as num).toDouble();
    final maxHpValue = (state.player["maxHp"] as num).toDouble();
    final bossHp = (state.boss["hp"] as num?)?.toDouble() ?? 0;
    final bossMax = (state.boss["maxHp"] as num?)?.toDouble() ?? 1;

    coins = state.coins.floor();
    score = state.score.floor();
    area = nextArea;
    hpRatio = ((hpValue / maxHpValue).clamp(0.0, 1.0) * 200).round() / 200;
    hp = hpValue.ceil();
    maxHp = maxHpValue.ceil();
    floorRatio = (state.areaFloor / areaDef.floors).clamp(0.0, 1.0);
    mechanic = "MEKANIK · ${areaDef.mechanic}";
    buffVisible = buffDef != null;
    if (buffDef != null) buff = "${buffDef.name} · ${state.buffs[buffDef.type]!.ceil()}";
    comboVisible = state.combo >= 2;
    combo = state.combo;
    comboRatio = ((state.comboTimer / 2.1).clamp(0.0, 1.0) * 20).round() / 20;
    dashCd = math.min(1.0, cd / 10.0);
    dashCdText = cd > 0 ? cd.ceil().toString() : "";
    slashCd = (((state.player["slashCooldown"] as num).toDouble() / 2).clamp(0.0, 1.0) * 20).round() / 20;
    skinName = skin.name;
    skillLabel = skin.skill;
    passive = skin.weapon;
    skinIndex = state.skinIndex;
    areaIndex = state.areaIndex;
    bossVisible = bossActive;
    bossName = areaDef.boss;
    bossRatio = ((bossHp / bossMax).clamp(0.0, 1.0) * 200).round() / 200;
    bossPhase = bossHp / bossMax < 0.3 ? 3 : bossHp / bossMax < 0.6 ? 2 : 1;
    running = state.mode == "running";
    // Nudge a player who is standing around, e.g. right after a boss falls.
    descendHint = running && !bossActive && state.player["grounded"] == true && (state.player["groundTime"] as num) > 4;

    final signature = Object.hashAll([coins, score, area, hpRatio, floorRatio, buffVisible, buff, combo, comboRatio, dashCdText, dashCd, slashCd, skinIndex, bossVisible, bossRatio, running, descendHint]);
    if (signature == _signature) return;
    _signature = signature;
    _notify();
  }

  void announce(String kind, String title, String subtitle, {int skin = 0}) {
    final next = Announcement(++_announceId, kind, title, subtitle, skin: skin);
    if (kind == "ult") {
      ultCut = next;
    } else if (kind == "powerup") {
      toast = next;
    } else {
      announcement = next;
    }
    _notify();
  }

  void clearAnnouncements() {
    announcement = null;
    toast = null;
    ultCut = null;
    _notify();
  }

  void setAreaTestIndex(int index) {
    areaTestIndex = index;
    _notify();
  }

  void setStart({required bool visible, String? status, bool? enabled}) {
    startVisible = visible;
    if (status != null) startStatus = status;
    if (enabled != null) startEnabled = enabled;
    _notify();
  }

  void setPause(bool visible) {
    pauseVisible = visible;
    _notify();
  }

  void setSettings(bool visible) {
    settingsVisible = visible;
    _notify();
  }

  void setTutorial(bool visible) {
    tutorialVisible = visible;
    _notify();
  }

  void setShop({required bool visible, String? message}) {
    shopVisible = visible;
    if (message != null) shopMessage = message;
    _notify();
  }

  void setShopFocus(int index) {
    shopFocus = index;
    _notify();
  }

  void setEnd({required bool visible, String? title, EndStats? stats}) {
    endVisible = visible;
    if (title != null) endTitle = title;
    if (stats != null) endStats = stats;
    _notify();
  }

  void setShopData({required int balance, required int selected, required List<int> unlocked, String? message}) {
    shopBalance = balance;
    selectedSkin = selected;
    this.unlocked = List<int>.from(unlocked);
    if (message != null) shopMessage = message;
    _notify();
  }

  void applySettings({required bool sfx, required bool music, required bool haptics, required bool low}) {
    sfxOn = sfx;
    musicOn = music;
    hapticsOn = haptics;
    lowEffects = low;
    _notify();
  }

  void _notify() => notifyListeners();
}
