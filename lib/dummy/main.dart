// import 'dart:math' as math;

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flame/game.dart';


// void main() => runApp(const MyApp());

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Ninja Descent',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(scaffoldBackgroundColor: const Color(0xff050914), colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
//       home: const GameScreen(),
//     );
//   }
// }

// class GameScreen extends StatefulWidget {
//   const GameScreen({super.key});

//   @override
//   State<GameScreen> createState() => _GameScreenState();
// }

// class _GameScreenState extends State<GameScreen> {
//   late final NinjaGame game;
//   final _focusNode = FocusNode();
//   PointerData? _pointer;

//   @override
//   void initState() {
//     super.initState();
//     game = NinjaGame();
//   }

//   @override
//   void dispose() {
//     _focusNode.dispose();
//     super.dispose();
//   }

//   void _onPointerDown(PointerDownEvent e) {
//     _pointer = PointerData(e.position.dx, e.position.dy, e.timeStamp.inMilliseconds);
//   }

//   void _onPointerUp(PointerUpEvent e) {
//     final start = _pointer;
//     _pointer = null;
//     if (start == null) return;
//     final dx = e.position.dx - start.x;
//     final dy = e.position.dy - start.y;
//     final distance = math.sqrt(dx * dx + dy * dy);
//     final duration = e.timeStamp.inMilliseconds - start.time;
//     if (distance > 34) {
//       if (dx.abs() > dy.abs()) {
//         game.move(dx < 0 ? -1 : 1);
//       } else if (dy < 0) {
//         game.slash();
//       } else {
//         game.fastFall(false);
//       }
//     } else {
//       game.shoot(duration > 360);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: KeyboardListener(
//         focusNode: _focusNode,
//         onKeyEvent: _onKey,
//         child: Listener(
//           onPointerDown: _onPointerDown,
//           onPointerUp: _onPointerUp,
//           child: Stack(
//             children: [
//               GameWidget(game: game),
//               GameUI(game: game),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   void _onKey(KeyEvent e) {
//     if (e is! KeyDownEvent) return;
//     final key = e.logicalKey;
//     if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) game.move(-1);
//     else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) game.move(1);
//     else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) game.slash();
//     else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) game.fastFall(false);
//     else if (key == LogicalKeyboardKey.space) game.shoot(false);
//     else if (key == LogicalKeyboardKey.keyE) game.dash();
//   }
// }

// class PointerData {
//   final double x;
//   final double y;
//   final int time;
//   PointerData(this.x, this.y, this.time);
// }
