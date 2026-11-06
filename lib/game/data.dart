// Mirror of game js/game/data.js — all gameplay data definitions.

class Skin {
  final String name;
  final String passive;
  final String weapon;
  final String skill;
  final int cost;
  final String motionKey;
  final String statusKey;
  final String arsenalKey;

  const Skin({
    required this.name,
    required this.passive,
    required this.weapon,
    required this.skill,
    required this.cost,
    required this.motionKey,
    required this.statusKey,
    required this.arsenalKey,
  });
}

class Powerup {
  final String type;
  final String name;
  final String effect;
  final double duration;

  const Powerup({
    required this.type,
    required this.name,
    required this.effect,
    required this.duration,
  });
}

class Area {
  final String name;
  final String boss;
  final int lanes;
  final int floors;
  final List<String> enemies;
  final List<String> hazards;
  final List<String> extraHazards;
  final String mechanic;
  final int index;
  final String backgroundKey;
  final String enemyKey;
  final String bossKey;

  const Area({
    required this.name,
    required this.boss,
    required this.lanes,
    required this.floors,
    required this.enemies,
    required this.hazards,
    required this.extraHazards,
    required this.mechanic,
    required this.index,
    required this.backgroundKey,
    required this.enemyKey,
    required this.bossKey,
  });
}

class AssetRef {
  final String key;
  const AssetRef(this.key);
  String get image => 'assets/images/${key.toLowerCase()}-transparent.webp';
  String get frames => 'assets/json/${key.toLowerCase()}-transparent.frames.json';
}

