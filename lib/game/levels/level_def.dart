import 'package:vector_math/vector_math_64.dart';

import '../materials/material_kind.dart';

/// Where a target pad sits and how (or whether) it moves.
class ZoneDef {
  const ZoneDef({
    required this.id,
    required this.colorKey,
    required this.shape,
    required this.x,
    this.z = 0.0,
    this.width = 1.9,
    this.depth = 1.9,
    this.top = 0.30,
    this.motion = ZoneMotion.still,
    this.motionRange = 0.0,
    this.motionSpeed = 0.6,
    this.isBonus = false,
  });

  final String id;

  /// One of cyan / green / orange / purple.
  final String colorKey;

  /// Geometric identity: diamond / square / circle / triangle. Zones are never
  /// distinguished by colour alone.
  final String shape;

  final double x;
  final double z;
  final double width;
  final double depth;
  final double top;

  final ZoneMotion motion;
  final double motionRange;
  final double motionSpeed;

  /// Bonus pads award extra score but are not required to pass.
  final bool isBonus;

  Vector3 centreAt(double t) {
    switch (motion) {
      case ZoneMotion.still:
        return Vector3(x, 0, z);
      case ZoneMotion.slideX:
        return Vector3(x + _wave(t) * motionRange, 0, z);
      case ZoneMotion.slideZ:
        return Vector3(x, 0, z + _wave(t) * motionRange);
    }
  }

  double _wave(double t) {
    // Triangle wave -- linear travel reads more predictably than a sine when
    // the player is timing a swipe against it.
    final phase = (t * motionSpeed) % 2.0;
    return phase < 1.0 ? phase * 2.0 - 1.0 : 3.0 - phase * 2.0;
  }
}

enum ZoneMotion { still, slideX, slideZ }

/// Maps a Blender material name onto gameplay meaning.
class MaterialRule {
  const MaterialRule({
    required this.materialName,
    required this.kind,
    this.zoneId,
    this.isBonus = false,
    this.isCore = false,
  });

  /// Material name as exported by Blender, e.g. `M_yellow`.
  final String materialName;
  final MaterialKind kind;

  /// The pad this section must reach. Null means "no requirement" (filler).
  final String? zoneId;

  final bool isBonus;

  /// Protected core: must be exposed, and must not land in the wrong zone.
  final bool isCore;
}

class FieldDef {
  const FieldDef({
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    this.width = 8.0,
    this.height = 8.0,
    this.depth = 8.0,
    this.strength = 6.0,
    this.dirX = 1.0,
    this.dirY = 0.0,
    this.dirZ = 0.0,
    this.affects,
  });

  final String kind; // 'wind' | 'magnet'
  final double x, y, z;
  final double width, height, depth;
  final double strength;
  final double dirX, dirY, dirZ;
  final MaterialKind? affects;
}

/// An extra body placed in the scene alongside the main structure.
///
/// A [frozen] prop hangs in place until a chain event releases it -- that is
/// what makes "one cut collapses a support" a real physical consequence rather
/// than an animation.
class PropDef {
  const PropDef({
    required this.model,
    required this.x,
    required this.y,
    this.z = 0.0,
    this.scale = 1.0,
    this.kind = MaterialKind.metal,
    this.zoneId,
    this.frozen = true,
    this.spin = 0.0,
  });

  final String model;
  final double x, y, z;
  final double scale;
  final MaterialKind kind;

  /// Pad this prop is expected to reach once it is released. Null means it is
  /// scenery and is not scored.
  final String? zoneId;

  /// Held in place until a chain event releases it.
  final bool frozen;

  /// Radians per second about Y while held.
  final double spin;
}

/// What starts a chain event.
enum ChainTrigger {
  /// The player's first cut of the attempt.
  onFirstCut,

  /// Every cut.
  onAnyCut,

  /// An explosive core going off.
  onDetonation,
}

/// What the chain event does.
enum ChainAction {
  /// Release every held prop so it falls.
  collapseSupports,

  /// Drop a fresh structure into the scene.
  dropStructure,

  /// Spin everything currently loose -- a machine kicking over.
  spinMachine,

  /// Split the largest remaining piece along a fixed plane.
  autoSplit,
}

/// A consequence scheduled by a cut: one action, after a delay.
class ChainEvent {
  const ChainEvent({
    required this.trigger,
    required this.action,
    this.delay = 0.7,
    this.model,
    this.modelScale = 1.0,
    this.x = 0.0,
    this.y = 6.5,
    this.z = 0.0,
    this.kind = MaterialKind.plasticToy,
    this.zoneId,
    this.strength = 3.0,
    this.planeNormalX = 1.0,
    this.planeNormalY = 0.0,
    this.planeNormalZ = 0.0,
  });

