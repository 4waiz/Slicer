import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban_slicer/game/levels/campaign.dart';
import 'package:kanban_slicer/game/levels/generators.dart';
import 'package:kanban_slicer/game/levels/level_def.dart';
import 'package:kanban_slicer/game/levels/level_validator.dart';
import 'package:kanban_slicer/game/materials/material_kind.dart';
import 'package:kanban_slicer/game/renderer/glb_loader.dart';
import 'package:kanban_slicer/game/renderer/mesh.dart';

const _crystal = MaterialKind.crystal;
const _toy = MaterialKind.plasticToy;

final Map<String, MeshData?> _meshCache = {};

MeshData? _mesh(String model) => _meshCache.putIfAbsent(model, () {
  final f = File('assets/models/$model');
  if (!f.existsSync()) return null;
  return GlbLoader.parse(
    Uint8List.fromList(f.readAsBytesSync()),
    debugName: model,
  );
});

Set<String> _modelsOnDisk() => Directory('assets/models')
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((n) => n.endsWith('.glb'))
    .toSet();

void main() {
  final validator = LevelValidator(
    meshFor: _mesh,
    knownModels: _modelsOnDisk(),
  );

  group('Campaign shape', () {
    test('has exactly 60 levels across 6 worlds of 10', () {
      expect(levelCount, 60);
      for (var w = 1; w <= 6; w++) {
        expect(levelsInWorld(w).length, 10, reason: 'world $w');
      }
    });

    test('level ids are 1..60 with no gaps or duplicates', () {
      final ids = allLevels.map((l) => l.id).toList()..sort();
      expect(ids, List<int>.generate(60, (i) => i + 1));
    });

    test('every level has a name and a real model', () {
      final onDisk = _modelsOnDisk();
      for (final l in allLevels) {
        expect(l.name.trim(), isNotEmpty, reason: 'level ${l.id}');
        expect(onDisk, contains(l.model), reason: 'level ${l.id}');
      }
    });

    test('difficulty broadly rises across the campaign', () {
      double avgCuts(int world) {
        final ls = levelsInWorld(world);
        return ls.fold<int>(0, (a, l) => a + l.allowedCuts) / ls.length;
      }

      double avgZones(int world) {
        final ls = levelsInWorld(world);
        return ls.fold<int>(0, (a, l) => a + l.zones.length) / ls.length;
      }

      expect(avgCuts(6), greaterThan(avgCuts(1)));
      expect(avgZones(6), greaterThan(avgZones(1)));
    });

    test('world 1 opens gently: one cut, two pads, no fields', () {
      for (final l in levelsInWorld(1).take(4)) {
        expect(l.allowedCuts, 1, reason: 'level ${l.id}');
        expect(l.zones.length, 2, reason: 'level ${l.id}');
        expect(l.fields, isEmpty, reason: 'level ${l.id}');
      }
      expect(
        levelsInWorld(1).first.rotationSpeed,
        0.0,
        reason: 'the very first level must not rotate',
      );
    });

    test('every world uses its own material identity', () {
      String kindOf(int world) {
        final counts = <String, int>{};
        for (final l in levelsInWorld(world)) {
          for (final r in l.materials) {
            counts[r.kind.id] = (counts[r.kind.id] ?? 0) + 1;
          }
        }
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }

      expect(kindOf(2), 'jelly');
      expect(kindOf(3), 'fruit');
      expect(kindOf(4), 'plastic');
      expect(kindOf(5), 'metal');
    });
  });

  group('Level validator', () {
    test('every shipped level passes validation', () {
      final issues = validator.validateAll(allLevels);
      expect(
        issues,
        isEmpty,
        reason: issues.map((i) => i.toString()).join('\n'),
      );
    });

    test('catches a zone with no material assigned', () {
      final broken = LevelDef(
        id: 900,
        world: 1,
        name: 'BROKEN',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        materials: const [
          MaterialRule(materialName: 'M_cyan', kind: _crystal, zoneId: 'cyan'),
        ],
      );
      final issues = validator.validate(broken);
      expect(issues.any((i) => i.code == 'impossible'), isTrue);
    });

    test('catches more required zones than cuts can produce', () {
      final broken = LevelDef(
        id: 901,
        world: 1,
        name: 'TOO MANY',
        model: 'toy_tower.glb',
        allowedCuts: 1,
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -4),
          ZoneDef(
            id: 'orange',
            colorKey: 'orange',
            shape: 'circle',
            x: -1.4,
            z: -0.6,
          ),
          ZoneDef(
            id: 'purple',
            colorKey: 'purple',
            shape: 'triangle',
            x: 1.4,
            z: -0.6,
          ),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 4),
        ],
        materials: const [
          MaterialRule(materialName: 'M_orange', kind: _toy, zoneId: 'cyan'),
          MaterialRule(materialName: 'M_cyan', kind: _toy, zoneId: 'orange'),
          MaterialRule(materialName: 'M_yellow', kind: _toy, zoneId: 'purple'),
          MaterialRule(materialName: 'M_purple', kind: _toy, zoneId: 'green'),
        ],
      );
      expect(
        validator.validate(broken).any((i) => i.code == 'impossible'),
        isTrue,
      );
    });

    test('catches overlapping pads', () {
      final broken = LevelDef(
        id: 902,
        world: 1,
        name: 'OVERLAP',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -0.4),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 0.4),
        ],
        materials: const [
          MaterialRule(materialName: 'M_cyan', kind: _crystal, zoneId: 'cyan'),
          MaterialRule(
            materialName: 'M_yellow',
            kind: _crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(validator.validate(broken).any((i) => i.code == 'zones'), isTrue);
    });

    test('catches a material the model does not have', () {
      final broken = LevelDef(
        id: 903,
        world: 1,
        name: 'GHOST MATERIAL',
        model: 'crystal_orb.glb',
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        materials: const [
          MaterialRule(materialName: 'M_cyan', kind: _crystal, zoneId: 'cyan'),
          MaterialRule(
            materialName: 'M_does_not_exist',
            kind: _crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(
        validator.validate(broken).any((i) => i.code == 'materials'),
        isTrue,
      );
    });

    test('catches out-of-order star thresholds', () {
      final broken = LevelDef(
        id: 904,
        world: 1,
        name: 'BAD STARS',
        model: 'crystal_orb.glb',
        minSuccess: 0.9,
        twoStar: 0.5,
        threeStar: 0.7,
        zones: const [
          ZoneDef(id: 'cyan', colorKey: 'cyan', shape: 'diamond', x: -2.5),
          ZoneDef(id: 'green', colorKey: 'green', shape: 'square', x: 2.5),
        ],
        materials: const [
          MaterialRule(materialName: 'M_cyan', kind: _crystal, zoneId: 'cyan'),
          MaterialRule(
            materialName: 'M_yellow',
            kind: _crystal,
            zoneId: 'green',
          ),
        ],
      );
      expect(
        validator.validate(broken).any((i) => i.code == 'threshold'),
        isTrue,
      );
    });
  });

  group('Procedural generation', () {
    test('the daily level is identical for the same date', () {
      final day = DateTime.utc(2026, 8, 5);
      final a = dailyLevel(day);
      final b = dailyLevel(day);
      expect(a.model, b.model);
      expect(a.zones.length, b.zones.length);
      expect(a.allowedCuts, b.allowedCuts);
      expect(a.rotationSpeed, b.rotationSpeed);
      expect(
        a.materials.map((m) => m.materialName).toList(),
        b.materials.map((m) => m.materialName).toList(),
      );
    });

    test('different dates give different puzzles', () {
      final a = dailyLevel(DateTime.utc(2026, 8, 5));
      final b = dailyLevel(DateTime.utc(2026, 8, 6));
      final same =
          a.model == b.model &&
          a.zones.length == b.zones.length &&
          a.rotationSpeed == b.rotationSpeed;
      expect(same, isFalse);
    });

    test('daily key formats as YYYY-MM-DD', () {
      expect(dailyKey(DateTime.utc(2026, 1, 9)), '2026-01-09');
    });

    test('a year of daily levels all validate', () {
      final start = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 365; i += 7) {
        final l = dailyLevel(start.add(Duration(days: i)));
        final issues = validator.validate(l);
        expect(
          issues,
          isEmpty,
          reason: 'day $i: ${issues.map((e) => e.toString()).join("; ")}',
        );
      }
    });

    test('endless rounds all validate and grow harder', () {
      LevelDef? prev;
      for (var round = 1; round <= 40; round++) {
        final l = endlessLevel(round, 12345);
        final issues = validator.validate(l);
        expect(
          issues,
          isEmpty,
          reason: 'round $round: ${issues.map((e) => e.toString()).join("; ")}',
        );
        prev = l;
      }
      expect(prev, isNotNull);
      expect(
        endlessLevel(30, 1).rotationSpeed,
        greaterThan(endlessLevel(1, 1).rotationSpeed),
      );
    });

    test('generated levels never exceed four pads or four cuts', () {
      for (var r = 1; r <= 60; r++) {
        final l = endlessLevel(r, 777);
        expect(l.zones.length, lessThanOrEqualTo(4));
        expect(l.allowedCuts, inInclusiveRange(1, 4));
      }
    });
  });
}
