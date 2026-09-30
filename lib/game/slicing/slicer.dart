import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../renderer/mesh.dart';
import 'plane.dart';

/// Result of cutting a mesh with a plane.
///
/// [front] holds the geometry on the plane-normal side, [back] the other side.
/// Either may be null when the plane misses the mesh entirely.
class SliceResult {
  const SliceResult({
    required this.front,
    required this.back,
    required this.loops,
    required this.cutArea,
  });

  final MeshData? front;
  final MeshData? back;

  /// Closed cut outlines in world/object space -- drives the cut-flash effect.
  final List<List<Vector3>> loops;

  /// Total area of the newly exposed surface. Used to score cut quality.
  final double cutArea;

  bool get didCut => front != null && back != null;

  static const SliceResult miss = SliceResult(
    front: null,
    back: null,
    loops: [],
    cutArea: 0,
  );
}

/// Runtime mesh slicing: splits a triangle soup by a plane and caps the hole
/// with newly generated interior geometry.
///
/// The cap is a real triangulation of the cut outline (ear clipping, with
/// concentric holes bridged), not a billboard -- so cut faces stay correct as
/// pieces tumble, and sliced pieces can be sliced again.
class MeshSlicer {
  /// Distances closer than this to the plane count as "on" it. Keeps slivers
  /// out of the output and stops the loop walker from choking on duplicates.
  static const double epsilon = 1e-5;

  /// Grid used to weld cut-segment endpoints into a shared vertex.
  static const double _weld = 1e-4;

  static SliceResult slice(MeshData mesh, CutPlane plane) {
    if (mesh.triCount == 0) return SliceResult.miss;

    // Cheap rejection: if the whole bounding sphere sits on one side, skip.
    final c = mesh.boundsCenter;
    final r = mesh.boundingRadius;
    final dc = plane.signedDistance(c);
    if (dc > r + epsilon || dc < -r - epsilon) return SliceResult.miss;

    final (materials, interiorOffset) = _materialsWithInteriors(mesh.materials);
    final front = MeshBuilder(materials);
    final back = MeshBuilder(materials);

    // Cut segments, tagged with the material of the triangle that made them.
    final segA = <Vector3>[];
    final segB = <Vector3>[];
    final segMat = <int>[];

    final p = mesh.positions;
    final d = List<double>.filled(3, 0);
    final vs = [Vector3.zero(), Vector3.zero(), Vector3.zero()];

    for (var t = 0; t < mesh.triCount; t++) {
      final i = t * 9;
      final mat = mesh.triMat[t];
      var nPos = 0, nNeg = 0, nZero = 0;
      for (var k = 0; k < 3; k++) {
        final o = i + k * 3;
        vs[k].setValues(p[o], p[o + 1], p[o + 2]);
        final dist = plane.signedDistanceRaw(p[o], p[o + 1], p[o + 2]);
        d[k] = dist;
        if (dist > epsilon) {
          nPos++;
        } else if (dist < -epsilon) {
          nNeg++;
        } else {
          nZero++;
        }
      }

      if (nNeg == 0 || nPos == 0) {
        if (nNeg == 0) {
          front.addTriangle(vs[0], vs[1], vs[2], mat);
        } else {
          back.addTriangle(vs[0], vs[1], vs[2], mat);
        }
        // A triangle sitting entirely on one side can still rest an edge
        // against the plane -- that edge is part of the cut outline. Without
        // this, a cut passing exactly through vertices (a swipe landing on a
        // box corner) leaves the outline open and the cap never closes.
        // Fully coplanar triangles are skipped: their edges are interior to
        // the cut face, not boundary.
        if (nZero == 2) {
          var e0 = -1, e1 = -1;
          for (var k = 0; k < 3; k++) {
            if (d[k].abs() <= epsilon) {
              if (e0 < 0) {
                e0 = k;
              } else {
                e1 = k;
              }
            }
          }
          segA.add(vs[e0].clone());
          segB.add(vs[e1].clone());
          segMat.add(mat);
        }
        continue;
      }

      // Straddles the plane: clip into a front polygon and a back polygon,
      // recording the shared edge as a cut segment.
      final fPoly = <Vector3>[];
      final bPoly = <Vector3>[];
      final cross = <Vector3>[];

      for (var k = 0; k < 3; k++) {
        final k2 = (k + 1) % 3;
        final a = vs[k], b = vs[k2];
        final da = d[k], db = d[k2];
        if (da >= -epsilon) fPoly.add(a.clone());
        if (da <= epsilon) bPoly.add(a.clone());
        // A vertex lying on the plane *is* a cut point; no edge crossing is
        // generated for it, so record it explicitly.
        if (da.abs() <= epsilon) cross.add(a.clone());
        if ((da > epsilon && db < -epsilon) ||
            (da < -epsilon && db > epsilon)) {
          final ip = plane.intersect(a, b, da, db);
          fPoly.add(ip);
          bPoly.add(ip.clone());
          cross.add(ip.clone());
        }
      }

      if (fPoly.length >= 3) front.addPolygon(fPoly, mat);
      if (bPoly.length >= 3) back.addPolygon(bPoly, mat);
      if (cross.length == 2) {
        segA.add(cross[0]);
        segB.add(cross[1]);
        segMat.add(mat);
      }
    }

    if (front.isEmpty || back.isEmpty) return SliceResult.miss;

    // Build the cap.
    final loops = _buildLoops(segA, segB, segMat);
    var cutArea = 0.0;
    for (final loop in loops) {
      cutArea += _capLoop(loop, plane, front, back, interiorOffset);
    }

    return SliceResult(
      front: front.build(),
      back: back.build(),
      loops: loops.map((l) => l.points).toList(growable: false),
      cutArea: cutArea,
    );
  }

