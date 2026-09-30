import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';

/// Minimal, dependency-free glTF 2.0 / GLB reader.
///
/// Reads exactly what this game needs and nothing more: node hierarchy with
/// TRS transforms, triangle primitives, POSITION accessors, indices, and
/// `pbrMetallicRoughness.baseColorFactor` per material. Everything is flattened
/// into a single object-space [MeshData] triangle soup, which is the format
/// the renderer, slicer and physics all consume.
class GlbLoader {
  static const int _magic = 0x46546C67; // 'glTF'
  static const int _chunkJson = 0x4E4F534A; // 'JSON'
  static const int _chunkBin = 0x004E4942; // 'BIN\0'

  /// Parses GLB bytes into a mesh. Throws [FormatException] on malformed input.
  static MeshData parse(Uint8List bytes, {String debugName = 'glb'}) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 12) {
      throw FormatException('$debugName: too short to be a GLB');
    }
    if (bd.getUint32(0, Endian.little) != _magic) {
      throw FormatException('$debugName: not a GLB (bad magic)');
    }
    final version = bd.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException('$debugName: unsupported glTF version $version');
    }

    Map<String, dynamic>? gltf;
    Uint8List? bin;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final len = bd.getUint32(offset, Endian.little);
      final type = bd.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + len;
      if (end > bytes.length) break;
      if (type == _chunkJson) {
        gltf =
            json.decode(utf8.decode(bytes.sublist(start, end)))
                as Map<String, dynamic>;
      } else if (type == _chunkBin) {
        bin = Uint8List.sublistView(bytes, start, end);
      }
      offset = end + ((4 - (len % 4)) % 4); // chunks are 4-byte aligned
    }
    if (gltf == null) throw FormatException('$debugName: no JSON chunk');

    return _Reader(gltf, bin, debugName).flatten();
  }
}

class _Reader {
  _Reader(this.gltf, this.bin, this.debugName);

  final Map<String, dynamic> gltf;
  final Uint8List? bin;
  final String debugName;

  List<dynamic> _list(String key) => (gltf[key] as List<dynamic>?) ?? const [];

  MeshData flatten() {
    final materials = _readMaterials();
    final builder = MeshBuilder(materials);

    final nodes = _list('nodes');
    final scenes = _list('scenes');
    final sceneIndex = (gltf['scene'] as int?) ?? 0;
    List<dynamic> roots;
    if (scenes.isNotEmpty && sceneIndex < scenes.length) {
      roots =
          ((scenes[sceneIndex] as Map)['nodes'] as List<dynamic>?) ?? const [];
    } else {
      roots = List<int>.generate(nodes.length, (i) => i);
    }

    for (final r in roots) {
      _walk(r as int, Matrix4.identity(), builder);
    }

    if (builder.isEmpty) {
      throw FormatException('$debugName: no triangle geometry found');
    }
    return builder.build();
  }

  void _walk(int nodeIndex, Matrix4 parent, MeshBuilder out) {
    final nodes = _list('nodes');
    if (nodeIndex < 0 || nodeIndex >= nodes.length) return;
    final node = nodes[nodeIndex] as Map<String, dynamic>;
    final local = _nodeMatrix(node);
    final world = parent.multiplied(local);

    final meshIndex = node['mesh'] as int?;
    if (meshIndex != null) _emitMesh(meshIndex, world, out);

    for (final c in (node['children'] as List<dynamic>?) ?? const []) {
      _walk(c as int, world, out);
    }
  }

  Matrix4 _nodeMatrix(Map<String, dynamic> node) {
    final m = node['matrix'] as List<dynamic>?;
    if (m != null && m.length == 16) {
      // glTF matrices are column-major, which is also Matrix4's storage order.
      return Matrix4.fromList(m.map((e) => (e as num).toDouble()).toList());
    }
    final t = node['translation'] as List<dynamic>?;
    final r = node['rotation'] as List<dynamic>?;
    final s = node['scale'] as List<dynamic>?;
    final out = Matrix4.identity();
    if (t != null) {
      out.setTranslation(Vector3(_d(t[0]), _d(t[1]), _d(t[2])));
    }
    if (r != null) {
      // glTF quaternion order is (x, y, z, w).
      final q = Quaternion(_d(r[0]), _d(r[1]), _d(r[2]), _d(r[3]))..normalize();
      out.multiply(Matrix4.compose(Vector3.zero(), q, Vector3(1, 1, 1)));
    }
    if (s != null) {
      out.multiply(Matrix4.diagonal3(Vector3(_d(s[0]), _d(s[1]), _d(s[2]))));
    }
    return out;
  }