const List<Skin> SKINS = [
  Skin(name: "Shadow Kunoichi", passive: "+10% gerak", weapon: "Crescent Star", skill: "UMBRA FAN", cost: 0, motionKey: "NINJA_SKIN_01_MOTION", statusKey: "NINJA_SKIN_01_STATUS", arsenalKey: "SKIN_01_ARSENAL"),
  Skin(name: "Cyber Ninja", passive: "bolt menembus", weapon: "Rail Bolt", skill: "NEON GRID", cost: 0, motionKey: "NINJA_SKIN_02_MOTION", statusKey: "NINJA_SKIN_02_STATUS", arsenalKey: "SKIN_02_ARSENAL"),
  Skin(name: "Kitsune Ninja", passive: "+15% api", weapon: "Foxfire", skill: "NINE-TAIL", cost: 0, motionKey: "NINJA_SKIN_03_MOTION", statusKey: "NINJA_SKIN_03_STATUS", arsenalKey: "SKIN_03_ARSENAL"),
  Skin(name: "Dragon Ninja", passive: "+20% HP", weapon: "Scale Blade", skill: "DRAGON BREATH", cost: 500, motionKey: "NINJA_SKIN_04_MOTION", statusKey: "NINJA_SKIN_04_STATUS", arsenalKey: "SKIN_04_ARSENAL"),
  Skin(name: "Ghost Ronin", passive: "5% evade", weapon: "Soul Wave", skill: "SOUL MARCH", cost: 700, motionKey: "NINJA_SKIN_05_MOTION", statusKey: "NINJA_SKIN_05_STATUS", arsenalKey: "SKIN_05_ARSENAL"),
  Skin(name: "Tengu Ninja", passive: "+10% lompatan", weapon: "Razor Feather", skill: "CYCLONE", cost: 900, motionKey: "NINJA_SKIN_06_MOTION", statusKey: "NINJA_SKIN_06_STATUS", arsenalKey: "SKIN_06_ARSENAL"),
  Skin(name: "Sakura Ninja", passive: "regen HP", weapon: "Petal Blade", skill: "BLOOM", cost: 1100, motionKey: "NINJA_SKIN_07_MOTION", statusKey: "NINJA_SKIN_07_STATUS", arsenalKey: "SKIN_07_ARSENAL"),
  Skin(name: "Thunder Oni", passive: "chain lightning", weapon: "Lightning Orb", skill: "RAIJIN CHAIN", cost: 1400, motionKey: "NINJA_SKIN_08_MOTION", statusKey: "NINJA_SKIN_08_STATUS", arsenalKey: "SKIN_08_ARSENAL"),
  Skin(name: "Shadow Monarch", passive: "+25% damage gelap", weapon: "Void Spear", skill: "ECLIPSE", cost: 1700, motionKey: "NINJA_SKIN_09_MOTION", statusKey: "NINJA_SKIN_09_STATUS", arsenalKey: "SKIN_09_ARSENAL"),
  Skin(name: "Golden Buddha", passive: "1 hit shield", weapon: "Bell Wave", skill: "DHARMA", cost: 2000, motionKey: "NINJA_SKIN_10_MOTION", statusKey: "NINJA_SKIN_10_STATUS", arsenalKey: "SKIN_10_ARSENAL"),
  Skin(name: "Crimson Moth", passive: "lifesteal halus", weapon: "Silk Needle", skill: "SCARLET COCOON", cost: 2200, motionKey: "NINJA_SKIN_11_MOTION", statusKey: "NINJA_SKIN_11_STATUS", arsenalKey: "SKIN_11_ARSENAL"),
  Skin(name: "Jade Alchemist", passive: "racun menumpuk", weapon: "Jade Chakram", skill: "TRANSMUTE", cost: 2500, motionKey: "NINJA_SKIN_12_MOTION", statusKey: "NINJA_SKIN_12_STATUS", arsenalKey: "SKIN_12_ARSENAL"),
  Skin(name: "Moon Rabbit", passive: "lompatan bulan", weapon: "Mochi Bomb", skill: "MOONFALL", cost: 2800, motionKey: "NINJA_SKIN_13_MOTION", statusKey: "NINJA_SKIN_13_STATUS", arsenalKey: "SKIN_13_ARSENAL"),
  Skin(name: "Iron Beetle", passive: "armor tebal", weapon: "Horn Disc", skill: "FORTRESS", cost: 3100, motionKey: "NINJA_SKIN_14_MOTION", statusKey: "NINJA_SKIN_14_STATUS", arsenalKey: "SKIN_14_ARSENAL"),
  Skin(name: "Void Sailor", passive: "tarik musuh", weapon: "Star Harpoon", skill: "EVENTIDE NET", cost: 3400, motionKey: "NINJA_SKIN_15_MOTION", statusKey: "NINJA_SKIN_15_STATUS", arsenalKey: "SKIN_15_ARSENAL"),
  Skin(name: "Paper Doll", passive: "clone projectile", weapon: "Paper Dart", skill: "1000 CLONES", cost: 3700, motionKey: "NINJA_SKIN_16_MOTION", statusKey: "NINJA_SKIN_16_STATUS", arsenalKey: "SKIN_16_ARSENAL"),
  Skin(name: "Solar Phoenix", passive: "revive bara", weapon: "Solar Feather", skill: "REBIRTH NOVA", cost: 4000, motionKey: "NINJA_SKIN_17_MOTION", statusKey: "NINJA_SKIN_17_STATUS", arsenalKey: "SKIN_17_ARSENAL"),
  Skin(name: "Bone Oracle", passive: "crit takdir", weapon: "Fate Needles", skill: "FATE CAGE", cost: 4300, motionKey: "NINJA_SKIN_18_MOTION", statusKey: "NINJA_SKIN_18_STATUS", arsenalKey: "SKIN_18_ARSENAL"),
  Skin(name: "Prism Pulse", passive: "gelombang lebar", weapon: "Sound Disc", skill: "RESONANCE", cost: 4600, motionKey: "NINJA_SKIN_19_MOTION", statusKey: "NINJA_SKIN_19_STATUS", arsenalKey: "SKIN_19_ARSENAL"),
  Skin(name: "Origin White", passive: "semua damage +", weapon: "Ink Blade", skill: "ORIGIN RESET", cost: 5000, motionKey: "NINJA_SKIN_20_MOTION", statusKey: "NINJA_SKIN_20_STATUS", arsenalKey: "SKIN_20_ARSENAL"),
];

const List<Powerup> POWERUPS = [
  Powerup(type: "bamboo_shield", name: "KEBAL BAMBU", effect: "shield_aura", duration: 9),
  Powerup(type: "shadow_cloak", name: "GHOST MODE", effect: "shadow_phase", duration: 6),
  Powerup(type: "time_hourglass", name: "SLOW TIME", effect: "slow_time", duration: 7),
  Powerup(type: "coin_magnet", name: "MAGNET KOIN", effect: "magnet_swirl", duration: 14),
  Powerup(type: "phoenix_heart", name: "PHOENIX HEART", effect: "phoenix_rebirth", duration: 1.2),
  Powerup(type: "storm_scroll", name: "STORM SHOT", effect: "storm_burst", duration: 9),
  Powerup(type: "moon_seal", name: "MOON FREEZE", effect: "moon_freeze", duration: 7),
  Powerup(type: "dragon_orb", name: "DRAGON RAGE", effect: "dragon_rage", duration: 10),
  Powerup(type: "healing_elixir", name: "HEALING ELIXIR", effect: "healing_bloom", duration: 1),
  Powerup(type: "celestial_aegis", name: "KEBAL CELESTIAL", effect: "aegis_shell", duration: 5),
  Powerup(type: "spirit_lantern", name: "REGEN ROH", effect: "spirit_regen", duration: 12),
  Powerup(type: "clone_charm", name: "CLONE SHOT", effect: "clone_echo", duration: 10),
];

