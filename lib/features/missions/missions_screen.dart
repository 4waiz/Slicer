import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/persistence/save_data.dart';
import '../../game/scoring/missions.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/stage_backdrop.dart';

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) {
        final claimable = claimableCount(save);
        return MenuScaffold(
          title: 'MISSIONS',
          subtitle: claimable > 0
              ? '$claimable READY TO CLAIM'
              : 'ONGOING GOALS',
          accent: K.green,
          trailing: AngularPanel(
            cut: 8,
            color: K.panel.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ZoneGlyph(shape: 'diamond', color: K.yellow, size: 12),
                const SizedBox(width: 7),
                Text('${save.coins}', style: K.number(13, color: K.yellow)),
              ],
            ),
          ),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 460,
              mainAxisExtent: 74,
              crossAxisSpacing: 12,
              mainAxisSpacing: 10,
            ),
            itemCount: missions.length,
            itemBuilder: (context, i) =>
                _MissionCard(mission: missions[i], save: save),
          ),
        );
      },
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission, required this.save});

  final Mission mission;
  final SaveData save;

  @override
  Widget build(BuildContext context) {
    final done = mission.isComplete(save);
    final claimed = mission.isClaimed(save);
    final accent = claimed ? K.steel : (done ? K.green : K.cyan);

    return AngularPanel(
      cut: 10,
      color: K.panel.withValues(alpha: 0.8),
      border: accent.withValues(alpha: claimed ? 0.3 : 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  mission.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: K.label(10, color: K.white, track: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          children: [
                            Container(color: K.bgDeep),
                            FractionallySizedBox(
                              widthFactor: mission
                                  .fraction(save)
                                  .clamp(0.0, 1.0),
                              child: Container(color: accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '${mission.progressFor(save)}/${mission.target}',
                      style: K.number(10, color: K.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (claimed)
            Text('CLAIMED', style: K.label(9, color: K.steel, track: 1.4))
          else if (done)
            KButton(
              label: '+${mission.reward}',
              color: K.yellow,
              compact: true,
              onTap: () {
                Haptics.instance.correct();
                AudioService.instance.play(Sfx.reward);
                claimMission(mission, save);
              },
            )
          else
            Text('+${mission.reward}', style: K.number(12, color: K.textDim)),
        ],
      ),
    );
  }
}