  // -- materials -----------------------------------------------------------

  /// Returns the material list to use plus the index offset of the interior
  /// variants.
  ///
  /// A mesh that has already been sliced carries its `#cut` variants in the
  /// upper half of the list; re-slicing must reuse them rather than append a
  /// second copy, otherwise repeated cuts grow the list without bound.
  static (List<SurfaceMaterial>, int) _materialsWithInteriors(
    List<SurfaceMaterial> src,
  ) {
    final half = src.length ~/ 2;
    if (half > 0 && src.length.isEven) {
      var alreadyExtended = true;
      for (var i = 0; i < half; i++) {
        if (src[half + i].name != '${src[i].name}#cut') {
          alreadyExtended = false;
          break;
        }
      }
      if (alreadyExtended) return (src, half);
    }

    final out = List<SurfaceMaterial>.from(src);
    for (final m in src) {
      out.add(
        SurfaceMaterial(
          name: '${m.name}#cut',
          base: m.interior,
          interior: m.interior,
          metallic: m.metallic * 0.4,
          roughness: math.min(1.0, m.roughness + 0.15),
          emission: math.max(m.emission, 0.35),
        ),
      );
    }
    return (out, src.length);
  }

  // -- loop extraction -----------------------------------------------------

  static List<_CutLoop> _buildLoops(
    List<Vector3> a,
    List<Vector3> b,
    List<int> mats,
  ) {
    if (a.isEmpty) return const [];

    // Weld endpoints onto a coarse grid so shared triangle edges collapse.
    final verts = <Vector3>[];
    final index = <(int, int, int), int>{};
    int weldOf(Vector3 v) {
      final key = _cell(v);
      final existing = index[key];
      if (existing != null) return existing;
      verts.add(v);
      index[key] = verts.length - 1;
      return verts.length - 1;
    }

    final adjacency = <int, List<int>>{};
    final edgeMat = <(int, int), int>{};
    final seenEdges = <(int, int)>{};
    for (var i = 0; i < a.length; i++) {
      final ia = weldOf(a[i]);
      final ib = weldOf(b[i]);
      if (ia == ib) continue;
      final key = _edgeKey(ia, ib);
      // An edge resting on the plane is reported by the triangles on both
      // sides of it. Inserting it twice would give its vertices four
      // neighbours and derail the loop walk.
      if (!seenEdges.add(key)) continue;
      (adjacency[ia] ??= <int>[]).add(ib);
      (adjacency[ib] ??= <int>[]).add(ia);
      edgeMat[key] = mats[i];
    }

    final visited = <int>{};
    final loops = <_CutLoop>[];

    for (final start in adjacency.keys) {
      if (visited.contains(start)) continue;
      final chain = <int>[];
      final matVotes = <int, int>{};
      var current = start;
      var prev = -1;
      // Walk the chain; caps out at the vertex count to stay safe on
      // non-manifold input.
      for (var guard = 0; guard <= verts.length + 2; guard++) {
        chain.add(current);
        visited.add(current);
        final neighbours = adjacency[current];
        if (neighbours == null) break;
        var next = -1;
        for (final n in neighbours) {
          if (n == prev) continue;
          if (n == start && chain.length > 2) {
            next = start;
            break;
          }
          if (!visited.contains(n)) {
            next = n;
            break;
          }
        }
        if (next == -1 || next == start) {
          if (next == start) {
            final m = edgeMat[_edgeKey(current, start)];
            if (m != null) matVotes[m] = (matVotes[m] ?? 0) + 1;
          }
          break;
        }
        final m = edgeMat[_edgeKey(current, next)];
        if (m != null) matVotes[m] = (matVotes[m] ?? 0) + 1;
        prev = current;
        current = next;
      }

      if (chain.length < 3) continue;
      var dominant = 0, bestVotes = -1;
      matVotes.forEach((m, v) {
        if (v > bestVotes) {
          bestVotes = v;
          dominant = m;
        }
      });
      loops.add(
        _CutLoop(chain.map((i) => verts[i]).toList(growable: false), dominant),
      );
    }
    return loops;
  }

