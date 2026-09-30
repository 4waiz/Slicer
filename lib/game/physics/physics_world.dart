import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../materials/material_kind.dart';
import '../renderer/mesh.dart';

/// A rigid piece produced by a cut (or an intact pre-cut body).
///
/// The collider is the mesh's own welded vertex cloud, so it regenerates for
/// free every time a piece is sliced -- new cut-face corners included.
class RigidPiece {
  RigidPiece({
    required this.id,
    required this.mesh,
    required this.kind,
    required Vector3 position,
    Quaternion? orientation,
    Vector3? velocity,
    Vector3? angularVelocity,
  }) : position = position.clone(),
       orientation = orientation ?? Quaternion.identity(),
       velocity = velocity ?? Vector3.zero(),
       angularVelocity = angularVelocity ?? Vector3.zero() {
    _rebuildCollider();
  }

  final int id;

  /// Object-space geometry, centred on its own centroid.
  MeshData mesh;
  MaterialKind kind;

  Vector3 position;
  Quaternion orientation;
  Vector3 velocity;
  Vector3 angularVelocity;

  double mass = 1.0;
  double invMass = 1.0;
  double invInertia = 1.0;
  double radius = 0.5;

  bool asleep = false;
  bool removed = false;

  /// Set once the piece comes to rest -- the scorer waits for this.
  bool settled = false;

  /// Held in place by the level (the intact structure before the first cut).
  /// Frozen bodies are posed by the controller and skipped by the solver.
  bool frozen = false;

  /// A level prop -- machinery or a support held above the stage until a chain
  /// event releases it. The player's blade passes straight through these:
  /// slicing a support would bypass the chain reaction it exists to cause.
  bool isHeldProp = false;

  /// True if any part of this piece is explosive, however small.
  ///
  /// Deliberately not "the dominant material is explosive": a reactor core is
  /// a small bright sphere inside a large housing, and freeing it is supposed
  /// to arm it regardless of how much casing came away with it.
  bool containsCore = false;

  /// Zone this piece ended up in, resolved by the target system.
  String? landedZoneId;

  /// Which zone this piece is *supposed* to reach.
  String? requiredZoneId;

  /// Fraction of this piece that genuinely belongs to [requiredZoneId], by
  /// surface area, in 0..1.
  ///
  /// A clean cut yields 1.0. A cut that leaves a wedge of the neighbouring
  /// section attached yields less, and the remainder is scored as
  /// contamination -- this is what makes cutting *accurately* matter rather
  /// than just cutting somewhere.
  double purity = 1.0;

  /// Scored on the results screen; bonus pieces are worth extra.
  bool isBonus = false;

  /// Counts down once an explosive core has been freed by a cut. Zero means
  /// inert -- every other material never arms.
  double fuseRemaining = 0.0;
  double fuseTotal = 0.0;

  bool get isArmed => fuseRemaining > 0;

  /// 0 the instant it arms, 1 the instant it goes off. Drives the telegraph.
  double get fuseProgress =>
      fuseTotal <= 0 ? 0.0 : (1.0 - fuseRemaining / fuseTotal).clamp(0.0, 1.0);

  /// Blast this piece will deliver when its fuse runs out. Carried on the
  /// piece rather than read from [kind] at detonation time: a core is usually
  /// a small insert inside a large housing, so the piece's dominant material
  /// is the casing and would report no blast at all.
  double blastRadius = 0.0;
  double blastImpulse = 0.0;

  /// Starts the countdown. Called when a cut frees an explosive section.
  ///
  /// [radius] and [impulse] default to this piece's own material, and are
  /// passed explicitly when a small core is embedded in a larger housing --
  /// there the piece's dominant material is the casing, which carries no blast.
  void arm(double seconds, {double? radius, double? impulse}) {
    fuseRemaining = seconds;
    fuseTotal = seconds;
    final profile = kind.profile;
    blastRadius = radius ?? profile.blastRadius;
    blastImpulse = impulse ?? profile.blastImpulse;
  }

  double _restTimer = 0.0;
  late List<Vector3> _collider;
  final Vector3 _tmp = Vector3.zero();

  List<Vector3> get collider => _collider;

