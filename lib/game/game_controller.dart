import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../core/audio/audio_service.dart';
import '../core/haptics/haptics.dart';
import '../shared/theme/app_theme.dart';
import 'camera/camera3d.dart';
import 'effects/effects.dart';
import 'levels/level_def.dart';
import 'materials/material_kind.dart';
import 'physics/physics_world.dart';
import 'renderer/mesh.dart';
import 'renderer/model_cache.dart';
import 'renderer/scene_renderer.dart';
import 'scoring/scoring.dart';
import 'slicing/plane.dart';
import 'slicing/slicer.dart';

enum GamePhase { loading, ready, cutting, falling, resolved, error }

/// Owns one attempt at one level: assets, physics, cutting, effects, scoring.
///
/// Deliberately free of Flutter widget types beyond painting primitives so it
/// can be driven headlessly by tests.
class GameController extends ChangeNotifier {
  GameController({required this.level, EffectSystem? effects, this.onResolved})
    : effects = effects ?? EffectSystem();

  final LevelDef level;
  final EffectSystem effects;
  final void Function(LevelResult result)? onResolved;

  final Camera3D camera = Camera3D();
  final PhysicsWorld world = PhysicsWorld();
  final Lighting lighting = Lighting();
  late final Scorer scorer = Scorer(level);

  GamePhase phase = GamePhase.loading;
  String? errorMessage;

  /// Elapsed level time, used for pad motion and rotation.
  double time = 0.0;
  double _rotation = 0.0;

  /// 1.0 normal, dips during the slow-motion slice.
  double timeScale = 1.0;
  double _slowMoRemaining = 0.0;

  int cutsUsed = 0;
  int get cutsRemaining => level.allowedCuts - cutsUsed;

  LevelResult? result;
  double liveAccuracy = 0.0;

  /// Swipe currently being drawn, in screen space.
  Offset? swipeStart;
  Offset? swipeCurrent;

  /// Blade animation state.
  double _bladeT = 0.0;
  bool _bladeActive = false;
  Vector3 _bladeFrom = Vector3.zero();
  Vector3 _bladeTo = Vector3.zero();
  Quaternion _bladeRot = Quaternion.identity();

  MeshData? _bladeMesh;
  final Map<String, MeshData> _padMeshes = <String, MeshData>{};
  final List<RenderNode> _nodes = <RenderNode>[];
  final Map<int, RenderNode> _pieceNodes = <int, RenderNode>{};
  final Map<String, RenderNode> _padNodes = <String, RenderNode>{};
  RenderNode? _bladeNode;

  double _settleTimer = 0.0;
  double _fallTimer = 0.0;
  bool _resolvedFired = false;

  /// Hard cap on how long pieces may keep moving before the attempt is scored
  /// anyway. A piece balanced on a pad edge can rock for a very long time;
  /// the player must never be left waiting on it.
  static const double maxFallSeconds = 6.5;
  final Set<int> _landingAnnounced = <int>{};

  /// Held props spin in place until released, so machinery reads as running.
  final Map<int, double> _propSpin = <int, double>{};
  final Map<int, double> _propAngle = <int, double>{};

  /// Chain events waiting on their delay, as (secondsLeft, event).
  final List<(double, ChainEvent)> _pendingChain = <(double, ChainEvent)>[];

  /// Chain events that have already fired, so onFirstCut fires exactly once.
  final Set<ChainEvent> _firedChain = <ChainEvent>{};

  bool get canCut =>
      (phase == GamePhase.ready || phase == GamePhase.falling) &&
      cutsRemaining > 0 &&
      !_bladeActive;

  List<RenderNode> get nodes => _nodes;

  /// Diagnostics surfaced by the debug readout and the performance report.
  int lastTriangles = 0;
  String cullReport = '';
  int paintTicks = 0;
  Size lastPaintSize = Size.zero;
  double fps = 0;
  int get nodeCount => _nodes.length;
  int get pieceCount => world.pieces.where((p) => !p.removed).length;

  // ---------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------

  Future<void> load() async {
    try {
      // Props and chain-spawned structures must be resident before the cut,
      // or a chain event would stall waiting on I/O mid-attempt.
      await ModelCache.instance.preload(level.requiredModels);
      final structure = await ModelCache.instance.load(level.model);
      for (final z in level.zones) {
        final file = 'pad_${z.colorKey}.glb';
        _padMeshes[z.id] = await ModelCache.instance.load(file);
      }
      _bladeMesh = await ModelCache.instance.load('default_blade.glb');

      _buildWorld(structure);
      phase = GamePhase.ready;
    } catch (e, st) {
      phase = GamePhase.error;
      errorMessage = '$e';
      debugPrint('Level ${level.id} failed to load: $e\n$st');
    }
    notifyListeners();
  }

