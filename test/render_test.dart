import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/camera/camera3d.dart';
import 'package:kanban_slicer/game/effects/effects.dart';
import 'package:kanban_slicer/game/renderer/glb_loader.dart';
import 'package:kanban_slicer/game/renderer/mesh.dart';
import 'package:kanban_slicer/game/renderer/scene_renderer.dart';
import 'package:vector_math/vector_math_64.dart';

MeshData _load(String name) => GlbLoader.parse(
  Uint8List.fromList(File('assets/models/$name').readAsBytesSync()),
  debugName: name,
);

/// Renders and returns how many triangles actually reached the canvas.
int _renderCount(Camera3D cam, List<RenderNode> nodes) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final r = SceneRenderer();
  r.render(canvas, cam, nodes, Lighting());
  recorder.endRecording().dispose();
  return r.lastTriangleCount;
}

void main() {
  group('SceneRenderer', () {
    test('a node in front of the camera submits triangles', () {
      final mesh = _load('kanban_core_structure.glb');
      final cam = Camera3D(position: Vector3(0, 2, 9), target: Vector3.zero())
        ..setViewport(const ui.Size(2400, 1080));
      final n = _renderCount(cam, [RenderNode(mesh: mesh)]);
      expect(n, greaterThan(0));
      // Back-face culling should discard roughly half a closed mesh.
      expect(n, lessThan(mesh.triCount));
    });

    test('a node behind the camera submits nothing', () {
      final mesh = _load('kanban_core_structure.glb');
      final cam = Camera3D(position: Vector3(0, 2, 9), target: Vector3.zero())
        ..setViewport(const ui.Size(2400, 1080));
      final n = _renderCount(cam, [
        RenderNode(mesh: mesh, position: Vector3(0, 0, 40)),
      ]);
      expect(n, 0);
    });

    test('the gameplay camera framing keeps the stage on screen', () {
      // Mirrors GameController._frameCamera for level 1.
      final hero = _load('kanban_core_structure.glb').recenteredOnCentroid();
      final padCyan = _load('pad_cyan.glb');
      final padGreen = _load('pad_green.glb');

      const spawnY = 4.2;
      const zoneX = 2.7, zoneW = 2.3;
      final minX = -(zoneX + zoneW * 0.5);
      final maxX = zoneX + zoneW * 0.5;
      final spanX = maxX - minX;
      final centreX = (minX + maxX) * 0.5;

      final cam = Camera3D()..setViewport(const ui.Size(2400, 1080));
      final radius = spanX * 0.5 > hero.boundingRadius * 1.5
          ? spanX * 0.5
          : hero.boundingRadius * 1.5;
      final dist = cam.distanceToFit(radius, fill: 0.52).clamp(9.0, 30.0);
      final look = Vector3(centreX, spawnY * 0.42, 0);
      cam.lookAt(
        Vector3(centreX + dist * 0.10, look.y + dist * 0.40, dist * 0.92),
        look,
      );

      final nodes = [
        RenderNode(mesh: hero, position: Vector3(0, spawnY, 0)),
        RenderNode(mesh: padCyan, position: Vector3(-zoneX, 0, 0)),
        RenderNode(mesh: padGreen, position: Vector3(zoneX, 0, 0)),
      ];

      // Every node's centre must project inside the viewport.
      for (final node in nodes) {
        final p = cam.project(node.position);
        expect(
          p,
          isNotNull,
          reason: 'node at ${node.position} is behind the eye',
        );
        expect(
          p!.dx,
          inInclusiveRange(0, 2400),
          reason: 'node at ${node.position} projects off-screen in x',
        );
        expect(
          p.dy,
          inInclusiveRange(0, 1080),
          reason: 'node at ${node.position} projects off-screen in y',
        );
      }

      final n = _renderCount(cam, nodes);
      expect(n, greaterThan(50), reason: 'the stage must actually draw');
    });

    test('rendered pixels are not all background', () async {
      final mesh = _load('crystal_cluster_large.glb');
      final cam = Camera3D(position: Vector3(0, 1.5, 6), target: Vector3.zero())
        ..setViewport(const ui.Size(400, 300));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 400, 300),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      SceneRenderer().render(canvas, cam, [RenderNode(mesh: mesh)], Lighting());
      final image = await recorder.endRecording().toImage(400, 300);
      final data = await image.toByteData();
      expect(data, isNotNull);

      var lit = 0;
      final bytes = data!.buffer.asUint8List();
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 20 || bytes[i + 1] > 20 || bytes[i + 2] > 20) lit++;
      }
      // The mesh should cover a meaningful slice of the frame.
      expect(
        lit,
        greaterThan(1500),
        reason: 'drawVertices produced almost no visible pixels',
      );
      image.dispose();
    });

    test('armed cores and blasts actually draw', () async {
      final cam = Camera3D(position: Vector3(0, 3, 10), target: Vector3.zero())
        ..setViewport(const ui.Size(400, 300));
      final fx = EffectSystem();

      Future<int> litPixels() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 400, 300),
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
        fx.drawWorld(canvas, cam);
        final image = await recorder.endRecording().toImage(400, 300);
        final data = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        var lit = 0;
        for (var i = 0; i < data.length; i += 4) {
          if (data[i] > 12 || data[i + 1] > 12 || data[i + 2] > 12) lit++;
        }
        return lit;
      }

      expect(await litPixels(), 0, reason: 'nothing to draw yet');

      // A core half way through its fuse must show its danger ring.
      fx.armedCores.add(
        ArmedCore(position: Vector3(0, 1, 0), radius: 3.4, progress: 0.5),
      );
      expect(
        await litPixels(),
        greaterThan(200),
        reason: 'the warning ring must be visible',
      );

      fx.armedCores.clear();
      fx.shockwave(Vector3(0, 1, 0), 3.4, const ui.Color(0xFFF07A2A));
      expect(
        await litPixels(),
        greaterThan(200),
        reason: 'the blast ring must be visible',
      );

      // And it must fade out rather than linger.
      fx.update(Shockwave.life + 0.01);
      expect(fx.shockwaves, isEmpty);
      expect(await litPixels(), 0);
    });

    test('shadows do not abort on the first off-screen node', () {
      final mesh = _load('crystal_orb.glb');
      final cam = Camera3D(position: Vector3(0, 3, 10), target: Vector3.zero())
        ..setViewport(const ui.Size(800, 400));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // First node is behind the camera; the second must still get a shadow.
      SceneRenderer.drawShadows(canvas, cam, [
        RenderNode(mesh: mesh, position: Vector3(0, 1, 60)),
        RenderNode(mesh: mesh, position: Vector3(0, 1, 0)),
      ], 0.0);
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, greaterThan(0));
      picture.dispose();
    });
  });
}