// Raw area config (lanes/floors are the *base*; the .map below adds the +1/+14 offsets).
const List<Map<String, dynamic>> _RAW_AREAS = [
  {"name": "Rooftop Dojo", "boss": "Samurai Apprentice", "lanes": 3, "floors": 24, "enemies": ["shadow_footsoldier", "bone_archer", "bomb_spirit"], "hazards": ["roof_spike", "pendulum_blade"]},
  {"name": "Bamboo Forest", "boss": "Giant Spider Yokai", "lanes": 3, "floors": 24, "enemies": ["bamboo_stalker", "spider_yokai", "poison_toad"], "hazards": ["bamboo_spear", "poison_mist"]},
  {"name": "Crystal Cave", "boss": "Bat Demon Lord", "lanes": 3, "floors": 25, "enemies": ["crystal_bat", "cave_ronin", "shard_slime"], "hazards": ["crystal_stalactite", "bat_swarm"]},
  {"name": "Flooded Dungeon", "boss": "Water Serpent", "lanes": 3, "floors": 25, "enemies": ["drowned_guard", "water_wisp", "kappa_raider"], "hazards": ["water_jet", "drowning_chain"]},
  {"name": "Fire Temple", "boss": "Inferno Monk", "lanes": 4, "floors": 26, "enemies": ["ember_monk", "lava_oni", "fire_wheel"], "hazards": ["fire_wall", "lava_geyser"]},
  {"name": "Forsaken Village", "boss": "Headless Samurai", "lanes": 4, "floors": 26, "enemies": ["headless_guard", "lantern_ghost", "grave_crawler"], "hazards": ["ghost_hand", "cursed_bell"]},
  {"name": "Shadow Market", "boss": "Twin Assassins", "lanes": 4, "floors": 27, "enemies": ["market_assassin", "mask_mage", "chain_brute"], "hazards": ["assassin_wire", "cannon_mask"]},
  {"name": "Spider's Nest", "boss": "Spider Queen", "lanes": 5, "floors": 27, "enemies": ["web_kunoichi", "egg_spider", "silk_priest"], "hazards": ["sticky_web", "falling_egg"]},
  {"name": "Frozen Peak", "boss": "Frost Oni", "lanes": 5, "floors": 28, "enemies": ["frost_ronin", "snow_tengu", "ice_wolf"], "hazards": ["snow_gust", "ice_shard"]},
  {"name": "Abyss Throne", "boss": "Shogun Kegelapan", "lanes": 5, "floors": 30, "enemies": ["abyss_ninja", "void_priest", "shadow_dragon"], "hazards": ["void_hand", "thunder_mark"]},
  {"name": "Storm Pagoda", "boss": "Raijin Herald", "lanes": 6, "floors": 30, "enemies": ["storm_ashigaru", "thunder_kite", "cloud_monk"], "hazards": ["lightning_gate", "storm_fireball"]},
  {"name": "Clockwork Shogunate", "boss": "Brass Daimyo", "lanes": 6, "floors": 31, "enemies": ["gear_samurai", "clockwork_tanuki", "steam_automaton"], "hazards": ["gear_saw", "steam_burst"]},
  {"name": "Sunken Torii", "boss": "Leviathan Priest", "lanes": 6, "floors": 32, "enemies": ["coral_ronin", "lantern_jelly", "shark_yokai"], "hazards": ["current_vortex", "torii_mine"]},
  {"name": "Moonlit Grave Sea", "boss": "Bone Admiral", "lanes": 6, "floors": 33, "enemies": ["boat_wraith", "bone_gunner", "soul_crab"], "hazards": ["soul_tide", "ghost_cannon"]},
  {"name": "Crimson Skyship", "boss": "Sky Oni Captain", "lanes": 6, "floors": 34, "enemies": ["sky_pirate", "cannon_tengu", "bomb_koi"], "hazards": ["cannon_volley", "propeller_blade"]},
  {"name": "Mirror Realm", "boss": "Mirror Empress", "lanes": 7, "floors": 36, "enemies": ["mirror_ninja", "glass_doll", "reflection_fox"], "hazards": ["mirror_beam", "reflection_gate"]},
  {"name": "Blood Moon Garden", "boss": "Gashadokuro Gardener", "lanes": 7, "floors": 37, "enemies": ["moon_cultist", "blood_lotus", "bone_stag"], "hazards": ["moon_laser", "carnivore_vine"]},
  {"name": "Celestial Forge", "boss": "Amaterasu Automaton", "lanes": 7, "floors": 38, "enemies": ["star_smith", "forge_drone", "plasma_oni"], "hazards": ["solar_jet", "star_hammer"]},
  {"name": "Time-Riven Citadel", "boss": "Chrono Tengu", "lanes": 7, "floors": 40, "enemies": ["chrono_guard", "rewind_wisp", "hourglass_beast"], "hazards": ["time_freeze_rune", "rewind_gate"]},
  {"name": "Origin Void", "boss": "Emperor of Nothing", "lanes": 7, "floors": 44, "enemies": ["origin_clone", "ink_seraph", "rainbow_voidling"], "hazards": ["reality_tear", "origin_flame"]},
];