  final ChainTrigger trigger;
  final ChainAction action;

  /// Seconds after the trigger before it fires. Gives the player time to read
  /// the first cut landing before the consequence arrives.
  final double delay;

  /// [ChainAction.dropStructure] only.
  final String? model;
  final double modelScale;
  final double x, y, z;
  final MaterialKind kind;
  final String? zoneId;

  /// Impulse or spin magnitude, depending on the action.
  final double strength;

  /// [ChainAction.autoSplit] only: the plane to cut along, in world space.
  final double planeNormalX, planeNormalY, planeNormalZ;
}

/// Bonus objective evaluated on top of the pass condition.
enum BonusGoal {
  none,

  /// Land every required section in its pad.
  allZonesPerfect,

  /// Finish using fewer cuts than allowed.
  underCutBudget,

  /// Land the bonus-marked section.
  collectBonus,

  /// Keep total wasted mass below the threshold.
  minimalWaste,
}

/// A complete, data-driven level definition.
class LevelDef {
  const LevelDef({
    required this.id,
    required this.world,
    required this.name,
    required this.model,
    required this.zones,
    required this.materials,
    this.modelScale = 1.0,
    this.spawnY = 5.0,
    this.spawnX = 0.0,
    this.rotationSpeed = 0.45,
    this.rotationAxisX = 0.0,
    this.rotationAxisY = 1.0,
    this.rotationAxisZ = 0.0,
    this.allowedCuts = 1,
    this.minSuccess = 0.60,
    this.twoStar = 0.80,
    this.threeStar = 0.96,
    this.bonus = BonusGoal.none,
    this.bonusThreshold = 0.15,
    this.gravity = -15.0,
    this.fields = const [],
    this.enforcePurity = false,
    this.props = const [],
    this.chain = const [],
    this.observeSeconds = 1.0,
    this.hint,
    this.defaultKind = MaterialKind.crystal,
  });

  final int id;
  final int world;
  final String name;

  /// GLB filename under `assets/models/`.
  final String model;
  final double modelScale;

  final double spawnY;
  final double spawnX;

  final double rotationSpeed;
  final double rotationAxisX, rotationAxisY, rotationAxisZ;

  final int allowedCuts;

  final List<ZoneDef> zones;
  final List<MaterialRule> materials;

  /// Fraction of required mass that must land correctly to pass.
  final double minSuccess;
  final double twoStar;
  final double threeStar;

  final BonusGoal bonus;
  final double bonusThreshold;

  final double gravity;
  final List<FieldDef> fields;

  /// Whether a piece is scored on how cleanly it was separated.
  ///
  /// Only meaningful when the structure's sections are actually separable by
  /// a plane -- side by side, or stacked. Concentric structures (orbs,
  /// planets, the reactor) cannot be split into pure pieces by *any* cut, so
  /// scoring them on purity would make them unwinnable. Those levels are
  /// about revealing the core, not sorting the shells.
  final bool enforcePurity;

  /// Extra bodies in the scene: supports, second structures, machinery.
  final List<PropDef> props;

  /// Consequences a cut sets off.
  final List<ChainEvent> chain;

  /// Every model this level needs loaded before it can start.
  Set<String> get requiredModels => {
    model,
    for (final p in props) p.model,
    for (final c in chain)
      if (c.model != null) c.model!,
  };

  final double observeSeconds;
  final String? hint;

  /// Used for any material the rules do not mention.
  final MaterialKind defaultKind;

  Vector3 get rotationAxis =>
      Vector3(rotationAxisX, rotationAxisY, rotationAxisZ).normalized();

  MaterialRule? ruleFor(String materialName) {
    // Cut faces inherit the rules of the surface they came from.
    final base = materialName.endsWith('#cut')
        ? materialName.substring(0, materialName.length - 4)
        : materialName;
    for (final r in materials) {
      if (r.materialName == base) return r;
    }
    return null;
  }

  MaterialKind kindFor(String materialName) =>
      ruleFor(materialName)?.kind ?? defaultKind;

  ZoneDef? zoneById(String? id) {
    if (id == null) return null;
    for (final z in zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// Zones a piece can actually be required to reach.
  Iterable<ZoneDef> get requiredZones => zones.where((z) => !z.isBonus);

  String get worldName => worldNameFor(world);

  static String worldNameFor(int world) => switch (world) {
    1 => 'CRYSTAL WORKSHOP',
    2 => 'JELLY LABORATORY',
    3 => 'FRUIT FOUNDRY',
    4 => 'TOY CITY',
    5 => 'MECHANICAL CORE',
    6 => 'KANBAN COMPLEX',
    _ => 'UNKNOWN',
  };
}