  void _rebuildCollider() {
    _collider = mesh.collisionPoints(weld: 0.09);
    radius = mesh.boundingRadius;
    final profile = kind.profile;
    mass = math.max(0.02, mesh.volume * profile.density);
    invMass = 1.0 / mass;
    // Solid-sphere inertia is a good enough stand-in for chunky low-poly
    // pieces and keeps the solver cheap and stable.
    final inertia = math.max(1e-4, 0.4 * mass * radius * radius);
    invInertia = 1.0 / inertia;
  }

  /// Replaces the geometry (after a re-slice) and refreshes mass properties.
  void setMesh(MeshData m) {
    mesh = m;
    _rebuildCollider();
  }

  /// Object -> world for a collider point, without allocating.
  Vector3 toWorld(Vector3 local, Vector3 out) {
    out.setFrom(local);
    orientation.rotate(out);
    out.add(position);
    return out;
  }

  /// Offset of a collider point from the centre of mass, in world space.
  Vector3 armOf(Vector3 local, Vector3 out) {
    out.setFrom(local);
    orientation.rotate(out);
    return out;
  }

  void wake() {
    asleep = false;
    settled = false;
    _restTimer = 0.0;
  }

  void applyImpulse(Vector3 impulse, Vector3 arm) {
    velocity.addScaled(impulse, invMass);
    _tmp
      ..setFrom(arm)
      ..crossInto(impulse, _tmp);
    angularVelocity.addScaled(_tmp, invInertia);
  }
}

/// An axis-aligned landing pad. Pieces resting on one count toward its zone.
class PadSurface {
  PadSurface({
    required this.id,
    required this.centre,
    required this.halfExtents,
    required this.top,
  });

  final String id;
  Vector3 centre;

  /// Half-size on X and Z.
  Vector3 halfExtents;

  /// World Y of the pad's upper surface.
  double top;

  bool containsXZ(double x, double z) =>
      (x - centre.x).abs() <= halfExtents.x &&
      (z - centre.z).abs() <= halfExtents.z;

  /// How centred a point is on the pad, 1 at the middle, 0 at the rim.
  double centeredness(double x, double z) {
    final u = ((x - centre.x).abs() / halfExtents.x).clamp(0.0, 1.0);
    final v = ((z - centre.z).abs() / halfExtents.z).clamp(0.0, 1.0);
    return 1.0 - math.max(u, v);
  }
}

/// A directional force applied over a box region (wind) or a pull toward a
/// point (magnet). Levels compose these to change how pieces fall.
class FieldZone {
  FieldZone({
    required this.kind,
    required this.centre,
    required this.halfExtents,
    required this.strength,
    this.direction,
    this.affects,
  });

  final FieldKind kind;
  final Vector3 centre;
  final Vector3 halfExtents;
  final double strength;
  final Vector3? direction;

  /// When set, only pieces of this material are affected (magnets vs metal).
  final MaterialKind? affects;

  bool contains(Vector3 p) =>
      (p.x - centre.x).abs() <= halfExtents.x &&
      (p.y - centre.y).abs() <= halfExtents.y &&
      (p.z - centre.z).abs() <= halfExtents.z;
}

enum FieldKind { wind, magnet }

/// An explosive core going off. Produced by the solver, drained by the
/// controller so it can play the flash, sparks, sound and haptic.
class Detonation {
  const Detonation({
    required this.position,
    required this.radius,
    required this.strength,
    required this.sourceId,
  });

  final Vector3 position;
  final double radius;
  final double strength;
  final int sourceId;
}

/// Fixed-step impulse solver.
///
/// Deterministic by construction: no wall-clock input, no randomness, and a
/// fixed substep. Feeding the same cut plane twice produces the same landing,
/// which is what makes retry and the seeded Daily Slice reproducible.
class PhysicsWorld {
  PhysicsWorld({
    Vector3? gravity,
    this.floorY = 0.0,
    this.killY = -14.0,
    this.substep = 1.0 / 120.0,
  }) : gravity = gravity ?? Vector3(0, -17.0, 0);

  Vector3 gravity;

  /// Stage floor. Pieces that miss every pad rest here.
  double floorY;

  /// Below this a piece is considered lost and is removed.
  double killY;

  final double substep;

  final List<RigidPiece> pieces = <RigidPiece>[];
  final List<PadSurface> pads = <PadSurface>[];
  final List<FieldZone> fields = <FieldZone>[];

  /// Detonations that fired this frame. The controller drains this.
  final List<Detonation> detonations = <Detonation>[];

  double _accumulator = 0.0;
  int _nextId = 1;

