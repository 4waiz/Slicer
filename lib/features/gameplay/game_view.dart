import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../game/game_controller.dart';
import '../../game/renderer/scene_renderer.dart';
import '../../shared/theme/app_theme.dart';

/// Draws the 3D stage: backdrop, shadows, meshes, effects and the swipe guide.
class GameView extends StatefulWidget {
  const GameView({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  final SceneRenderer _renderer = SceneRenderer();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        widget.controller.camera.setViewport(size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => widget.controller.onPanStart(d.localPosition),
          onPanUpdate: (d) => widget.controller.onPanUpdate(d.localPosition),
          onPanEnd: (_) => widget.controller.onPanEnd(),
          onPanCancel: widget.controller.onPanEnd,
          child: CustomPaint(
            size: size,
            painter: _ScenePainter(widget.controller, _renderer),
            isComplex: true,
            willChange: true,
          ),
        );
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.c, this.renderer) : super(repaint: c);

  final GameController c;
  final SceneRenderer renderer;

  @override
  void paint(Canvas canvas, Size size) {
    c.paintTicks++;
    c.lastPaintSize = size;
    _drawBackdrop(canvas, size);

    if (c.phase == GamePhase.loading || c.phase == GamePhase.error) return;

    SceneRenderer.drawShadows(canvas, c.camera, c.nodes, 0.02);
    renderer.render(canvas, c.camera, c.nodes, c.lighting);
    c.lastTriangles = renderer.lastTriangleCount;
    c.effects.drawWorld(canvas, c.camera);
    _drawSwipeGuide(canvas, size);
    c.effects.drawScreen(canvas, size);
  }

  /// Dark teal stage: radial pool of light, horizon band, perspective grid.
  void _drawBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, size.height * 0.44),
          size.width * 0.78,
          const [K.bgMid, K.bg, K.bgDeep],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Horizon glow behind the pads anchors the stage in landscape.
    final horizonY = size.height * 0.66;
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        horizonY - size.height * 0.22,
        size.width,
        size.height * 0.44,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizonY - size.height * 0.22),
          Offset(0, horizonY + size.height * 0.22),
          [
            K.cyan.withValues(alpha: 0.0),
            K.cyanDim.withValues(alpha: 0.09),
            K.cyan.withValues(alpha: 0.0),
          ],
          // dart:ui requires explicit stops for anything other than exactly
          // two colours -- omitting them throws on every frame.
          const [0.0, 0.5, 1.0],
        ),
    );

    final grid = Paint()
      ..color = K.cyan.withValues(alpha: 0.055)
      ..strokeWidth = 1.0;
    for (var i = 1; i < 9; i++) {
      final t = i / 9.0;
      final y = horizonY + math.pow(t, 2.1) * size.height * 0.42;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = -7; i <= 7; i++) {
      final x = size.width * 0.5 + i * size.width * 0.085;
      canvas.drawLine(
        Offset(size.width * 0.5 + i * size.width * 0.028, horizonY),
        Offset(x, size.height),
        grid,
      );
    }
  }

  /// Thin cutting guide plus the projected blade line while the finger is down.
  void _drawSwipeGuide(Canvas canvas, Size size) {
    final a = c.swipeStart;
    final b = c.swipeCurrent;
    if (a == null || b == null) return;

    final d = b - a;
    final len = d.distance;
    if (len < 2) return;

    // Extend the guide across the whole screen so the player sees the plane.
    final dir = d / len;
    final ext = size.longestSide * 1.5;
    final p1 = a - dir * ext;
    final p2 = a + dir * ext;

    final armed = len >= 24.0;
    final colour = armed ? K.cyan : K.steel;

    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = colour.withValues(alpha: 0.16)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = colour.withValues(alpha: armed ? 0.95 : 0.5)
        ..strokeWidth = armed ? 3.4 : 2.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = K.white.withValues(alpha: armed ? 0.95 : 0.45)
        ..strokeWidth = armed ? 1.6 : 1.0
        ..strokeCap = StrokeCap.round,
    );

    // Entry / exit markers.
    for (final (pt, r) in [(a, 5.0), (b, 7.0)]) {
      canvas.drawCircle(
        pt,
        r,
        Paint()
          ..color = colour.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}
