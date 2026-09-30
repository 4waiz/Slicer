import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All persisted player state, behind one small API.
///
/// Everything is mirrored in memory so reads never await; writes are
/// fire-and-forget so saving cannot stall a frame.
class SaveData extends ChangeNotifier {
  SaveData._();

  static final SaveData instance = SaveData._();

  static const _kStars = 'stars';
  static const _kCoins = 'coins';
  static const _kUnlocked = 'unlocked';
  static const _kBlade = 'blade';
  static const _kOwnedBlades = 'owned_blades';
  static const _kSettings = 'settings';
  static const _kDaily = 'daily';
  static const _kMissions = 'missions';
  static const _kStats = 'stats';
  static const _kEndlessBest = 'endless_best';

  SharedPreferences? _prefs;
  bool get ready => _prefs != null;

  /// levelId -> stars (0..3)
  final Map<int, int> stars = <int, int>{};
  int coins = 0;
  int highestUnlocked = 1;
  String equippedBlade = 'silver';
  final Set<String> ownedBlades = <String>{'silver'};
  int endlessBest = 0;

  // Settings
  bool soundEnabled = true;
  bool musicEnabled = true;
  bool hapticsEnabled = true;
  bool reducedMotion = false;
  bool cameraShake = true;

  /// 0 = low, 1 = medium, 2 = high
  int graphicsQuality = 2;

  // Daily Slice
  String? lastDailyDate;
  int dailyStreak = 0;
  int dailyBestPercent = 0;

  /// missionId -> progress
  final Map<String, int> missionProgress = <String, int>{};

  /// Lifetime counters used by missions and the stats panel.
  final Map<String, int> stats = <String, int>{};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    try {
      final rawStars = p.getString(_kStars);
      if (rawStars != null) {
        final m = json.decode(rawStars) as Map<String, dynamic>;
        stars
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(int.parse(k), v as int)));
      }
      coins = p.getInt(_kCoins) ?? 0;
      highestUnlocked = p.getInt(_kUnlocked) ?? 1;
      equippedBlade = p.getString(_kBlade) ?? 'silver';
      endlessBest = p.getInt(_kEndlessBest) ?? 0;
      ownedBlades
        ..clear()
        ..addAll(p.getStringList(_kOwnedBlades) ?? const ['silver']);

      final s = p.getString(_kSettings);
      if (s != null) {
        final m = json.decode(s) as Map<String, dynamic>;
        soundEnabled = m['sound'] as bool? ?? true;
        musicEnabled = m['music'] as bool? ?? true;
        hapticsEnabled = m['haptics'] as bool? ?? true;
        reducedMotion = m['reducedMotion'] as bool? ?? false;
        cameraShake = m['shake'] as bool? ?? true;
        graphicsQuality = m['quality'] as int? ?? 2;
      }

      final d = p.getString(_kDaily);
      if (d != null) {
        final m = json.decode(d) as Map<String, dynamic>;
        lastDailyDate = m['date'] as String?;
        dailyStreak = m['streak'] as int? ?? 0;
        dailyBestPercent = m['best'] as int? ?? 0;
      }

      final ms = p.getString(_kMissions);
      if (ms != null) {
        final m = json.decode(ms) as Map<String, dynamic>;
        missionProgress
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, v as int)));
      }

      final st = p.getString(_kStats);
      if (st != null) {
        final m = json.decode(st) as Map<String, dynamic>;
        stats
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, v as int)));
      }
    } catch (e) {
      debugPrint('SaveData: ignoring corrupt save ($e)');
    }
    notifyListeners();
  }

  int starsFor(int levelId) => stars[levelId] ?? 0;

  bool isUnlocked(int levelId) => levelId <= highestUnlocked;

  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  int get levelsCompleted => stars.values.where((s) => s > 0).length;

  /// Records a completed attempt. Stars only ever go up.
  void recordLevel(
    int levelId,
    int newStars,
    int earnedCoins, {
    required int totalLevels,
  }) {
    final prev = stars[levelId] ?? 0;
    if (newStars > prev) stars[levelId] = newStars;
    coins += earnedCoins;
    if (newStars > 0 && levelId >= highestUnlocked) {
      highestUnlocked = (levelId + 1).clamp(1, totalLevels);
    }
    _saveProgress();
    notifyListeners();
  }

  void bump(String stat, [int by = 1]) {
    stats[stat] = (stats[stat] ?? 0) + by;
    _write(_kStats, json.encode(stats));
  }

  int stat(String key) => stats[key] ?? 0;

  void addCoins(int n) {
    coins += n;
    _prefs?.setInt(_kCoins, coins);
    notifyListeners();
  }

  bool spendCoins(int n) {
    if (coins < n) return false;
    coins -= n;
    _prefs?.setInt(_kCoins, coins);
    notifyListeners();
    return true;
  }

  void unlockBlade(String id) {
    ownedBlades.add(id);
    _prefs?.setStringList(_kOwnedBlades, ownedBlades.toList());
    notifyListeners();
  }

  void equipBlade(String id) {
    if (!ownedBlades.contains(id)) return;
    equippedBlade = id;
    _prefs?.setString(_kBlade, id);
    notifyListeners();
  }

  void setEndlessBest(int score) {
    if (score <= endlessBest) return;
    endlessBest = score;
    _prefs?.setInt(_kEndlessBest, score);
    notifyListeners();
  }

  void recordDaily(String date, int percent) {
    // A gap of more than one day breaks the streak.
    if (lastDailyDate != null) {
      final prev = DateTime.tryParse(lastDailyDate!);
      final now = DateTime.tryParse(date);
      if (prev != null && now != null) {
        dailyStreak = now.difference(prev).inDays == 1 ? dailyStreak + 1 : 1;
      } else {
        dailyStreak = 1;
      }
    } else {
      dailyStreak = 1;
    }
    lastDailyDate = date;
    if (percent > dailyBestPercent) dailyBestPercent = percent;
    _write(
      _kDaily,
      json.encode({
        'date': date,
        'streak': dailyStreak,
        'best': dailyBestPercent,
      }),
    );
    notifyListeners();
  }

  bool dailyDoneFor(String date) => lastDailyDate == date;

  void setMissionProgress(String id, int value) {
    missionProgress[id] = value;
    _write(_kMissions, json.encode(missionProgress));
    notifyListeners();
  }

  void saveSettings() {
    _write(
      _kSettings,
      json.encode({
        'sound': soundEnabled,
        'music': musicEnabled,
        'haptics': hapticsEnabled,
        'reducedMotion': reducedMotion,
        'shake': cameraShake,
        'quality': graphicsQuality,
      }),
    );
    notifyListeners();
  }

  void _saveProgress() {
    final p = _prefs;
    if (p == null) return;
    p.setString(_kStars, json.encode(stars.map((k, v) => MapEntry('$k', v))));
    p.setInt(_kCoins, coins);
    p.setInt(_kUnlocked, highestUnlocked);
  }

  void _write(String key, String value) => _prefs?.setString(key, value);

  /// Wipes everything -- used by the settings screen and by tests.
  Future<void> resetAll() async {
    await _prefs?.clear();
    stars.clear();
    missionProgress.clear();
    stats.clear();
    coins = 0;
    highestUnlocked = 1;
    equippedBlade = 'silver';
    ownedBlades
      ..clear()
      ..add('silver');
    endlessBest = 0;
    dailyStreak = 0;
    dailyBestPercent = 0;
    lastDailyDate = null;
    notifyListeners();
  }
}
