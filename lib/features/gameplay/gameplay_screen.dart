import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/persistence/save_data.dart';
import '../../game/game_controller.dart';
import '../../game/levels/campaign.dart';
import '../../game/levels/level_def.dart';
import '../../game/scoring/scoring.dart';
import '../../shared/theme/app_theme.dart';
import 'game_view.dart';

/// One playable attempt: 3D stage, HUD, and the result / failure overlays.
class GameplayScreen extends StatefulWidget {
  const GameplayScreen({
    super.key,
    required this.level,
    this.onExit,
    this.onNext,
    this.onAttemptResolved,
    this.recordProgress = true,
    this.modeLabel,
  });

  final LevelDef level;
  final VoidCallback? onExit;
  final void Function(LevelResult result)? onNext;

  /// Fires every time an attempt resolves, whether the player continues,
  /// retries or backs out. Modes that score outside the campaign use this.
  final void Function(LevelResult result)? onAttemptResolved;

  /// Daily and Endless score differently, so they opt out of campaign saves.
  final bool recordProgress;
  final String? modeLabel;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with SingleTickerProviderStateMixin {
  late GameController _controller;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  int _failStreak = 0;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _controller = GameController(level: widget.level, onResolved: _onResolved);
    _controller.load();
    _ticker?.dispose();
    _last = Duration.zero;
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    if (_paused) {
      _last = elapsed;
      return;
    }
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // Clamp so a dropped frame cannot teleport the simulation.
    _controller.update(dt.clamp(0.0, 1 / 20));
  }

