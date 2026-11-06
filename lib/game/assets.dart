// Loads the game's sprite sheets. Mirrors game js/game/assets.js, except that
// images are decoded by location instead of all up front: frame data for
// every sheet is parsed at startup (small), while images are decoded for the
// areas around the player and the equipped skin only, then freed again once
// unused. Decoding everything at once took ~1.4 GB and made phones stutter.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'atlas.dart';
import 'data.dart';

Future<Map<String, dynamic>> _loadJson(String path) async {
  final s = await rootBundle.loadString(path);
  return json.decode(s) as Map<String, dynamic>;
}

Future<Atlas> _loadSheet(AssetRef ref, {bool pinned = false}) async =>
    parseAtlas(ref.image, await _loadJson(ref.frames), pinned: pinned);

class SkinAssets {
  final Atlas motion;
  final Atlas status;
  final Atlas arsenal;
  SkinAssets(this.motion, this.status, this.arsenal);
  List<Atlas> get all => [motion, status, arsenal];
}

class AreaAssets {
  final Atlas background;
  final Atlas enemies;
  final Atlas boss;
  AreaAssets(this.background, this.enemies, this.boss);
  List<Atlas> get all => [background, enemies, boss];
}

class GameAssets {
  final Atlas platforms;
  final Atlas objects;
  final Atlas effects;
  final Atlas obstaclesEarly;
  final Atlas obstaclesLate;
  final Atlas obstaclesAscended;
  final Atlas obstaclesTranscendent;
  final Atlas obstaclesRemixA;
  final Atlas obstaclesRemixB;
  final Atlas powerups;
  final Atlas powerupEffectsA;
  final Atlas powerupEffectsB;
  final Atlas powerupsB;
  final Atlas powerupEffectsC;
  final List<SkinAssets> skins;
  final List<AreaAssets> areas;

  GameAssets({
    required this.platforms,
    required this.objects,
    required this.effects,
    required this.obstaclesEarly,
    required this.obstaclesLate,
    required this.obstaclesAscended,
    required this.obstaclesTranscendent,
    required this.obstaclesRemixA,
    required this.obstaclesRemixB,
    required this.powerups,
    required this.powerupEffectsA,
    required this.powerupEffectsB,
    required this.powerupsB,
    required this.powerupEffectsC,
    required this.skins,
    required this.areas,
  });

  late final List<Atlas> obstacleSheets = [obstaclesEarly, obstaclesLate, obstaclesAscended, obstaclesTranscendent, obstaclesRemixA, obstaclesRemixB];
  late final List<Atlas> _all = [
    platforms, objects, effects, powerups, powerupsB, powerupEffectsA, powerupEffectsB, powerupEffectsC,
    ...obstacleSheets,
    for (final skin in skins) ...skin.all,
    for (final area in areas) ...area.all,
  ];

  // Which obstacle sheet holds a hazard / projectile frame (first match wins,
  // like the JS lookup chain).
  final Map<String, Atlas?> _obstacleIndex = {};
  Atlas? obstacleAtlas(String type) =>
      _obstacleIndex.putIfAbsent(type, () => obstacleSheets.where((a) => a.frames.containsKey(type)).firstOrNull);

  // Keeps everything the next few seconds of play can draw decoded: the
  // current and next area (background, enemies, boss, hazards) and the
  // equipped skin. Chain shots borrow skin 8's impact art, revives skin 17's.
  void prefetch({required int areaIndex, required int skinIndex, bool chain = false, bool revive = false}) {
    for (int i = areaIndex; i <= areaIndex + 1 && i < areas.length; i += 1) {
      for (final atlas in areas[i].all) {
        atlas.touch();
      }
      for (final hazard in AREAS[i].hazards) {
        obstacleAtlas(hazard)?.touch();
      }
    }
    for (final atlas in skins[skinIndex].all) {
      atlas.touch();
    }
    if (chain) skins[7].arsenal.touch();
    if (revive) skins[16].arsenal.touch();
  }

  // Frees sheets nothing has drawn or prefetched for a while.
  void sweep({double idleSeconds = 6}) {
    final cutoff = assetClock - idleSeconds;
    for (final atlas in _all) {
      if (!atlas.pinned && atlas.isLoaded && atlas.lastUsed < cutoff) atlas.evict();
    }
  }

  // Once an old area is entirely above the viewport, its large theme sheets
  // cannot be drawn again during normal forward play.
  void releasePassedAreas(int areaIndex, double cameraY, List<Map<String, dynamic>> layouts, double viewHeight) {
    for (int i = 0; i < areaIndex; i += 1) {
      final endY = (layouts[i]["endY"] as num).toDouble();
      if (cameraY <= endY + viewHeight) continue;
      for (final atlas in areas[i].all) {
        atlas.evict();
      }
    }
  }

  Future<void> ensureArea(int index) => Future.wait([
        for (final atlas in areas[index].all) (atlas..touch()).load(),
        for (final hazard in AREAS[index].hazards) (obstacleAtlas(hazard)?..touch())?.load() ?? Future.value(),
      ]);

