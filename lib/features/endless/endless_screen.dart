import 'package:flutter/widgets.dart';

import '../../app/app.dart';
import '../../core/persistence/save_data.dart';
import '../../game/levels/generators.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/model_preview.dart';
import '../../shared/widgets/stage_backdrop.dart';
import '../gameplay/gameplay_screen.dart';

/// Endless Slicing Lab: procedural rounds of rising complexity. A failed
/// round ends the run; the multiplier grows while the streak survives.
class EndlessScreen extends StatefulWidget {
  const EndlessScreen({super.key});

  @override
  State<EndlessScreen> createState() => _EndlessScreenState();
}

class _EndlessScreenState extends State<EndlessScreen> {
  int _round = 0;
  int _score = 0;
  int _multiplier = 1;
  bool _running = false;

  void _startRun() {
    setState(() {
      _round = 1;
      _score = 0;
      _multiplier = 1;
      _running = true;
    });
    _playRound();
  }

  void _playRound() {
    // Seed from the run's starting score so a run is reproducible in-session.
    final level = endlessLevel(_round, _round * 31 + 17);
    var roundScore = 0;
    var passed = false;

    pushScreen(
      context,
      GameplayScreen(
        level: level,
        modeLabel: 'ROUND $_round  x$_multiplier',
        recordProgress: false,
        onAttemptResolved: (r) {
          roundScore = (r.accuracy * 1000).round() * _multiplier;
          passed = r.passed;
        },
        onExit: () => Navigator.of(context).maybePop(),
        onNext: (_) => Navigator.of(context).maybePop(),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _score += roundScore;
        if (passed) {
          _round++;
          _multiplier = (_multiplier + 1).clamp(1, 9);
        } else {
          _running = false;
          SaveData.instance.setEndlessBest(_score);
          SaveData.instance.bump('endless_runs');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) => MenuScaffold(
        title: 'ENDLESS SLICING LAB',
        subtitle: 'BEST ${save.endlessBest}',
        accent: K.orange,
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _running ? 'RUN IN PROGRESS' : 'READY',
                    style: K.display(22, color: K.orange, track: 5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat('SCORE', '$_score', K.white),
                      const SizedBox(width: 28),
                      _Stat('ROUND', '$_round', K.orange),
                      const SizedBox(width: 28),
                      _Stat('MULTIPLIER', 'x$_multiplier', K.yellow),
                      const SizedBox(width: 28),
                      _Stat('BEST', '${save.endlessBest}', K.cyan),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 400,
                    child: Text(
                      'STRUCTURES ARE GENERATED FRESH EACH ROUND. '
                      'PADS MULTIPLY, ROTATION QUICKENS, AND FIELDS APPEAR. '
                      'ONE FAILED ROUND ENDS THE RUN.',
                      style: K.label(9.5, color: K.textDim, track: 1.4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      KButton(
                        label: _running ? 'Continue Run' : 'Start Run',
                        color: K.orange,
                        wide: true,
                        onTap: _running ? _playRound : _startRun,
                      ),
                      if (_running) ...[
                        const SizedBox(width: 12),
                        KButton(
                          label: 'End Run',
                          color: K.steel,
                          onTap: () {
                            SaveData.instance.setEndlessBest(_score);
                            setState(() => _running = false);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: ModelPreview(
                model: endlessLevel(
                  _running ? _round : 1,
                  _running ? _round * 31 + 17 : 48,
                ).model,
                spin: 0.45,
                fill: 0.66,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: K.label(9, color: K.textDim, track: 2)),
      const SizedBox(height: 4),
      Text(value, style: K.number(22, color: color)),
    ],
  );
}