  void _buildWorld(MeshData raw) {
    world.clear();
    world.gravity = Vector3(0, level.gravity, 0);
    _nodes.clear();
    _pieceNodes.clear();
    _padNodes.clear();
    _landingAnnounced.clear();
    _propSpin.clear();
    _propAngle.clear();
    effects.clear();

    // Bake scale in so every downstream stage can assume unit scale.
    final scaled = level.modelScale == 1.0 ? raw : raw.scaled(level.modelScale);
    final mesh = scaled.recenteredOnCentroid();

    // Pads.
    for (final z in level.zones) {
      final c = z.centreAt(0);
      world.pads.add(
        PadSurface(
          id: z.id,
          centre: Vector3(c.x, 0, c.z),
          halfExtents: Vector3(z.width * 0.5, 0, z.depth * 0.5),
          top: z.top,
        ),
      );
      final padMesh = _padMeshes[z.id];
      if (padMesh != null) {
        final node = RenderNode(
          mesh: padMesh,
          position: Vector3(c.x, 0, c.z),
          scale: z.width / 1.9,
          castShadow: false,
        );
        _padNodes[z.id] = node;
        _nodes.add(node);
      }
    }

    // Force fields.
    for (final f in level.fields) {
      world.fields.add(
        FieldZone(
          kind: f.kind == 'magnet' ? FieldKind.magnet : FieldKind.wind,
          centre: Vector3(f.x, f.y, f.z),
          halfExtents: Vector3(f.width * 0.5, f.height * 0.5, f.depth * 0.5),
          strength: f.strength,
          direction: Vector3(f.dirX, f.dirY, f.dirZ),
          affects: f.affects,
        ),
      );
    }

    // The intact structure: present in the world but frozen, so the solver
    // leaves it alone while the controller spins it.
    final piece = RigidPiece(
      id: world.nextId,
      mesh: mesh,
      kind: _dominantKind(mesh),
      position: Vector3(level.spawnX, level.spawnY, 0),
    )..frozen = true;
    _assignRule(piece);
    world.add(piece);

    final node = RenderNode(mesh: mesh, position: piece.position.clone());
    _pieceNodes[piece.id] = node;
    _nodes.add(node);

    _spawnProps();
    _frameCamera(mesh);
    _syncNodes();
  }

  /// Places the level's extra bodies: supports, second structures, machinery.
  void _spawnProps() {
    for (final def in level.props) {
      final raw = ModelCache.instance.peek(def.model);
      if (raw == null) continue;
      final mesh = (def.scale == 1.0 ? raw : raw.scaled(def.scale))
          .recenteredOnCentroid();
      final prop = RigidPiece(
        id: world.nextId,
        mesh: mesh,
        kind: def.kind,
        position: Vector3(def.x, def.y, def.z),
      )..frozen = def.frozen;
      prop.isHeldProp = def.frozen;
      prop.requiredZoneId = def.zoneId;
      _propSpin[prop.id] = def.spin;
      world.add(prop);

      final node = RenderNode(mesh: mesh, position: prop.position.clone());
      _pieceNodes[prop.id] = node;
      _nodes.add(node);
    }
  }

  /// Elevated three-quarter framing that fits the structure and both pad rows.
  void _frameCamera(MeshData mesh) {
    var minX = level.spawnX, maxX = level.spawnX;
    for (final z in level.zones) {
      minX = math.min(minX, z.x - z.width * 0.5 - z.motionRange);
      maxX = math.max(maxX, z.x + z.width * 0.5 + z.motionRange);
    }
    final spanX = math.max(4.0, maxX - minX);
    final centreX = (minX + maxX) * 0.5;
    // Weighted toward the structure: the pads only need to be readable, the
    // object being cut needs to fill enough of the frame to aim at.
    final radius = math.max(spanX * 0.42, mesh.boundingRadius * 2.2);
    final dist = camera.distanceToFit(radius, fill: 0.72).clamp(8.0, 26.0);

    final look = Vector3(centreX, level.spawnY * 0.55, 0);
    // Kept on the stage centre line: an off-axis eye turns a vertical swipe
    // into a slanted world plane, which quietly shaves the wrong material off
    // one half and makes a visually clean cut score badly.
    camera.lookAt(Vector3(centreX, look.y + dist * 0.30, dist * 0.88), look);
  }

