// Parses the custom frames.json atlas format used by the game assets, and
// owns the (lazily decoded) sprite-sheet image behind it.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Frame {
  final String name;
  final ui.Rect source;
  final ui.Rect content;
  final ui.Offset anchor;

  Frame({
    required this.name,
    required this.source,
    required this.content,
    required this.anchor,
  });

  factory Frame.fromJson(Map<String, dynamic> json) {
    final s = json['source'] as Map<String, dynamic>;
    final c = (json['content'] as Map<String, dynamic>?) ?? s;
    final a = (json['anchor'] as Map<String, dynamic>?) ??
        {'x': s['x']! + s['w']! / 2, 'y': s['y']! + s['h']!};
    return Frame(
      name: json['name'] as String,
      source: ui.Rect.fromLTWH(_d(s['x']), _d(s['y']), _d(s['w']), _d(s['h'])),
      content: ui.Rect.fromLTWH(_d(c['x']), _d(c['y']), _d(c['w']), _d(c['h'])),
      anchor: ui.Offset(_d(a['x']), _d(a['y'])),
    );
  }
}

class Animation {
  final String name;
  final List<Frame> frames;
  // Tallest frame, used to scale anchored actors consistently across frames.
  late final double maxHeight = frames.fold(0.0, (m, f) => f.content.height > m ? f.content.height : m);
  Animation(this.name, this.frames);
}

// Seconds since startup; atlases record when they were last drawn.
final Stopwatch _clock = Stopwatch()..start();
double get assetClock => _clock.elapsedMilliseconds / 1000;

// A sprite sheet whose frame data is always available but whose image is
// decoded only while it is needed. Decoded, the 134 sheets take ~1.4 GB, so
// the game keeps just what is around the player (see GameAssets.prefetch).
class Atlas {
  final String imagePath;
  final Map<String, Frame> frames;
  final Map<String, Animation> animations;
  // Pinned atlases (platforms, coins, effects…) are needed everywhere and are
  // never evicted.
  final bool pinned;

  ui.Image? _image;
  Future<ui.Image?>? _loading;
  double lastUsed = double.negativeInfinity;

  Atlas(this.imagePath, this.frames, this.animations, {this.pinned = false});

  bool get isLoaded => _image != null;

  // The image to draw this frame. Marks the atlas as in use and starts
  // decoding it if needed; null until the decode finishes.
  ui.Image? get image {
    lastUsed = assetClock;
    if (_image == null) load();
    return _image;
  }

  // Marks the atlas as needed soon without drawing it.
  void touch() {
    lastUsed = assetClock;
    if (_image == null) load();
  }

  Future<ui.Image?> load() => _loading ??= _decode();

  Future<ui.Image?> _decode() async {
    try {
      final data = await rootBundle.load(imagePath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      _image = frame.image;
      return _image;
    } catch (error) {
      debugPrint("Atlas load failed: $imagePath $error");
      _loading = null;
      return null;
    }
  }

  // Frees the decoded image; it is decoded again on next use.
  void evict() {
    if (pinned || _image == null) return;
    _image!.dispose();
    _image = null;
    _loading = null;
  }

  Frame? operator [](String name) => frames[name];
  Animation? anim(String name) => animations[name];
}

double _d(dynamic v) => (v as num).toDouble();

Atlas parseAtlas(String imagePath, Map<String, dynamic>? json, {bool pinned = false}) {
  final frameList = (json?['frames'] as List?) ?? [];
  final frames = <String, Frame>{
    for (final frame in frameList.map((f) => Frame.fromJson(f as Map<String, dynamic>))) frame.name: frame,
  };
  final animList = (json?['animations'] as List?) ?? [];
  final animations = <String, Animation>{};
  for (final a in animList) {
    final am = a as Map<String, dynamic>;
    final fl = (am['frames'] as List?) ?? [];
    animations[am['name'] as String] = Animation(
      am['name'] as String,
      [for (final f in fl) Frame.fromJson(f as Map<String, dynamic>)],
    );
  }
  return Atlas(imagePath, frames, animations, pinned: pinned);
}
