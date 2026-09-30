import 'dart:math' as math;

import '../levels/level_def.dart';
import '../physics/physics_world.dart';

/// Per-pad fill state, surfaced live in the HUD.
class ZoneResult {
  ZoneResult(this.zoneId);

  final String zoneId;

  /// Mass of correctly matched pieces resting on this pad.
  double correctMass = 0;

  /// Mass of pieces that do not belong here.
  double wrongMass = 0;

  /// Total mass the level expects this pad to receive.
  double requiredMass = 0;

  int correctPieces = 0;
  int wrongPieces = 0;

  double get fill =>
      requiredMass <= 0 ? 0.0 : (correctMass / requiredMass).clamp(0.0, 1.0);

  bool get isPerfect => fill >= 0.995 && !isContaminated;

  /// True if anything landed here that does not belong -- either a whole wrong
  /// piece, or enough impure material carried in by a sloppy cut to matter.
  bool get isContaminated =>
      wrongPieces > 0 || wrongMass > math.max(1e-6, requiredMass * 0.02);
}

/// The outcome of a completed attempt.
class LevelResult {
  const LevelResult({
    required this.accuracy,
    required this.stars,
    required this.passed,
    required this.perfect,
    required this.zones,
    required this.cutsUsed,
    required this.wastedMass,
    required this.bonusAchieved,
    required this.coins,
    required this.correctMass,
    required this.totalRequiredMass,
  });

  /// 0..1 -- the headline percentage.
  final double accuracy;
  final int stars;
  final bool passed;

  /// Every required pad perfectly filled with nothing contaminating it.
  final bool perfect;

  final List<ZoneResult> zones;
  final int cutsUsed;

  /// Required mass that never reached its pad.
  final double wastedMass;
  final bool bonusAchieved;
  final int coins;

  final double correctMass;
  final double totalRequiredMass;

  int get percent => (accuracy * 100).round();
}

/// Turns settled physics pieces into zone fills, accuracy and stars.
class Scorer {
  const Scorer(this.level);

  final LevelDef level;

  /// Evaluates the current world state. Safe to call every frame for live HUD
  /// feedback as well as once at the end.
  LevelResult evaluate(
    PhysicsWorld world,
    List<RigidPiece> pieces, {
    required int cutsUsed,
  }) {
    final zones = <String, ZoneResult>{
      for (final z in level.zones) z.id: ZoneResult(z.id),
    };

    var totalRequired = 0.0;
    var correct = 0.0;
    var wasted = 0.0;
    var bonusLanded = false;

    for (final p in pieces) {
      final required = p.requiredZoneId;
      final mass = p.mass;

      if (required != null) {
        totalRequired += mass;
        zones[required]?.requiredMass += mass;
      }

      // A removed piece fell off the stage -- it landed nowhere.
      final landed = p.removed ? null : world.padUnder(p);
      p.landedZoneId = landed?.id;

      if (landed == null) {
        if (required != null) wasted += mass;
        continue;
      }

      final zr = zones[landed.id];
      if (zr == null) continue;

      if (required != null && landed.id == required) {
        // Only the part of the piece that genuinely belongs here counts. The
        // rest is material the cut failed to separate, delivered into a pad it
        // does not belong in -- so it is scored as contamination.
        final pure = level.enforcePurity ? p.purity.clamp(0.0, 1.0) : 1.0;
        final good = mass * pure;
        final bad = mass - good;
        zr.correctMass += good;
        zr.correctPieces++;
        correct += good;
        if (bad > 1e-9) {
          zr.wrongMass += bad;
          wasted += bad;
        }
        if (p.isBonus) bonusLanded = true;
      } else if (p.isBonus && level.zoneById(landed.id)?.isBonus == true) {
        // Bonus piece in the bonus pad.
        zr.correctMass += mass;
        zr.correctPieces++;
        bonusLanded = true;
      } else {
        zr.wrongMass += mass;
        zr.wrongPieces++;
        if (required != null) wasted += mass;
      }
    }

    // Contaminating a pad costs accuracy -- landing everything everywhere is
    // not a winning strategy.
    var contaminationPenalty = 0.0;
    for (final zr in zones.values) {
      if (zr.wrongMass > 0) {
        contaminationPenalty += zr.wrongMass * 0.5;
      }
    }

    final denom = totalRequired <= 1e-9 ? 1.0 : totalRequired;
    var accuracy = (correct - contaminationPenalty) / denom;
    accuracy = accuracy.clamp(0.0, 1.0);

    final zoneList = level.zones
        .map((z) => zones[z.id]!)
        .toList(growable: false);

    final requiredZonesPerfect = zoneList
        .where((z) => level.zoneById(z.zoneId)?.isBonus == false)
        .every((z) => z.isPerfect);

    final bonusAchieved = switch (level.bonus) {
      BonusGoal.none => false,
      BonusGoal.allZonesPerfect => requiredZonesPerfect,
      BonusGoal.underCutBudget => cutsUsed < level.allowedCuts,
      BonusGoal.collectBonus => bonusLanded,
      BonusGoal.minimalWaste => wasted / denom <= level.bonusThreshold,
    };

    final passed = accuracy >= level.minSuccess;
    var stars = 0;
    if (accuracy >= level.minSuccess) stars = 1;
    if (accuracy >= level.twoStar) stars = 2;
    if (accuracy >= level.threeStar &&
        (level.bonus == BonusGoal.none || bonusAchieved)) {
      stars = 3;
    }

    final perfect = accuracy >= 0.995 && requiredZonesPerfect;

    // Coins reward accuracy, star count, spare cuts and the bonus goal.
    var coins = 0;
    if (passed) {
      coins = 12 + (accuracy * 26).round() + stars * 10;
      coins += (level.allowedCuts - cutsUsed).clamp(0, 3) * 6;
      if (bonusAchieved) coins += 20;
      if (perfect) coins += 30;
      coins += (level.world - 1) * 4;
    }

    return LevelResult(
      accuracy: accuracy,
      stars: stars,
      passed: passed,
      perfect: perfect,
      zones: zoneList,
      cutsUsed: cutsUsed,
      wastedMass: wasted,
      bonusAchieved: bonusAchieved,
      coins: coins,
      correctMass: correct,
      totalRequiredMass: totalRequired,
    );
  }

  /// Live accuracy while pieces are still falling, for the rising HUD meter.
  static double liveAccuracy(LevelResult r) => r.accuracy;

  /// Star thresholds as a readable string for the results screen.
  static String thresholdLabel(LevelDef l, int stars) => switch (stars) {
    1 => '${(l.minSuccess * 100).round()}%',
    2 => '${(l.twoStar * 100).round()}%',
    _ => '${(l.threeStar * 100).round()}%',
  };

  /// Grade text shown on the results banner.
  static String grade(LevelResult r) {
    if (r.perfect) return 'PERFECT CUT';
    if (r.stars >= 3) return 'FLAWLESS';
    if (r.stars == 2) return 'CLEAN CUT';
    if (r.passed) return 'COMPLETE';
    return 'MISSED';
  }

  static int comboFor(int consecutiveCorrect) =>
      math.min(9, math.max(1, consecutiveCorrect));
}