  Future<void> ensureSkin(int index) => Future.wait([for (final atlas in skins[index].all) (atlas..touch()).load()]);

  // Shop thumbnails (drawShopPreview in game.js). Built one at a time so the
  // shop never decodes 20 full skin sheets at once; a sheet decoded only for
  // its thumbnail is freed right after.
  final Map<int, Future<ui.Image?>> _previews = {};
  Future<void> _previewQueue = Future.value();

  Future<ui.Image?> skinPreview(int index) => _previews[index] ??= _queuePreview(index);

  Future<ui.Image?> _queuePreview(int index) {
    final result = _previewQueue.then((_) => _buildPreview(index));
    _previewQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<ui.Image?> _buildPreview(int index) async {
    const size = 160.0;
    final atlas = skins[index].motion;
    final wasLoaded = atlas.isLoaded;
    final started = assetClock;
    final image = await atlas.load();
    final frame = atlas.anim("idle")?.frames.firstOrNull;
    if (image == null || frame == null) return null;
    final crop = frame.content;
    final scale = [size * 0.72 / crop.width, size * 0.92 / crop.height].reduce((a, b) => a < b ? a : b);
    final w = crop.width * scale;
    final h = crop.height * scale;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(image, crop, ui.Rect.fromLTWH((size - w) / 2, size - h, w, h), ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final picture = recorder.endRecording();
    final thumbnail = await picture.toImage(size.toInt(), size.toInt());
    picture.dispose();
    if (!wasLoaded && atlas.lastUsed < started) atlas.evict();
    return thumbnail;
  }
}

String _backgroundPath(String key) => 'assets/images/${key.toLowerCase()}.webp';

// Parses every frames.json and decodes only what the first screen needs:
// the shared world sheets, the starting area and the equipped skin.
Future<GameAssets> preloadGameAssets({int skinIndex = 0, int areaIndex = 0}) async {
  final skinFutures = SKINS.map((skin) async => SkinAssets(
        await _loadSheet(AssetRef(skin.motionKey)),
        await _loadSheet(AssetRef(skin.statusKey)),
        await _loadSheet(AssetRef(skin.arsenalKey)),
      ));

  final areaFutures = AREAS.map((area) async => AreaAssets(
        parseAtlas(_backgroundPath(area.backgroundKey), null),
        await _loadSheet(AssetRef(area.enemyKey)),
        await _loadSheet(AssetRef(area.bossKey)),
      ));

  final results = await Future.wait([
    _loadSheet(WorldAssets.platforms, pinned: true),
    _loadSheet(WorldAssets.objects, pinned: true),
    _loadSheet(WorldAssets.effects, pinned: true),
    _loadSheet(WorldAssets.obstaclesEarly),
    _loadSheet(WorldAssets.obstaclesLate),
    _loadSheet(WorldAssets.obstaclesAscended),
    _loadSheet(WorldAssets.obstaclesTranscendent),
    _loadSheet(WorldAssets.obstaclesRemixA),
    _loadSheet(WorldAssets.obstaclesRemixB),
    _loadSheet(WorldAssets.powerups, pinned: true),
    _loadSheet(WorldAssets.powerupEffectsA, pinned: true),
    _loadSheet(WorldAssets.powerupEffectsB, pinned: true),
    _loadSheet(WorldAssets.powerupsB, pinned: true),
    _loadSheet(WorldAssets.powerupEffectsC, pinned: true),
    Future.wait(skinFutures),
    Future.wait(areaFutures),
  ]);

  final assets = GameAssets(
    platforms: results[0] as Atlas,
    objects: results[1] as Atlas,
    effects: results[2] as Atlas,
    obstaclesEarly: results[3] as Atlas,
    obstaclesLate: results[4] as Atlas,
    obstaclesAscended: results[5] as Atlas,
    obstaclesTranscendent: results[6] as Atlas,
    obstaclesRemixA: results[7] as Atlas,
    obstaclesRemixB: results[8] as Atlas,
    powerups: results[9] as Atlas,
    powerupEffectsA: results[10] as Atlas,
    powerupEffectsB: results[11] as Atlas,
    powerupsB: results[12] as Atlas,
    powerupEffectsC: results[13] as Atlas,
    skins: results[14] as List<SkinAssets>,
    areas: results[15] as List<AreaAssets>,
  );

  final pinned = assets._all.where((a) => a.pinned).map((a) => a.load());
  await Future.wait([...pinned, assets.ensureArea(areaIndex), assets.ensureSkin(skinIndex)]);
  if (assets._all.where((a) => a.pinned).any((a) => !a.isLoaded)) {
    throw StateError("Gagal memuat aset dunia");
  }
  // Warm the next area in the background.
  if (areaIndex + 1 < AREAS.length) unawaited(assets.ensureArea(areaIndex + 1));
  return assets;
}