  MaterialKind _dominantKind(MeshData mesh) {
    final counts = <MaterialKind, double>{};
    for (var t = 0; t < mesh.triCount; t++) {
      final name = mesh.materials[mesh.triMat[t]].name;
      final k = level.kindFor(name);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    var best = level.defaultKind;
    var bestN = -1.0;
    counts.forEach((k, n) {
      if (n > bestN) {
        bestN = n;
        best = k;
      }
    });
    return best;
  }

  /// Resolves which zone a piece must reach from its dominant material.
  ///
  /// Dominance is measured by triangle area, not count, so a section made of a
  /// few large faces is not out-voted by a densely tessellated sliver.
  void _assignRule(RigidPiece piece) {
    final mesh = piece.mesh;
    final area = <int, double>{};
    for (var t = 0; t < mesh.triCount; t++) {
      final i = t * 9;
      final ax = mesh.positions[i],
          ay = mesh.positions[i + 1],
          az = mesh.positions[i + 2];
      final bx = mesh.positions[i + 3],
          by = mesh.positions[i + 4],
          bz = mesh.positions[i + 5];
      final cx = mesh.positions[i + 6],
          cy = mesh.positions[i + 7],
          cz = mesh.positions[i + 8];
      final ux = bx - ax, uy = by - ay, uz = bz - az;
      final vx = cx - ax, vy = cy - ay, vz = cz - az;
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      final a = math.sqrt(nx * nx + ny * ny + nz * nz) * 0.5;

      var name = mesh.materials[mesh.triMat[t]].name;
      // Cut faces vote for the surface they were carved from.
      if (name.endsWith('#cut')) name = name.substring(0, name.length - 4);
      final idx = _ruleIndexFor(name);
      area[idx] = (area[idx] ?? 0) + a;
    }

    // Group the areas by destination pad, not by material: two materials that
    // want the same pad are not a contaminated piece.
    final byZone = <String, double>{};
    var zonedArea = 0.0;
    var bestIdx = -1;
    var bestArea = -1.0;
    var hasCore = false;
    area.forEach((idx, a) {
      if (idx < 0) return;
      if (a > 1e-9 && level.materials[idx].kind.profile.isExplosive) {
        hasCore = true;
      }
      if (a > bestArea) {
        bestArea = a;
        bestIdx = idx;
      }
      final zone = level.materials[idx].zoneId;
      if (zone != null) {
        byZone[zone] = (byZone[zone] ?? 0) + a;
        zonedArea += a;
      }
    });

    piece.containsCore = hasCore;

    if (bestIdx < 0) {
      piece.kind = level.defaultKind;
      piece.requiredZoneId = null;
      piece.isBonus = false;
      piece.purity = 1.0;
      return;
    }

    // The piece goes wherever most of its *zoned* area wants to go. Falling
    // back to the largest material covers pieces made entirely of filler.
    String? destination;
    var destArea = 0.0;
    byZone.forEach((zone, a) {
      if (a > destArea) {
        destArea = a;
        destination = zone;
      }
    });

    final rule = level.materials[bestIdx];
    piece.kind = rule.kind;
    piece.isBonus = rule.isBonus;

    if (destination == null || zonedArea <= 1e-9) {
      piece.requiredZoneId = null;
      piece.purity = 1.0;
    } else {
      piece.requiredZoneId = destination;
      // Everything zoned but heading elsewhere is contamination the player
      // left attached.
      piece.purity = (destArea / zonedArea).clamp(0.0, 1.0);
    }
  }

  int _ruleIndexFor(String materialName) {
    for (var i = 0; i < level.materials.length; i++) {
      if (level.materials[i].materialName == materialName) return i;
    }
    return -1;
  }

  // ---------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------

  void onPanStart(Offset p) {
    if (!canCut) return;
    swipeStart = p;
    swipeCurrent = p;
    AudioService.instance.play(Sfx.swipeStart, gain: 0.6);
    Haptics.instance.swipeTick();
    notifyListeners();
  }

  void onPanUpdate(Offset p) {
    if (swipeStart == null) return;
    swipeCurrent = p;
    notifyListeners();
  }

  void onPanEnd() {
    final a = swipeStart;
    final b = swipeCurrent;
    swipeStart = null;
    swipeCurrent = null;
    if (a == null || b == null || !canCut) {
      notifyListeners();
      return;
    }
    final plane = camera.planeFromSwipe(a, b);
    if (plane == null) {
      notifyListeners();
      return;
    }
    _performCut(plane, a, b);
  }

  // ---------------------------------------------------------------------
  // Cutting
  // ---------------------------------------------------------------------

  /// Cuts one body with a world-space plane.
  ///
  /// Returns the two halves, or an empty list if the plane missed. The parent
  /// is marked removed and its render node dropped. Shared by the player's
  /// swipe and by chain-reaction auto-splits.
  List<RigidPiece> _sliceOne(
    RigidPiece piece,
    CutPlane plane, {
    List<List<Vector3>>? outLoops,
  }) {
    // Express the world plane in the piece's own object space.
    final inv = piece.orientation.conjugated();
    final localNormal = inv.rotated(plane.normal);
    final localOffset = plane.offset - plane.normal.dot(piece.position);
    final sliced = MeshSlicer.slice(
      piece.mesh,
      CutPlane(localNormal, localOffset),
    );
    if (!sliced.didCut) return const <RigidPiece>[];

    // Cut outlines are in object space; lift them to world for the effect.
    if (outLoops != null) {
      for (final loop in sliced.loops) {
        outLoops.add(
          loop
              .map((p) {
                final v = p.clone();
                piece.orientation.rotate(v);
                return v + piece.position;
              })
              .toList(growable: false),
        );
      }
    }

    final profile = piece.kind.profile;
    final worldNormal = plane.normal;

    RigidPiece spawn(MeshData half, double side) {
      final centroid = half.centroid;
      final centred = half.recenteredOnCentroid();
      final worldOffset = centroid.clone();
      piece.orientation.rotate(worldOffset);

      // Inherit the parent's motion, including the spin it had at the moment
      // of the cut, then push the halves apart.
      final v = piece.velocity.clone();
      v.add(piece.angularVelocity.cross(worldOffset));

      // Separation is split between the cut normal (physically what pushes the
      // halves apart) and a horizontal spread away from the structure's
      // centre. The spread is what makes a cut at any angle send each half
      // toward the side it came from, instead of dropping both on the same
      // spot -- the pads sit out to the sides, so this is the shot.
      v.addScaled(worldNormal, side * profile.separationImpulse * 0.40);
      final lateral = Vector3(worldOffset.x, 0, worldOffset.z);
      if (lateral.length2 > 1e-5) {
        lateral.normalize();
        v.addScaled(lateral, profile.separationImpulse * 0.62);
      }

      final child = RigidPiece(
        id: world.nextId,
        mesh: centred,
        kind: piece.kind,
        position: piece.position + worldOffset,
        orientation: piece.orientation.clone(),
        velocity: v,
        angularVelocity: piece.angularVelocity.clone()
          ..addScaled(worldNormal, side * 0.6),
      );
      _assignRule(child);
      _aimAtZone(child);
      return child;
    }

    final halves = [spawn(sliced.front!, 1.0), spawn(sliced.back!, -1.0)];

    piece.removed = true;
    // Drop the parent's node too. Only removing it from the id map would leave
    // it in the render list with nothing left to update its visibility, so the
    // uncut structure would hang in the air forever.
    final oldNode = _pieceNodes.remove(piece.id);
    if (oldNode != null) _nodes.remove(oldNode);
    _propSpin.remove(piece.id);

    return halves;
  }

  /// Launches a freshly separated piece onto its own pad.
  ///
  /// The skill in this game is deciding *what ends up in each piece*, not
  /// throwing it — so once a piece exists, the cut launches it on a ballistic
  /// arc onto the pad its material requires. Pieces no longer scatter into the
  /// gaps between pads, which was pure noise.
  ///
  /// A sloppy cut is still punished, and harder than before: a piece carrying
  /// the wrong material delivers that material straight into a pad it does not
  /// belong in, and [RigidPiece.purity] scores the difference.
  ///
  /// Force fields are deliberately *not* compensated for. Wind and magnets
  /// perturb the arc, which is exactly what makes those levels levels.
  void _aimAtZone(RigidPiece child) {
    final zone = level.zoneById(child.requiredZoneId);
    if (zone == null) return; // unzoned filler just falls where it was cut

    final g = math.max(1.0, -level.gravity);
    final restY = zone.top + 0.35;

    // A little longer than free fall, so the piece arcs up and over rather
    // than sliding sideways off the structure.
    final drop = math.max(0.5, child.position.y - restY);
    final flight = (math.sqrt(2 * drop / g) * 1.28).clamp(0.55, 1.5);

    // Lead a moving pad to where it will actually be on arrival.
    final target = zone.centreAt(time + flight);

    // Deterministic spread so several pieces bound for one pad do not stack
    // in exactly the same spot.
    final spread = ((child.id * 37) % 7 - 3) * 0.11;
    var tx = target.x + spread;
    var tz = target.z + spread * 0.6;

    // Aim short by however far this material will slide after touchdown.
    // Ice, at friction 0.07, would otherwise glide straight off the far edge.
    final dx = tx - child.position.x;
    final dz = tz - child.position.z;
    final horiz = math.sqrt(dx * dx + dz * dz);
    if (horiz > 1e-4) {
      final vh = horiz / flight;
      final mu = math.max(0.05, child.kind.profile.friction);
      final slide = (vh * vh / (2 * mu * g)).clamp(0.0, zone.width * 0.42);
      final k = math.max(0.0, (horiz - slide * 0.9) / horiz);
      tx = child.position.x + dx * k;
      tz = child.position.z + dz * k;
    }

    child.velocity.setValues(
      (tx - child.position.x) / flight,
      (restY - child.position.y + 0.5 * g * flight * flight) / flight,
      (tz - child.position.z) / flight,
    );
  }

  void _performCut(CutPlane plane, Offset screenA, Offset screenB) {
    final newPieces = <RigidPiece>[];
    final allLoops = <List<Vector3>>[];
    var cutAnything = false;
    var cutSound = 'cut_crystal';

    for (final piece in List<RigidPiece>.from(world.pieces)) {
      if (piece.removed || piece.isHeldProp) continue;
      final halves = _sliceOne(piece, plane, outLoops: allLoops);
      if (halves.isEmpty) continue;
      cutAnything = true;
      cutSound = piece.kind.profile.cutSound;
      newPieces.addAll(halves);
    }

    if (!cutAnything) {
      // Swipe missed the structure entirely -- no cut is consumed.
      notifyListeners();
      return;
    }

    world.pieces.removeWhere((p) => p.removed);
    var armedAny = false;
    for (final p in newPieces) {
      p.frozen = false;
      world.add(p);
      final node = RenderNode(mesh: p.mesh, position: p.position.clone());
      _pieceNodes[p.id] = node;
      _nodes.add(node);

      // Freeing any explosive material starts its fuse.
      if (p.containsCore) {
        final core = MaterialKind.explosiveCore.profile;
        p.arm(
          core.fuseSeconds,
          radius: core.blastRadius,
          impulse: core.blastImpulse,
        );
        armedAny = true;
      }
    }

    cutsUsed++;
    phase = GamePhase.falling;

    if (armedAny) {
      AudioService.instance.play(Sfx.coreArm);
      Haptics.instance.contact();
    }
    _scheduleChain(
      cutsUsed == 1
          ? const {ChainTrigger.onFirstCut, ChainTrigger.onAnyCut}
          : const {ChainTrigger.onAnyCut},
    );

    // Feedback: slow motion, flash, sparks, sound, haptics.
    _slowMoRemaining = 0.42;
    _startBlade(plane, screenA, screenB);
    effects.cutOutline(allLoops, K.white);
    effects.burstAlongCut(allLoops, K.white, 7);
    effects.flash(K.cyan, 0.24, intensity: 0.85);
    AudioService.instance.playCut(cutSound);
    AudioService.instance.play(Sfx.separation, gain: 0.7);
    Haptics.instance.contact();

    notifyListeners();
  }

  /// Poses the blade along the swipe and starts its sweep.
  void _startBlade(CutPlane plane, Offset a, Offset b) {
    final depth = camera.position.distanceTo(
      Vector3(level.spawnX, level.spawnY, 0),
    );
    final pa = camera.position + camera.rayThrough(a) * depth;
    final pb = camera.position + camera.rayThrough(b) * depth;

    var dir = pb - pa;
    if (dir.length2 < 1e-9) return;
    dir.normalize();

    // Blade basis: long axis along the swipe, thin axis along the plane
    // normal, so the blade lies exactly in the cut plane.
    final zAxis = dir.cross(plane.normal).normalized();
    final basis = Matrix3.columns(plane.normal, dir, zAxis);
    _bladeRot = Quaternion.fromRotation(basis);

    final span = (pb - pa).length * 0.5 + 3.0;
    final mid = (pa + pb) * 0.5;
    _bladeFrom = mid - dir * span;
    _bladeTo = mid + dir * span;
    _bladeT = 0.0;
    _bladeActive = true;

    if (_bladeMesh != null && _bladeNode == null) {
      _bladeNode = RenderNode(
        mesh: _bladeMesh!,
        glowBoost: 0.5,
        castShadow: false,
      );
    }
    if (_bladeNode != null && !_nodes.contains(_bladeNode)) {
      _nodes.add(_bladeNode!);
    }
    AudioService.instance.play(Sfx.bladeMove, gain: 0.8);
  }

  // ---------------------------------------------------------------------
  // Chain reactions
  // ---------------------------------------------------------------------

  /// Queues every not-yet-fired chain event whose trigger just happened.
  void _scheduleChain(Set<ChainTrigger> triggers) {
    for (final e in level.chain) {
      if (!triggers.contains(e.trigger)) continue;
      // onFirstCut and onDetonation are one-shot; onAnyCut can repeat.
      if (e.trigger != ChainTrigger.onAnyCut && _firedChain.contains(e)) {
        continue;
      }
      _firedChain.add(e);
      _pendingChain.add((e.delay, e));
    }
  }

  void _tickChain(double dt) {
    if (_pendingChain.isEmpty) return;
    for (var i = _pendingChain.length - 1; i >= 0; i--) {
      final (remaining, event) = _pendingChain[i];
      final left = remaining - dt;
      if (left > 0) {
        _pendingChain[i] = (left, event);
        continue;
      }
      _pendingChain.removeAt(i);
      _runChain(event);
    }
  }

  void _runChain(ChainEvent e) {
    switch (e.action) {
      case ChainAction.collapseSupports:
        _collapseSupports(e);
      case ChainAction.dropStructure:
        _dropStructure(e);
      case ChainAction.spinMachine:
        _spinMachine(e);
      case ChainAction.autoSplit:
        _autoSplit(e);
    }
    notifyListeners();
  }

  /// Releases every held prop. Whatever they were holding up now falls.
  void _collapseSupports(ChainEvent e) {
    var released = false;
    for (final p in world.pieces) {
      if (p.removed || !p.frozen || !p.isHeldProp) continue;
      p.frozen = false;
      p.isHeldProp = false;
      p.wake();
      // A nudge so it topples rather than dropping dead straight.
      p.velocity.setValues(e.strength * 0.25, -e.strength * 0.2, 0);
      p.angularVelocity.setValues(0, 0, e.strength * 0.35);
      _propSpin.remove(p.id);
      released = true;
    }
    if (!released) return;
    AudioService.instance.play(Sfx.separation, gain: 0.9);
    Haptics.instance.contact();
    effects.flash(K.orange, 0.22, intensity: 0.4);
  }

  /// Drops a fresh structure into the scene.
  void _dropStructure(ChainEvent e) {
    final model = e.model;
    if (model == null) return;
    final raw = ModelCache.instance.peek(model);
    if (raw == null) return;

    final mesh = (e.modelScale == 1.0 ? raw : raw.scaled(e.modelScale))
        .recenteredOnCentroid();
    final piece = RigidPiece(
      id: world.nextId,
      mesh: mesh,
      kind: e.kind,
      position: Vector3(e.x, e.y, e.z),
      velocity: Vector3(0, -e.strength * 0.4, 0),
    );
    _assignRule(piece);
    // The event's zone wins: a dropped structure's materials need not appear
    // in the level's own rule table.
    if (e.zoneId != null) piece.requiredZoneId = e.zoneId;
    piece.kind = e.kind;
    world.add(piece);

    final node = RenderNode(mesh: mesh, position: piece.position.clone());
    _pieceNodes[piece.id] = node;
    _nodes.add(node);

    AudioService.instance.play(Sfx.separation);
    Haptics.instance.contact();
  }

  /// Kicks everything loose into a spin -- machinery throwing its contents.
  void _spinMachine(ChainEvent e) {
    var kicked = false;
    for (final p in world.pieces) {
      if (p.removed || p.frozen) continue;
      // Tangential kick about the machine's axis, so pieces are flung out
      // rather than simply spun on the spot.
      final dx = p.position.x - e.x;
      final dz = p.position.z - e.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len > 1e-3) {
        p.velocity.x += -dz / len * e.strength;
        p.velocity.z += dx / len * e.strength;
      }
      p.velocity.y += e.strength * 0.25;
      p.angularVelocity.y += e.strength * 0.8;
      p.wake();
      kicked = true;
    }
    if (!kicked) return;
    AudioService.instance.play(Sfx.cutMetal, gain: 0.8);
    Haptics.instance.contact();
    effects.flash(K.yellow, 0.2, intensity: 0.35);
  }