const List<List<String>> _EXTRA_HAZARDS = [
  ["moon_spear", "lantern_bomb"], ["bamboo_crusher", "venom_web"], ["crystal_laser", "cave_collapse"], ["flood_gate", "eel_arc"],
  ["magma_chain", "ember_rain"], ["grave_scream", "spirit_mine"], ["red_lantern_drop", "razor_awning"], ["web_hook", "brood_wave"],
  ["blizzard_wall", "frost_mine"], ["abyss_eye", "void_column"], ["thunder_drum", "cloud_fireline"], ["gear_press", "clock_bomb"],
  ["coral_tentacle", "bubble_mine"], ["grave_anchor", "moon_cannon"], ["sky_hook", "fuel_burst"], ["mirror_clone", "glass_rain"],
  ["blood_root", "moon_orb"], ["forge_beam", "molten_anvil"], ["time_slice", "stasis_bubble"], ["ink_wave", "rainbow_rift"],
];

const List<String> _MECHANICS = [
  "GUST BULAN", "BAMBU MENJEPIT", "GEMA KRISTAL", "ARUS BALIK", "PANAS MENUMPUK",
  "KUTUKAN LAPAR", "SERGAP PASAR", "GRAVITASI JARING", "WHITEOUT", "KEDIP VOID",
  "RITME PETIR", "GEAR SHIFT", "ARUS LAUT", "PAJAK JIWA", "BROADSIDE",
  "CERMIN TERBALIK", "DARAH MEKAR", "FORGE OVERHEAT", "TIME FRACTURE", "REALITY SHUFFLE",
];

final List<Area> AREAS = _RAW_AREAS.asMap().entries.map((entry) {
  final index = entry.key;
  final a = entry.value;
  final id = (index + 1).toString().padLeft(2, "0");
  return Area(
    name: a["name"] as String,
    boss: a["boss"] as String,
    lanes: (a["lanes"] as int) + 1,
    floors: (a["floors"] as int) + 14,
    enemies: List<String>.from(a["enemies"] as List),
    hazards: [...List<String>.from(a["hazards"] as List), ..._EXTRA_HAZARDS[index]],
    extraHazards: _EXTRA_HAZARDS[index],
    mechanic: _MECHANICS[index],
    index: index,
    backgroundKey: index == 0 ? "ROOFTOP_DOJO_BG" : "AREA_${id}_BG",
    enemyKey: "AREA_${id}_ENEMIES",
    bossKey: "AREA_${id}_BOSS",
  );
}).toList();

class WorldAssets {
  static const platforms = AssetRef("PLATFORM_ATLAS");
  static const objects = AssetRef("OBJECT_ATLAS");
  static const effects = AssetRef("EFFECT_SHEET");
  static const obstaclesEarly = AssetRef("OBSTACLES_EARLY");
  static const obstaclesLate = AssetRef("OBSTACLES_LATE");
  static const obstaclesAscended = AssetRef("OBSTACLES_ASCENDED");
  static const obstaclesTranscendent = AssetRef("OBSTACLES_TRANSCENDENT");
  static const obstaclesRemixA = AssetRef("OBSTACLES_REMIX_A");
  static const obstaclesRemixB = AssetRef("OBSTACLES_REMIX_B");
  static const powerups = AssetRef("POWERUP_ATLAS");
  static const powerupEffectsA = AssetRef("POWERUP_EFFECTS_A");
  static const powerupEffectsB = AssetRef("POWERUP_EFFECTS_B");
  static const powerupsB = AssetRef("POWERUP_ATLAS_B");
  static const powerupEffectsC = AssetRef("POWERUP_EFFECTS_C");
}

const List<String> PLATFORM_TYPES = [
  "normal_wood",
  "cracked_bamboo",
  "moving_chain",
  "vanishing_spirit",
  "spiked_wood",
  "ice_bridge",
  "fire_grate",
  "trampoline_drums",
];

class Tweaks {
  final double gravity;
  final double enemyRate;
  final double bossHp;
  final double effectsIntensity;

  const Tweaks({
    required this.gravity,
    required this.enemyRate,
    required this.bossHp,
    required this.effectsIntensity,
  });

  factory Tweaks.defaults() => const Tweaks(
        gravity: 920,
        enemyRate: 0.48,
        bossHp: 24,
        effectsIntensity: 1,
      );
}

const FLOOR_SPACING = 112.0;
const START_Y = 360.0;
