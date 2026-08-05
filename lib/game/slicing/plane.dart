import 'package:vector_math/vector_math_64.dart';

/// An oriented cutting plane: points with a positive [signedDistance] are on
/// the "front" side, which is the side the blade's normal points toward.
class CutPlane {
  CutPlane(Vector3 normal, this.offset) : normal = normal.normalized();

  /// Plane through [point] with the given [normal].
  factory CutPlane.throughPoint(Vector3 normal, Vector3 point) {
    final n = normal.normalized();
    return CutPlane(n, n.dot(point));
  }

  final Vector3 normal;

  /// Distance from the origin along [normal].
  final double offset;

  double signedDistance(Vector3 p) => normal.dot(p) - offset;

  double signedDistanceRaw(double x, double y, double z) =>
      normal.x * x + normal.y * y + normal.z * z - offset;

  /// Point where segment a->b crosses the plane. Caller guarantees a crossing.
  Vector3 intersect(Vector3 a, Vector3 b, double da, double db) {
    final t = da / (da - db);
    return Vector3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }

  /// An arbitrary orthonormal basis (u, v) spanning the plane.
  ///
  /// Used to flatten cut loops into 2D for triangulation. A polygon wound
  /// counter-clockwise in this basis has a face normal equal to [normal].
  (Vector3, Vector3) basis() {
    final ref = normal.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final u = ref.cross(normal).normalized();
    final v = normal.cross(u).normalized();
    return (u, v);
  }

  CutPlane get flipped => CutPlane(-normal, -offset);

  @override
  String toString() =>
      'CutPlane(n=(${normal.x.toStringAsFixed(3)}, '
      '${normal.y.toStringAsFixed(3)}, ${normal.z.toStringAsFixed(3)}), '
      'd=${offset.toStringAsFixed(3)})';
}
