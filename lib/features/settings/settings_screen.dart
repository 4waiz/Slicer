import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/monetization/ad_service.dart';
import '../../core/persistence/save_data.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/stage_backdrop.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmReset = false;

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) => MenuScaffold(
        title: 'SETTINGS',
        accent: K.steel,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Toggle(
                    label: 'SOUND EFFECTS',
                    value: save.soundEnabled,
                    onChanged: (v) {
                      save.soundEnabled = v;
                      AudioService.instance.soundEnabled = v;
                      save.saveSettings();
                    },
                  ),
                  _Toggle(
                    label: 'MUSIC',
                    value: save.musicEnabled,
                    onChanged: (v) {
                      save.musicEnabled = v;
                      AudioService.instance.musicEnabled = v;
                      save.saveSettings();
                    },
                  ),
                  _Toggle(
                    label: 'HAPTICS',
                    value: save.hapticsEnabled,
                    onChanged: (v) {
                      save.hapticsEnabled = v;
                      Haptics.instance.enabled = v;
                      save.saveSettings();
                    },
                  ),
                  _Toggle(
                    label: 'REDUCED MOTION',
                    value: save.reducedMotion,
                    onChanged: (v) {
                      save.reducedMotion = v;
                      save.saveSettings();
                    },
                  ),
                  _Toggle(
                    label: 'CAMERA SHAKE',
                    value: save.cameraShake,
                    onChanged: (v) {
                      save.cameraShake = v;
                      save.saveSettings();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Segmented(
                    label: 'GRAPHICS QUALITY',
                    options: const ['LOW', 'MEDIUM', 'HIGH'],
                    index: save.graphicsQuality,
                    onChanged: (i) {
                      save.graphicsQuality = i;
                      save.saveSettings();
                    },
                  ),
                  const SizedBox(height: 14),
                  AngularPanel(
                    cut: 9,
                    color: K.panel.withValues(alpha: 0.7),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRIVACY',
                          style: K.label(10, color: K.cyan, track: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'KANBAN SLICER STORES PROGRESS ONLY ON THIS DEVICE. '
                          'NO ACCOUNT IS REQUIRED AND NO PERSONAL DATA IS '
                          'COLLECTED OR TRANSMITTED. ADVERTISING IS '
                          '${AdService.instance.enabled ? "ENABLED" : "DISABLED"} '
                          'IN THIS BUILD.',
                          style: K.label(8.5, color: K.textDim, track: 1.1),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            KButton(
                              label: 'Restore Purchases',
                              color: K.steel,
                              compact: true,
                              onTap: () =>
                                  AdService.instance.restorePurchases(),
                            ),
                            const SizedBox(width: 10),
                            KButton(
                              label: _confirmReset
                                  ? 'Confirm Wipe'
                                  : 'Reset Progress',
                              color: _confirmReset ? K.red : K.steel,
                              compact: true,
                              onTap: () {
                                if (_confirmReset) {
                                  save.resetAll();
                                  setState(() => _confirmReset = false);
                                } else {
                                  setState(() => _confirmReset = true);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'KANBAN SLICER  ·  V1.0.0  ·  KANBAN STUDIOS',
                    style: K.label(8.5, color: K.stroke, track: 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: GestureDetector(
      onTap: () {
        Haptics.instance.uiTap();
        onChanged(!value);
      },
      child: AngularPanel(
        cut: 8,
        color: K.panel.withValues(alpha: 0.72),
        border: value ? K.cyan.withValues(alpha: 0.6) : K.stroke,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Text(label, style: K.label(10, color: K.white, track: 1.8)),
            const Spacer(),
            Container(
              width: 40,
              height: 16,
              color: value ? K.cyan.withValues(alpha: 0.25) : K.bgDeep,
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 16,
                  color: value ? K.cyan : K.stroke,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => AngularPanel(
    cut: 8,
    color: K.panel.withValues(alpha: 0.72),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        Text(label, style: K.label(10, color: K.white, track: 1.8)),
        const Spacer(),
        for (var i = 0; i < options.length; i++)
          GestureDetector(
            onTap: () {
              Haptics.instance.uiTap();
              onChanged(i);
            },
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: i == index ? K.cyan.withValues(alpha: 0.3) : K.bgDeep,
              child: Text(
                options[i],
                style: K.label(
                  9,
                  color: i == index ? K.cyan : K.textDim,
                  track: 1.2,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
