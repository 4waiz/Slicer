import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../camera/camera3d.dart';

/// A short-lived 3D spark / fragment drawn as a screen-space streak.
///
/// Debris is deliberately not fed through the mesh pipeline: hundreds of tiny
/// rigid bodies would dominate the frame for something on screen for 600 ms.
class Spark {
  Spark({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
    this.size = 3.0,
    this.gravity = -12.0,
    this.streak = 1.0,
  }) : age = 0.0;

  Vector3 position;
  Vector3 velocity;
  Color color;
  double life;
  double age;
  double size;
  double gravity;

  /// How much the previous position smears into a motion streak.
  double streak;

  bool get dead => age >= life;
  double get t => (age / life).clamp(0.0, 1.0);
}

/// Screen-space flash overlay (cut flash, perfect-cut burst, error pulse).
class Flash {
  Flash({required this.color, required this.life, this.intensity = 1.0})
    : age = 0.0;

  Color color;
  double life;
  double age;
  double intensity;

  bool get dead => age >= life;
  double get t => (age / life).clamp(0.0, 1.0);
}

/// Fading world-space cut outline, drawn as a bright line along the cut loop.
class CutGlow {
  CutGlow({required this.loops, required this.color, this.life = 0.55})
    : age = 0.0;

  final List<List<Vector3>> loops;
  final Color color;
  final double life;
  double age;

  bool get dead => age >= life;
  double get t => (age / life).clamp(0.0, 1.0);
}

/// A live warning ring around an armed explosive core.
///
/// Rebuilt from the physics state every frame rather than animated
/// independently, so what the player sees is exactly the real fuse.
class ArmedCore {
  ArmedCore({
    required this.position,
    required this.radius,
    required this.progress,
  });

  final Vector3 position;

  /// Blast radius in world units -- the ring shows the actual danger area.
  final double radius;

  /// 0 when it arms, 1 when it goes off.
  final double progress;
}

/// Expanding ring left behind by a detonation.
class Shockwave {
  Shockwave({required this.position, required this.radius, required this.color})
    : age = 0.0;

  final Vector3 position;
  final double radius;
  final Color color;
  double age;

  static const double life = 0.5;

  bool get dead => age >= life;
  double get t => (age / life).clamp(0.0, 1.0);
}

/// Owns all transient visual effects and draws the ones that live in 2D.
class EffectSystem {
  EffectSystem({math.Random? rng}) : _rng = rng ?? math.Random(7);

  final math.Random _rng;

  final List<Spark> sparks = <Spark>[];
  final List<Flash> flashes = <Flash>[];
  final List<CutGlow> cutGlows = <CutGlow>[];
  final List<Shockwave> shockwaves = <Shockwave>[];

  /// Refreshed every frame by the controller from live fuse state.
  final List<ArmedCore> armedCores = <ArmedCore>[];

  /// Screen-space confetti for a perfect result.
  final List<_Confetti> _confetti = <_Confetti>[];

  int get activeCount => sparks.length + flashes.length + cutGlows.length;

  void clear() {
    sparks.clear();
    flashes.clear();
    cutGlows.clear();
    shockwaves.clear();
    armedCores.clear();
    _confetti.clear();
  }

  /// Expanding ring marking a detonation.
  void shockwave(Vector3 at, double radius, Color color) {
    shockwaves.add(Shockwave(position: at, radius: radius, color: color));
  }

  void update(double dt) {
    for (var i = sparks.length - 1; i >= 0; i--) {
      final s = sparks[i];
      s.age += dt;
      if (s.dead) {
        sparks.removeAt(i);
        continue;
      }
      s.velocity.y += s.gravity * dt;
      s.position.addScaled(s.velocity, dt);
    }
    for (var i = flashes.length - 1; i >= 0; i--) {
      flashes[i].age += dt;
      if (flashes[i].dead) flashes.removeAt(i);
    }
    for (var i = cutGlows.length - 1; i >= 0; i--) {
      cutGlows[i].age += dt;
      if (cutGlows[i].dead) cutGlows.removeAt(i);
    }
    for (var i = shockwaves.length - 1; i >= 0; i--) {
      shockwaves[i].age += dt;
      if (shockwaves[i].dead) shockwaves.removeAt(i);
    }
    for (var i = _confetti.length - 1; i >= 0; i--) {
      final c = _confetti[i];
      c.age += dt;
      if (c.age >= c.life) {
        _confetti.removeAt(i);
        continue;
      }
      c.vy += 900 * dt;
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.spin += c.spinRate * dt;
    }
  }

