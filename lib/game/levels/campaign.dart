import '../materials/material_kind.dart';
import 'campaign_worlds.dart';
import 'level_def.dart';

/// Material groupings for the hero Kanban structure.
///
/// The left half of the structure (orange orb, steel arm, dark core) belongs
/// to the cyan pad; the right half (gold, yellow gem, purple gem) belongs to
/// the green pad -- exactly the split the art bible's icon depicts.
List<MaterialRule> heroRules({
  required String leftZone,
  required String rightZone,
  MaterialKind leftKind = MaterialKind.crystal,
  MaterialKind rightKind = MaterialKind.crystal,
  String? bonusZone,
}) => [
  MaterialRule(materialName: 'M_orange', kind: leftKind, zoneId: leftZone),
  MaterialRule(materialName: 'M_orange_deep', kind: leftKind, zoneId: leftZone),
  MaterialRule(
    materialName: 'M_steel',
    kind: MaterialKind.metal,
    zoneId: leftZone,
  ),
  MaterialRule(
    materialName: 'M_steel_deep',
    kind: MaterialKind.metal,
    zoneId: leftZone,
  ),
  MaterialRule(
    materialName: 'M_metal_dark',
    kind: MaterialKind.metal,
    zoneId: leftZone,
  ),
  MaterialRule(materialName: 'M_gold', kind: rightKind, zoneId: rightZone),
  MaterialRule(materialName: 'M_yellow', kind: rightKind, zoneId: rightZone),
  MaterialRule(
    materialName: 'M_purple',
    kind: rightKind,
    zoneId: bonusZone ?? rightZone,
    isBonus: bonusZone != null,
  ),
];

// Two-pad layouts are deliberately wide and close in: a freshly separated
// half travels roughly 1.3-3.2 units out, so the catchment has to cover that
// whole band or a clean cut can still miss.
const ZoneDef cyanLeft = ZoneDef(
  id: 'cyan',
  colorKey: 'cyan',
  shape: 'diamond',
  x: -2.4,
  width: 2.9,
  depth: 2.9,
);

const ZoneDef greenRight = ZoneDef(
  id: 'green',
  colorKey: 'green',
  shape: 'square',
  x: 2.4,
  width: 2.9,
  depth: 2.9,
);

