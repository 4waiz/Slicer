import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../camera/camera3d.dart';
import 'mesh.dart';

/// A mesh placed in the world.
class RenderNode {
  RenderNode({
    required this.mesh,
    Vector3? position,
    Quaternion? orientation,
    this.scale = 1.0,
    this.visible = true,
    this.glowBoost = 0.0,
    this.tint,
    this.tintAmount = 0.0,
    this.brightness = 1.0,
    this.castShadow = true,
  }) : position = position ?? Vector3.zero(),
       orientation = orientation ?? Quaternion.identity();

  MeshData mesh;
  Vector3 position;
  Quaternion orientation;
  double scale;
  bool visible;

  /// Extra additive glow on top of whatever the materials emit.
  double glowBoost;

  /// Optional flat colour blended over the shaded result (hit flashes, etc).
  Color? tint;
  double tintAmount;

  /// Multiplies the final shaded colour -- used for the pre-cut dim/highlight.
  double brightness;
  bool castShadow;

  final Matrix4 _model = Matrix4.identity();

  Matrix4 get modelMatrix {
    _model.setFromTranslationRotationScale(
      position,
      orientation,
      Vector3(scale, scale, scale),
    );
    return _model;
  }
}

/// Directional key light plus hemisphere ambient and a rim term.
class Lighting {
  Lighting({
    Vector3? keyDirection,
    this.keyColor = const Color(0xFFFFF4E0),
    this.keyStrength = 0.88,
    this.skyColor = const Color(0xFF5A9CB4),
    this.groundColor = const Color(0xFF24505F),
    this.ambientStrength = 0.82,
    this.rimColor = const Color(0xFF6FE8FF),
    this.rimStrength = 0.55,
    this.specStrength = 0.42,
  }) : keyDirection = (keyDirection ?? Vector3(-0.45, 0.82, 0.36)).normalized();

  Vector3 keyDirection;
  Color keyColor;
  double keyStrength;
  Color skyColor;
  Color groundColor;
  double ambientStrength;
  Color rimColor;
  double rimStrength;
  double specStrength;
}

/// Software transform + shade, GPU raster via `Canvas.drawVertices`.
///
/// Flat shading needs a unique colour per face, so the pipeline expands to a
/// triangle soup, back-face culls in world space, depth-sorts (painter's
/// algorithm) and emits one batched draw call for opaque faces and one for the
/// additive glow pass.
class SceneRenderer {
  SceneRenderer({this.maxTriangles = 24000});

  final int maxTriangles;

  Float32List _pos = Float32List(0);
  Int32List _col = Int32List(0);
  Float32List _depth = Float32List(0);
  List<int> _order = <int>[];
  int _count = 0;

  Float32List _glowPos = Float32List(0);
  Int32List _glowCol = Int32List(0);
  int _glowCount = 0;

  final List<double> _p0 = [0, 0];
  final List<double> _p1 = [0, 0];
  final List<double> _p2 = [0, 0];

  /// Triangles submitted on the most recent frame -- surfaced in the perf HUD.
  int get lastTriangleCount => _count;

  /// Per-stage reject counts from the most recent frame. Diagnostic only.
  int consideredTris = 0;
  int culledDegenerate = 0;
  int culledBackface = 0;
  int culledBehind = 0;

  String get cullReport =>
      'c=$consideredTris d=$culledDegenerate b=$culledBackface z=$culledBehind';

  void _ensureCapacity(int tris) {
    if (_depth.length >= tris) return;
    final n = math.max(tris, math.max(1024, _depth.length * 2));
    _pos = Float32List(n * 6);
    _col = Int32List(n * 3);
    _depth = Float32List(n);
    _glowPos = Float32List(n * 6);
    _glowCol = Int32List(n * 3);
    _order = List<int>.filled(n, 0, growable: false);
  }

