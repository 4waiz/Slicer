import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Every sound the game can play. Values map to `assets/audio/<id>.wav`.
enum Sfx {
  uiTap('ui_tap'),
  swipeStart('swipe_start'),
  bladeMove('blade_move'),
  cutCrystal('cut_crystal'),
  cutJelly('cut_jelly'),
  cutFruit('cut_fruit'),
  cutPlastic('cut_plastic'),
  cutMetal('cut_metal'),
  cutIce('cut_ice'),
  separation('separation'),
  landCorrect('land_correct'),
  landWrong('land_wrong'),
  percentTick('percent_tick'),
  combo('combo'),
  perfectCut('perfect_cut'),
  failure('failure'),
  levelComplete('level_complete'),
  reward('reward'),
  bladeUnlock('blade_unlock'),
  coreArm('core_arm'),
  coreBlast('core_blast');

  const Sfx(this.id);

  final String id;

  static Sfx byId(String id) =>
      Sfx.values.firstWhere((s) => s.id == id, orElse: () => Sfx.uiTap);
}

/// Pooled one-shot playback.
///
/// Audio is a polish layer, never a dependency: every entry point is wrapped
/// so a device with no working audio backend still plays the game.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  static const int _poolSize = 6;

  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _cursor = 0;
  bool _ready = false;
  bool _broken = false;

  bool soundEnabled = true;
  bool musicEnabled = true;
  double volume = 0.85;

  Future<void> init() async {
    if (_ready || _broken) return;
    try {
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer(playerId: 'ks_$i');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _pool.add(p);
      }
      _ready = true;
    } catch (e) {
      // No audio backend (some emulators, headless CI). Carry on silently.
      _broken = true;
      debugPrint('AudioService disabled: $e');
    }
  }

  void play(Sfx sfx, {double gain = 1.0}) {
    if (!soundEnabled || !_ready || _broken) return;
    unawaited(_playAsync(sfx, gain));
  }

  Future<void> _playAsync(Sfx sfx, double gain) async {
    try {
      final player = _pool[_cursor];
      _cursor = (_cursor + 1) % _pool.length;
      await player.stop();
      await player.setVolume((volume * gain).clamp(0.0, 1.0));
      await player.play(AssetSource('audio/${sfx.id}.wav'));
    } catch (_) {
      // A single failed one-shot must never break the frame loop.
    }
  }

  /// Convenience for material-specific cut sounds.
  void playCut(String soundId) => play(Sfx.byId(soundId));

  Future<void> dispose() async {
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    _ready = false;
  }
}
