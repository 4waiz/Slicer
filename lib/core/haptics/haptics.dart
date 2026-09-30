import 'package:flutter/services.dart';

/// Haptic vocabulary for the slice loop.
///
/// Uses the platform channel directly rather than a plugin, so it adds no
/// dependency and degrades to nothing where unsupported.
class Haptics {
  Haptics._();

  static final Haptics instance = Haptics._();

  bool enabled = true;

  /// Light pulse while the player is drawing the swipe.
  void swipeTick() => _run(HapticFeedback.selectionClick);

  /// Medium pulse at blade contact.
  void contact() => _run(HapticFeedback.mediumImpact);

  /// Small pulse for a correct landing.
  void correct() => _run(HapticFeedback.lightImpact);

  /// Error pulse for a wrong landing.
  void wrong() => _run(HapticFeedback.vibrate);

  /// Strong pulse for a perfect cut.
  void perfect() => _run(HapticFeedback.heavyImpact);

  void uiTap() => _run(HapticFeedback.selectionClick);

  void _run(Future<void> Function() f) {
    if (!enabled) return;
    // Fire and forget -- a missing vibrator must not stall the frame.
    f().catchError((_) {});
  }
}