/// World 1 -- Crystal Workshop. Teaches the swipe, two pads, and reading a
/// rotating structure. Difficulty ramps through angle and timing, not speed.
final List<LevelDef> world1 = [
  LevelDef(
    id: 1,
    enforcePurity: true,
    world: 1,
    name: 'FIRST CUT',
    model: 'kanban_core_structure.glb',
    zones: const [cyanLeft, greenRight],
    materials: heroRules(leftZone: 'cyan', rightZone: 'green'),
    rotationSpeed: 0.0,
    allowedCuts: 1,
    minSuccess: 0.55,
    twoStar: 0.78,
    threeStar: 0.93,
    hint: 'Swipe down through the middle to split the structure.',
  ),
  LevelDef(
    id: 2,
    enforcePurity: true,
    world: 1,
    name: 'SLOW SPIN',
    model: 'kanban_core_structure.glb',
    zones: const [cyanLeft, greenRight],
    materials: heroRules(leftZone: 'cyan', rightZone: 'green'),
    rotationSpeed: 0.30,
    allowedCuts: 1,
    minSuccess: 0.58,
    twoStar: 0.80,
    threeStar: 0.94,
    hint: 'Time the swipe while it turns.',
  ),
  LevelDef(
    id: 3,
    enforcePurity: true,
    world: 1,
    name: 'WIDE PADS',
    model: 'kanban_core_structure.glb',
    zones: const [
      ZoneDef(
        id: 'cyan',
        colorKey: 'cyan',
        shape: 'diamond',
        x: -2.8,
        width: 3.1,
        depth: 3.1,
      ),
      ZoneDef(
        id: 'green',
        colorKey: 'green',
        shape: 'square',
        x: 2.8,
        width: 3.1,
        depth: 3.1,
      ),
    ],
    materials: heroRules(leftZone: 'cyan', rightZone: 'green'),
    rotationSpeed: 0.42,
    spawnY: 4.8,
    allowedCuts: 1,
    minSuccess: 0.60,
    twoStar: 0.82,
    threeStar: 0.95,
  ),
  LevelDef(
    id: 4,
    enforcePurity: true,
    world: 1,
    name: 'ANGLED FACE',
    model: 'kanban_core_structure.glb',
    zones: const [cyanLeft, greenRight],
    materials: heroRules(leftZone: 'cyan', rightZone: 'green'),
    rotationSpeed: 0.5,
    rotationAxisX: 0.25,
    allowedCuts: 1,
    minSuccess: 0.62,
    twoStar: 0.84,
    threeStar: 0.95,
    bonus: BonusGoal.minimalWaste,
    hint: 'A clean vertical cut wastes the least.',
  ),
  LevelDef(
    id: 5,
    enforcePurity: true,
    world: 1,
    name: 'TWIN CRYSTALS',
    model: 'crystal_cluster_large.glb',
    zones: const [cyanLeft, greenRight],
    materials: const [
      MaterialRule(
        materialName: 'M_cyan',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_cyan_deep',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_purple',
        kind: MaterialKind.crystal,
        zoneId: 'green',
      ),
      MaterialRule(
        materialName: 'M_purple_deep',
        kind: MaterialKind.crystal,
        zoneId: 'green',
      ),
    ],
    rotationSpeed: 0.4,
    allowedCuts: 1,
    minSuccess: 0.62,
    twoStar: 0.84,
    threeStar: 0.95,
  ),
  LevelDef(
    id: 6,
    enforcePurity: true,
    world: 1,
    name: 'TOWER SPLIT',
    model: 'crystal_tower.glb',
    zones: const [cyanLeft, greenRight],
    materials: const [
      MaterialRule(
        materialName: 'M_cyan',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_purple',
        kind: MaterialKind.crystal,
        zoneId: 'green',
      ),
      MaterialRule(
        materialName: 'M_steel_deep',
        kind: MaterialKind.metal,
        zoneId: 'cyan',
      ),
    ],
    rotationSpeed: 0.55,
    allowedCuts: 1,
    minSuccess: 0.64,
    twoStar: 0.85,
    threeStar: 0.95,
  ),
  LevelDef(
    id: 7,
    enforcePurity: true,
    world: 1,
    name: 'THREE WAYS',
    model: 'layered_crystal.glb',
    zones: const [
      ZoneDef(
        id: 'cyan',
        colorKey: 'cyan',
        shape: 'diamond',
        x: -3.6,
        width: 2.1,
        depth: 2.1,
      ),
      ZoneDef(
        id: 'purple',
        colorKey: 'purple',
        shape: 'triangle',
        x: 0.0,
        z: -0.4,
        width: 2.1,
        depth: 2.1,
      ),
      ZoneDef(
        id: 'green',
        colorKey: 'green',
        shape: 'square',
        x: 3.6,
        width: 2.1,
        depth: 2.1,
      ),
    ],
    materials: const [
      MaterialRule(
        materialName: 'M_cyan',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_purple',
        kind: MaterialKind.crystal,
        zoneId: 'purple',
      ),
      MaterialRule(
        materialName: 'M_yellow',
        kind: MaterialKind.crystal,
        zoneId: 'green',
      ),
    ],
    rotationSpeed: 0.42,
    allowedCuts: 2,
    minSuccess: 0.60,
    twoStar: 0.80,
    threeStar: 0.93,
    hint: 'Two cuts. Three pads.',
  ),
  LevelDef(
    id: 8,
    world: 1,
    name: 'ORB CORE',
    model: 'crystal_orb.glb',
    zones: const [cyanLeft, greenRight],
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
      MaterialRule(
        materialName: 'M_white',
        kind: MaterialKind.crystal,
        zoneId: 'green',
        isCore: true,
      ),
    ],
    rotationSpeed: 0.62,
    allowedCuts: 1,
    minSuccess: 0.64,
    twoStar: 0.85,
    threeStar: 0.96,
    bonus: BonusGoal.allZonesPerfect,
  ),
  LevelDef(
    id: 9,
    enforcePurity: true,
    world: 1,
    name: 'BRIDGE BREAK',
    model: 'crystal_bridge.glb',
    zones: const [
      ZoneDef(
        id: 'cyan',
        colorKey: 'cyan',
        shape: 'diamond',
        x: -2.5,
        width: 2.8,
        depth: 2.8,
      ),
      ZoneDef(
        id: 'green',
        colorKey: 'green',
        shape: 'square',
        x: 2.5,
        width: 2.8,
        depth: 2.8,
      ),
    ],
    materials: const [
      MaterialRule(
        materialName: 'M_cyan',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_green',
        kind: MaterialKind.crystal,
        zoneId: 'green',
      ),
      MaterialRule(
        materialName: 'M_steel',
        kind: MaterialKind.metal,
        zoneId: 'cyan',
      ),
    ],
    rotationSpeed: 0.22,
    spawnY: 4.6,
    allowedCuts: 1,
    minSuccess: 0.66,
    twoStar: 0.86,
    threeStar: 0.96,
  ),
  LevelDef(
    id: 10,
    world: 1,
    name: 'CORE MACHINE',
    model: 'crystal_core_machine.glb',
    zones: const [
      ZoneDef(
        id: 'cyan',
        colorKey: 'cyan',
        shape: 'diamond',
        x: -3.2,
        width: 2.2,
        depth: 2.2,
      ),
      ZoneDef(
        id: 'green',
        colorKey: 'green',
        shape: 'square',
        x: 3.2,
        width: 2.2,
        depth: 2.2,
      ),
      ZoneDef(
        id: 'purple',
        colorKey: 'purple',
        shape: 'triangle',
        x: 0,
        z: -2.6,
        width: 1.8,
        depth: 1.8,
        isBonus: true,
      ),
    ],
    materials: const [
      MaterialRule(
        materialName: 'M_cyan',
        kind: MaterialKind.crystal,
        zoneId: 'cyan',
      ),
      MaterialRule(
        materialName: 'M_orange',
        kind: MaterialKind.metal,
        zoneId: 'green',
      ),
      MaterialRule(
        materialName: 'M_metal_dark',
        kind: MaterialKind.metal,
        zoneId: 'green',
      ),
      MaterialRule(
        materialName: 'M_purple',
        kind: MaterialKind.crystal,
        zoneId: 'purple',
        isBonus: true,
      ),
    ],
    rotationSpeed: 0.5,
    allowedCuts: 2,
    minSuccess: 0.66,
    twoStar: 0.86,
    threeStar: 0.96,
    bonus: BonusGoal.collectBonus,
    hint: 'The purple core is worth extra.',
  ),
];

/// The full campaign. Worlds 2-6 are appended by `campaign_worlds.dart`.
List<LevelDef> get allLevels => <LevelDef>[...world1, ...worlds2to6];

LevelDef? levelById(int id) {
  for (final l in allLevels) {
    if (l.id == id) return l;
  }
  return null;
}

List<LevelDef> levelsInWorld(int world) =>
    allLevels.where((l) => l.world == world).toList(growable: false);

int get levelCount => allLevels.length;