  int get nextId => _nextId++;

  /// An armed core counts as unsettled: the attempt is not over until it has
  /// gone off and whatever it shoved has come back to rest.
  bool get allSettled =>
      pieces.isEmpty ||
      pieces.every(
        (p) => (p.settled || p.removed || p.frozen) && p.fuseRemaining <= 0,
      );

  void clear() {
    pieces.clear();
    pads.clear();
    fields.clear();
    detonations.clear();
    _accumulator = 0.0;
    _nextId = 1;
  }

  void add(RigidPiece p) => pieces.add(p);

  /// Advances by [dt] in fixed substeps. Returns the number of substeps run.
  int advance(double dt) {
    // Clamp so a stalled frame can't spiral into a hundred catch-up steps.
    _accumulator += dt.clamp(0.0, 0.1);
    var steps = 0;
    while (_accumulator >= substep && steps < 12) {
      _step(substep);
      _accumulator -= substep;
      steps++;
    }
    return steps;
  }

  final Vector3 _v = Vector3.zero();
  final Vector3 _arm = Vector3.zero();
  final Vector3 _rel = Vector3.zero();
  final Vector3 _imp = Vector3.zero();
  final Vector3 _cross = Vector3.zero();
  final Vector3 _world = Vector3.zero();
  final Vector3 _yAxis = Vector3(0, 1, 0);
  final Vector3 _dv = Vector3.zero();
  final Vector3 _dw = Vector3.zero();
  final List<Vector3> _contacts = <Vector3>[];

  void _step(double dt) {
    _tickFuses(dt);

    for (final p in pieces) {
      if (p.removed || p.asleep || p.frozen) continue;
      final profile = p.kind.profile;

      p.velocity.addScaled(gravity, dt);
      _applyFields(p, dt);

      final ld = math.max(0.0, 1.0 - profile.linearDamping * dt * 60.0 * 0.016);
      final ad = math.max(
        0.0,
        1.0 - profile.angularDamping * dt * 60.0 * 0.016,
      );
      p.velocity.scale(ld);
      p.angularVelocity.scale(ad);

      p.position.addScaled(p.velocity, dt);
      _integrateOrientation(p, dt);

      if (p.position.y < killY) {
        p.removed = true;
        p.settled = true;
        continue;
      }

      _resolveSupport(p, dt);
      _sleepCheck(p, dt);
    }

    _resolvePieceCollisions();
  }