  static double _d(dynamic v) => (v as num).toDouble();

  void _emitMesh(int meshIndex, Matrix4 world, MeshBuilder out) {
    final meshes = _list('meshes');
    if (meshIndex >= meshes.length) return;
    final prims =
        ((meshes[meshIndex] as Map)['primitives'] as List<dynamic>?) ??
        const [];

    for (final p in prims) {
      final prim = p as Map<String, dynamic>;
      final mode = (prim['mode'] as int?) ?? 4;
      if (mode != 4) continue; // TRIANGLES only
      final attrs = prim['attributes'] as Map<String, dynamic>?;
      if (attrs == null) continue;
      final posAcc = attrs['POSITION'] as int?;
      if (posAcc == null) continue;

      final pos = _readAccessorFloats(posAcc, 3);
      final idxAcc = prim['indices'] as int?;
      final Int32List indices;
      if (idxAcc != null) {
        indices = _readAccessorInts(idxAcc);
      } else {
        indices = Int32List(pos.length ~/ 3);
        for (var i = 0; i < indices.length; i++) {
          indices[i] = i;
        }
      }

      final matIndex = (prim['material'] as int?) ?? 0;
      final safeMat = matIndex.clamp(0, out.materials.length - 1);

      final v = Vector3.zero();
      final a = Vector3.zero(), b = Vector3.zero(), c = Vector3.zero();
      for (var i = 0; i + 2 < indices.length; i += 3) {
        for (var k = 0; k < 3; k++) {
          final vi = indices[i + k] * 3;
          if (vi + 2 >= pos.length) continue;
          v.setValues(pos[vi], pos[vi + 1], pos[vi + 2]);
          world.transform3(v);
          if (k == 0) {
            a.setFrom(v);
          } else if (k == 1) {
            b.setFrom(v);
          } else {
            c.setFrom(v);
          }
        }
        out.addTriangle(a, b, c, safeMat);
      }
    }
  }

  List<SurfaceMaterial> _readMaterials() {
    final raw = _list('materials');
    if (raw.isEmpty) {
      const fallback = Color(0xFF9FB4C4);
      return <SurfaceMaterial>[
        SurfaceMaterial(
          name: 'default',
          base: fallback,
          interior: SurfaceMaterial.deriveInterior(fallback),
        ),
      ];
    }
    return raw
        .map((m) {
          final mm = m as Map<String, dynamic>;
          final pbr = mm['pbrMetallicRoughness'] as Map<String, dynamic>?;
          final bcf = pbr?['baseColorFactor'] as List<dynamic>?;
          // glTF baseColorFactor is linear; the renderer works in display sRGB.
          final base = bcf != null && bcf.length >= 3
              ? _linearToSrgb(_d(bcf[0]), _d(bcf[1]), _d(bcf[2]))
              : const Color(0xFF9FB4C4);
          final emissive = mm['emissiveFactor'] as List<dynamic>?;
          var emission = 0.0;
          if (emissive != null && emissive.length >= 3) {
            emission = math.max(
              _d(emissive[0]),
              math.max(_d(emissive[1]), _d(emissive[2])),
            );
            // Blender's emission strengths are authored for a physically-based
            // renderer. Taken at face value here they saturate every channel and
            // glowing pads read as flat white, so scale into a range that still
            // blooms but keeps the colour identity.
            emission *= 0.42;
          }
          return SurfaceMaterial(
            name: (mm['name'] as String?) ?? 'material',
            base: base,
            interior: SurfaceMaterial.deriveInterior(base),
            metallic: pbr?['metallicFactor'] == null
                ? 1.0
                : _d(pbr!['metallicFactor']),
            roughness: pbr?['roughnessFactor'] == null
                ? 0.5
                : _d(pbr!['roughnessFactor']),
            emission: emission,
          );
        })
        .toList(growable: false);
  }