  /// Sparks thrown along the cut line at the moment of contact.
  void burstAlongCut(
    List<List<Vector3>> loops,
    Color color,
    int perLoop, {
    double speed = 3.2,
  }) {
    for (final loop in loops) {
      if (loop.isEmpty) continue;
      for (var i = 0; i < perLoop; i++) {
        final p = loop[_rng.nextInt(loop.length)];
        sparks.add(
          Spark(
            position: p.clone(),
            velocity: Vector3(
              (_rng.nextDouble() - 0.5) * speed,
              _rng.nextDouble() * speed * 0.9 + 0.4,
              (_rng.nextDouble() - 0.5) * speed,
            ),
            color: color,
            life: 0.35 + _rng.nextDouble() * 0.45,
            size: 2.0 + _rng.nextDouble() * 3.4,
            streak: 1.4,
          ),
        );
      }
    }
  }

  /// Impact puff when a piece lands.
  void landing(Vector3 at, Color color, {int count = 10, double speed = 2.2}) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      sparks.add(
        Spark(
          position: at.clone(),
          velocity: Vector3(
            math.cos(a) * speed * _rng.nextDouble(),
            _rng.nextDouble() * speed * 0.7 + 0.5,
            math.sin(a) * speed * _rng.nextDouble(),
          ),
          color: color,
          life: 0.3 + _rng.nextDouble() * 0.3,
          size: 2.0 + _rng.nextDouble() * 2.5,
          gravity: -9.0,
          streak: 0.7,
        ),
      );
    }
  }

  void flash(Color color, double life, {double intensity = 1.0}) {
    flashes.add(Flash(color: color, life: life, intensity: intensity));
  }

  void cutOutline(List<List<Vector3>> loops, Color color) {
    if (loops.isEmpty) return;
    cutGlows.add(CutGlow(loops: loops, color: color));
  }

  void confetti(Size screen, List<Color> colors, {int count = 90}) {
    for (var i = 0; i < count; i++) {
      _confetti.add(
        _Confetti(
          x: screen.width * (0.2 + _rng.nextDouble() * 0.6),
          y: screen.height * (0.3 + _rng.nextDouble() * 0.2),
          vx: (_rng.nextDouble() - 0.5) * 900,
          vy: -320 - _rng.nextDouble() * 520,
          w: 5 + _rng.nextDouble() * 9,
          h: 3 + _rng.nextDouble() * 6,
          color: colors[_rng.nextInt(colors.length)],
          life: 1.3 + _rng.nextDouble() * 1.0,
          spin: _rng.nextDouble() * 6.28,
          spinRate: (_rng.nextDouble() - 0.5) * 14,
        ),
      );
    }
  }

  /// Draws sparks and cut outlines, which live in the world and must be
  /// composited after the 3D pass.
  void drawWorld(Canvas canvas, Camera3D camera) {
    final paint = Paint()..blendMode = BlendMode.plus;

    _drawBlastRings(canvas, camera, paint);

    for (final g in cutGlows) {
      final fade = 1.0 - g.t;
      paint
        ..color = g.color.withValues(alpha: fade * 0.9)
        ..strokeWidth = 2.0 + fade * 4.0
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 + fade * 6.0);
      for (final loop in g.loops) {
        if (loop.length < 2) continue;
        final path = Path();
        var started = false;
        for (final p in loop) {
          final s = camera.project(p);
          if (s == null) continue;
          if (!started) {
            path.moveTo(s.dx, s.dy);
            started = true;
          } else {
            path.lineTo(s.dx, s.dy);
          }
        }
        if (started) {
          path.close();
          canvas.drawPath(path, paint);
        }
      }
    }

    paint
      ..style = PaintingStyle.fill
      ..maskFilter = null;
    for (final s in sparks) {
      final head = camera.project(s.position);
      if (head == null) continue;
      final fade = 1.0 - s.t;
      final a = (fade * fade).clamp(0.0, 1.0);
      paint.color = s.color.withValues(alpha: a);

      if (s.streak > 0.2) {
        // Trail the previous position to read as motion blur.
        final tailPos = s.position - s.velocity * (0.026 * s.streak);
        final tail = camera.project(tailPos);
        if (tail != null) {
          paint
            ..strokeWidth = s.size * fade
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(tail, head, paint);
          paint.style = PaintingStyle.fill;
        }
      }
      canvas.drawCircle(head, s.size * fade * 0.55, paint);
    }
  }

  /// Projects a world-space circle to a screen ellipse.
  ///
  /// Returns null if the centre is behind the eye. The vertical squash is the
  /// same trick the contact shadows use -- a true projected circle would need
  /// a full conic, and at these radii the difference is invisible.
  (Offset, double)? _projectRing(
    Camera3D camera,
    Vector3 centre,
    double radius,
  ) {
    final c = camera.project(centre);
    if (c == null) return null;
    final edge = camera.project(Vector3(centre.x + radius, centre.y, centre.z));
    if (edge == null) return null;
    return (c, (edge - c).distance);
  }

  /// Danger rings around armed cores, and the ring a blast leaves behind.
  void _drawBlastRings(Canvas canvas, Camera3D camera, Paint paint) {
    paint
      ..style = PaintingStyle.stroke
      ..maskFilter = null;

    for (final core in armedCores) {
      final projected = _projectRing(camera, core.position, core.radius);
      if (projected == null) continue;
      final (centre, px) = projected;

      // Pulse accelerates as the fuse runs down -- the same signal the core's
      // own glow is giving, so the two read as one warning.
      final pulse =
          0.5 +
          0.5 *
              math.sin(core.progress * math.pi * (6.0 + core.progress * 22.0));
      final alpha = (0.20 + 0.45 * core.progress) * (0.45 + 0.55 * pulse);

      paint
        ..color = const Color(0xFFF07A2A).withValues(alpha: alpha)
        ..strokeWidth = 1.6 + 2.6 * core.progress;
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: px * 2, height: px * 0.82),
        paint,
      );

      // A second ring closing in on the first shows time running out.
      final closing = px * (1.0 - core.progress * 0.72);
      paint
        ..color = const Color(0xFFF5C93A).withValues(alpha: alpha * 0.7)
        ..strokeWidth = 1.4;
      canvas.drawOval(
        Rect.fromCenter(
          center: centre,
          width: closing * 2,
          height: closing * 0.82,
        ),
        paint,
      );
    }

    for (final w in shockwaves) {
      // easeOutQuad: fast expansion that decelerates, so the ring reads as a
      // pressure wave rather than a linear wipe.
      final inv = 1.0 - w.t;
      final grow = 1.0 - inv * inv;
      final projected = _projectRing(
        camera,
        w.position,
        w.radius * (0.25 + grow * 0.95),
      );
      if (projected == null) continue;
      final (centre, px) = projected;
      final fade = 1.0 - w.t;
      paint
        ..color = w.color.withValues(alpha: fade * 0.85)
        ..strokeWidth = 2.0 + fade * 7.0
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.0 + fade * 5.0);
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: px * 2, height: px * 0.86),
        paint,
      );
    }

    paint
      ..style = PaintingStyle.fill
      ..maskFilter = null;
  }

  /// Full-screen flashes and confetti, drawn last.
  void drawScreen(Canvas canvas, Size size) {
    for (final f in flashes) {
      final fade = (1.0 - f.t);
      final a = (fade * fade * f.intensity).clamp(0.0, 1.0);
      if (a <= 0.002) continue;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = f.color.withValues(alpha: a * 0.55)
          ..blendMode = BlendMode.plus,
      );
    }

    for (final c in _confetti) {
      final fade = 1.0 - (c.age / c.life).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(c.x, c.y);
      canvas.rotate(c.spin);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: c.w, height: c.h),
        Paint()..color = c.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }
}

class _Confetti {
  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required this.color,
    required this.life,
    required this.spin,
    required this.spinRate,
  }) : age = 0;

  double x, y, vx, vy, w, h, spin, spinRate, life, age;
  Color color;
}
