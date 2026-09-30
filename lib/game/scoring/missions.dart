import '../../core/persistence/save_data.dart';

/// A long-running goal tracked across sessions.
class Mission {
  const Mission({
    required this.id,
    required this.title,
    required this.stat,
    required this.target,
    required this.reward,
  });

  final String id;
  final String title;

  /// Key in [SaveData.stats] this mission counts.
  final String stat;
  final int target;
  final int reward;

  int progressFor(SaveData s) => s.stat(stat).clamp(0, target);

  bool isComplete(SaveData s) => s.stat(stat) >= target;

  /// Claimed missions store their reward flag under the mission id.
  bool isClaimed(SaveData s) => (s.missionProgress[id] ?? 0) == 1;

  double fraction(SaveData s) => target == 0 ? 0 : progressFor(s) / target;
}

const List<Mission> missions = [
  Mission(
    id: 'm_perfect3',
    title: 'ACHIEVE THREE PERFECT CUTS',
    stat: 'perfect_cuts',
    target: 3,
    reward: 120,
  ),
  Mission(
    id: 'm_crystal10',
    title: 'SLICE TEN CRYSTAL STRUCTURES',
    stat: 'material_crystal',
    target: 10,
    reward: 90,
  ),
  Mission(
    id: 'm_land500',
    title: 'LAND 500 PIECES CORRECTLY',
    stat: 'pieces_landed',
    target: 500,
    reward: 240,
  ),
  Mission(
    id: 'm_onecut5',
    title: 'FINISH FIVE LEVELS WITH ONE CUT',
    stat: 'one_cut_wins',
    target: 5,
    reward: 150,
  ),
  Mission(
    id: 'm_acc95',
    title: 'COMPLETE A LEVEL ABOVE 95%',
    stat: 'high_accuracy',
    target: 1,
    reward: 80,
  ),
  Mission(
    id: 'm_threestar10',
    title: 'EARN THREE STARS ON TEN LEVELS',
    stat: 'three_stars',
    target: 10,
    reward: 200,
  ),
  Mission(
    id: 'm_daily',
    title: 'COMPLETE THE DAILY CHALLENGE',
    stat: 'daily_done',
    target: 1,
    reward: 100,
  ),
  Mission(
    id: 'm_win25',
    title: 'COMPLETE TWENTY-FIVE LEVELS',
    stat: 'levels_won',
    target: 25,
    reward: 300,
  ),
  Mission(
    id: 'm_jelly8',
    title: 'SLICE EIGHT JELLY STRUCTURES',
    stat: 'material_jelly',
    target: 8,
    reward: 90,
  ),
  Mission(
    id: 'm_metal8',
    title: 'SLICE EIGHT MECHANICAL STRUCTURES',
    stat: 'material_metal',
    target: 8,
    reward: 110,
  ),
];

/// Claims a completed mission's reward exactly once. Returns coins granted.
int claimMission(Mission m, SaveData save) {
  if (!m.isComplete(save) || m.isClaimed(save)) return 0;
  save.setMissionProgress(m.id, 1);
  save.addCoins(m.reward);
  return m.reward;
}

int claimableCount(SaveData save) =>
    missions.where((m) => m.isComplete(save) && !m.isClaimed(save)).length;