  /// Splits the largest remaining piece along a fixed world plane.
  void _autoSplit(ChainEvent e) {
    RigidPiece? target;
    var best = 0.0;
    for (final p in world.pieces) {
      if (p.removed || p.frozen) continue;
      if (p.mesh.volume > best) {
        best = p.mesh.volume;
        target = p;
      }
    }
    if (target == null) return;

    final normal = Vector3(e.planeNormalX, e.planeNormalY, e.planeNormalZ);
    if (normal.length2 < 1e-6) return;
    final plane = CutPlane.throughPoint(normal.normalized(), target.position);
    final pieces = _sliceOne(target, plane);
    if (pieces.isEmpty) return;

    world.pieces.removeWhere((p) => p.removed);
    for (final p in pieces) {
      p.frozen = false;
      world.add(p);
      final node = RenderNode(mesh: p.mesh, position: p.position.clone());
      _pieceNodes[p.id] = node;
      _nodes.add(node);
      if (p.containsCore) {
        final core = MaterialKind.explosiveCore.profile;
        p.arm(
          core.fuseSeconds,
          radius: core.blastRadius,
          impulse: core.blastImpulse,
        );
      }
    }
    AudioService.instance.playCut(target.kind.profile.cutSound);
    Haptics.instance.contact();
    effects.flash(K.cyan, 0.2, intensity: 0.5);
  }

