import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/game_controller.dart';
import 'package:kanban_slicer/game/levels/campaign.dart';
import 'package:kanban_slicer/game/levels/level_def.dart';
import 'package:kanban_slicer/game/levels/level_validator.dart';
import 'package:kanban_slicer/game/materials/material_kind.dart';
import 'package:kanban_slicer/game/physics/physics_world.dart';
import 'package:kanban_slicer/game/renderer/glb_loader.dart';
import 'package:kanban_slicer/game/renderer/mesh.dart';
import 'package:kanban_slicer/game/renderer/model_cache.dart';
import 'package:kanban_slicer/game/renderer/primitives.dart';
import 'package:kanban_slicer/game/scoring/scoring.dart';
import 'package:vector_math/vector_math_64.dart';

const _viewport = Size(2400, 1080);
const _cyan = Color(0xFF35D6F0);

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

RigidPiece _piece(PhysicsWorld w, Vector3 at, MaterialKind kind) {
  final p = RigidPiece(
    id: w.nextId,
    mesh: Primitives.box(Vector3(0.6, 0.6, 0.6), _cyan),
    kind: kind,
    position: at,
  );
  w.add(p);
  return p;
}

(Offset, Offset) _swipeThrough(GameController c) {
  final p = c.camera.project(Vector3(c.level.spawnX, c.level.spawnY, 0))!;
  return (Offset(p.dx, p.dy - 320), Offset(p.dx, p.dy + 320));
}