  void render(
    Canvas canvas,
    Camera3D camera,
    List<RenderNode> nodes,
    Lighting light,
  ) {
    var total = 0;
    for (final n in nodes) {
      if (n.visible) total += n.mesh.triCount;
    }
    if (total == 0) {
      _count = 0;
      return;
    }
    _ensureCapacity(math.min(total, maxTriangles));

    _count = 0;
    _glowCount = 0;
    consideredTris = 0;
    culledDegenerate = 0;
    culledBackface = 0;
    culledBehind = 0;

    final camX = camera.position.x,
        camY = camera.position.y,
        camZ = camera.position.z;
    final lx = light.keyDirection.x,
        ly = light.keyDirection.y,
        lz = light.keyDirection.z;
    final keyR = light.keyColor.r,
        keyG = light.keyColor.g,
        keyB = light.keyColor.b;
    final skyR = light.skyColor.r,
        skyG = light.skyColor.g,
        skyB = light.skyColor.b;
    final grR = light.groundColor.r,
        grG = light.groundColor.g,
        grB = light.groundColor.b;
    final rimR = light.rimColor.r,
        rimG = light.rimColor.g,
        rimB = light.rimColor.b;

    for (final node in nodes) {
      if (!node.visible || node.mesh.triCount == 0) continue;
      final m = node.modelMatrix;
      final s = m.storage;
      final mesh = node.mesh;
      final p = mesh.positions;

      // Per-material colour channels, resolved once per node per frame.
      final matCount = mesh.materials.length;
      final mr = Float32List(matCount);
      final mg = Float32List(matCount);
      final mb = Float32List(matCount);
      final me = Float32List(matCount);
      final mspec = Float32List(matCount);
      for (var i = 0; i < matCount; i++) {
        final mat = mesh.materials[i];
        mr[i] = mat.base.r;
        mg[i] = mat.base.g;
        mb[i] = mat.base.b;
        me[i] = mat.emission + node.glowBoost;
        mspec[i] = (0.25 + mat.metallic * 0.75) * (1.0 - mat.roughness * 0.7);
      }

      final tintC = node.tint;
      final tr = tintC?.r ?? 0.0, tg = tintC?.g ?? 0.0, tb = tintC?.b ?? 0.0;
      final ta = tintC == null ? 0.0 : node.tintAmount.clamp(0.0, 1.0);

      for (var t = 0; t < mesh.triCount; t++) {
        if (_count >= maxTriangles) break;
        consideredTris++;
        final i = t * 9;

        // Object -> world.
        final ox0 = p[i], oy0 = p[i + 1], oz0 = p[i + 2];
        final ox1 = p[i + 3], oy1 = p[i + 4], oz1 = p[i + 5];
        final ox2 = p[i + 6], oy2 = p[i + 7], oz2 = p[i + 8];

        final ax = s[0] * ox0 + s[4] * oy0 + s[8] * oz0 + s[12];
        final ay = s[1] * ox0 + s[5] * oy0 + s[9] * oz0 + s[13];
        final az = s[2] * ox0 + s[6] * oy0 + s[10] * oz0 + s[14];
        final bx = s[0] * ox1 + s[4] * oy1 + s[8] * oz1 + s[12];
        final by = s[1] * ox1 + s[5] * oy1 + s[9] * oz1 + s[13];
        final bz = s[2] * ox1 + s[6] * oy1 + s[10] * oz1 + s[14];
        final cx = s[0] * ox2 + s[4] * oy2 + s[8] * oz2 + s[12];
        final cy = s[1] * ox2 + s[5] * oy2 + s[9] * oz2 + s[13];
        final cz = s[2] * ox2 + s[6] * oy2 + s[10] * oz2 + s[14];

        // Face normal.
        var nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay);
        var ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az);
        var nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
        final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (nLen < 1e-12) {
          culledDegenerate++;
          continue;
        }
        nx /= nLen;
        ny /= nLen;
        nz /= nLen;

        // Back-face cull against the eye, in world space.
        final ctrX = (ax + bx + cx) / 3.0;
        final ctrY = (ay + by + cy) / 3.0;
        final ctrZ = (az + bz + cz) / 3.0;
        var vx = camX - ctrX, vy = camY - ctrY, vz = camZ - ctrZ;
        final vLen = math.sqrt(vx * vx + vy * vy + vz * vz);
        if (vLen < 1e-9) {
          culledDegenerate++;
          continue;
        }
        vx /= vLen;
        vy /= vLen;
        vz /= vLen;
        if (nx * vx + ny * vy + nz * vz <= 0.0) {
          culledBackface++;
          continue;
        }

        final d0 = camera.projectRaw(ax, ay, az, _p0);
        final d1 = camera.projectRaw(bx, by, bz, _p1);
        final d2 = camera.projectRaw(cx, cy, cz, _p2);
        if (d0 < 0 || d1 < 0 || d2 < 0) {
          culledBehind++;
          continue;
        }

        // Shade.
        final mi = mesh.triMat[t];
        final lambert = math.max(0.0, nx * lx + ny * ly + nz * lz);
        final hemi = 0.5 + 0.5 * ny;
        final ambR = (grR + (skyR - grR) * hemi) * light.ambientStrength;
        final ambG = (grG + (skyG - grG) * hemi) * light.ambientStrength;
        final ambB = (grB + (skyB - grB) * hemi) * light.ambientStrength;
        final kk = lambert * light.keyStrength;

        // Blinn-Phong highlight -- what makes metal and crystal read as hard.
        var hx = lx + vx, hy = ly + vy, hz = lz + vz;
        final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
        var spec = 0.0;
        if (hLen > 1e-9) {
          hx /= hLen;
          hy /= hLen;
          hz /= hLen;
          final nh = math.max(0.0, nx * hx + ny * hy + nz * hz);
          final nh2 = nh * nh;
          final nh4 = nh2 * nh2;
          spec = nh4 * nh4 * nh4 * mspec[mi] * light.specStrength;
        }

        final ndv = (nx * vx + ny * vy + nz * vz).abs();
        final oneMinus = 1.0 - ndv;
        final rim = oneMinus * oneMinus * oneMinus * light.rimStrength;

        final baseR = mr[mi], baseG = mg[mi], baseB = mb[mi];
        final emis = me[mi];
        var rr =
            baseR * (ambR + keyR * kk) +
            rimR * rim +
            baseR * emis +
            keyR * spec;
        var gg =
            baseG * (ambG + keyG * kk) +
            rimG * rim +
            baseG * emis +
            keyG * spec;
        var bb =
            baseB * (ambB + keyB * kk) +
            rimB * rim +
            baseB * emis +
            keyB * spec;

        if (ta > 0) {
          rr = rr + (tr - rr) * ta;
          gg = gg + (tg - gg) * ta;
          bb = bb + (tb - bb) * ta;
        }
        final br = node.brightness;
        final packed =
            0xFF000000 |
            (((rr * br).clamp(0.0, 1.0) * 255).toInt() << 16) |
            (((gg * br).clamp(0.0, 1.0) * 255).toInt() << 8) |
            ((bb * br).clamp(0.0, 1.0) * 255).toInt();

        final vi = _count * 6;
        _pos[vi] = _p0[0];
        _pos[vi + 1] = _p0[1];
        _pos[vi + 2] = _p1[0];
        _pos[vi + 3] = _p1[1];
        _pos[vi + 4] = _p2[0];
        _pos[vi + 5] = _p2[1];
        final ci = _count * 3;
        _col[ci] = packed;
        _col[ci + 1] = packed;
        _col[ci + 2] = packed;
        _depth[_count] = ((d0 + d1 + d2) / 3.0);
        _count++;

        // Emissive faces are re-submitted into the additive bloom pass.
        if (emis > 0.08 && _glowCount < maxTriangles) {
          final gi = _glowCount * 6;
          _glowPos[gi] = _p0[0];
          _glowPos[gi + 1] = _p0[1];
          _glowPos[gi + 2] = _p1[0];
          _glowPos[gi + 3] = _p1[1];
          _glowPos[gi + 4] = _p2[0];
          _glowPos[gi + 5] = _p2[1];
          final gc = _glowCount * 3;
          final glowA = (emis * 0.55).clamp(0.0, 0.85);
          final gp =
              ((glowA * 255).toInt() << 24) |
              (((baseR * 0.85 + 0.15).clamp(0.0, 1.0) * 255).toInt() << 16) |
              (((baseG * 0.85 + 0.15).clamp(0.0, 1.0) * 255).toInt() << 8) |
              ((baseB * 0.85 + 0.15).clamp(0.0, 1.0) * 255).toInt();
          _glowCol[gc] = gp;
          _glowCol[gc + 1] = gp;
          _glowCol[gc + 2] = gp;
          _glowCount++;
        }
      }
    }

    if (_count == 0) return;

    // Painter's algorithm: far triangles first.
    for (var i = 0; i < _count; i++) {
      _order[i] = i;
    }
    final orderView = _order.sublist(0, _count);
    orderView.sort((a, b) => _depth[b].compareTo(_depth[a]));

    final sortedPos = Float32List(_count * 6);
    final sortedCol = Int32List(_count * 3);
    for (var k = 0; k < _count; k++) {
      final src = orderView[k] * 6;
      final dst = k * 6;
      sortedPos[dst] = _pos[src];
      sortedPos[dst + 1] = _pos[src + 1];
      sortedPos[dst + 2] = _pos[src + 2];
      sortedPos[dst + 3] = _pos[src + 3];
      sortedPos[dst + 4] = _pos[src + 4];
      sortedPos[dst + 5] = _pos[src + 5];
      final cs = orderView[k] * 3;
      final cd = k * 3;
      sortedCol[cd] = _col[cs];
      sortedCol[cd + 1] = _col[cs + 1];
      sortedCol[cd + 2] = _col[cs + 2];
    }

    final vertices = Vertices.raw(
      VertexMode.triangles,
      sortedPos,
      colors: sortedCol,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    vertices.dispose();

    if (_glowCount > 0) {
      final gp = Float32List.sublistView(_glowPos, 0, _glowCount * 6);
      final gc = Int32List.sublistView(_glowCol, 0, _glowCount * 3);
      final glowVerts = Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(gp),
        colors: Int32List.fromList(gc),
      );
      canvas.drawVertices(
        glowVerts,
        BlendMode.srcOver,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0),
      );
      glowVerts.dispose();
    }
  }

  /// Soft contact shadows: each node is blobbed onto the stage plane, fading
  /// and spreading with height. Cheap, and it anchors falling pieces.
  static void drawShadows(
    Canvas canvas,
    Camera3D camera,
    List<RenderNode> nodes,
    double planeY, {
    double maxHeight = 7.0,
    double opacity = 0.34,
  }) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    for (final n in nodes) {
      if (!n.visible || !n.castShadow) continue;
      final h = (n.position.y - planeY).clamp(0.0, maxHeight);
      final fade = 1.0 - (h / maxHeight);
      if (fade <= 0.02) continue;
      final ground = Vector3(n.position.x, planeY + 0.01, n.position.z);
      final centre = camera.project(ground);
      // Skip this node, not the whole pass -- one node behind the eye must
      // not cost every other node its shadow.
      if (centre == null) continue;
      final r = n.mesh.boundingRadius * n.scale;
      final edge = camera.project(Vector3(ground.x + r, ground.y, ground.z));
      if (edge == null) continue;
      final px = (edge - centre).distance * (1.0 + h * 0.16);
      paint.color = Color.fromRGBO(2, 12, 18, opacity * fade * fade);
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: px * 2.0, height: px * 0.9),
        paint,
      );
    }
  }
}
