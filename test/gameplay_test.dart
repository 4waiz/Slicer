import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/game_controller.dart';
import 'package:kanban_slicer/game/levels/campaign.dart';
import 'package:kanban_slicer/game/levels/level_def.dart';
import 'package:kanban_slicer/game/renderer/glb_loader.dart';
import 'package:kanban_slicer/game/renderer/model_cache.dart';
import 'package:vector_math/vector_math_64.dart';

const _viewport = Size(2400, 1080);

void _seedCache() {
  for (final f in Directory('assets/models').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.glb')) continue;
    ModelCache.instance.put(
      name,
      GlbLoader.parse(Uint8List.fromList(f.readAsBytesSync()), debugName: name),
    );
  }
}

/// Drives a controller to a resolved result, as the ticker would.
Future<GameController> playCut(
  LevelDef level, {
  required Offset from,
  required Offset to,
  int maxFrames = 900,
}) async {
  final c = GameController(level: level);
  await c.load();
  expect(c.phase, GamePhase.ready, reason: c.errorMessage ?? '');
  c.camera.setViewport(_viewport);

  // Let it sit briefly, as a player would while reading the structure.
  for (var i = 0; i < 6; i++) {
    c.update(1 / 60);
  }

  c.onPanStart(from);
  c.onPanUpdate(Offset.lerp(from, to, 0.5)!);
  c.onPanUpdate(to);
  c.onPanEnd();

  for (var i = 0; i < maxFrames && c.phase != GamePhase.resolved; i++) {
    c.update(1 / 60);
  }
  return c;
}

