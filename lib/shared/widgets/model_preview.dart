import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../game/camera/camera3d.dart';
import '../../game/renderer/mesh.dart';
import '../../game/renderer/model_cache.dart';
import '../../game/renderer/scene_renderer.dart';

/// A slowly rotating 3D model, used for the home hero and the blade shop.
class ModelPreview extends StatefulWidget {
  const ModelPreview({
    super.key,
    required this.model,
    this.spin = 0.42,
    this.tiltX = 0.16,
    this.fill = 0.72,
    this.tint,
    this.glowBoost = 0.0,
    this.scale = 1.0,
  });

  final String model;
  final double spin;
  final double tiltX;
  final double fill;
  final Color? tint;
  final double glowBoost;
  final double scale;

  @override
  State<ModelPreview> createState() => _ModelPreviewState();
}

class _ModelPreviewState extends State<ModelPreview>
    with SingleTickerProviderStateMixin {
  final Camera3D _camera = Camera3D();
  final SceneRenderer _renderer = SceneRenderer();
  final Lighting _light = Lighting(rimStrength: 0.7);
  Ticker? _ticker;
  MeshData? _mesh;
  RenderNode? _node;
  double _t = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(ModelPreview old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      _mesh = null;
      _node = null;
      _load();
    }
    if (old.tint != widget.tint && _node != null) {
      _node!
        ..tint = widget.tint
        ..tintAmount = widget.tint == null ? 0.0 : 0.65;
    }
  }

  Future<void> _load() async {
    try {
      final m = await ModelCache.instance.load(widget.model);
      if (!mounted) return;
      setState(() {
        _mesh = m;
        _node = RenderNode(
          mesh: m,
          glowBoost: widget.glowBoost,
          tint: widget.tint,
          tintAmount: widget.tint == null ? 0.0 : 0.65,
          castShadow: false,
          scale: widget.scale,
        );
      });
    } catch (_) {
      // A missing preview must never take down the screen it sits on.
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _t += dt;
    if (_node != null) {
      _node!.orientation =
          Quaternion.axisAngle(Vector3(0, 1, 0), _t * widget.spin) *
          Quaternion.axisAngle(Vector3(1, 0, 0), widget.tiltX);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = _mesh;
    final node = _node;
    if (mesh == null || node == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        _camera.setViewport(size);
        final r = mesh.boundingRadius * widget.scale;
        final dist = _camera.distanceToFit(r, fill: widget.fill);
        _camera.lookAt(Vector3(0, dist * 0.22, dist), Vector3.zero());
        return CustomPaint(
          size: size,
          painter: _PreviewPainter(_camera, _renderer, [node], _light),
        );
      },
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.camera, this.renderer, this.nodes, this.light);

  final Camera3D camera;
  final SceneRenderer renderer;
  final List<RenderNode> nodes;
  final Lighting light;

  @override
  void paint(Canvas canvas, Size size) =>
      renderer.render(canvas, camera, nodes, light);

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