  // ---------------------------------------------------------------------
  // Tick
  // ---------------------------------------------------------------------

  void update(double rawDt) {
    if (phase == GamePhase.loading || phase == GamePhase.error) return;

    // Ease the slow-motion ramp back to full speed.
    if (_slowMoRemaining > 0) {
      _slowMoRemaining -= rawDt;
      final k = (_slowMoRemaining / 0.42).clamp(0.0, 1.0);
      timeScale = 0.18 + (1.0 - k) * 0.82;
    } else {
      timeScale = 1.0;
    }

    if (rawDt > 1e-5) {
      // Smoothed so the readout is legible rather than flickering.
      fps = fps == 0 ? 1.0 / rawDt : fps * 0.9 + (1.0 / rawDt) * 0.1;
    }

    final dt = rawDt * timeScale;
    time += dt;

    if (_bladeActive) {
      _bladeT += rawDt * 2.6;
      if (_bladeT >= 1.0) {
        _bladeT = 1.0;
        _bladeActive = false;
        if (_bladeNode != null) _nodes.remove(_bladeNode);
      }
    }

    _updatePads();
    _tickChain(dt);
    _spinHeldProps(dt);

    if (phase == GamePhase.ready) {
      _rotation += level.rotationSpeed * dt;
      for (final p in world.pieces) {
        if (!p.frozen || _propSpin.containsKey(p.id)) continue;
        p.orientation = Quaternion.axisAngle(level.rotationAxis, _rotation);
      }
    } else if (phase == GamePhase.falling) {
      world.advance(dt);
      _drainDetonations();
      _checkLandings();
      _updateLiveScore();
      _fallTimer += rawDt;

      if (world.allSettled) {
        _settleTimer += rawDt;
        if (_settleTimer > 0.45) _resolve();
      } else {
        _settleTimer = 0.0;
        if (_fallTimer > maxFallSeconds) _resolve();
      }
    }

    effects.update(rawDt);
    _syncNodes();
    notifyListeners();
  }

