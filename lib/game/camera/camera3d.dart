import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

import '../slicing/plane.dart';

/// Perspective camera with an explicit orthonormal basis.
///
/// Keeping (forward, right, up) around means screen->world rays need no matrix
/// inversion, which is what makes swipe-to-plane conversion exact and cheap.
class Camera3D {
  Camera3D({
    Vector3? position,
    Vector3? target,
    this.fovY = 0.62,
    this.near = 0.1,
    this.far = 120.0,
  })  : position = position ?? Vector3(0, 3.4, 9.0),
        target = target ?? Vector3.zero() {
    _rebuild();
  }

  Vector3 position;
  Vector3 target;
  double fovY;
  double near;
  double far;

  Size viewport = const Size(1, 1);

  final Vector3 _forward = Vector3(0, 0, -1);
  final Vector3 _right = Vector3(1, 0, 0);
  final Vector3 _up = Vector3(0, 1, 0);

  Vector3 get forward => _forward;
  Vector3 get right => _right;
  Vector3 get upVector => _up;

  double _tanHalf = 1.0;
  double _aspect = 1.0;
  double _halfW = 0.5;
  double _halfH = 0.5;

  void setViewport(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    viewport = size;
    _aspect = size.width / size.height;
    _halfW = size.width * 0.5;
    _halfH = size.height * 0.5;
    _rebuild();
  }

  void lookAt(Vector3 eye, Vector3 at) {
    position = eye;
    target = at;
    _rebuild();
  }

  void _rebuild() {
    _tanHalf = math.tan(fovY * 0.5);
    _forward
      ..setFrom(target)
      ..sub(position);
    if (_forward.length2 < 1e-12) _forward.setValues(0, 0, -1);
    _forward.normalize();

    // Guard against a degenerate basis when looking straight up or down.
    final worldUp =
        _forward.y.abs() > 0.999 ? Vector3(0, 0, 1) : Vector3(0, 1, 0);
    _right
      ..setFrom(_forward.cross(worldUp))
      ..normalize();
    _up
      ..setFrom(_right.cross(_forward))
      ..normalize();
  }

  /// Camera-space depth (distance along [forward]). Larger is farther away.
  double depthOf(double wx, double wy, double wz) =>
      (wx - position.x) * _forward.x +
      (wy - position.y) * _forward.y +
      (wz - position.z) * _forward.z;

  /// Projects a world point to screen pixels. Returns null when behind the eye.
  Offset? project(Vector3 world) {
    final dx = world.x - position.x;
    final dy = world.y - position.y;
    final dz = world.z - position.z;
    final z = dx * _forward.x + dy * _forward.y + dz * _forward.z;
    if (z <= near) return null;
    final x = dx * _right.x + dy * _right.y + dz * _right.z;
    final y = dx * _up.x + dy * _up.y + dz * _up.z;
    final invZ = 1.0 / (z * _tanHalf);
    return Offset(
      _halfW + (x * invZ / _aspect) * _halfW,
      _halfH - (y * invZ) * _halfH,
    );
  }

  /// Fast path used by the renderer's inner loop: writes screen x/y into [out]
  /// and returns camera depth, or a negative value when behind the eye.
  double projectRaw(double wx, double wy, double wz, List<double> out) {
    final dx = wx - position.x;
    final dy = wy - position.y;
    final dz = wz - position.z;
    final z = dx * _forward.x + dy * _forward.y + dz * _forward.z;
    if (z <= near) return -1.0;
    final x = dx * _right.x + dy * _right.y + dz * _right.z;
    final y = dx * _up.x + dy * _up.y + dz * _up.z;
    final invZ = 1.0 / (z * _tanHalf);
    out[0] = _halfW + (x * invZ / _aspect) * _halfW;
    out[1] = _halfH - (y * invZ) * _halfH;
    return z;
  }

  /// World-space direction of the ray through a screen pixel.
  Vector3 rayThrough(Offset screen) {
    final ndcX = (screen.dx / viewport.width) * 2.0 - 1.0;
    final ndcY = 1.0 - (screen.dy / viewport.height) * 2.0;
    final sx = ndcX * _tanHalf * _aspect;
    final sy = ndcY * _tanHalf;
    return Vector3(
      _forward.x + _right.x * sx + _up.x * sy,
      _forward.y + _right.y * sx + _up.y * sy,
      _forward.z + _right.z * sx + _up.z * sy,
    )..normalize();
  }

  /// Converts an on-screen swipe into the world-space plane it sweeps.
  ///
  /// Every world point that projects onto the swipe line lies on the plane
  /// containing the eye and both edge rays, so this is exact rather than an
  /// approximation: the cut lands precisely where the player drew it.
  /// Returns null for a swipe too short to define a direction.
  CutPlane? planeFromSwipe(Offset start, Offset end, {double minPixels = 24.0}) {
    if ((end - start).distance < minPixels) return null;
    final r1 = rayThrough(start);
    final r2 = rayThrough(end);
    final n = r1.cross(r2);
    if (n.length2 < 1e-10) return null;
    return CutPlane.throughPoint(n.normalized(), position);
  }

  /// Where a screen ray meets a horizontal plane at height [y], or null if it
  /// runs parallel to it.
  Vector3? rayToGroundPlane(Offset screen, double y) {
    final dir = rayThrough(screen);
    if (dir.y.abs() < 1e-6) return null;
    final t = (y - position.y) / dir.y;
    if (t < 0) return null;
    return position + dir * t;
  }

  /// Distance at which an object of [radius] fits the smaller viewport axis,
  /// with [fill] as the fraction of that axis it should occupy.
  double distanceToFit(double radius, {double fill = 0.62}) {
    final vFov = fovY;
    final hFov = 2.0 * math.atan(math.tan(fovY * 0.5) * _aspect);
    final limiting = math.min(vFov, hFov);
    return radius / (math.tan(limiting * 0.5) * fill.clamp(0.05, 1.0));
  }
}