  void _onResolved(LevelResult r) {
    if (_recorded) return;
    _recorded = true;

    final save = SaveData.instance;
    if (widget.recordProgress) {
      save.recordLevel(
        widget.level.id,
        r.stars,
        r.coins,
        totalLevels: levelCount,
      );
    } else if (r.coins > 0) {
      save.addCoins(r.coins);
    }

    save.bump('cuts', r.cutsUsed);
    save.bump('levels_played');
    if (r.passed) save.bump('levels_won');
    if (r.perfect) save.bump('perfect_cuts');
    if (r.stars >= 3) save.bump('three_stars');
    if (r.cutsUsed == 1 && r.passed) save.bump('one_cut_wins');
    if (r.accuracy >= 0.95) save.bump('high_accuracy');
    save.bump('pieces_landed', r.zones.fold(0, (a, z) => a + z.correctPieces));
    save.bump('material_${widget.level.defaultKind.id}');

    _failStreak = r.passed ? 0 : _failStreak + 1;
    widget.onAttemptResolved?.call(r);

    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    Haptics.instance.uiTap();
    AudioService.instance.play(Sfx.uiTap);
    _recorded = false;
    setState(() => _paused = false);
    await _controller.restart();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.phase;
        return Stack(
          fit: StackFit.expand,
          children: [
            GameView(controller: _controller),
            if (phase == GamePhase.loading) const _LoadingVeil(),
            if (phase == GamePhase.error)
              _ErrorVeil(
                message: _controller.errorMessage ?? 'unknown',
                onBack: widget.onExit,
              ),
            if (phase != GamePhase.loading && phase != GamePhase.error)
              _Hud(
                controller: _controller,
                modeLabel: widget.modeLabel,
                onPause: () => setState(() => _paused = true),
              ),
            if (phase == GamePhase.ready && widget.level.hint != null)
              _HintBanner(text: widget.level.hint!),
            if (phase == GamePhase.resolved && _controller.result != null)
              _ResultOverlay(
                level: widget.level,
                result: _controller.result!,
                failStreak: _failStreak,
                onRetry: _retry,
                onNext: () => widget.onNext?.call(_controller.result!),
                onExit: widget.onExit,
              ),
            if (_paused)
              _PauseOverlay(
                onResume: () => setState(() => _paused = false),
                onRetry: _retry,
                onExit: widget.onExit,
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _Hud extends StatelessWidget {
  const _Hud({required this.controller, required this.onPause, this.modeLabel});

  final GameController controller;
  final VoidCallback onPause;
  final String? modeLabel;

  @override
  Widget build(BuildContext context) {
    final level = controller.level;
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: pad.left + 16,
        right: pad.right + 16,
        top: pad.top + 12,
        bottom: pad.bottom + 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AngularPanel(
                cut: 9,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                color: K.panel.withValues(alpha: 0.86),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      modeLabel ?? 'LEVEL ${level.id}',
                      style: K.label(12, color: K.cyan),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 13, color: K.stroke),
                    const SizedBox(width: 10),
                    Text(level.name, style: K.label(12, color: K.white)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CutPips(used: controller.cutsUsed, total: level.allowedCuts),
              const Spacer(),
              _AccuracyMeter(value: controller.liveAccuracy, level: level),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onPause,
                child: AngularPanel(
                  cut: 8,
                  color: K.panel.withValues(alpha: 0.86),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  child: const _PauseGlyph(),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (kDebugMode)
            Align(
              alignment: Alignment.centerLeft,
              child: AngularPanel(
                cut: 6,
                color: K.bgDeep.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  '${controller.fps.toStringAsFixed(0)} FPS · '
                  '${controller.lastTriangles} TRI · '
                  '${controller.nodeCount} NODES · '
                  '${controller.pieceCount} PIECES · '
                  'PAINT ${controller.paintTicks}@'
                  '${controller.lastPaintSize.width.toStringAsFixed(0)}x'
                  '${controller.lastPaintSize.height.toStringAsFixed(0)} · '
                  '${controller.cullReport} · '
                  '${controller.phase.name.toUpperCase()} · CAM '
                  '${controller.camera.position.x.toStringAsFixed(1)},'
                  '${controller.camera.position.y.toStringAsFixed(1)},'
                  '${controller.camera.position.z.toStringAsFixed(1)} · FWD '
                  '${controller.camera.forward.x.toStringAsFixed(2)},'
                  '${controller.camera.forward.y.toStringAsFixed(2)},'
                  '${controller.camera.forward.z.toStringAsFixed(2)} · N '
                  '${controller.nodes.map((n) => "${n.mesh.triCount}@"
                      "${n.position.x.toStringAsFixed(1)},"
                      "${n.position.y.toStringAsFixed(1)},"
                      "${n.position.z.toStringAsFixed(1)}"
                      "${n.visible ? "" : "!"}").join(" ")}',
                  style: K.label(8, color: K.textDim, track: 1),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final z in level.zones)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _ZoneChip(zone: z, result: _resultFor(z.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  ZoneResult? _resultFor(String id) {
    final r = controller.result;
    if (r == null) return null;
    for (final z in r.zones) {
      if (z.zoneId == id) return z;
    }
    return null;
  }
}

class _CutPips extends StatelessWidget {
  const _CutPips({required this.used, required this.total});

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    return AngularPanel(
      cut: 8,
      color: K.panel.withValues(alpha: 0.86),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CUTS', style: K.label(10, color: K.textDim)),
          const SizedBox(width: 8),
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 11,
                height: 3.5,
                decoration: BoxDecoration(
                  color: i < (total - used) ? K.cyan : K.stroke,
                  boxShadow: i < (total - used)
                      ? [
                          BoxShadow(
                            color: K.cyan.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccuracyMeter extends StatelessWidget {
  const _AccuracyMeter({required this.value, required this.level});

  final double value;
  final LevelDef level;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    final colour = value >= level.threeStar
        ? K.white
        : value >= level.twoStar
        ? K.green
        : value >= level.minSuccess
        ? K.cyan
        : K.steel;
    return AngularPanel(
      cut: 8,
      color: K.panel.withValues(alpha: 0.86),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 4,
            child: Stack(
              children: [
                Container(color: K.bgDeep),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colour,
                      boxShadow: [
                        BoxShadow(
                          color: colour.withValues(alpha: 0.7),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: K.number(15, color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.zone, this.result});

  final ZoneDef zone;
  final ZoneResult? result;

  @override
  Widget build(BuildContext context) {
    final c = K.zoneColor(zone.colorKey);
    final fill = result?.fill ?? 0.0;
    final bad = result?.isContaminated ?? false;
    return AngularPanel(
      cut: 7,
      color: K.panel.withValues(alpha: 0.8),
      border: bad ? K.red : c.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZoneGlyph(shape: zone.shape, color: bad ? K.red : c, size: 13),
          const SizedBox(width: 7),
          Text(
            '${(fill * 100).round()}%',
            style: K.number(11, color: bad ? K.red : K.white),
          ),
          if (zone.isBonus) ...[
            const SizedBox(width: 5),
            Text('BONUS', style: K.label(8, color: K.yellow, track: 1.2)),
          ],
        ],
      ),
    );
  }
}

class _PauseGlyph extends StatelessWidget {
  const _PauseGlyph();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 13,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(width: 3.2, color: K.white),
        Container(width: 3.2, color: K.white),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Overlays
// ---------------------------------------------------------------------------

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, 0.74),
    child: AngularPanel(
      cut: 9,
      color: K.bgDeep.withValues(alpha: 0.78),
      border: K.cyan.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Text(
        text.toUpperCase(),
        style: K.label(10.5, color: K.cyan, track: 1.6),
      ),
    ),
  );
}

class _LoadingVeil extends StatelessWidget {
  const _LoadingVeil();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: K.bgDeep,
    child: Center(
      child: Text('LOADING', style: K.label(13, color: K.cyan, track: 6)),
    ),
  );
}

class _ErrorVeil extends StatelessWidget {
  const _ErrorVeil({required this.message, this.onBack});

  final String message;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: K.bgDeep,
    child: Center(
      child: AngularPanel(
        border: K.red,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LEVEL FAILED TO LOAD',
              style: K.label(13, color: K.red, track: 3),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 380,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: K.label(10, color: K.textDim, track: 0.4),
              ),
            ),
            const SizedBox(height: 18),
            KButton(label: 'Back', onTap: onBack ?? () {}, color: K.steel),
          ],
        ),
      ),
    ),
  );
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onRetry,
    this.onExit,
  });

  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: K.bgDeep.withValues(alpha: 0.86),
    child: Center(
      child: AngularPanel(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        glow: K.cyan.withValues(alpha: 0.25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PAUSED', style: K.display(26, track: 8)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KButton(label: 'Resume', onTap: onResume),
                const SizedBox(width: 12),
                KButton(label: 'Retry', onTap: onRetry, color: K.yellow),
                const SizedBox(width: 12),
                KButton(
                  label: 'Levels',
                  onTap: onExit ?? () {},
                  color: K.steel,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.level,
    required this.result,
    required this.failStreak,
    required this.onRetry,
    required this.onNext,
    this.onExit,
  });

  final LevelDef level;
  final LevelResult result;
  final int failStreak;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final passed = result.passed;
    final accent = result.perfect
        ? K.white
        : passed
        ? K.green
        : K.red;

    return Align(
      alignment: Alignment.center,
      child: AngularPanel(
        cut: 18,
        color: K.bg.withValues(alpha: 0.95),
        border: accent,
        glow: accent.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Scorer.grade(result),
              style: K.display(
                result.perfect ? 30 : 24,
                color: accent,
                track: 6,
              ),
            ),
            const SizedBox(height: 12),
            StarRow(stars: result.stars, size: 30),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stat(
                  label: 'ACCURACY',
                  value: '${result.percent}%',
                  color: accent,
                ),
                _Divider(),
                _Stat(
                  label: 'CUTS',
                  value: '${result.cutsUsed}/${level.allowedCuts}',
                ),
                _Divider(),
                _Stat(
                  label: 'COINS',
                  value: passed ? '+${result.coins}' : '0',
                  color: passed ? K.yellow : K.textDim,
                ),
                if (level.bonus != BonusGoal.none) ...[
                  _Divider(),
                  _Stat(
                    label: 'BONUS',
                    value: result.bonusAchieved ? 'YES' : 'NO',
                    color: result.bonusAchieved ? K.yellow : K.textDim,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final z in result.zones)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _ZoneResultChip(
                      zone: level.zoneById(z.zoneId)!,
                      result: z,
                    ),
                  ),
              ],
            ),
            if (!passed && failStreak >= 2 && level.hint != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 400,
                child: Text(
                  'HINT  ${level.hint!.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: K.label(9.5, color: K.cyan, track: 1.2),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KButton(
                  label: 'Levels',
                  onTap: onExit ?? () {},
                  color: K.steel,
                ),
                const SizedBox(width: 10),
                KButton(label: 'Retry', onTap: onRetry, color: K.yellow),
                if (passed) ...[
                  const SizedBox(width: 10),
                  KButton(label: 'Continue', onTap: onNext, wide: true),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color = K.white});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: K.label(9, color: K.textDim, track: 1.8)),
      const SizedBox(height: 5),
      Text(value, style: K.number(19, color: color)),
    ],
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: 18),
    color: K.stroke,
  );
}

class _ZoneResultChip extends StatelessWidget {
  const _ZoneResultChip({required this.zone, required this.result});

  final ZoneDef zone;
  final ZoneResult result;

  @override
  Widget build(BuildContext context) {
    final c = K.zoneColor(zone.colorKey);
    final bad = result.isContaminated;
    final good = result.isPerfect;
    return AngularPanel(
      cut: 6,
      color: (bad ? K.red : c).withValues(alpha: 0.14),
      border: bad ? K.red : (good ? c : K.stroke),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZoneGlyph(shape: zone.shape, color: bad ? K.red : c, size: 11),
          const SizedBox(width: 6),
          Text(
            '${(result.fill * 100).round()}%',
            style: K.number(10.5, color: bad ? K.red : K.white),
          ),
        ],
      ),
    );
  }
}