  /// Held machinery keeps turning on its own axis so it reads as running,
  /// independent of the structure's own rotation.
  void _spinHeldProps(double dt) {
    if (_propSpin.isEmpty) return;
    for (final p in world.pieces) {
      final spin = _propSpin[p.id];
      if (spin == null || !p.frozen) continue;
      _propAngle[p.id] = (_propAngle[p.id] ?? 0.0) + spin * dt;
      p.orientation = Quaternion.axisAngle(Vector3(0, 1, 0), _propAngle[p.id]!);
    }
  }

  /// Turns physics detonation events into flash, sparks, sound and haptics,
  /// and lets a blast trigger its own chain events.
  void _drainDetonations() {
    if (world.detonations.isEmpty) return;
    for (final d in world.detonations) {
      effects.shockwave(d.position.clone(), d.radius, K.orange);
      effects.landing(d.position.clone(), K.orange, count: 26, speed: 5.5);
      effects.flash(K.orange, 0.32, intensity: 0.75);
      AudioService.instance.play(Sfx.coreBlast);
      Haptics.instance.perfect();
    }
    world.detonations.clear();
    _scheduleChain(const {ChainTrigger.onDetonation});
  }

  void _updatePads() {
    for (final z in level.zones) {
      if (z.motion == ZoneMotion.still) continue;
      final c = z.centreAt(time);
      for (final pad in world.pads) {
        if (pad.id == z.id) pad.centre.setValues(c.x, 0, c.z);
      }
      _padNodes[z.id]?.position.setValues(c.x, 0, c.z);
    }
  }

