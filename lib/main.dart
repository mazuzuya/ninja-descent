import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';

import 'game/game.dart';
import 'game/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A one-handed portrait game: full screen, no system bars over the HUD.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ninja Descent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: "Inter",
        scaffoldBackgroundColor: const Color(0xff050914),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffd5b260), brightness: Brightness.dark),
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final NinjaGame game;
  PointerData? _pointer;

  @override
  void initState() {
    super.initState();
    game = NinjaGame();
    WidgetsBinding.instance.addObserver(this);
    // A global handler: Flame's GameWidget takes keyboard focus for itself, so a
    // focus-based KeyboardListener above it never receives any key.
    HardwareKeyboard.instance.addHandler(_onKey);
    if (NinjaGame.devTools) SchedulerBinding.instance.addTimingsCallback(_logFrameTimings);
  }

  // Dev builds log frame cost to logcat so jank can be measured on a device.
  void _logFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _buildMs.add(t.buildDuration.inMicroseconds / 1000);
      _rasterMs.add(t.rasterDuration.inMicroseconds / 1000);
    }
    if (_buildMs.length < 180) return;
    String stats(List<double> ms) {
      ms.sort();
      return "avg ${(ms.reduce((a, b) => a + b) / ms.length).toStringAsFixed(1)} p95 ${ms[(ms.length * 0.95).floor()].toStringAsFixed(1)} max ${ms.last.toStringAsFixed(1)}";
    }

    final slow = [for (int i = 0; i < _buildMs.length; i += 1) i].where((i) => _buildMs[i] + _rasterMs[i] > 16.7).length;
    debugPrint("FRAMES n=${_buildMs.length} over16ms=$slow ui[${stats([..._buildMs])}] raster[${stats([..._rasterMs])}]");
    _buildMs.clear();
    _rasterMs.clear();
  }

  final List<double> _buildMs = [];
  final List<double> _rasterMs = [];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      game.onAppForegrounded();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      game.onAppBackgrounded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = PointerData(e.pointer, e.position.dx, e.position.dy, e.timeStamp.inMilliseconds);
    game.setCharging(true);
  }

  // Swipes fire as soon as they cross the threshold rather than on release, so
  // lane changes feel immediate. A consumed pointer can no longer become a tap.
  void _onPointerMove(PointerMoveEvent e) {
    final start = _pointer;
    if (start == null || start.id != e.pointer || start.consumed) return;
    final dx = e.position.dx - start.x;
    final dy = e.position.dy - start.y;
    if (math.sqrt(dx * dx + dy * dy) <= 34) return;
    start.consumed = true;
    game.setCharging(false);
    if (dx.abs() > dy.abs()) {
      game.move(dx < 0 ? -1 : 1);
    } else if (dy < 0) {
      game.slash();
    } else {
      game.fastFall(false);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final start = _pointer;
    if (start == null || start.id != e.pointer) return;
    _pointer = null;
    game.setCharging(false);
    if (!start.consumed) game.shoot(e.timeStamp.inMilliseconds - start.time > 360);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !game.handleBack()) SystemNavigator.pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Only the arena reads swipes/taps (JS binds them to the canvas
            // and ignores buttons/overlays), so HUD buttons never also shoot.
            Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerMove: _onPointerMove,
              onPointerCancel: (_) {
                _pointer = null;
                game.setCharging(false);
              },
              child: RepaintBoundary(child: GameWidget(game: game)),
            ),
            // Separate layer so HUD repaints don't repaint the arena (and vice versa).
            RepaintBoundary(child: GameUI(game: game)),
          ],
        ),
      ),
    );
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      game.move(-1);
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      game.move(1);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      game.slash();
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      game.fastFall(false);
    } else if (key == LogicalKeyboardKey.space) {
      game.shoot(false);
    } else if (key == LogicalKeyboardKey.keyE) {
      game.dash();
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      game.pauseGame();
    } else if (NinjaGame.devTools && key == LogicalKeyboardKey.keyB) {
      game.devJump(toBoss: true);
    } else if (NinjaGame.devTools && key == LogicalKeyboardKey.keyN) {
      game.devJump();
    } else if (NinjaGame.devTools && key == LogicalKeyboardKey.keyU) {
      game.devNextSkin();
    } else if (NinjaGame.devTools && key == LogicalKeyboardKey.keyH) {
      game.devHeal();
    } else if (key == LogicalKeyboardKey.backquote) {
      // D is "move right" in the JS, so the debug overlay lives on `.
      game.toggleDebug();
    }
    return false;
  }
}

class PointerData {
  final int id;
  final double x;
  final double y;
  final int time;
  bool consumed = false;
  PointerData(this.id, this.x, this.y, this.time);
}
