// Audio layer mirroring game js/game/audio.js. SFX live in assets/sfx and
// music in assets/bgm as .mp3. Files are placeholders until replaced by hand;
// a missing or empty file fails silently (see the catchError / try blocks).
import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class Audio {
  static AudioContext _mixingContext() => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

  // Non-boss tracks are picked at random; the boss track is always bgm_boss.
  static const normalTracks = ["bgm_1", "bgm_2", "bgm_3", "bgm_4"];
  static const bossTrack = "bgm_boss";

  final math.Random _rng = math.Random();
  final Map<String, Future<AudioPool?>> _pools = {};
  final Map<String, int> _lastPlayed = {};
  final Stopwatch _clock = Stopwatch()..start();
  bool _disposed = false;

  bool sfxEnabled = true;
  bool hapticsEnabled = true;
  bool _musicEnabled = true;

  AudioPlayer? _music;
  String? _track;
  bool _musicHeld = false;

  bool get musicEnabled => _musicEnabled;
  set musicEnabled(bool value) {
    _musicEnabled = value;
    _applyMusic();
  }

  // ---- SFX (assets/sfx/<name>.mp3) ----
  void jump() => _play("jump");
  void shoot() => _play("shoot", players: 6);
  void slash() => _play("slash");
  void hit() => _play("hit", players: 4);
  void enemyDie() => _play("enemy_die", players: 3);
  void coin() => _play("coin", players: 2);
  void dash() => _play("dash");
  void win() => _play("win");
  void powerup() => _play("powerup");
  void land() => _play("land", players: 2);
  void pound() => _play("pound");
  void bossAppear() => _play("boss_appear", players: 1);
  void bossAttack() => _play("boss_attack", players: 2);
  void areaClear() => _play("area_clear", players: 1);
  void gameOver() => _play("gameover", players: 1);
  void shield() => _play("shield", players: 1);
  void revive() => _play("revive", players: 1);
  void heal() => _play("heal", players: 1);
  void skinChange() => _play("skin_change", players: 1);
  void uiTap() => _play("ui_tap", players: 2);
  void uiBuy() => _play("ui_buy", players: 1);

  // ---- BGM (assets/bgm/<track>.mp3), looping ----
  // Random non-boss track, avoiding [avoid] when there is another choice.
  String pickNormalTrack([String? avoid]) {
    final pool = normalTracks.where((t) => t != avoid).toList();
    return pool[_rng.nextInt(pool.length)];
  }

  // Looping background track; null stops it. Re-selecting the same track is a no-op.
  void playMusic(String? track) {
    if (_track == track) return;
    _track = track;
    _applyMusic(restart: true);
  }

  // Held while the app is in the background.
  void holdMusic(bool held) {
    _musicHeld = held;
    _applyMusic();
  }

  Future<void> _applyMusic({bool restart = false}) async {
    if (_disposed) return;
    try {
      final player = _music ??= AudioPlayer();
      await player.setAudioContext(_mixingContext());
      await player.setReleaseMode(ReleaseMode.loop);
      if (_track == null || !_musicEnabled || _musicHeld) {
        await (_track == null ? player.stop() : player.pause());
        return;
      }
      if (restart || player.source == null) {
        await player.setVolume(0.42);
        await player.play(AssetSource("bgm/$_track.mp3"));
      } else {
        await player.resume();
      }
    } catch (_) {}
  }

  // sdk.device.haptics.vibrate(45 / 18) in the JS.
  void haptic({bool strong = false}) {
    if (!hapticsEnabled) return;
    unawaited((strong ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact()).catchError((_) {}));
  }

  Future<void> unlock() async {}

  void _play(String name, {int players = 3}) {
    if (_disposed || !sfxEnabled) return;
    // Bursts of the same sound in one instant only make it louder and clip.
    final now = _clock.elapsedMilliseconds;
    if (now - (_lastPlayed[name] ?? -1000) < 40) return;
    _lastPlayed[name] = now;
    final pool = _pools.putIfAbsent(
      name,
      () => AudioPool.create(
            source: AssetSource("sfx/$name.mp3"),
            maxPlayers: players,
            audioContext: _mixingContext(),
          )
          .then<AudioPool?>((pool) => pool)
          .catchError((Object _) => null),
    );
    unawaited(pool.then((p) async {
      try {
        await p?.start();
      } catch (_) {}
    }));
  }

  Future<void> dispose() async {
    _disposed = true;
    await _music?.dispose();
    for (final pool in _pools.values) {
      final p = await pool;
      await p?.dispose();
    }
    _pools.clear();
  }
}
