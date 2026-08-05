import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/renderer/mesh.dart';
import 'package:kanban_slicer/game/renderer/primitives.dart';
import 'package:kanban_slicer/game/slicing/plane.dart';
import 'package:kanban_slicer/game/slicing/slicer.dart';
import 'package:vector_math/vector_math_64.dart';

const _cyan = Color(0xFF35D6F0);

void main() {
  group('CutPlane', () {
    test('signed distance follows the normal', () {
      final p = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3(0, 2, 0));
      expect(p.signedDistance(Vector3(0, 5, 0)), closeTo(3, 1e-9));
      expect(p.signedDistance(Vector3(0, -1, 0)), closeTo(-3, 1e-9));
      expect(p.signedDistance(Vector3(9, 2, -4)), closeTo(0, 1e-9));
    });

    test('basis is orthonormal and right-handed w.r.t. the normal', () {
      for (final n in [
        Vector3(0, 1, 0),
        Vector3(1, 0, 0),
        Vector3(0.3, -0.8, 0.5),
      ]) {
        final plane = CutPlane.throughPoint(n, Vector3.zero());
        final (u, v) = plane.basis();
        expect(u.length, closeTo(1, 1e-9));
        expect(v.length, closeTo(1, 1e-9));
        expect(u.dot(v), closeTo(0, 1e-9));
        expect(u.dot(plane.normal), closeTo(0, 1e-9));
        // u x v must point along the plane normal.
        expect(u.cross(v).dot(plane.normal), closeTo(1, 1e-9));
      }
    });
  });

  group('MeshSlicer', () {
    final cube = Primitives.box(Vector3(2, 2, 2), _cyan);

    test('unit cube has the expected volume and centroid', () {
      expect(cube.volume, closeTo(8.0, 1e-6));
      expect(cube.centroid.length, closeTo(0, 1e-6));
    });

    test('a plane that misses the mesh reports no cut', () {
      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3(0, 9, 0));
      final r = MeshSlicer.slice(cube, plane);
      expect(r.didCut, isFalse);
      expect(r.front, isNull);
      expect(r.back, isNull);
    });

    test('a mid cut splits the cube into two equal, closed halves', () {
      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero());
      final r = MeshSlicer.slice(cube, plane);

      expect(r.didCut, isTrue);
      // Volume is computed by the divergence theorem, so it only comes out
      // right if the cut cap actually sealed each half.
      expect(r.front!.volume, closeTo(4.0, 1e-4));
      expect(r.back!.volume, closeTo(4.0, 1e-4));
      expect(r.front!.volume + r.back!.volume, closeTo(cube.volume, 1e-4));
      // The exposed face is the 2x2 cross-section.
      expect(r.cutArea, closeTo(4.0, 1e-4));
      expect(r.loops.length, 1);
    });

    test('halves sit on the correct side of the plane', () {
      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero());
      final r = MeshSlicer.slice(cube, plane);
      expect(r.front!.centroid.y, greaterThan(0.4));
      expect(r.back!.centroid.y, lessThan(-0.4));
      for (var i = 1; i < r.front!.positions.length; i += 3) {
        expect(r.front!.positions[i], greaterThan(-MeshSlicer.epsilon - 1e-6));
      }
      for (var i = 1; i < r.back!.positions.length; i += 3) {
        expect(r.back!.positions[i], lessThan(MeshSlicer.epsilon + 1e-6));
      }
    });

    test('off-centre cut conserves volume', () {
      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3(0, 0.6, 0));
      final r = MeshSlicer.slice(cube, plane);
      expect(r.didCut, isTrue);
      expect(r.front!.volume, closeTo(2 * 2 * 1.4, 1e-4));
      expect(r.back!.volume, closeTo(2 * 2 * 2.6, 1e-4));
    });

    test('diagonal cut conserves volume and produces a larger cut face', () {
      final plane =
          CutPlane.throughPoint(Vector3(1, 1, 0).normalized(), Vector3.zero());
      final r = MeshSlicer.slice(cube, plane);
      expect(r.didCut, isTrue);
      expect(r.front!.volume + r.back!.volume, closeTo(8.0, 1e-3));
      // A 45-degree cut through a 2-cube exposes 2 * 2*sqrt(2).
      expect(r.cutArea, closeTo(2 * 2 * math.sqrt2, 1e-3));
    });

    test('cut faces get an interior material distinct from the surface', () {
      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero());
      final r = MeshSlicer.slice(cube, plane);
      final mats = r.front!.materials;
      expect(mats.length, 2, reason: 'one surface + one interior variant');
      expect(mats[1].name, endsWith('#cut'));
      expect(mats[1].base, isNot(equals(mats[0].base)));
      // Some face must actually use it.
      expect(r.front!.triMat.contains(1), isTrue);
      expect(r.back!.triMat.contains(1), isTrue);
    });

    test('a piece can be sliced again without growing the material list', () {
      final plane1 = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero());
      final first = MeshSlicer.slice(cube, plane1);
      final plane2 = CutPlane.throughPoint(Vector3(1, 0, 0), Vector3.zero());
      final second = MeshSlicer.slice(first.front!, plane2);

      expect(second.didCut, isTrue);
      expect(second.front!.volume, closeTo(2.0, 1e-4));
      expect(second.back!.volume, closeTo(2.0, 1e-4));
      expect(second.front!.materials.length, first.front!.materials.length,
          reason: 'interior variants must be reused, not appended again');
    });

    test('sphere cut conserves volume (many straddling triangles)', () {
      final sphere = Primitives.sphere(1.0, _cyan, segments: 16, rings: 10);
      final before = sphere.volume;
      final plane =
          CutPlane.throughPoint(Vector3(0.2, 1, 0.1).normalized(), Vector3(0, 0.15, 0));
      final r = MeshSlicer.slice(sphere, plane);
      expect(r.didCut, isTrue);
      expect(r.front!.volume + r.back!.volume, closeTo(before, 1e-3));
    });

    test('multi-shell mesh produces one cut loop per shell', () {
      // Two separated boxes joined into one soup, cut through both.
      final left = Primitives.box(Vector3(1, 1, 1), _cyan);
      final right = Primitives.box(Vector3(1, 1, 1), _cyan);
      final b = MeshBuilder(left.materials);
      void append(MeshData m, double dx) {
        for (var t = 0; t < m.triCount; t++) {
          final i = t * 9;
          b.addRaw(
            m.positions[i] + dx, m.positions[i + 1], m.positions[i + 2],
            m.positions[i + 3] + dx, m.positions[i + 4], m.positions[i + 5],
            m.positions[i + 6] + dx, m.positions[i + 7], m.positions[i + 8],
            0,
          );
        }
      }

      append(left, -2.0);
      append(right, 2.0);
      final joined = b.build();

      final plane = CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero());
      final r = MeshSlicer.slice(joined, plane);
      expect(r.didCut, isTrue);
      expect(r.loops.length, 2, reason: 'each shell caps independently');
      expect(r.front!.volume, closeTo(1.0, 1e-4));
      expect(r.back!.volume, closeTo(1.0, 1e-4));
      expect(r.cutArea, closeTo(2.0, 1e-4));
    });

    test('cut loop points all lie on the plane', () {
      final plane =
          CutPlane.throughPoint(Vector3(0.4, 1, -0.2).normalized(), Vector3(0, 0.1, 0));
      final r = MeshSlicer.slice(cube, plane);
      expect(r.loops, isNotEmpty);
      for (final loop in r.loops) {
        for (final p in loop) {
          expect(plane.signedDistance(p).abs(), lessThan(1e-6));
        }
      }
    });
  });

  group('MeshData', () {
    test('collision points are welded but keep the silhouette', () {
      final cube = Primitives.box(Vector3(2, 2, 2), _cyan);
      final pts = cube.collisionPoints(weld: 0.05);
      expect(pts.length, 8, reason: 'a box has 8 distinct corners');
    });

    test('recentering moves the centroid to the origin', () {
      final b = MeshBuilder([Primitives.material(_cyan)]);
      final box = Primitives.box(Vector3(1, 1, 1), _cyan);
      for (var t = 0; t < box.triCount; t++) {
        final i = t * 9;
        b.addRaw(
          box.positions[i] + 5, box.positions[i + 1], box.positions[i + 2],
          box.positions[i + 3] + 5, box.positions[i + 4], box.positions[i + 5],
          box.positions[i + 6] + 5, box.positions[i + 7], box.positions[i + 8],
          0,
        );
      }
      final shifted = b.build();
      expect(shifted.centroid.x, closeTo(5, 1e-6));
      expect(shifted.recenteredOnCentroid().centroid.length, closeTo(0, 1e-6));
    });
  });
}
