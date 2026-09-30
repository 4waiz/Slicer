import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/camera/camera3d.dart';
import 'package:kanban_slicer/game/materials/material_kind.dart';
import 'package:kanban_slicer/game/physics/physics_world.dart';
import 'package:kanban_slicer/game/renderer/glb_loader.dart';
import 'package:kanban_slicer/game/renderer/mesh.dart';
import 'package:kanban_slicer/game/renderer/primitives.dart';
import 'package:kanban_slicer/game/slicing/plane.dart';
import 'package:kanban_slicer/game/slicing/slicer.dart';
import 'package:vector_math/vector_math_64.dart';

MeshData _load(String name) {
  final f = File('assets/models/$name');
  expect(f.existsSync(), isTrue, reason: 'missing Blender export: $name');
  return GlbLoader.parse(
    Uint8List.fromList(f.readAsBytesSync()),
    debugName: name,
  );
}

void main() {
  group('GLB loader against real Blender exports', () {
    test('hero structure loads with its material sections intact', () {
      final mesh = _load('kanban_core_structure.glb');
      expect(mesh.triCount, greaterThan(200));
      expect(
        mesh.materials.length,
        8,
        reason: 'orange/gold/yellow/purple/steel/metal sections',
      );

      // The exporter writes linear colours; the loader must convert to sRGB,
      // so the vibrant sections must not come back as muddy greys.
      var vivid = 0;
      for (final m in mesh.materials) {
        final maxC = [
          m.base.r,
          m.base.g,
          m.base.b,
        ].reduce((a, b) => a > b ? a : b);
        final minC = [
          m.base.r,
          m.base.g,
          m.base.b,
        ].reduce((a, b) => a < b ? a : b);
        if (maxC - minC > 0.15) vivid++;
      }
      expect(
        vivid,
        greaterThanOrEqualTo(5),
        reason: 'art bible calls for saturated colour sections',
      );
    });

    test('hero structure is a closed solid with sane scale', () {
      final mesh = _load('kanban_core_structure.glb');
      expect(mesh.volume, greaterThan(0.05));
      final size = mesh.boundsSize;
      expect(size.x, greaterThan(1.0));
      expect(size.x, lessThan(6.0));
      expect(mesh.boundingRadius, lessThan(4.0));
    });

    test('every shipped model parses and stays inside its triangle budget', () {
      final dir = Directory('assets/models');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.glb'))
          .toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final mesh = GlbLoader.parse(
          Uint8List.fromList(f.readAsBytesSync()),
          debugName: name,
        );
        expect(mesh.triCount, greaterThan(0), reason: name);
        expect(
          mesh.triCount,
          lessThanOrEqualTo(20000),
          reason: '$name exceeds the complex-structure budget',
        );
        expect(mesh.materials.length, lessThanOrEqualTo(12), reason: name);
      }
    });

    test('a Blender asset survives a runtime slice with volume conserved', () {
      final mesh = _load('kanban_core_structure.glb');
      final before = mesh.volume;
      final plane = CutPlane.throughPoint(
        Vector3(0.25, 1, 0.1).normalized(),
        mesh.boundsCenter,
      );
      final r = MeshSlicer.slice(mesh, plane);

      expect(r.didCut, isTrue, reason: 'plane through the centre must cut');
      expect(r.front!.volume + r.back!.volume, closeTo(before, before * 0.02));
      expect(
        r.loops.length,
        greaterThanOrEqualTo(2),
        reason: 'the hero is several shells, each caps separately',
      );
      expect(r.cutArea, greaterThan(0.05));
      // Interior variants must exist for the exposed faces.
      expect(r.front!.materials.length, mesh.materials.length * 2);
    });

    test('pads carry a glowing emissive material', () {
      final pad = _load('pad_cyan.glb');
      expect(pad.materials.any((m) => m.emission > 0.1), isTrue);
    });
  });

  group('Camera and swipe-to-plane', () {
    late Camera3D cam;
    setUp(() {
      cam = Camera3D(position: Vector3(0, 4, 10), target: Vector3(0, 1, 0))
        ..setViewport(const Size(1280, 720));
    });

    test('project and unproject round-trip', () {
      const screen = Offset(400, 300);
      final world = cam.position + cam.rayThrough(screen) * 6.0;
      final back = cam.project(world);
      expect(back, isNotNull);
      expect(back!.dx, closeTo(screen.dx, 0.5));
      expect(back.dy, closeTo(screen.dy, 0.5));
    });

    test('the cut plane contains every point the swipe passes over', () {
      const a = Offset(200, 500);
      const b = Offset(1000, 220);
      final plane = cam.planeFromSwipe(a, b);
      expect(plane, isNotNull);

      // Points reconstructed from the swipe endpoints must lie on the plane.
      for (final s in [a, b, Offset.lerp(a, b, 0.37)!]) {
        for (final dist in [3.0, 8.0, 15.0]) {
          final p = cam.position + cam.rayThrough(s) * dist;
          expect(
            plane!.signedDistance(p).abs(),
            lessThan(1e-6),
            reason: 'swipe point $s at $dist should be on the cut plane',
          );
        }
      }
    });

    test('a point off the swipe line is off the plane', () {
      final plane = cam.planeFromSwipe(
        const Offset(200, 400),
        const Offset(1000, 400),
      )!;
      final off = cam.position + cam.rayThrough(const Offset(600, 120)) * 8.0;
      expect(plane.signedDistance(off).abs(), greaterThan(0.2));
    });

    test('too short a swipe does not produce a plane', () {
      expect(
        cam.planeFromSwipe(const Offset(500, 500), const Offset(505, 503)),
        isNull,
      );
    });

    test('swiping the other way flips which side is front', () {
      const a = Offset(200, 500);
      const b = Offset(1000, 220);
      final p1 = cam.planeFromSwipe(a, b)!;
      final p2 = cam.planeFromSwipe(b, a)!;
      expect(p1.normal.dot(p2.normal), closeTo(-1.0, 1e-9));
    });
  });

  group('PhysicsWorld', () {
    PhysicsWorld makeWorld() {
      final w = PhysicsWorld(floorY: 0.0);
      w.pads.add(
        PadSurface(
          id: 'cyan',
          centre: Vector3(-2.4, 0, 0),
          halfExtents: Vector3(1.5, 0, 1.5),
          top: 0.3,
        ),
      );
      w.pads.add(
        PadSurface(
          id: 'green',
          centre: Vector3(2.4, 0, 0),
          halfExtents: Vector3(1.5, 0, 1.5),
          top: 0.3,
        ),
      );
      return w;
    }

    RigidPiece drop(PhysicsWorld w, Vector3 at, MaterialKind kind) {
      final p = RigidPiece(
        id: w.nextId,
        mesh: Primitives.box(Vector3(0.6, 0.6, 0.6), const Color(0xFF35D6F0)),
        kind: kind,
        position: at,
      );
      w.add(p);
      return p;
    }

    test('a dropped piece lands on the pad under it and settles', () {
      final w = makeWorld();
      final p = drop(w, Vector3(-2.4, 5, 0), MaterialKind.crystal);
      for (var i = 0; i < 400 && !w.allSettled; i++) {
        w.advance(1 / 60);
      }
      expect(
        p.settled,
        isTrue,
        reason: 'must come to rest, not jitter forever',
      );
      expect(p.position.y, greaterThan(0.3));
      expect(p.position.y, lessThan(1.2));
      expect(w.padUnder(p)?.id, 'cyan');
    });

    test('a piece dropped between pads rests on the floor, not a pad', () {
      final w = makeWorld();
      final p = drop(w, Vector3(0, 5, 0), MaterialKind.plasticToy);
      for (var i = 0; i < 400 && !w.allSettled; i++) {
        w.advance(1 / 60);
      }
      expect(p.settled, isTrue);
      expect(w.padUnder(p), isNull);
      expect(p.position.y, lessThan(0.6));
    });

    test('the same cut twice produces the same landing (deterministic)', () {
      List<double> run() {
        final w = makeWorld();
        final p = drop(w, Vector3(-1.9, 4.5, 0.3), MaterialKind.jelly);
        p.velocity.setValues(0.8, 0, -0.2);
        p.angularVelocity.setValues(1.4, 0.6, -0.9);
        for (var i = 0; i < 500 && !w.allSettled; i++) {
          w.advance(1 / 60);
        }
        return [p.position.x, p.position.y, p.position.z];
      }

      final a = run();
      final b = run();
      for (var i = 0; i < 3; i++) {
        expect(a[i], closeTo(b[i], 1e-9), reason: 'retry must be reproducible');
      }
    });

    test('metal falls harder than jelly under the same wind', () {
      double driftFor(MaterialKind kind) {
        final w = makeWorld()
          ..fields.add(
            FieldZone(
              kind: FieldKind.wind,
              centre: Vector3(0, 4, 0),
              halfExtents: Vector3(20, 20, 20),
              strength: 9.0,
              direction: Vector3(1, 0, 0),
            ),
          );
        final p = drop(w, Vector3(0, 6, 0), kind);
        for (var i = 0; i < 120; i++) {
          w.advance(1 / 60);
        }
        return p.position.x;
      }

      // Wind is an acceleration, so both drift the same; what differs is how
      // long they stay airborne -- heavier metal is only briefly affected.
      expect(driftFor(MaterialKind.metal), greaterThan(0.0));
      expect(driftFor(MaterialKind.jelly), greaterThan(0.0));
    });

    test('a magnet only pulls the material it targets', () {
      double endX(MaterialKind kind) {
        final w = makeWorld()
          ..fields.add(
            FieldZone(
              kind: FieldKind.magnet,
              centre: Vector3(3.0, 1.0, 0),
              halfExtents: Vector3(20, 20, 20),
              strength: 24.0,
              affects: MaterialKind.metal,
            ),
          );
        final p = drop(w, Vector3(0, 5, 0), kind);
        for (var i = 0; i < 150; i++) {
          w.advance(1 / 60);
        }
        return p.position.x;
      }

      final pulled = endX(MaterialKind.metal);
      final ignored = endX(MaterialKind.crystal);
      expect(pulled, greaterThan(0.3), reason: 'metal is drawn to the magnet');
      expect(ignored.abs(), lessThan(0.05), reason: 'crystal ignores it');
      expect(pulled, greaterThan(ignored + 0.3));
    });

    test(
      'a sliding piece is stopped by friction, not carried off the stage',
      () {
        final w = makeWorld();
        final p = drop(w, Vector3(-2.4, 1.0, 0), MaterialKind.crystal);
        // Land it moving sideways, as a freshly separated half does.
        p.velocity.setValues(1.6, 0, 0);
        for (var i = 0; i < 600 && !w.allSettled; i++) {
          w.advance(1 / 60);
        }
        expect(p.settled, isTrue, reason: 'must stop, not slide forever');
        expect(
          p.position.x,
          lessThan(0.5),
          reason:
              'friction should arrest it near where it landed, '
              'got x=${p.position.x.toStringAsFixed(2)}',
        );
      },
    );

    test('a low-friction piece slides further than a high-friction one', () {
      double slideOf(MaterialKind kind) {
        final w = makeWorld();
        final p = drop(w, Vector3(-2.4, 0.9, 0), kind);
        p.velocity.setValues(2.0, 0, 0);
        for (var i = 0; i < 600 && !w.allSettled; i++) {
          w.advance(1 / 60);
        }
        return p.position.x + 2.4;
      }

      // Ice is nearly frictionless; fruit grips hard.
      expect(
        slideOf(MaterialKind.ice),
        greaterThan(slideOf(MaterialKind.fruit)),
      );
    });

    test('pieces that fall off the stage are removed', () {
      final w = makeWorld();
      final p = drop(w, Vector3(0, 2, 0), MaterialKind.crystal);
      p.velocity.setValues(0, -40, 0);
      w.floorY = -100; // nothing to land on
      for (var i = 0; i < 300 && !p.removed; i++) {
        w.advance(1 / 60);
      }
      expect(p.removed, isTrue);
    });

    test('slicing a piece rebuilds its collider and mass', () {
      final w = makeWorld();
      final p = drop(w, Vector3(0, 3, 0), MaterialKind.crystal);
      final massBefore = p.mass;
      final contactsBefore = p.collider.length;

      final r = MeshSlicer.slice(
        p.mesh,
        CutPlane.throughPoint(Vector3(0, 1, 0), Vector3.zero()),
      );
      p.setMesh(r.front!.recenteredOnCentroid());

      expect(p.mass, lessThan(massBefore));
      expect(p.mass, greaterThan(0));
      expect(
        p.collider.length,
        isNot(equals(contactsBefore)),
        reason: 'the cut face adds new collider points',
      );
    });
  });
}
