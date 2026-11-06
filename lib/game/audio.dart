// Audio layer mirroring game js/game/audio.js. The JS synthesizes WebAudio
// tones at runtime; the identical synthesis is baked into assets/sfx by
// tool/generate_sfx.dart and played here through low-latency pools.
import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class Audio {
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

  void jump() => _play("jump");
  void shoot([bool charged = false]) => _play(charged ? "shoot_charged" : "shoot", players: 6);
  void slash() => _play("slash");
  void hit() => _play("hit", players: 4);
  // Pitch rises with combo up to the 1.5x cap reached at combo 15.
  void coin([int combo = 1]) => _play("coin_${math.max(0, math.min(15, combo))}", players: 2);
  void dash() => _play("dash");
  void victory() => _play("victory");
  void land() => _play("land", players: 2);
  void pound() => _play("pound");
  void bossHit() => _play("boss_hit", players: 4);
  void bossAppear() => _play("boss_appear", players: 1);
  void areaClear() => _play("area_clear", players: 1);
  void gameOver() => _play("gameover", players: 1);
  void uiTap() => _play("ui_tap", players: 2);
  void uiBuy() => _play("ui_buy", players: 1);
  void heal() => _play("heal", players: 1);

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
      final player = _music ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      if (_track == null || !_musicEnabled || _musicHeld) {
        await (_track == null ? player.stop() : player.pause());
        return;
      }
      if (restart || player.source == null) {
        await player.setVolume(0.42);
        await player.play(AssetSource("sfx/$_track.wav"));
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
      () => AudioPool.createFromAsset(path: "sfx/$name.wav", maxPlayers: players)
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
