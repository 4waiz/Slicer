import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:vector_math/vector_math_64.dart';

/// A surface appearance shared by many triangles.
///
/// [interior] is the colour revealed on a freshly cut face -- brighter and
/// more saturated than [base], which is what sells the slice visually.
class SurfaceMaterial {
  const SurfaceMaterial({
    required this.name,
    required this.base,
    required this.interior,
    this.metallic = 0.0,
    this.roughness = 0.4,
    this.emission = 0.0,
  });

  final String name;
  final Color base;
  final Color interior;
  final double metallic;
  final double roughness;
  final double emission;

  /// Derives a plausible interior colour: brighter, punchier, slightly warmer.
  static Color deriveInterior(Color base) {
    final hsl = _RgbHsl.fromColor(base);
    return _RgbHsl(
      hsl.h,
      math.min(1.0, hsl.s * 1.25 + 0.12),
      math.min(0.94, hsl.l * 0.55 + 0.44),
    ).toColor();
  }

  SurfaceMaterial copyWith({Color? base, Color? interior, double? emission}) =>
      SurfaceMaterial(
        name: name,
        base: base ?? this.base,
        interior: interior ?? this.interior,
        metallic: metallic,
        roughness: roughness,
        emission: emission ?? this.emission,
      );
}

/// Minimal HSL helper (Flutter's HSLColor lives in widgets, we stay in dart:ui).
class _RgbHsl {
  _RgbHsl(this.h, this.s, this.l);

  final double h, s, l;

  factory _RgbHsl.fromColor(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final maxV = math.max(r, math.max(g, b));
    final minV = math.min(r, math.min(g, b));
    final l = (maxV + minV) / 2.0;
    if (maxV == minV) return _RgbHsl(0, 0, l);
    final d = maxV - minV;
    final s = l > 0.5 ? d / (2.0 - maxV - minV) : d / (maxV + minV);
    double h;
    if (maxV == r) {
      h = (g - b) / d + (g < b ? 6.0 : 0.0);
    } else if (maxV == g) {
      h = (b - r) / d + 2.0;
    } else {
      h = (r - g) / d + 4.0;
    }
    return _RgbHsl(h / 6.0, s, l);
  }

  Color toColor() {
    if (s == 0) {
      final v = (l * 255).round().clamp(0, 255);
      return Color.fromARGB(255, v, v, v);
    }
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    int ch(double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      double v;
      if (t < 1 / 6) {
        v = p + (q - p) * 6 * t;
      } else if (t < 1 / 2) {
        v = q;
      } else if (t < 2 / 3) {
        v = p + (q - p) * (2 / 3 - t) * 6;
      } else {
        v = p;
      }
      return (v * 255).round().clamp(0, 255);
    }

    return Color.fromARGB(255, ch(h + 1 / 3), ch(h), ch(h - 1 / 3));
  }
}

/// A triangle soup with a material index per face.
///
/// Deliberately *not* indexed: flat shading needs unique vertices per face
/// anyway, and plane slicing is far simpler and more robust on a soup.
/// 9 floats per triangle (3 vertices x xyz), all in object space.
class MeshData {
  MeshData(this.positions, this.triMat, this.materials)
    : assert(positions.length == triMat.length * 9);

  final Float32List positions;
  final Uint8List triMat;
  final List<SurfaceMaterial> materials;

  int get triCount => triMat.length;

  Vector3? _boundsMin, _boundsMax;
  double? _volume;
  Vector3? _centroid;

  void _computeBounds() {
    if (positions.isEmpty) {
      _boundsMin = Vector3.zero();
      _boundsMax = Vector3.zero();
      return;
    }
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    _boundsMin = Vector3(minX, minY, minZ);
    _boundsMax = Vector3(maxX, maxY, maxZ);
  }

  Vector3 get boundsMin {
    if (_boundsMin == null) _computeBounds();
    return _boundsMin!;
  }

  Vector3 get boundsMax {
    if (_boundsMax == null) _computeBounds();
    return _boundsMax!;
  }

  Vector3 get boundsCenter => (boundsMin + boundsMax) * 0.5;
  Vector3 get boundsSize => boundsMax - boundsMin;

  double get boundingRadius {
    final c = boundsCenter;
    var best = 0.0;
    for (var i = 0; i < positions.length; i += 3) {
      final dx = positions[i] - c.x;
      final dy = positions[i + 1] - c.y;
      final dz = positions[i + 2] - c.z;
      final d = dx * dx + dy * dy + dz * dz;
      if (d > best) best = d;
    }
    return math.sqrt(best);
  }