  /// Fires landing feedback the first time each piece comes to rest.
  void _checkLandings() {
    for (final p in world.pieces) {
      if (!p.settled || p.removed || _landingAnnounced.contains(p.id)) continue;
      _landingAnnounced.add(p.id);

      final pad = world.padUnder(p);
      if (pad == null) continue;
      final correct = p.requiredZoneId != null && pad.id == p.requiredZoneId;
      final colour = K.zoneColor(level.zoneById(pad.id)?.colorKey ?? 'cyan');

      effects.landing(p.position.clone(), correct ? colour : K.red, count: 12);
      if (correct) {
        effects.flash(colour, 0.18, intensity: 0.4);
        AudioService.instance.play(Sfx.landCorrect);
        Haptics.instance.correct();
      } else {
        effects.flash(K.red, 0.2, intensity: 0.45);
        AudioService.instance.play(Sfx.landWrong);
        Haptics.instance.wrong();
      }
    }
  }

  void _updateLiveScore() {
    final r = scorer.evaluate(world, world.pieces, cutsUsed: cutsUsed);
    liveAccuracy = r.accuracy;
  }

  void _resolve() {
    if (_resolvedFired) return;
    _resolvedFired = true;

    final r = scorer.evaluate(world, world.pieces, cutsUsed: cutsUsed);
    result = r;
    liveAccuracy = r.accuracy;
    phase = GamePhase.resolved;

    if (r.perfect) {
      effects.flash(K.white, 0.6, intensity: 1.0);
      AudioService.instance.play(Sfx.perfectCut);
      Haptics.instance.perfect();
    } else if (r.passed) {
      effects.flash(K.green, 0.35, intensity: 0.55);
      AudioService.instance.play(Sfx.levelComplete);
      Haptics.instance.correct();
    } else {
      effects.flash(K.red, 0.35, intensity: 0.5);
      AudioService.instance.play(Sfx.failure);
      Haptics.instance.wrong();
    }

    onResolved?.call(r);
    notifyListeners();
  }

