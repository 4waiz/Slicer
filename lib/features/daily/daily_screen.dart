import 'package:flutter/widgets.dart';

import '../../app/app.dart';
import '../../core/persistence/save_data.dart';
import '../../game/levels/generators.dart';
import '../../game/levels/level_def.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/model_preview.dart';
import '../../shared/widgets/stage_backdrop.dart';
import '../gameplay/gameplay_screen.dart';

/// One deterministic puzzle per calendar day, with a streak.
///
/// The level is derived from the UTC date, so it needs no server and works
/// offline -- everyone playing on the same day gets the same structure.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late final DateTime _today = DateTime.now().toUtc();
  late final LevelDef _level = dailyLevel(_today);
  late final String _key = dailyKey(_today);

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) {
        final done = save.dailyDoneFor(_key);
        return MenuScaffold(
          title: 'DAILY SLICE',
          subtitle: _key,
          accent: K.yellow,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      done ? 'COMPLETED TODAY' : 'TODAY\'S CHALLENGE',
                      style: K.display(
                        22,
                        color: done ? K.green : K.white,
                        track: 5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _Stat('STREAK', '${save.dailyStreak}', K.yellow),
                        const SizedBox(width: 26),
                        _Stat('BEST', '${save.dailyBestPercent}%', K.cyan),
                        const SizedBox(width: 26),
                        _Stat('CUTS', '${_level.allowedCuts}', K.white),
                        const SizedBox(width: 26),
                        _Stat('PADS', '${_level.zones.length}', K.purple),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 380,
                      child: Text(
                        'A NEW SEEDED STRUCTURE EVERY DAY. '
                        'MATERIAL: ${_level.defaultKind.label}. '
                        'COME BACK TOMORROW TO EXTEND YOUR STREAK.',
                        style: K.label(9.5, color: K.textDim, track: 1.4),
                      ),
                    ),
                    const SizedBox(height: 24),
                    KButton(
                      label: done ? 'Play Again' : 'Start Daily',
                      color: done ? K.steel : K.yellow,
                      wide: true,
                      onTap: () => _start(save),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: ModelPreview(model: _level.model, spin: 0.4, fill: 0.66),
              ),
            ],
          ),
        );
      },
    );
  }

  void _start(SaveData save) {
    var best = -1;
    pushScreen(
      context,
      GameplayScreen(
        level: _level,
        modeLabel: 'DAILY',
        recordProgress: false,
        // Keep the best attempt of the session; retries should not lower it.
        onAttemptResolved: (r) {
          if (r.percent > best) best = r.percent;
        },
        onExit: () => Navigator.of(context).maybePop(),
        onNext: (_) => Navigator.of(context).maybePop(),
      ),
    ).then((_) {
      if (best >= 0) {
        save.recordDaily(_key, best);
        save.bump('daily_done');
      }
      if (mounted) setState(() {});
    });
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