  void _computeMass() {
    // Signed tetrahedron sum from the origin. Correct for closed meshes and
    // still well-behaved (via the abs() guard) if a mesh has small gaps.
    var vol = 0.0;
    var cx = 0.0, cy = 0.0, cz = 0.0;
    for (var t = 0; t < triCount; t++) {
      final i = t * 9;
      final ax = positions[i], ay = positions[i + 1], az = positions[i + 2];
      final bx = positions[i + 3], by = positions[i + 4], bz = positions[i + 5];
      final cx2 = positions[i + 6],
          cy2 = positions[i + 7],
          cz2 = positions[i + 8];
      final v =
          (ax * (by * cz2 - bz * cy2) -
              ay * (bx * cz2 - bz * cx2) +
              az * (bx * cy2 - by * cx2)) /
          6.0;
      vol += v;
      cx += (ax + bx + cx2) * 0.25 * v;
      cy += (ay + by + cy2) * 0.25 * v;
      cz += (az + bz + cz2) * 0.25 * v;
    }
    _volume = vol.abs();
    if (_volume! > 1e-9) {
      _centroid = Vector3(cx / vol, cy / vol, cz / vol);
    } else {
      _centroid = boundsCenter;
      // Degenerate/flat shell: fall back to a bounds-derived pseudo volume so
      // sliver pieces still get sane, non-zero mass.
      final s = boundsSize;
      _volume = math.max(1e-5, s.x * s.y * s.z * 0.25);
    }
  }

  /// Enclosed volume in cubic world units. Used as the mass proxy everywhere.
  double get volume {
    if (_volume == null) _computeMass();
    return _volume!;
  }

  Vector3 get centroid {
    if (_centroid == null) _computeMass();
    return _centroid!;
  }

  /// Returns a copy translated so that [centroid] sits at the origin.
  MeshData recenteredOnCentroid() {
    final c = centroid;
    final p = Float32List.fromList(positions);
    for (var i = 0; i < p.length; i += 3) {
      p[i] -= c.x;
      p[i + 1] -= c.y;
      p[i + 2] -= c.z;
    }
    return MeshData(p, triMat, materials);
  }

  MeshData scaled(double s) {
    final p = Float32List(positions.length);
    for (var i = 0; i < p.length; i++) {
      p[i] = positions[i] * s;
    }
    return MeshData(p, triMat, materials);
  }

  MeshData transformed(Matrix4 m) {
    final p = Float32List(positions.length);
    final v = Vector3.zero();
    for (var i = 0; i < positions.length; i += 3) {
      v.setValues(positions[i], positions[i + 1], positions[i + 2]);
      m.transform3(v);
      p[i] = v.x;
      p[i + 1] = v.y;
      p[i + 2] = v.z;
    }
    return MeshData(p, triMat, materials);
  }

  /// All unique-ish vertex positions, welded on a coarse grid.
  ///
  /// These double as the contact points for the point-cloud collider, so the
  /// weld keeps the count low without losing the silhouette.
  List<Vector3> collisionPoints({double weld = 0.05}) {
    final seen = <(int, int, int), Vector3>{};
    final inv = 1.0 / weld;
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      // Record keys give exact structural equality -- an integer hash mix
      // here silently collides and merges distinct corners.
      final key = ((x * inv).round(), (y * inv).round(), (z * inv).round());
      seen[key] ??= Vector3(x, y, z);
    }
    return seen.values.toList(growable: false);
  }

  static final MeshData empty = MeshData(
    Float32List(0),
    Uint8List(0),
    const <SurfaceMaterial>[],
  );
}

/// Growable builder used by the loader and the slicer.
class MeshBuilder {
  MeshBuilder(this.materials);

  final List<SurfaceMaterial> materials;
  final List<double> _pos = <double>[];
  final List<int> _mat = <int>[];

  int get triCount => _mat.length;
  bool get isEmpty => _mat.isEmpty;

  void addTriangle(Vector3 a, Vector3 b, Vector3 c, int material) {
    _pos
      ..add(a.x)
      ..add(a.y)
      ..add(a.z)
      ..add(b.x)
      ..add(b.y)
      ..add(b.z)
      ..add(c.x)
      ..add(c.y)
      ..add(c.z);
    _mat.add(material);
  }

  void addRaw(
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    double cx,
    double cy,
    double cz,
    int material,
  ) {
    _pos
      ..add(ax)
      ..add(ay)
      ..add(az)
      ..add(bx)
      ..add(by)
      ..add(bz)
      ..add(cx)
      ..add(cy)
      ..add(cz);
    _mat.add(material);
  }

  /// Fan-triangulates a convex polygon.
  void addPolygon(List<Vector3> poly, int material) {
    for (var i = 1; i + 1 < poly.length; i++) {
      addTriangle(poly[0], poly[i], poly[i + 1], material);
    }
  }

  MeshData build() =>
      MeshData(Float32List.fromList(_pos), Uint8List.fromList(_mat), materials);
}