/// A vertical swipe straight through the structure's screen position.
(Offset, Offset) swipeThroughStructure(GameController c) {
  final p = c.camera.project(Vector3(c.level.spawnX, c.level.spawnY, 0));
  expect(p, isNotNull, reason: 'structure must be on screen');
  return (Offset(p!.dx, p.dy - 320), Offset(p.dx, p.dy + 320));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_seedCache);

  group('Level 1 vertical slice', () {
    test('loads, frames the stage, and starts ready', () async {
      final c = GameController(level: allLevels.first);
      await c.load();
      expect(c.phase, GamePhase.ready);
      c.camera.setViewport(_viewport);

      // Structure plus both pads must all be on screen.
      for (final p in [
        Vector3(0, c.level.spawnY, 0),
        Vector3(-2.7, 0, 0),
        Vector3(2.7, 0, 0),
      ]) {
        final s = c.camera.project(p);
        expect(s, isNotNull);
        expect(s!.dx, inInclusiveRange(0, _viewport.width));
        expect(s.dy, inInclusiveRange(0, _viewport.height));
      }
      expect(c.nodes.length, 3, reason: 'structure + two pads');
      expect(c.cutsRemaining, 1);
      c.dispose();
    });

    test(
      'a swipe through the middle splits it and both halves land correctly',
      () async {
        final level = allLevels.first;
        final probe = GameController(level: level);
        await probe.load();
        probe.camera.setViewport(_viewport);
        final (from, to) = swipeThroughStructure(probe);
        probe.dispose();

        final c = await playCut(level, from: from, to: to);

        expect(c.phase, GamePhase.resolved, reason: 'must settle and score');
        expect(c.cutsUsed, 1);
        expect(
          c.world.pieces.where((p) => !p.removed).length,
          greaterThanOrEqualTo(2),
        );

        final r = c.result!;
        final where = c.world.pieces
            .where((p) => !p.removed)
            .map(
              (p) =>
                  '${p.requiredZoneId}->${p.landedZoneId} @'
                  '${p.position.x.toStringAsFixed(2)},'
                  '${p.position.y.toStringAsFixed(2)},'
                  '${p.position.z.toStringAsFixed(2)}',
            )
            .join(' | ');

        // Each half must find its own pad.
        final cyan = r.zones.firstWhere((z) => z.zoneId == 'cyan');
        final green = r.zones.firstWhere((z) => z.zoneId == 'green');
        expect(
          cyan.correctPieces,
          greaterThan(0),
          reason: 'orange half should reach the cyan pad; landings: $where',
        );
        expect(
          green.correctPieces,
          greaterThan(0),
          reason: 'crystal half should reach the green pad; landings: $where',
        );
        expect(
          r.passed,
          isTrue,
          reason:
              'a clean central cut should clear the level, '
              'got ${r.percent}%',
        );
        c.dispose();
      },
    );

    test('a swipe that misses the structure consumes no cut', () async {
      final level = allLevels.first;
      final c = GameController(level: level);
      await c.load();
      c.camera.setViewport(_viewport);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      // Far below everything.
      c.onPanStart(const Offset(200, 1040));
      c.onPanUpdate(const Offset(2200, 1040));
      c.onPanEnd();

      expect(c.cutsUsed, 0);
      expect(c.phase, GamePhase.ready);
      c.dispose();
    });

    test('a swipe too short to define a plane is ignored', () async {
      final c = GameController(level: allLevels.first);
      await c.load();
      c.camera.setViewport(_viewport);
      c.onPanStart(const Offset(1200, 500));
      c.onPanUpdate(const Offset(1205, 503));
      c.onPanEnd();
      expect(c.cutsUsed, 0);
      c.dispose();
    });

    test('cuts are limited to the level budget', () async {
      final level = allLevels.first;
      final probe = GameController(level: level);
      await probe.load();
      probe.camera.setViewport(_viewport);
      final (from, to) = swipeThroughStructure(probe);
      probe.dispose();

      final c = GameController(level: level);
      await c.load();
      c.camera.setViewport(_viewport);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }

      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();
      expect(c.cutsUsed, 1);
      expect(c.cutsRemaining, 0);
      expect(c.canCut, isFalse, reason: 'budget spent');

      // A second attempt must be refused.
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();
      expect(c.cutsUsed, 1);
      c.dispose();
    });

    test('restart returns the level to an identical starting state', () async {
      final level = allLevels.first;
      final c = GameController(level: level);
      await c.load();
      c.camera.setViewport(_viewport);
      final (from, to) = swipeThroughStructure(c);

      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();
      for (var i = 0; i < 200 && c.phase != GamePhase.resolved; i++) {
        c.update(1 / 60);
      }
      expect(c.cutsUsed, 1);

      await c.restart();
      expect(c.phase, GamePhase.ready);
      expect(c.cutsUsed, 0);
      expect(c.result, isNull);
      expect(c.liveAccuracy, 0);
      expect(c.world.pieces.where((p) => !p.removed).length, 1);
      expect(c.nodes.length, 3);
      c.dispose();
    });

    test('the same swipe twice gives the same score', () async {
      final level = allLevels.first;
      final probe = GameController(level: level);
      await probe.load();
      probe.camera.setViewport(_viewport);
      final (from, to) = swipeThroughStructure(probe);
      probe.dispose();

      final a = await playCut(level, from: from, to: to);
      final b = await playCut(level, from: from, to: to);
      expect(a.result!.accuracy, closeTo(b.result!.accuracy, 1e-9));
      expect(a.result!.stars, b.result!.stars);
      a.dispose();
      b.dispose();
    });
  });

  group('Cut geometry through the controller', () {
    test('halves keep the parent volume and gain real cut faces', () async {
      final level = allLevels.first;
      final probe = GameController(level: level);
      await probe.load();
      probe.camera.setViewport(_viewport);
      final before = probe.world.pieces.first.mesh.volume;
      final (from, to) = swipeThroughStructure(probe);

      for (var i = 0; i < 6; i++) {
        probe.update(1 / 60);
      }
      probe.onPanStart(from);
      probe.onPanUpdate(to);
      probe.onPanEnd();

      final pieces = probe.world.pieces.where((p) => !p.removed).toList();
      expect(pieces.length, 2);
      final after = pieces.fold<double>(0, (a, p) => a + p.mesh.volume);
      expect(after, closeTo(before, before * 0.03));

      // Both halves must carry interior faces from the cut.
      for (final p in pieces) {
        final hasCut = p.mesh.triMat.any(
          (m) => p.mesh.materials[m].name.endsWith('#cut'),
        );
        expect(hasCut, isTrue, reason: 'piece ${p.id} has no cut face');
      }
      probe.dispose();
    });

    test(
      'each half is assigned the zone its dominant material requires',
      () async {
        final level = allLevels.first;
        final c = GameController(level: level);
        await c.load();
        c.camera.setViewport(_viewport);
        final (from, to) = swipeThroughStructure(c);
        for (var i = 0; i < 6; i++) {
          c.update(1 / 60);
        }
        c.onPanStart(from);
        c.onPanUpdate(to);
        c.onPanEnd();

        final zones = c.world.pieces
            .where((p) => !p.removed)
            .map((p) => p.requiredZoneId)
            .toSet();
        expect(
          zones,
          containsAll(<String>{'cyan', 'green'}),
          reason: 'the two halves must want different pads',
        );
        c.dispose();
      },
    );
  });

  group('Campaign smoke', () {
    test('every level loads and frames its stage on screen', () async {
      for (final level in allLevels) {
        final c = GameController(level: level);
        await c.load();
        expect(
          c.phase,
          GamePhase.ready,
          reason: 'level ${level.id}: ${c.errorMessage}',
        );
        c.camera.setViewport(_viewport);

        final s = c.camera.project(Vector3(level.spawnX, level.spawnY, 0));
        expect(s, isNotNull, reason: 'level ${level.id} structure off screen');
        expect(
          s!.dx,
          inInclusiveRange(0, _viewport.width),
          reason: 'level ${level.id}',
        );
        expect(
          s.dy,
          inInclusiveRange(0, _viewport.height),
          reason: 'level ${level.id}',
        );

        for (final z in level.zones) {
          final p = c.camera.project(Vector3(z.x, 0, z.z));
          expect(p, isNotNull, reason: 'level ${level.id} pad ${z.id}');
          expect(
            p!.dx,
            inInclusiveRange(-50.0, _viewport.width + 50),
            reason: 'level ${level.id} pad ${z.id} off screen',
          );
        }
        expect(
          c.nodes.length,
          level.zones.length + 1 + level.props.length,
          reason: 'level ${level.id}: structure + pads + props',
        );
        c.dispose();
      }
    });
  });
}
