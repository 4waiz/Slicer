import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/audio/audio_service.dart';
import 'core/haptics/haptics.dart';
import 'core/persistence/save_data.dart';
import 'game/renderer/model_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Landscape only -- the stage is composed around a wide frame.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final save = SaveData.instance;
  await save.load();

  AudioService.instance
    ..soundEnabled = save.soundEnabled
    ..musicEnabled = save.musicEnabled;
  Haptics.instance.enabled = save.hapticsEnabled;

  // Warm the models the first screen needs so the hero does not pop in.
  ModelCache.instance
      .preload(const [
        'kanban_core_structure.glb',
        'default_blade.glb',
        'pad_cyan.glb',
        'pad_green.glb',
      ])
      .catchError((_) {});

  await AudioService.instance.init();

  runApp(const KanbanSlicerApp());
}
