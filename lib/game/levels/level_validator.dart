import '../renderer/mesh.dart';
import 'level_def.dart';

class ValidationIssue {
  const ValidationIssue(this.levelId, this.code, this.message);

  final int levelId;
  final String code;
  final String message;

  @override
  String toString() => 'L$levelId [$code] $message';
}

/// Static checks over level data, run as a test over the whole campaign so a
/// broken level can never ship.
///
/// [meshFor] supplies the parsed model when available; without it the
/// asset-dependent checks are skipped rather than reported as failures.
class LevelValidator {
  const LevelValidator({this.meshFor, this.knownModels});

  final MeshData? Function(String model)? meshFor;
  final Set<String>? knownModels;

  List<ValidationIssue> validate(LevelDef l) {
    final issues = <ValidationIssue>[];
    void bad(String code, String msg) =>
        issues.add(ValidationIssue(l.id, code, msg));

    // -- assets ------------------------------------------------------------
    if (l.model.isEmpty || !l.model.endsWith('.glb')) {
      bad('asset', 'model "${l.model}" is not a .glb');
    }
    if (knownModels != null && !knownModels!.contains(l.model)) {
      bad('asset', 'model "${l.model}" is not in assets/models');
    }

    // -- zones -------------------------------------------------------------
    if (l.zones.length < 2) {
      bad('zones', 'needs at least two target zones, has ${l.zones.length}');
    }
    final ids = <String>{};
    for (final z in l.zones) {
      if (!ids.add(z.id)) bad('zones', 'duplicate zone id "${z.id}"');
      if (z.width <= 0 || z.depth <= 0) {
        bad('zones', 'zone "${z.id}" has non-positive size');
      }
      if (z.top <= 0) {
        bad('zones', 'zone "${z.id}" top must be above the floor');
      }
      if (!const {
        'diamond',
        'square',
        'circle',
        'triangle',
      }.contains(z.shape)) {
        bad('zones', 'zone "${z.id}" has unknown shape "${z.shape}"');
      }
      if (!const {'cyan', 'green', 'orange', 'purple'}.contains(z.colorKey)) {
        bad('zones', 'zone "${z.id}" has unknown colour "${z.colorKey}"');
      }
      if (z.motion != ZoneMotion.still && z.motionRange <= 0) {
        bad('zones', 'moving zone "${z.id}" has zero range');
      }
    }

    // Zones must not overlap at any point in their travel, or a piece could
    // satisfy two pads at once. Travel only widens the axis it moves along.
    double xExtent(ZoneDef z) =>
        z.width * 0.5 + (z.motion == ZoneMotion.slideX ? z.motionRange : 0.0);
    double zExtent(ZoneDef z) =>
        z.depth * 0.5 + (z.motion == ZoneMotion.slideZ ? z.motionRange : 0.0);

    for (var i = 0; i < l.zones.length; i++) {
      for (var j = i + 1; j < l.zones.length; j++) {
        final a = l.zones[i], b = l.zones[j];
        if ((a.x - b.x).abs() < xExtent(a) + xExtent(b) &&
            (a.z - b.z).abs() < zExtent(a) + zExtent(b)) {
          bad('zones', 'zones "${a.id}" and "${b.id}" overlap');
        }
      }
    }

    // Every zone must also be visually distinct by shape, not colour alone.
    final shapes = l.zones.map((z) => z.shape).toSet();
    if (shapes.length != l.zones.length) {
      bad('zones', 'zones must each use a unique shape glyph');
    }

    // -- material rules ----------------------------------------------------
    if (l.materials.isEmpty) {
      bad('materials', 'no material rules defined');
    }
    final ruleNames = <String>{};
    for (final r in l.materials) {
      if (!ruleNames.add(r.materialName)) {
        bad('materials', 'duplicate rule for "${r.materialName}"');
      }
      if (r.zoneId != null && l.zoneById(r.zoneId) == null) {
        bad(
          'materials',
          'rule "${r.materialName}" targets unknown zone "${r.zoneId}"',
        );
      }
    }

    // Every non-bonus zone must be reachable by at least one material,
    // otherwise it can never be filled and the level is unwinnable.
    for (final z in l.zones) {
      if (z.isBonus) continue;
      final reachable = l.materials.any((r) => r.zoneId == z.id);
      if (!reachable) {
        bad('impossible', 'zone "${z.id}" has no material assigned to it');
      }
    }

    // -- thresholds --------------------------------------------------------
    if (l.minSuccess <= 0 || l.minSuccess > 1) {
      bad('threshold', 'minSuccess ${l.minSuccess} out of range');
    }
    if (!(l.minSuccess <= l.twoStar && l.twoStar <= l.threeStar)) {
      bad(
        'threshold',
        'star thresholds must ascend: ${l.minSuccess}/${l.twoStar}/${l.threeStar}',
      );
    }
    if (l.threeStar > 1.0) bad('threshold', 'threeStar above 100%');

    // -- cuts --------------------------------------------------------------
    if (l.allowedCuts < 1 || l.allowedCuts > 4) {
      bad('cuts', 'allowedCuts ${l.allowedCuts} outside 1..4');
    }
    // N cuts can produce at most N+1 pieces from one body, so a level cannot
    // demand more distinct destinations than the cut budget can create.
    final requiredZones = l.materials
        .map((r) => r.zoneId)
        .whereType<String>()
        .toSet();
    if (requiredZones.length > l.allowedCuts + 1) {
      bad(
        'impossible',
        '${requiredZones.length} required zones needs at least '
            '${requiredZones.length - 1} cuts, only ${l.allowedCuts} allowed',
      );
    }

    // -- bonus -------------------------------------------------------------
    if (l.bonus == BonusGoal.collectBonus &&
        !l.materials.any((r) => r.isBonus)) {
      bad('bonus', 'collectBonus goal with no bonus material');
    }
    if (l.bonus == BonusGoal.underCutBudget && l.allowedCuts < 2) {
      bad('bonus', 'underCutBudget is unreachable with only one cut');
    }
    if (l.bonus == BonusGoal.minimalWaste &&
        (l.bonusThreshold <= 0 || l.bonusThreshold >= 1)) {
      bad('bonus', 'minimalWaste threshold ${l.bonusThreshold} out of range');
    }

    // -- placement ---------------------------------------------------------
    if (l.spawnY < 2.0) {
      bad('placement', 'spawnY ${l.spawnY} too low for pieces to fall');
    }
    if (l.gravity >= 0) bad('placement', 'gravity must be negative');
    if (l.rotationSpeed < 0) bad('placement', 'negative rotation speed');
    if (l.rotationAxis.length2 < 0.5) {
      bad('placement', 'rotation axis is degenerate');
    }

    // -- fields ------------------------------------------------------------
    for (final f in l.fields) {
      if (f.kind != 'wind' && f.kind != 'magnet') {
        bad('field', 'unknown field kind "${f.kind}"');
      }
      if (f.strength <= 0) bad('field', '${f.kind} field has no strength');
      if (f.kind == 'wind' && f.dirX == 0 && f.dirY == 0 && f.dirZ == 0) {
        bad('field', 'wind field has no direction');
      }
    }

    // -- props --------------------------------------------------------------
    for (final prop in l.props) {
      if (knownModels != null && !knownModels!.contains(prop.model)) {
        bad('prop', 'prop model "${prop.model}" is not in assets/models');
      }
      if (prop.scale <= 0) bad('prop', 'prop "${prop.model}" has zero scale');
      if (prop.y < 1.0) {
        bad('prop', 'prop "${prop.model}" starts below the stage');
      }
      if (prop.zoneId != null && l.zoneById(prop.zoneId) == null) {
        bad(
          'prop',
          'prop "${prop.model}" targets unknown zone "${prop.zoneId}"',
        );
      }
      if (prop.spin != 0 && !prop.frozen) {
        bad('prop', 'only held props can spin in place');
      }
    }

    // -- chain events -------------------------------------------------------
    var releasesProps = false;
    for (final c in l.chain) {
      if (c.delay < 0) bad('chain', 'negative chain delay');
      if (c.delay > 4.0) {
        bad('chain', 'chain delay ${c.delay}s outlives the attempt');
      }
      switch (c.action) {
        case ChainAction.dropStructure:
          final model = c.model;
          if (model == null) {
            bad('chain', 'dropStructure with no model');
          } else if (knownModels != null && !knownModels!.contains(model)) {
            bad('chain', 'chain model "$model" is not in assets/models');
          }
          if (c.y < 2.0) {
            bad('chain', 'dropped structure starts too low to fall');
          }
          if (c.zoneId != null && l.zoneById(c.zoneId) == null) {
            bad('chain', 'chain targets unknown zone "${c.zoneId}"');
          }
        case ChainAction.autoSplit:
          final n =
              c.planeNormalX.abs() +
              c.planeNormalY.abs() +
              c.planeNormalZ.abs();
          if (n < 1e-6) bad('chain', 'autoSplit has a degenerate plane');
        case ChainAction.spinMachine:
          if (c.strength <= 0) bad('chain', 'spinMachine with no strength');
        case ChainAction.collapseSupports:
          releasesProps = true;
      }
      // A detonation trigger needs something that can actually detonate.
      if (c.trigger == ChainTrigger.onDetonation &&
          !l.materials.any((m) => m.kind.profile.isExplosive)) {
        bad('chain', 'onDetonation trigger with no explosive material');
      }
    }
    if (releasesProps && !l.props.any((p) => p.frozen)) {
      bad('chain', 'collapseSupports with no held props to release');
    }
    if (l.props.any((p) => p.frozen) &&
        !l.chain.any((c) => c.action == ChainAction.collapseSupports)) {
      bad('prop', 'held props with nothing to ever release them');
    }

    // -- asset-dependent checks -------------------------------------------
    final mesh = meshFor?.call(l.model);
    if (mesh != null) {
      final present = mesh.materials.map((m) => m.name).toSet();
      for (final r in l.materials) {
        if (!present.contains(r.materialName)) {
          bad(
            'materials',
            'rule "${r.materialName}" is not a material of ${l.model} '
                '(has: ${present.join(", ")})',
          );
        }
      }
      // Every non-bonus zone needs a material that the model actually has.
      for (final z in l.zones) {
        if (z.isBonus) continue;
        final ok = l.materials.any(
          (r) => r.zoneId == z.id && present.contains(r.materialName),
        );
        if (!ok) {
          bad(
            'impossible',
            'zone "${z.id}" cannot be filled: no material of ${l.model} maps to it',
          );
        }
      }
      if (mesh.triCount > 20000) {
        bad('budget', '${l.model} exceeds the 20k triangle budget');
      }
      if (mesh.volume <= 0) bad('asset', '${l.model} has no enclosed volume');
    }

    return issues;
  }

  List<ValidationIssue> validateAll(List<LevelDef> levels) {
    final issues = <ValidationIssue>[];
    final seen = <int>{};
    for (final l in levels) {
      if (!seen.add(l.id)) {
        issues.add(ValidationIssue(l.id, 'id', 'duplicate level id'));
      }
      issues.addAll(validate(l));
    }
    return issues;
  }
}
