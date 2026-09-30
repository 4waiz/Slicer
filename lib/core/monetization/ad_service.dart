import 'package:flutter/foundation.dart';

/// Placements the game can request.
enum AdPlacement {
  rewardedHint,
  rewardedExtraCut,
  rewardedDoubleCoins,
  interstitial,
}

/// Monetization behind configuration flags.
///
/// Deliberately an interface with a no-op default: nothing about the game
/// depends on ads succeeding, and no network SDK is linked unless a build
/// explicitly enables it via `--dart-define`. If a provider is wired in and
/// fails at runtime, every call still returns a sane result and play continues.
class AdService extends ChangeNotifier {
  AdService._();

  static final AdService instance = AdService._();

  /// Master switch. Off unless a build passes `--dart-define=ADS_ENABLED=true`.
  static const bool _adsEnabledFlag = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: false,
  );

  /// Production unit IDs come from the environment; debug builds use the
  /// well-known Google test IDs so no real inventory is ever requested.
  static const String rewardedUnitId = String.fromEnvironment(
    'AD_UNIT_REWARDED',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );
  static const String interstitialUnitId = String.fromEnvironment(
    'AD_UNIT_INTERSTITIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  bool _removedAds = false;
  int _levelsSinceInterstitial = 0;

  /// Ads are disabled entirely when the flag is off or the player has paid.
  bool get enabled => _adsEnabledFlag && !_removedAds && !kDebugMode;

  bool get removedAds => _removedAds;

  /// The provider hook. Left null in shipped builds; a concrete provider can
  /// be installed at startup without touching any call site.
  Future<bool> Function(AdPlacement placement)? provider;

  Future<void> init() async {
    // No SDK to initialise in the default configuration.
  }

  /// Requests a rewarded ad. Returns whether the reward should be granted.
  ///
  /// With no provider installed the reward is granted anyway -- a cosmetic
  /// or convenience bonus must never be withheld because ads are unavailable.
  Future<bool> showRewarded(AdPlacement placement) async {
    if (!enabled || provider == null) return true;
    try {
      return await provider!(placement);
    } catch (e) {
      debugPrint('Rewarded ad failed, granting anyway: $e');
      return true;
    }
  }

  /// Interstitials are heavily rate-limited by design:
  /// never during a slice, never after a failure, never in the first three
  /// levels, and never more than once every three completed levels.
  Future<void> maybeShowInterstitial({
    required int levelId,
    required bool passed,
  }) async {
    if (!enabled || !passed || levelId <= 3) return;
    _levelsSinceInterstitial++;
    if (_levelsSinceInterstitial < 3) return;
    _levelsSinceInterstitial = 0;
    try {
      await provider?.call(AdPlacement.interstitial);
    } catch (e) {
      debugPrint('Interstitial failed, ignoring: $e');
    }
  }

  void setRemovedAds(bool value) {
    _removedAds = value;
    notifyListeners();
  }

  /// Store integration point. No-op without a billing provider.
  Future<void> restorePurchases() async {
    notifyListeners();
  }
}