  static Color _linearToSrgb(double r, double g, double b) {
    int enc(double c) {
      final v = c <= 0.0031308
          ? c * 12.92
          : 1.055 * math.pow(c.clamp(0.0, 1.0), 1 / 2.4) - 0.055;
      return (v * 255.0).round().clamp(0, 255);
    }

    return Color.fromARGB(255, enc(r), enc(g), enc(b));
  }

  // -- accessor decoding ---------------------------------------------------

  Map<String, dynamic> _accessor(int i) =>
      _list('accessors')[i] as Map<String, dynamic>;

  ({ByteData data, int stride, int offset}) _view(
    Map<String, dynamic> acc,
    int elementSize,
  ) {
    final bvIndex = acc['bufferView'] as int?;
    final accOffset = (acc['byteOffset'] as int?) ?? 0;
    if (bvIndex == null || bin == null) {
      return (data: ByteData(0), stride: elementSize, offset: 0);
    }
    final bv = _list('bufferViews')[bvIndex] as Map<String, dynamic>;
    final bvOffset = (bv['byteOffset'] as int?) ?? 0;
    final stride = (bv['byteStride'] as int?) ?? elementSize;
    return (
      data: ByteData.sublistView(bin!),
      stride: stride,
      offset: bvOffset + accOffset,
    );
  }

  static const Map<int, int> _componentSize = {
    5120: 1, // BYTE
    5121: 1, // UNSIGNED_BYTE
    5122: 2, // SHORT
    5123: 2, // UNSIGNED_SHORT
    5125: 4, // UNSIGNED_INT
    5126: 4, // FLOAT
  };

  static const Map<String, int> _typeCount = {
    'SCALAR': 1,
    'VEC2': 2,
    'VEC3': 3,
    'VEC4': 4,
    'MAT4': 16,
  };

  Float32List _readAccessorFloats(int index, int expectedComponents) {
    final acc = _accessor(index);
    final count = acc['count'] as int;
    final compType = acc['componentType'] as int;
    final comps = _typeCount[acc['type'] as String] ?? expectedComponents;
    final compSize = _componentSize[compType] ?? 4;
    final elementSize = compSize * comps;
    final v = _view(acc, elementSize);
    final out = Float32List(count * comps);
    if (v.data.lengthInBytes == 0) return out;

    for (var i = 0; i < count; i++) {
      final base = v.offset + i * v.stride;
      for (var c = 0; c < comps; c++) {
        final p = base + c * compSize;
        if (p + compSize > v.data.lengthInBytes) continue;
        out[i * comps + c] = switch (compType) {
          5126 => v.data.getFloat32(p, Endian.little),
          5123 => v.data.getUint16(p, Endian.little).toDouble(),
          5125 => v.data.getUint32(p, Endian.little).toDouble(),
          5122 => v.data.getInt16(p, Endian.little).toDouble(),
          5121 => v.data.getUint8(p).toDouble(),
          5120 => v.data.getInt8(p).toDouble(),
          _ => 0.0,
        };
      }
    }
    return out;
  }

  Int32List _readAccessorInts(int index) {
    final acc = _accessor(index);
    final count = acc['count'] as int;
    final compType = acc['componentType'] as int;
    final compSize = _componentSize[compType] ?? 2;
    final v = _view(acc, compSize);
    final out = Int32List(count);
    if (v.data.lengthInBytes == 0) return out;
    for (var i = 0; i < count; i++) {
      final p = v.offset + i * v.stride;
      if (p + compSize > v.data.lengthInBytes) continue;
      out[i] = switch (compType) {
        5125 => v.data.getUint32(p, Endian.little),
        5123 => v.data.getUint16(p, Endian.little),
        5121 => v.data.getUint8(p),
        5122 => v.data.getInt16(p, Endian.little),
        _ => 0,
      };
    }
    return out;
  }
}