  /// Ends the attempt early when the player runs out of cuts without cutting.
  void forceResolve() {
    if (phase == GamePhase.ready) {
      phase = GamePhase.falling;
    }
    _resolve();
  }

  void _syncNodes() {
    for (final p in world.pieces) {
      final node = _pieceNodes[p.id];
      if (node == null) continue;
      node.position.setFrom(p.position);
      node.orientation = p.orientation;
      node.visible = !p.removed;

      if (p.isArmed) {
        // Telegraph: an armed core pulses hotter, brighter and faster the
        // closer it gets to going off, so the player can read the timing.
        final t = p.fuseProgress;
        final pulse = 0.5 + 0.5 * math.sin(time * (13.0 + t * 48.0));
        node.glowBoost = 0.30 + pulse * (0.45 + t * 1.3);
        node.tint = K.orange;
        node.tintAmount = 0.20 + pulse * 0.45 * (0.35 + t);
        node.scale = 1.0 + pulse * 0.05 * (0.4 + t);
        continue;
      }
      if (node.tint != null) {
        // Just went off -- drop straight back to the material's own look.
        node.tint = null;
        node.tintAmount = 0.0;
        node.glowBoost = 0.0;
        node.scale = 1.0;
      }

      // Jelly keeps a little post-cut wobble.
      final wobble = p.kind.profile.wobble;
      if (wobble > 0 && !p.settled) {
        node.scale = 1.0 + math.sin(time * 17.0 + p.id) * 0.035 * wobble;
      }
    }
    _nodes.removeWhere((n) => !n.visible && n != _bladeNode);

    // Warning rings are rebuilt each frame from the live fuse state.
    effects.armedCores.clear();
    for (final p in world.pieces) {
      if (p.removed || !p.isArmed) continue;
      effects.armedCores.add(
        ArmedCore(
          position: p.position.clone(),
          radius: p.kind.profile.blastRadius,
          progress: p.fuseProgress,
        ),
      );
    }

    final bn = _bladeNode;
    if (bn != null && _bladeActive) {
      final t = Curves3.easeOutCubic(_bladeT);
      bn.position
        ..setFrom(_bladeFrom)
        ..addScaled(_bladeTo - _bladeFrom, t);
      bn.orientation = _bladeRot;
      bn.visible = true;
    }
  }

  /// Full deterministic reset -- retry must return an identical starting state.
  Future<void> restart() async {
    cutsUsed = 0;
    time = 0;
    _rotation = 0;
    timeScale = 1.0;
    _slowMoRemaining = 0;
    _settleTimer = 0;
    _fallTimer = 0;
    _pendingChain.clear();
    _firedChain.clear();
    _resolvedFired = false;
    _bladeActive = false;
    _bladeNode = null;
    result = null;
    liveAccuracy = 0;
    swipeStart = null;
    swipeCurrent = null;
    phase = GamePhase.loading;
    notifyListeners();
    await load();
  }

  @override
  void dispose() {
    world.clear();
    effects.clear();
    super.dispose();
  }
}

/// Small easing helpers (kept local so the game layer stays widget-free).
class Curves3 {
  const Curves3._();

  static double easeOutCubic(double t) {
    final u = 1.0 - t.clamp(0.0, 1.0);
    return 1.0 - u * u * u;
  }

  static double easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final u = t.clamp(0.0, 1.0) - 1.0;
    return 1 + c3 * u * u * u + c1 * u * u;
  }

  static double easeInOut(double t) {
    final u = t.clamp(0.0, 1.0);
    return u < 0.5 ? 2 * u * u : 1 - math.pow(-2 * u + 2, 2) / 2;
  }
}