  /// Runs down every armed core and fires the ones that reach zero.
  void _tickFuses(double dt) {
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      if (p.removed || p.fuseRemaining <= 0) continue;
      p.fuseRemaining -= dt;
      if (p.fuseRemaining <= 0) {
        p.fuseRemaining = 0.0;
        _detonate(p);
      }
    }
  }

  /// Shoves everything inside the blast radius away from the core.
  ///
  /// The impulse is applied through inverse mass, so a dense metal slab barely
  /// budges while a light jelly wedge is thrown clear -- the shove is a
  /// gameplay tool for repositioning pieces, not an instant kill.
  void _detonate(RigidPiece source) {
    final radius = source.blastRadius;
    final strength = source.blastImpulse;
    if (radius <= 0 || strength <= 0) return;

    detonations.add(
      Detonation(
        position: source.position.clone(),
        radius: radius,
        strength: strength,
        sourceId: source.id,
      ),
    );

    for (final other in pieces) {
      if (other.removed || other.frozen) continue;

      if (other.id == source.id) {
        // The core pops straight up rather than shoving itself sideways.
        other.velocity.y += strength * other.invMass * 0.30;
        other.wake();
        continue;
      }

      _v
        ..setFrom(other.position)
        ..sub(source.position);
      final dist = _v.length;
      if (dist > radius) continue;

      // Quadratic falloff: firm at the core, gentle at the rim.
      final falloff = 1.0 - dist / radius;
      final j = strength * falloff * falloff;

      if (dist < 1e-4) {
        _v.setValues(0, 1, 0);
      } else {
        _v.scale(1.0 / dist);
        // Bias upward so the shove reads as a pop, not a shunt along the floor.
        _v.y += 0.55;
        _v.normalize();
      }

      other.velocity.addScaled(_v, j * other.invMass);
      // A little tumble, scaled down hard -- invInertia is large for small
      // pieces and an unscaled kick would send them spinning wildly.
      other.angularVelocity.x += _v.z * j * other.invInertia * 0.04;
      other.angularVelocity.z += -_v.x * j * other.invInertia * 0.04;
      other.wake();
    }
  }

  void _applyFields(RigidPiece p, double dt) {
    for (final f in fields) {
      if (f.affects != null && f.affects != p.kind) continue;
      if (!f.contains(p.position)) continue;
      switch (f.kind) {
        case FieldKind.wind:
          final d = f.direction ?? Vector3(1, 0, 0);
          p.velocity.addScaled(d, f.strength * dt);
        case FieldKind.magnet:
          _v
            ..setFrom(f.centre)
            ..sub(p.position);
          final dist = _v.length;
          if (dist > 1e-3) {
            _v.scale(1.0 / dist);
            // Falls off with distance so magnets feel like a pull, not a snap.
            p.velocity.addScaled(
              _v,
              f.strength * dt / math.max(1.0, dist * 0.5),
            );
          }
      }
    }
  }

  void _integrateOrientation(RigidPiece p, double dt) {
    final w = p.angularVelocity;
    if (w.length2 < 1e-12) return;
    final q = p.orientation;
    final dq = Quaternion(w.x, w.y, w.z, 0.0)..scale(0.5 * dt);
    final nq = Quaternion(
      q.x + (dq.w * q.x + dq.x * q.w + dq.y * q.z - dq.z * q.y),
      q.y + (dq.w * q.y - dq.x * q.z + dq.y * q.w + dq.z * q.x),
      q.z + (dq.w * q.z + dq.x * q.y - dq.y * q.x + dq.z * q.w),
      q.w + (dq.w * q.w - dq.x * q.x - dq.y * q.y - dq.z * q.z),
    )..normalize();
    p.orientation = nq;
  }

  /// Collides a piece's vertex cloud against whichever surface is under each
  /// point -- a pad top if it is over one, otherwise the stage floor.
  ///
  /// Contacts are gathered first and the impulse is then shared between them.
  /// Applying a full impulse per corner instead makes a flat landing kick off
  /// with several times the correct force, which shows up as pieces that
  /// buzz forever and drift sideways for no reason.
  void _resolveSupport(RigidPiece p, double dt) {
    final profile = p.kind.profile;
    _contacts.clear();
    var maxPenetration = 0.0;

    for (final local in p.collider) {
      p.toWorld(local, _world);
      var surfaceY = floorY;
      for (final pad in pads) {
        if (pad.containsXZ(_world.x, _world.z) && pad.top > surfaceY) {
          surfaceY = pad.top;
        }
      }
      final penetration = surfaceY - _world.y;
      if (penetration <= 0) continue;
      _contacts.add(local);
      if (penetration > maxPenetration) maxPenetration = penetration;
    }

    if (_contacts.isEmpty) return;
    final share = 1.0 / _contacts.length;

    // Impulse each contact must supply just to hold the piece against gravity
    // this substep. Without it a resting piece has vn ~= 0, so the normal
    // impulse -- and therefore the Coulomb friction bound derived from it --
    // collapses to zero and the piece slides across the stage forever.
    final supportImpulse = p.mass * gravity.length * dt * share;

    // Jacobi accumulation: every contact is evaluated against the *same*
    // starting velocity and the deltas are applied together. Solving them
    // one-at-a-time (Gauss-Seidel) lets each corner see a velocity the
    // previous one already changed, so the four corners of a flat landing
    // stop cancelling and inject phantom spin and sideways drift.
    for (var iter = 0; iter < 2; iter++) {
      _dv.setZero();
      _dw.setZero();
      var touching = false;

      for (final local in _contacts) {
        p.armOf(local, _arm);
        // v_point = v + omega x r
        p.angularVelocity.crossInto(_arm, _cross);
        _rel
          ..setFrom(p.velocity)
          ..add(_cross);

        final vn = _rel.y; // contact normal is +Y
        touching = true;

        _arm.crossInto(_yAxis, _cross);
        final denom = p.invMass + p.invInertia * _cross.length2;
        if (denom < 1e-9) continue;

        // Restitution is suppressed for slow contacts, otherwise a resting
        // piece keeps trading tiny bounces with the pad and never sleeps.
        var j = 0.0;
        if (vn < 0) {
          final e = vn < -1.2 ? profile.restitution : 0.0;
          j = -(1.0 + e) * vn / denom * share;

          _dv.y += j * p.invMass;
          // arm x (0, j, 0)
          _dw.x += (-_arm.z * j) * p.invInertia;
          _dw.z += (_arm.x * j) * p.invInertia;
        }

        // Coulomb friction along the tangent, bounded by the total normal
        // load: the impulse that stopped the approach plus the piece's weight.
        _rel.y = 0;
        final tLen = _rel.length;
        if (tLen > 1e-5) {
          _rel.scale(1.0 / tLen);
          _arm.crossInto(_rel, _cross);
          final denomT = p.invMass + p.invInertia * _cross.length2;
          if (denomT > 1e-9) {
            var jt = -tLen / denomT * share;
            final maxT = profile.friction * (j.abs() + supportImpulse);
            jt = jt.clamp(-maxT, maxT);
            _imp
              ..setFrom(_rel)
              ..scale(jt);
            _dv.addScaled(_imp, p.invMass);
            _arm.crossInto(_imp, _cross);
            _dw.addScaled(_cross, p.invInertia);
          }
        }
      }

      if (!touching) break;
      p.velocity.add(_dv);
      p.angularVelocity.add(_dw);
    }

    // Friction acting at the contact points produces a real tipping torque,
    // which in a Jacobi solver leaves a piece teetering indefinitely. Bleeding
    // it off while in contact is what lets pieces settle crisply.
    final damp = math.max(0.0, 1.0 - 3.0 * dt * 60.0 * 0.05);
    p.angularVelocity.scale(damp);
    if (p.velocity.length2 < 0.5) {
      p.velocity.x *= damp;
      p.velocity.z *= damp;
    }

    // One positional correction per step, with slop, keeps stacks calm.
    const slop = 0.002;
    p.position.y += math.max(0.0, maxPenetration - slop) * 0.6;
  }

  void _sleepCheck(RigidPiece p, double dt) {
    const vEps = 0.22;
    const wEps = 1.0;
    if (p.velocity.length2 < vEps * vEps &&
        p.angularVelocity.length2 < wEps * wEps) {
      p._restTimer += dt;
      if (p._restTimer > 0.32) {
        p.asleep = true;
        p.settled = true;
        p.velocity.setZero();
        p.angularVelocity.setZero();
      }
    } else {
      p._restTimer = 0.0;
    }
  }

  /// Bounding-sphere separation between pieces. Enough to stop stacks from
  /// interpenetrating without paying for full convex collision.
  void _resolvePieceCollisions() {
    for (var i = 0; i < pieces.length; i++) {
      final a = pieces[i];
      if (a.removed || a.frozen) continue;
      for (var j = i + 1; j < pieces.length; j++) {
        final b = pieces[j];
        if (b.removed || b.frozen) continue;
        if (a.asleep && b.asleep) continue;

        _v
          ..setFrom(b.position)
          ..sub(a.position);
        final minDist = (a.radius + b.radius) * 0.78;
        final d2 = _v.length2;
        if (d2 >= minDist * minDist || d2 < 1e-9) continue;

        final dist = math.sqrt(d2);
        _v.scale(1.0 / dist);
        final penetration = minDist - dist;

        final totalInv = a.invMass + b.invMass;
        if (totalInv < 1e-9) continue;
        a.position.addScaled(_v, -penetration * (a.invMass / totalInv) * 0.5);
        b.position.addScaled(_v, penetration * (b.invMass / totalInv) * 0.5);

        _rel
          ..setFrom(b.velocity)
          ..sub(a.velocity);
        final vn = _rel.dot(_v);
        if (vn >= 0) continue;
        final e = math.min(
          a.kind.profile.restitution,
          b.kind.profile.restitution,
        );
        final impulse = -(1.0 + e) * vn / totalInv;
        _imp
          ..setFrom(_v)
          ..scale(impulse);
        a.velocity.addScaled(_imp, -a.invMass);
        b.velocity.addScaled(_imp, b.invMass);
        a.wake();
        b.wake();
      }
    }
  }

  /// Which pad a piece is resting on, if any.
  PadSurface? padUnder(RigidPiece p) {
    PadSurface? best;
    var bestTop = double.negativeInfinity;
    for (final pad in pads) {
      if (!pad.containsXZ(p.position.x, p.position.z)) continue;
      if (pad.top > bestTop) {
        bestTop = pad.top;
        best = pad;
      }
    }
    return best;
  }
}
