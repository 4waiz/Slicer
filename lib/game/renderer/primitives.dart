import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';

/// Procedural primitives used for particles, fragments and tests.
///
/// Gameplay-critical geometry comes from Blender GLBs; these exist for the
/// cheap throwaway shapes it would be wasteful to ship as assets.
class Primitives {
  static SurfaceMaterial material(Color c, {String name = 'proc'}) =>
      SurfaceMaterial(
        name: name,
        base: c,
        interior: SurfaceMaterial.deriveInterior(c),
      );

  /// Axis-aligned box centred on the origin.
  static MeshData box(Vector3 size, Color colour, {String name = 'box'}) {
    final b = MeshBuilder([material(colour, name: name)]);
    final h = size * 0.5;
    final v = <Vector3>[
      Vector3(-h.x, -h.y, -h.z),
      Vector3(h.x, -h.y, -h.z),
      Vector3(h.x, h.y, -h.z),
      Vector3(-h.x, h.y, -h.z),
      Vector3(-h.x, -h.y, h.z),
      Vector3(h.x, -h.y, h.z),
      Vector3(h.x, h.y, h.z),
      Vector3(-h.x, h.y, h.z),
    ];
    // Outward-facing winding on every face.
    const faces = <List<int>>[
      [0, 3, 2, 1], // -z
      [4, 5, 6, 7], // +z
      [0, 1, 5, 4], // -y
      [3, 7, 6, 2], // +y
      [0, 4, 7, 3], // -x
      [1, 2, 6, 5], // +x
    ];
    for (final f in faces) {
      b.addTriangle(v[f[0]], v[f[1]], v[f[2]], 0);
      b.addTriangle(v[f[0]], v[f[2]], v[f[3]], 0);
    }
    return b.build();
  }

  /// Faceted tetra-ish shard, used as slice debris.
  static MeshData shard(double size, Color colour, math.Random rng) {
    final b = MeshBuilder([material(colour, name: 'shard')]);
    Vector3 j(double x, double y, double z) => Vector3(
      x * size * (0.6 + rng.nextDouble() * 0.8),
      y * size * (0.6 + rng.nextDouble() * 0.8),
      z * size * (0.6 + rng.nextDouble() * 0.8),
    );
    final a = j(0, 1, 0);
    final c = j(-0.9, -0.5, 0.6);
    final d = j(0.9, -0.5, 0.6);
    final e = j(0, -0.5, -1.0);
    b.addTriangle(a, c, d, 0);
    b.addTriangle(a, d, e, 0);
    b.addTriangle(a, e, c, 0);
    b.addTriangle(c, e, d, 0);
    return b.build();
  }

  /// Low-poly UV sphere. [segments] x [rings] quads, flat shaded.
  static MeshData sphere(
    double radius,
    Color colour, {
    int segments = 10,
    int rings = 6,
  }) {
    final b = MeshBuilder([material(colour, name: 'sphere')]);
    Vector3 at(int s, int r) {
      final theta = math.pi * r / rings;
      final phi = 2 * math.pi * s / segments;
      return Vector3(
        radius * math.sin(theta) * math.cos(phi),
        radius * math.cos(theta),
        radius * math.sin(theta) * math.sin(phi),
      );
    }

    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < segments; s++) {
        final p00 = at(s, r), p10 = at(s + 1, r);
        final p01 = at(s, r + 1), p11 = at(s + 1, r + 1);
        if (r != 0) b.addTriangle(p00, p01, p11, 0);
        if (r != rings - 1) b.addTriangle(p00, p11, p10, 0);
      }
    }
    return b.build();
  }
}
