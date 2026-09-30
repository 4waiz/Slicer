import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'glb_loader.dart';
import 'mesh.dart';

/// Loads and caches Blender GLB exports.
///
/// Meshes are immutable once parsed (the slicer always produces new
/// [MeshData]), so a single parse can back every instance of a model.
class ModelCache {
  ModelCache._();

  static final ModelCache instance = ModelCache._();

  final Map<String, MeshData> _cache = <String, MeshData>{};
  final Map<String, Future<MeshData>> _inFlight = <String, Future<MeshData>>{};

  bool isLoaded(String name) => _cache.containsKey(name);

  MeshData? peek(String name) => _cache[name];

  Future<MeshData> load(String name) {
    final cached = _cache[name];
    if (cached != null) return Future<MeshData>.value(cached);
    return _inFlight[name] ??= _read(name);
  }

  Future<MeshData> _read(String name) async {
    try {
      final data = await rootBundle.load('assets/models/$name');
      final mesh = GlbLoader.parse(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        debugName: name,
      );
      _cache[name] = mesh;
      return mesh;
    } finally {
      _inFlight.remove(name);
    }
  }

  /// Warms several models at once, e.g. during a level transition.
  Future<void> preload(Iterable<String> names) async {
    await Future.wait(names.toSet().map(load));
  }

  /// Drops everything except [keep] -- called when leaving a world so the
  /// heap does not grow across a long session.
  void trim({Set<String> keep = const {}}) {
    _cache.removeWhere((k, _) => !keep.contains(k));
  }

  int get count => _cache.length;

  int get approximateBytes {
    var n = 0;
    for (final m in _cache.values) {
      n += m.positions.lengthInBytes + m.triMat.lengthInBytes;
    }
    return n;
  }

  /// Test seam: inject a mesh without touching the asset bundle.
  void put(String name, MeshData mesh) => _cache[name] = mesh;

  /// Parses bytes directly -- used by tests and the level validator.
  static MeshData parseBytes(Uint8List bytes, String name) =>
      GlbLoader.parse(bytes, debugName: name);
}
