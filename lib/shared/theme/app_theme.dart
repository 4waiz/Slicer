import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Kanban Slicer design system.
///
/// Colours and roles come straight from the art bible: dark teal environment,
/// cyan for guidance, green for success, orange/yellow for warm object
/// sections, purple for advanced mechanics, red for failure, white for the
/// blade and a perfect cut.
class K {
  const K._();

  // Environment
  static const Color bgDeep = Color(0xFF07161C);
  static const Color bg = Color(0xFF0B1E26);
  static const Color bgMid = Color(0xFF12303A);
  static const Color panel = Color(0xFF16323E);
  static const Color panelHi = Color(0xFF1D4354);
  static const Color stroke = Color(0xFF2A5A6E);

  // Roles
  static const Color cyan = Color(0xFF35D6F0);
  static const Color cyanDim = Color(0xFF1BA8C4);
  static const Color green = Color(0xFF3CE08A);
  static const Color orange = Color(0xFFF07A2A);
  static const Color yellow = Color(0xFFF5C93A);
  static const Color purple = Color(0xFFA05FD0);
  static const Color red = Color(0xFFF0524A);
  static const Color white = Color(0xFFF2FBFF);
  static const Color steel = Color(0xFF7FA8C4);
  static const Color textDim = Color(0xFF6F9AB0);

  static const List<Color> zonePalette = [cyan, green, orange, purple];

  static Color zoneColor(String key) => switch (key) {
    'cyan' => cyan,
    'green' => green,
    'orange' => orange,
    'purple' => purple,
    _ => cyan,
  };

  // Type -- condensed, wide-tracked, uppercase. Uses the platform sans so no
  // font binary ships; weight and tracking carry the character.
  static TextStyle display(
    double size, {
    Color color = white,
    double track = 3,
  }) => TextStyle(
    fontSize: size,
    height: 1.05,
    color: color,
    fontWeight: FontWeight.w800,
    letterSpacing: track,
  );

  static TextStyle label(
    double size, {
    Color color = textDim,
    double track = 2.2,
    FontWeight w = FontWeight.w700,
  }) => TextStyle(
    fontSize: size,
    height: 1.1,
    color: color,
    fontWeight: w,
    letterSpacing: track,
  );

  static TextStyle number(double size, {Color color = white}) => TextStyle(
    fontSize: size,
    height: 1.0,
    color: color,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Panel with cut corners -- the angular geometric frame used across the UI.
class AngularPanel extends StatelessWidget {
  const AngularPanel({
    super.key,
    required this.child,
    this.color = K.panel,
    this.border = K.stroke,
    this.cut = 14,
    this.padding = const EdgeInsets.all(16),
    this.glow,
    this.borderWidth = 1.4,
  });

  final Widget child;
  final Color color;
  final Color border;
  final double cut;
  final EdgeInsets padding;
  final Color? glow;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AngularPainter(color, border, cut, glow, borderWidth),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _AngularPainter extends CustomPainter {
  _AngularPainter(this.fill, this.border, this.cut, this.glow, this.strokeW);

  final Color fill;
  final Color border;
  final double cut;
  final Color? glow;
  final double strokeW;

  static Path pathFor(Size size, double cut) {
    final c = cut.clamp(0.0, size.shortestSide * 0.4);
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = pathFor(size, cut);
    if (glow != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glow!.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
  }

  @override
  bool shouldRepaint(_AngularPainter old) =>
      old.fill != fill || old.border != border || old.glow != glow;
}

/// Primary action button in the game's angular style.
class KButton extends StatefulWidget {
  const KButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = K.cyan,
    this.wide = false,
    this.enabled = true,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool wide;
  final bool enabled;
  final Widget? icon;
  final bool compact;

  @override
  State<KButton> createState() => _KButtonState();
}

class _KButtonState extends State<KButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.enabled ? widget.color : K.steel.withValues(alpha: 0.35);
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AngularPanel(
          color: c.withValues(alpha: _down ? 0.34 : 0.20),
          border: c,
          glow: widget.enabled ? c.withValues(alpha: 0.55) : null,
          cut: widget.compact ? 8 : 12,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 14 : (widget.wide ? 46 : 28),
            vertical: widget.compact ? 8 : 14,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                widget.icon!,
                const SizedBox(width: 10),
              ],
              Text(
                widget.label.toUpperCase(),
                style: K.label(
                  widget.compact ? 11 : 14,
                  color: widget.enabled ? K.white : K.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small geometric zone glyph: diamond, square, circle or triangle.
class ZoneGlyph extends StatelessWidget {
  const ZoneGlyph({
    super.key,
    required this.shape,
    required this.color,
    this.size = 18,
    this.filled = true,
  });

  final String shape;
  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(shape, color, filled),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.shape, this.color, this.filled);

  final String shape;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = size.width / 2;
    final c = Offset(r, r);
    switch (shape) {
      case 'circle':
        canvas.drawCircle(c, r * 0.86, p);
      case 'square':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 1.55, height: r * 1.55),
          p,
        );
      case 'triangle':
        canvas.drawPath(
          Path()
            ..moveTo(r, r * 0.14)
            ..lineTo(r * 1.9, r * 1.78)
            ..lineTo(r * 0.1, r * 1.78)
            ..close(),
          p,
        );
      default: // diamond
        canvas.drawPath(
          Path()
            ..moveTo(r, r * 0.1)
            ..lineTo(r * 1.9, r)
            ..lineTo(r, r * 1.9)
            ..lineTo(r * 0.1, r)
            ..close(),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.shape != shape || old.color != color || old.filled != filled;
}

/// Star row used on results and the level map.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 26, this.max = 3});

  final int stars;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      max,
      (i) => Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.09),
        child: CustomPaint(
          size: Size.square(size),
          painter: _StarPainter(i < stars),
        ),
      ),
    ),
  );
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.filled);

  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? r : r * 0.44;
      final x = r + rad * math.cos(angle);
      final y = r + rad * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = K.yellow.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(path, Paint()..color = K.yellow);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = K.steel.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.filled != filled;
}
