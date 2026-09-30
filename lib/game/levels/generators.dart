import 'dart:math' as math;

import '../materials/material_kind.dart';
import 'level_def.dart';

/// Structures the procedural modes may draw from, grouped by material feel.
const Map<MaterialKind, List<String>> _modelsByKind = {
  MaterialKind.crystal: [
    'crystal_cluster_large.glb',
    'crystal_tower.glb',
    'layered_crystal.glb',
    'crystal_orb.glb',
    'crystal_planet.glb',
  ],
  MaterialKind.jelly: [
    'jelly_tower.glb',
    'layered_jelly.glb',
    'jelly_capsule.glb',
    'candy_planet.glb',
  ],
  MaterialKind.fruit: [
    'watermelon_tower.glb',
    'orange_stack.glb',
    'layered_fruit_planet.glb',
    'dragonfruit_crystal.glb',
  ],
  MaterialKind.plasticToy: [
    'toy_tower.glb',
    'stacked_toy_buildings.glb',
    'block_city.glb',
    'toy_castle.glb',
  ],
  MaterialKind.metal: [
    'layered_engine.glb',
    'turbine_stack.glb',
    'reactor_machine.glb',
    'mechanical_planet.glb',
  ],
  MaterialKind.ice: ['ice_planet.glb'],
};

/// Material names each model exposes, so generated rules always resolve.
const Map<String, List<String>> _materialsOf = {
  'crystal_cluster_large.glb': [
    'M_cyan',
    'M_cyan_deep',
    'M_purple',
    'M_purple_deep',
    'M_steel_deep',
  ],
  'crystal_tower.glb': ['M_cyan', 'M_purple', 'M_steel_deep'],
  'layered_crystal.glb': ['M_cyan', 'M_purple', 'M_yellow'],
  'crystal_orb.glb': ['M_cyan', 'M_yellow', 'M_white'],
  'crystal_planet.glb': ['M_cyan', 'M_purple', 'M_white'],
  'jelly_tower.glb': ['M_cyan', 'M_pink', 'M_lime'],
  'layered_jelly.glb': ['M_pink', 'M_lime', 'M_cyan', 'M_yellow'],
  'jelly_capsule.glb': ['M_lime', 'M_pink'],
  'candy_planet.glb': ['M_pink', 'M_white', 'M_lime', 'M_magenta'],
  'watermelon_tower.glb': ['M_green_deep', 'M_white', 'M_red'],
  'orange_stack.glb': ['M_orange', 'M_gold', 'M_green'],
  'layered_fruit_planet.glb': ['M_green_deep', 'M_white', 'M_red', 'M_gold'],
  'dragonfruit_crystal.glb': ['M_magenta', 'M_white', 'M_lime'],
  'toy_tower.glb': ['M_orange', 'M_cyan', 'M_yellow', 'M_purple'],
  'stacked_toy_buildings.glb': ['M_orange', 'M_cyan', 'M_yellow', 'M_purple'],
  'block_city.glb': [
    'M_cyan',
    'M_orange',
    'M_yellow',
    'M_purple',
    'M_green',
    'M_steel_deep',
  ],
  'toy_castle.glb': ['M_steel', 'M_purple', 'M_yellow'],
  'layered_engine.glb': ['M_metal_dark', 'M_metal', 'M_orange', 'M_cyan'],
  'turbine_stack.glb': ['M_metal_dark', 'M_metal', 'M_orange'],
  'reactor_machine.glb': ['M_metal_dark', 'M_orange', 'M_cyan'],
  'mechanical_planet.glb': ['M_metal', 'M_metal_dark', 'M_cyan', 'M_orange'],
  'ice_planet.glb': ['M_ice', 'M_cyan', 'M_white'],
};

const List<(String, String, String)> _zoneKit = [
  ('cyan', 'cyan', 'diamond'),
  ('green', 'green', 'square'),
  ('purple', 'purple', 'triangle'),
  ('orange', 'orange', 'circle'),
];

