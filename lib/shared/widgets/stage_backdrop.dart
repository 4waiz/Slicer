import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The shared dark-teal environment used behind every non-gameplay screen.
class StageBackdrop extends StatelessWidget {
  const StageBackdrop({super.key, this.accent = K.cyan, this.grid = true});

  final Color accent;
  final bool grid;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BackdropPainter(accent, grid), size: Size.infinite);
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.accent, this.grid);

  final Color accent;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.62, size.height * 0.42),
          size.width * 0.8,
          [K.bgMid, K.bg, K.bgDeep],
          const [0.0, 0.5, 1.0],
        ),
    );

    if (!grid) return;

    final line = Paint()
      ..color = accent.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    final horizon = size.height * 0.70;
    for (var i = 1; i < 8; i++) {
      final t = i / 8.0;
      final y = horizon + math.pow(t, 2.0) * size.height * 0.36;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(
        Offset(size.width * 0.5 + i * size.width * 0.03, horizon),
        Offset(size.width * 0.5 + i * size.width * 0.10, size.height),
        line,
      );
    }

    // Soft accent bloom in the upper corner, echoing the art bible lighting.
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.14),
      size.width * 0.24,
      Paint()
        ..color = accent.withValues(alpha: 0.05)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 60),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.accent != accent || old.grid != grid;
}

/// Screen chrome shared by every menu screen: backdrop, title and back button.
class MenuScaffold extends StatelessWidget {
  const MenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.accent = K.cyan,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        StageBackdrop(accent: accent),
        Padding(
          padding: EdgeInsets.only(
            left: pad.left + 22,
            right: pad.right + 22,
            top: pad.top + 14,
            bottom: pad.bottom + 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: AngularPanel(
                      cut: 8,
                      color: K.panel.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 9,
                      ),
                      child: Text('BACK', style: K.label(10, color: K.steel)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: K.display(20, track: 6)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: K.label(9.5, color: accent, track: 2.4),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}