Future<GameController> _open(LevelDef level) async {
  final c = GameController(level: level);
  await c.load();
  expect(c.phase, GamePhase.ready, reason: c.errorMessage ?? '');
  c.camera.setViewport(_viewport);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_seedCache);

  group('Explosive cores', () {
    test('a core is inert until armed', () {
      final w = PhysicsWorld();
      final core = _piece(w, Vector3(0, 4, 0), MaterialKind.explosiveCore);
      expect(core.isArmed, isFalse);
      for (var i = 0; i < 60; i++) {
        w.advance(1 / 60);
      }
      expect(w.detonations, isEmpty);
    });

    test('an armed core fires once, after its fuse', () {
      final w = PhysicsWorld();
      final core = _piece(w, Vector3(0, 4, 0), MaterialKind.explosiveCore);
      final fuse = MaterialKind.explosiveCore.profile.fuseSeconds;
      core.arm(fuse);

      // Half way through the fuse, nothing has happened yet.
      for (var i = 0; i < (fuse * 60 * 0.5).round(); i++) {
        w.advance(1 / 60);
      }
      expect(w.detonations, isEmpty);
      expect(core.isArmed, isTrue);
      expect(core.fuseProgress, closeTo(0.5, 0.1));

      for (var i = 0; i < (fuse * 60).round() + 10; i++) {
        w.advance(1 / 60);
      }
      expect(w.detonations.length, 1);
      expect(core.isArmed, isFalse);

      // And never again.
      w.detonations.clear();
      for (var i = 0; i < 120; i++) {
        w.advance(1 / 60);
      }
      expect(w.detonations, isEmpty);
    });

    test('the blast shoves nearby pieces away and spares distant ones', () {
      final w = PhysicsWorld(gravity: Vector3.zero());
      final core = _piece(w, Vector3(0, 4, 0), MaterialKind.explosiveCore);
      final near = _piece(w, Vector3(1.0, 4, 0), MaterialKind.plasticToy);
      final far = _piece(w, Vector3(9.0, 4, 0), MaterialKind.plasticToy);
      core.arm(0.1);

      for (var i = 0; i < 30; i++) {
        w.advance(1 / 60);
      }

      expect(w.detonations.length, 1);
      expect(
        near.velocity.x,
        greaterThan(0.5),
        reason: 'the near piece is pushed away from the core',
      );
      expect(
        far.velocity.length,
        closeTo(0, 1e-9),
        reason: 'outside the blast radius nothing happens',
      );
    });

    test('the shove falls off with distance', () {
      double kickAt(double x) {
        final w = PhysicsWorld(gravity: Vector3.zero());
        final core = _piece(w, Vector3(0, 4, 0), MaterialKind.explosiveCore);
        final other = _piece(w, Vector3(x, 4, 0), MaterialKind.plasticToy);
        core.arm(0.1);
        for (var i = 0; i < 30; i++) {
          w.advance(1 / 60);
        }
        return other.velocity.length;
      }

      expect(kickAt(0.8), greaterThan(kickAt(2.0)));
      expect(kickAt(2.0), greaterThan(kickAt(3.2)));
    });

    test('heavy metal resists the blast more than light jelly', () {
      double kickFor(MaterialKind kind) {
        final w = PhysicsWorld(gravity: Vector3.zero());
        final core = _piece(w, Vector3(0, 4, 0), MaterialKind.explosiveCore);
        final other = _piece(w, Vector3(1.2, 4, 0), kind);
        core.arm(0.1);
        for (var i = 0; i < 30; i++) {
          w.advance(1 / 60);
        }
        return other.velocity.length;
      }

      expect(
        kickFor(MaterialKind.jelly),
        greaterThan(kickFor(MaterialKind.metal)),
      );
    });

    test('an armed core keeps the attempt open', () {
      final w = PhysicsWorld();
      final core = _piece(w, Vector3(0, 0.3, 0), MaterialKind.explosiveCore);
      core.arm(0.6);
      core.settled = true;
      core.asleep = true;
      expect(
        w.allSettled,
        isFalse,
        reason: 'scoring must wait for the core to go off',
      );
      for (var i = 0; i < 60; i++) {
        w.advance(1 / 60);
      }
      expect(core.isArmed, isFalse);
    });

    test('cutting a core level arms it and it detonates in play', () async {
      final level = levelById(45)!;
      final c = await _open(level);
      final (from, to) = _swipeThrough(c);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();

      final armed = c.world.pieces.where((p) => p.isArmed).toList();
      expect(armed, isNotEmpty, reason: 'the freed core must arm');
      // The warning ring is fed from live fuse state.
      c.update(1 / 60);
      expect(c.effects.armedCores, isNotEmpty);

      var sawShockwave = false;
      for (var i = 0; i < 600 && c.phase != GamePhase.resolved; i++) {
        c.update(1 / 60);
        if (c.effects.shockwaves.isNotEmpty) sawShockwave = true;
      }
      expect(sawShockwave, isTrue, reason: 'the blast must be shown');
      expect(c.phase, GamePhase.resolved);
      c.dispose();
    });
  });

  group('Chain reactions', () {
    test('held props hang in place until a cut releases them', () async {
      final level = levelById(47)!;
      final c = await _open(level);

      final prop = c.world.pieces.firstWhere((p) => p.isHeldProp);
      final startY = prop.position.y;
      for (var i = 0; i < 60; i++) {
        c.update(1 / 60);
      }
      expect(
        prop.position.y,
        closeTo(startY, 1e-9),
        reason: 'a held prop must not fall before the cut',
      );

      final (from, to) = _swipeThrough(c);
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();

      // Still held during the chain delay.
      c.update(1 / 60);
      expect(prop.frozen, isTrue);

      for (var i = 0; i < 90; i++) {
        c.update(1 / 60);
      }
      expect(prop.frozen, isFalse, reason: 'the chain must release it');
      expect(prop.position.y, lessThan(startY), reason: 'and it must fall');
      c.dispose();
    });

    test('a held machine spins in place before release', () async {
      final c = await _open(levelById(47)!);
      final prop = c.world.pieces.firstWhere((p) => p.isHeldProp);
      final start = prop.orientation.clone();
      for (var i = 0; i < 30; i++) {
        c.update(1 / 60);
      }
      expect(
        prop.orientation.x == start.x && prop.orientation.w == start.w,
        isFalse,
        reason: 'machinery should read as running while held',
      );
      c.dispose();
    });

    test('spinMachine kicks loose pieces outward', () async {
      final level = levelById(49)!;
      final c = await _open(level);
      final (from, to) = _swipeThrough(c);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();

      final before = c.world.pieces
          .where((p) => !p.removed)
          .map((p) => p.angularVelocity.y.abs())
          .reduce((a, b) => a > b ? a : b);

      for (var i = 0; i < 60; i++) {
        c.update(1 / 60);
      }
      final after = c.world.pieces
          .where((p) => !p.removed)
          .map((p) => p.angularVelocity.y.abs())
          .reduce((a, b) => a > b ? a : b);
      expect(
        after,
        greaterThan(before),
        reason: 'the machine kick must add spin',
      );
      c.dispose();
    });

    test('dropStructure adds a scored body after a detonation', () async {
      final level = levelById(50)!;
      final c = await _open(level);
      final startPieces = c.world.pieces.length;
      final (from, to) = _swipeThrough(c);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();

      var maxPieces = 0;
      for (var i = 0; i < 600 && c.phase != GamePhase.resolved; i++) {
        c.update(1 / 60);
        final live = c.world.pieces.where((p) => !p.removed).length;
        if (live > maxPieces) maxPieces = live;
      }
      expect(
        maxPieces,
        greaterThan(startPieces + 1),
        reason: 'the detonation must drop an extra structure in',
      );
      c.dispose();
    });

    test('autoSplit cuts a second time on its own', () async {
      final level = levelById(53)!;
      final c = await _open(level);
      final (from, to) = _swipeThrough(c);
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();

      final afterPlayerCut = c.world.pieces.where((p) => !p.removed).length;
      var most = afterPlayerCut;
      for (var i = 0; i < 600 && c.phase != GamePhase.resolved; i++) {
        c.update(1 / 60);
        final live = c.world.pieces.where((p) => !p.removed).length;
        if (live > most) most = live;
      }
      expect(
        most,
        greaterThan(afterPlayerCut),
        reason: 'the chain split must produce more pieces',
      );
      // The player still only spent one cut.
      expect(c.cutsUsed, 1);
      c.dispose();
    });

    test('restart clears chain state and re-holds the props', () async {
      final c = await _open(levelById(47)!);
      final (from, to) = _swipeThrough(c);
      c.onPanStart(from);
      c.onPanUpdate(to);
      c.onPanEnd();
      for (var i = 0; i < 120; i++) {
        c.update(1 / 60);
      }
      expect(c.world.pieces.any((p) => p.isHeldProp), isFalse);

      await c.restart();
      expect(c.cutsUsed, 0);
      expect(
        c.world.pieces.where((p) => p.isHeldProp).length,
        1,
        reason: 'the prop must be held again on retry',
      );
      expect(c.world.pieces.any((p) => p.isArmed), isFalse);
      c.dispose();
    });
  });

  group('Cut purity', () {
    /// Worst purity across the halves produced by a vertical cut offset
    /// [dx] pixels from the structure's centre.
    Future<double> worstPurityAt(double dx) async {
      final c = await _open(allLevels.first);
      final centre = c.camera.project(
        Vector3(c.level.spawnX, c.level.spawnY, 0),
      )!;
      for (var i = 0; i < 6; i++) {
        c.update(1 / 60);
      }
      c.onPanStart(Offset(centre.dx + dx, centre.dy - 320));
      c.onPanUpdate(Offset(centre.dx + dx, centre.dy + 320));
      c.onPanEnd();
      final pieces = c.world.pieces
          .where((p) => !p.removed && p.requiredZoneId != null)
          .map((p) => p.purity)
          .toList();
      c.dispose();
      expect(pieces, isNotEmpty);
      return pieces.reduce((a, b) => a < b ? a : b);
    }

    test('a cut on the material seam is purer than one off it', () async {
      // The hero's colour boundary sits a little right of its centroid, so
      // finding the seam is the actual skill the level is testing.
      final onSeam = await worstPurityAt(24);
      final wayOff = await worstPurityAt(230);
      expect(
        onSeam,
        greaterThan(wayOff + 0.1),
        reason:
            'cutting the seam must beat cutting anywhere: '
            'seam=$onSeam off=$wayOff',
      );
      expect(onSeam, greaterThan(0.8));
    });

    test('a lopsided cut measurably contaminates a piece', () async {
      expect(await worstPurityAt(230), lessThan(0.9));
    });

    test('impurity costs accuracy', () {
      // Two identical landings, differing only in purity.
      double scoreWith(double purity) {
        final level = allLevels.first;
        expect(
          level.enforcePurity,
          isTrue,
          reason: 'level 1 must score on cut purity',
        );
        final w = PhysicsWorld();
        w.pads.add(
          PadSurface(
            id: 'cyan',
            centre: Vector3(-2.4, 0, 0),
            halfExtents: Vector3(1.45, 0, 1.45),
            top: 0.3,
          ),
        );
        final p = _piece(w, Vector3(-2.4, 0.5, 0), MaterialKind.crystal)
          ..requiredZoneId = 'cyan'
          ..purity = purity
          ..settled = true;
        return Scorer(level).evaluate(w, [p], cutsUsed: 1).accuracy;
      }

      expect(scoreWith(1.0), greaterThan(scoreWith(0.7)));
      expect(scoreWith(1.0), closeTo(1.0, 1e-6));
    });
  });

  group('Validator covers the new data', () {
    final knownModels = Directory('assets/models')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.glb'))
        .toSet();
    MeshData? meshFor(String m) => ModelCache.instance.peek(m);
    final validator = LevelValidator(
      meshFor: meshFor,
      knownModels: knownModels,
    );

    test('every shipped level still passes', () {
      final issues = validator.validateAll(allLevels);
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('catches a held prop nothing can release', () {
      final broken = LevelDef(
        id: 950,
        world: 5,
        name: 'STUCK',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        props: const [PropDef(model: 'gear_machine.glb', x: 0, y: 6)],
        materials: const [
          MaterialRule(
            materialName: 'M_cyan',
            kind: MaterialKind.crystal,
            zoneId: 'cyan',
          ),
          MaterialRule(
            materialName: 'M_yellow',
            kind: MaterialKind.crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(validator.validate(broken).any((i) => i.code == 'prop'), isTrue);
    });

    test('catches a detonation trigger with nothing explosive', () {
      final broken = LevelDef(
        id: 951,
        world: 5,
        name: 'NO BOOM',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        chain: const [
          ChainEvent(
            trigger: ChainTrigger.onDetonation,
            action: ChainAction.spinMachine,
            strength: 2.0,
          ),
        ],
        materials: const [
          MaterialRule(
            materialName: 'M_cyan',
            kind: MaterialKind.crystal,
            zoneId: 'cyan',
          ),
          MaterialRule(
            materialName: 'M_yellow',
            kind: MaterialKind.crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(validator.validate(broken).any((i) => i.code == 'chain'), isTrue);
    });

    test('catches a dropStructure with a missing model', () {
      final broken = LevelDef(
        id: 952,
        world: 5,
        name: 'GHOST DROP',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        chain: const [
          ChainEvent(
            trigger: ChainTrigger.onFirstCut,
            action: ChainAction.dropStructure,
            model: 'not_a_real_model.glb',
          ),
        ],
        materials: const [
          MaterialRule(
            materialName: 'M_cyan',
            kind: MaterialKind.crystal,
            zoneId: 'cyan',
          ),
          MaterialRule(
            materialName: 'M_yellow',
            kind: MaterialKind.crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(validator.validate(broken).any((i) => i.code == 'chain'), isTrue);
    });
  });
}