  /// Quantised grid cell for vertex welding. A record key is used deliberately:
  /// a mixed integer hash collides and can fuse separate shells into one loop.
  static (int, int, int) _cell(Vector3 v) {
    final inv = 1.0 / _weld;
    return ((v.x * inv).round(), (v.y * inv).round(), (v.z * inv).round());
  }

  static (int, int) _edgeKey(int a, int b) => a < b ? (a, b) : (b, a);

  // -- capping -------------------------------------------------------------

  /// Triangulates one cut loop and emits it into both halves with opposite
  /// winding. Returns the area added.
  static double _capLoop(
    _CutLoop loop,
    CutPlane plane,
    MeshBuilder front,
    MeshBuilder back,
    int interiorOffset,
  ) {
    final pts = loop.points;
    if (pts.length < 3) return 0;

    final (u, v) = plane.basis();
    final origin = pts.first;
    final flat = pts
        .map((p) => Vector2((p - origin).dot(u), (p - origin).dot(v)))
        .toList(growable: false);

    var area = _signedArea(flat);
    List<Vector2> poly = flat;
    List<Vector3> poly3 = pts;
    if (area < 0) {
      // Normalise to counter-clockwise so the winding rules below hold.
      poly = flat.reversed.toList(growable: false);
      poly3 = pts.reversed.toList(growable: false);
      area = -area;
    }

    final tris = _earClip(poly);

    // Map the loop's material to its interior variant. On a re-slice the
    // dominant material can itself already be an interior one (the cut passed
    // through a previous cut face), and blindly adding the offset again would
    // index past the end of the list -- a crash on any second cut.
    final base = loop.material >= interiorOffset
        ? loop.material - interiorOffset
        : loop.material;
    final mat = interiorOffset + base;

    for (var i = 0; i + 2 < tris.length; i += 3) {
      final a = poly3[tris[i]];
      final b = poly3[tris[i + 1]];
      final c = poly3[tris[i + 2]];
      // CCW in (u, v) faces +normal -> that is the *back* piece's cut face.
      back.addTriangle(a, b, c, mat);
      // The front piece's cut face looks the other way.
      front.addTriangle(c, b, a, mat);
    }
    return area;
  }

  static double _signedArea(List<Vector2> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final j = (i + 1) % p.length;
      s += p[i].x * p[j].y - p[j].x * p[i].y;
    }
    return s * 0.5;
  }

  /// Ear clipping for a simple CCW polygon. Returns index triples.
  ///
  /// Falls back to a centroid fan if the polygon is degenerate enough that no
  /// ear can be found -- always producing *some* cap beats leaving a hole.
  static List<int> _earClip(List<Vector2> poly) {
    final n = poly.length;
    final out = <int>[];
    if (n < 3) return out;
    if (n == 3) return [0, 1, 2];

    final remaining = List<int>.generate(n, (i) => i);
    var guard = n * n + 16;

    while (remaining.length > 3 && guard-- > 0) {
      var clipped = false;
      for (var i = 0; i < remaining.length; i++) {
        final ip = remaining[(i - 1 + remaining.length) % remaining.length];
        final ic = remaining[i];
        final inx = remaining[(i + 1) % remaining.length];
        final a = poly[ip], b = poly[ic], c = poly[inx];

        // Convex in a CCW polygon means a positive cross product.
        final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
        if (cross <= 1e-12) continue;

        var contains = false;
        for (final other in remaining) {
          if (other == ip || other == ic || other == inx) continue;
          if (_strictlyInside(poly[other], a, b, c)) {
            contains = true;
            break;
          }
        }
        if (contains) continue;

        out.addAll([ip, ic, inx]);
        remaining.removeAt(i);
        clipped = true;
        break;
      }
      if (!clipped) break; // no ear found -- bail to the fan below
    }

    if (remaining.length == 3) {
      out.addAll(remaining);
    } else if (remaining.length > 3) {
      for (var i = 1; i + 1 < remaining.length; i++) {
        out.addAll([remaining[0], remaining[i], remaining[i + 1]]);
      }
    }
    return out;
  }

  static bool _strictlyInside(Vector2 p, Vector2 a, Vector2 b, Vector2 c) {
    final d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    final d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    final d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);
    const e = 1e-10;
    final hasNeg = d1 < -e || d2 < -e || d3 < -e;
    final hasPos = d1 > e || d2 > e || d3 > e;
    return !(hasNeg && hasPos);
  }
}

class _CutLoop {
  _CutLoop(this.points, this.material);

  final List<Vector3> points;
  final int material;
}
