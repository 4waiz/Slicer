import 'package:flutter/widgets.dart';

import '../../app/app.dart';
import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/persistence/save_data.dart';
import '../../game/levels/campaign.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/model_preview.dart';
import '../../shared/widgets/stage_backdrop.dart';
import '../daily/daily_screen.dart';
import '../endless/endless_screen.dart';
import '../level_select/level_select_screen.dart';
import '../missions/missions_screen.dart';
import '../settings/settings_screen.dart';
import '../shop/shop_screen.dart';
import '../gameplay/gameplay_screen.dart';

/// Landscape home: hero structure on the right, actions on the left.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) {
        final pad = MediaQuery.paddingOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            const StageBackdrop(),
            Positioned(
              right: -20,
              top: 0,
              bottom: 0,
              width: MediaQuery.sizeOf(context).width * 0.52,
              child: const ModelPreview(
                model: 'kanban_core_structure.glb',
                spin: 0.36,
                fill: 0.62,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: pad.left + 26,
                right: pad.right + 20,
                top: pad.top + 16,
                bottom: pad.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(save: save),
                  const Spacer(),
                  Text('KANBAN', style: K.display(46, track: 12)),
                  const SizedBox(height: 2),
                  Text(
                    'SLICER',
                    style: K.display(46, color: K.cyan, track: 12),
                  ),
                  const SizedBox(height: 10),
                  Container(width: 190, height: 2, color: K.orange),
                  const SizedBox(height: 10),
                  Text(
                    'CUT THROUGH COMPLEXITY',
                    style: K.label(11, color: K.textDim, track: 4.4),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      KButton(
                        label: 'Play',
                        wide: true,
                        onTap: () => _play(context, save),
                      ),
                      const SizedBox(width: 12),
                      KButton(
                        label: 'Levels',
                        color: K.purple,
                        onTap: () {
                          Haptics.instance.uiTap();
                          pushScreen(context, const LevelSelectScreen());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _MiniButton(
                        label: 'DAILY',
                        colour: K.yellow,
                        badge: save.dailyStreak > 0
                            ? '${save.dailyStreak}'
                            : null,
                        onTap: () => pushScreen(context, const DailyScreen()),
                      ),
                      const SizedBox(width: 9),
                      _MiniButton(
                        label: 'ENDLESS',
                        colour: K.orange,
                        onTap: () => pushScreen(context, const EndlessScreen()),
                      ),
                      const SizedBox(width: 9),
                      _MiniButton(
                        label: 'MISSIONS',
                        colour: K.green,
                        onTap: () =>
                            pushScreen(context, const MissionsScreen()),
                      ),
                      const SizedBox(width: 9),
                      _MiniButton(
                        label: 'BLADES',
                        colour: K.cyan,
                        onTap: () => pushScreen(context, const ShopScreen()),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'LEVEL ${save.highestUnlocked.clamp(1, levelCount)} OF $levelCount'
                    '   ·   ${save.totalStars} / ${levelCount * 3} STARS',
                    style: K.label(9.5, color: K.textDim, track: 2.2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _play(BuildContext context, SaveData save) {
    Haptics.instance.uiTap();
    AudioService.instance.play(Sfx.uiTap);
    final id = save.highestUnlocked.clamp(1, levelCount);
    final level = levelById(id) ?? allLevels.first;
    pushScreen(
      context,
      GameplayScreen(
        level: level,
        onExit: () => Navigator.of(context).maybePop(),
        onNext: (_) {
          Navigator.of(context).maybePop();
          pushScreen(context, const LevelSelectScreen());
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.save});

  final SaveData save;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AngularPanel(
        cut: 8,
        color: K.panel.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZoneGlyph(shape: 'diamond', color: K.yellow, size: 13),
            const SizedBox(width: 8),
            Text('${save.coins}', style: K.number(14, color: K.yellow)),
          ],
        ),
      ),
      const SizedBox(width: 9),
      AngularPanel(
        cut: 8,
        color: K.panel.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StarRow(stars: 1, max: 1, size: 13),
            const SizedBox(width: 8),
            Text('${save.totalStars}', style: K.number(14)),
          ],
        ),
      ),
      const Spacer(),
      GestureDetector(
        onTap: () {
          Haptics.instance.uiTap();
          pushScreen(context, const SettingsScreen());
        },
        child: AngularPanel(
          cut: 8,
          color: K.panel.withValues(alpha: 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text('SETTINGS', style: K.label(10, color: K.steel)),
        ),
      ),
    ],
  );
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.colour,
    required this.onTap,
    this.badge,
  });

  final String label;
  final Color colour;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      Haptics.instance.uiTap();
      AudioService.instance.play(Sfx.uiTap);
      onTap();
    },
    child: AngularPanel(
      cut: 8,
      color: colour.withValues(alpha: 0.13),
      border: colour.withValues(alpha: 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: K.label(10, color: colour, track: 1.8)),
          if (badge != null) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              color: colour,
              child: Text(badge!, style: K.number(9, color: K.bgDeep)),
            ),
          ],
        ],
      ),
    ),
  );
}