/// Builds a level from a seed. Same seed in, same level out -- which is what
/// lets the Daily Slice be identical for everyone without a server.
LevelDef generateLevel({
  required int seed,
  required int id,
  required String name,
  required int difficulty,
  bool allowFields = true,
}) {
  final rng = math.Random(seed);
  final d = difficulty.clamp(0, 20);

  final kinds = _modelsByKind.keys.toList();
  final kind = kinds[rng.nextInt(kinds.length)];
  final models = _modelsByKind[kind]!;
  final model = models[rng.nextInt(models.length)];
  final matNames = _materialsOf[model] ?? const ['M_cyan'];

  // Zone count grows with difficulty but never exceeds the material count.
  final zoneCount = math
      .min(matNames.length, 2 + (d ~/ 5) + (rng.nextDouble() < 0.3 ? 1 : 0))
      .clamp(2, 4);

  final spread = switch (zoneCount) {
    2 => 2.9,
    3 => 3.6,
    _ => 4.8,
  };
  final padSize = switch (zoneCount) {
    2 => 2.35,
    3 => 2.05,
    _ => 1.70,
  };
  final moving = d >= 6 && rng.nextDouble() < 0.35;

  // Travel has to be derived from the gap between pads, not picked freely --
  // otherwise a four-pad layout with wide travel puts two pads on the same
  // patch of floor and a piece could satisfy either.
  final spacing = (spread * 2) / (zoneCount - 1);
  final maxRange = ((spacing - padSize) * 0.5 - 0.2).clamp(0.0, 1.4);

  final zones = <ZoneDef>[];
  for (var i = 0; i < zoneCount; i++) {
    final kit = _zoneKit[i];
    final t = zoneCount == 1 ? 0.5 : i / (zoneCount - 1);
    final x = -spread + t * spread * 2;
    final slides = moving && i.isEven && maxRange > 0.15;
    zones.add(
      ZoneDef(
        id: kit.$1,
        colorKey: kit.$2,
        shape: kit.$3,
        x: x,
        z: (i > 0 && i < zoneCount - 1) ? -0.55 : 0.0,
        width: padSize,
        depth: padSize,
        motion: slides ? ZoneMotion.slideX : ZoneMotion.still,
        motionRange: slides ? maxRange * (0.55 + rng.nextDouble() * 0.45) : 0.0,
        motionSpeed: 0.45 + rng.nextDouble() * 0.45,
      ),
    );
  }

  // Deal materials round-robin across zones so every pad is reachable.
  final rules = <MaterialRule>[];
  for (var i = 0; i < matNames.length; i++) {
    rules.add(
      MaterialRule(
        materialName: matNames[i],
        kind: kind,
        zoneId: zones[i % zones.length].id,
      ),
    );
  }

  final fields = <FieldDef>[];
  if (allowFields && d >= 8 && rng.nextDouble() < 0.4) {
    if (kind == MaterialKind.metal && rng.nextBool()) {
      final target = zones[rng.nextInt(zones.length)];
      fields.add(
        FieldDef(
          kind: 'magnet',
          x: target.x,
          y: 0.9,
          z: 0,
          width: 7,
          height: 12,
          depth: 10,
          strength: 11.0 + d.toDouble(),
          affects: MaterialKind.metal,
        ),
      );
    } else {
      fields.add(
        FieldDef(
          kind: 'wind',
          x: 0,
          y: 2.5,
          z: 0,
          width: 14,
          height: 6,
          depth: 8,
          strength: 3.0 + d * 0.25,
          dirX: rng.nextBool() ? 1.0 : -1.0,
        ),
      );
    }
  }

  final cuts = (zoneCount - 1).clamp(1, 3);

  return LevelDef(
    id: id,
    world: 0,
    name: name,
    model: model,
    zones: zones,
    materials: rules,
    defaultKind: kind,
    rotationSpeed: 0.22 + d * 0.045 + rng.nextDouble() * 0.2,
    rotationAxisX: rng.nextDouble() < 0.25 ? 0.3 : 0.0,
    allowedCuts: cuts,
    minSuccess: (0.58 - d * 0.006).clamp(0.42, 0.60),
    twoStar: (0.80 - d * 0.006).clamp(0.62, 0.82),
    threeStar: (0.94 - d * 0.005).clamp(0.80, 0.96),
    fields: fields,
    bonus: d >= 4 ? BonusGoal.minimalWaste : BonusGoal.none,
  );
}

/// Deterministic seed for a calendar day (UTC), so everyone gets the same run.
int dailySeed(DateTime day) {
  final d = DateTime.utc(day.year, day.month, day.day);
  return d.year * 10000 + d.month * 100 + d.day;
}

String dailyKey(DateTime day) {
  final d = DateTime.utc(day.year, day.month, day.day);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Today's Daily Slice.
LevelDef dailyLevel(DateTime day) {
  final seed = dailySeed(day);
  // Difficulty cycles over a week so the daily does not feel samey.
  final difficulty = 4 + (seed % 7) * 2;
  return generateLevel(
    seed: seed,
    id: -1,
    name: 'DAILY SLICE',
    difficulty: difficulty,
  );
}

/// One round of the Endless Slicing Lab. Difficulty climbs with [round].
LevelDef endlessLevel(int round, int runSeed) {
  return generateLevel(
    seed: runSeed * 7919 + round * 104729,
    id: -(round + 2),
    name: 'ROUND $round',
    difficulty: round,
  );
}
