import 'ability.dart';

/// 分享貼文附帶的訓練成果卡。
///
/// 原本只有一行字（「課表名 · 總重量 · 組數」），別人看不出這場練得怎麼樣。
/// 這裡改成結構化的欄位，畫面才畫得出完成度、練了哪些動作、階級有沒有提升。
///
/// **隱私在建立時就決定了，不是顯示時才藏。** 卡片會存進雲端、所有人讀得到，
/// 不公開能力值的人，卡片裡就不能有六維成長的數字（見 `AppState.shareWorkout`）。
class WorkoutCard {
  final String planName;
  final double volumeKg;
  final int doneSets;
  final int plannedSets;
  final int durationMinutes;
  final int streakDays;

  /// 這場有做的動作與完成組數（沒完成任何一組的不列）。
  final List<WorkoutCardExercise> exercises;

  /// 階級提升（沒提升就都是空值）。階級本來就是公開資訊，貼文旁邊一直顯示著。
  final int? rankFrom;
  final int? rankTo;

  /// 各維的能力值成長。**空＝沒有成長，或使用者不公開能力值。**
  final Map<Dim, int> abilityGains;

  /// 這場訓練造成的成就解鎖（名稱）。
  final List<String> achievements;

  const WorkoutCard({
    required this.planName,
    required this.volumeKg,
    required this.doneSets,
    required this.plannedSets,
    required this.durationMinutes,
    required this.streakDays,
    this.exercises = const [],
    this.rankFrom,
    this.rankTo,
    this.abilityGains = const {},
    this.achievements = const [],
  });

  /// 完成度（整數百分比）。計畫組數為 0（自由訓練）時沒有意義，回空值。
  int? get completionPercent =>
      plannedSets == 0 ? null : (doneSets * 100 / plannedSets).round();

  bool get rankedUp => rankFrom != null && rankTo != null && rankTo! > rankFrom!;

  /// 單行摘要 —— 舊版畫面與搜尋用，也是貼文上 `attachedWorkout` 的內容。
  String get summaryLine =>
      '$planName　·　${volumeKg.round()} kg　·　$doneSets 組';

  Map<String, dynamic> toJson() => {
        'planName': planName,
        'volumeKg': volumeKg,
        'doneSets': doneSets,
        'plannedSets': plannedSets,
        'durationMinutes': durationMinutes,
        'streakDays': streakDays,
        // Firestore 不收陣列裡再放陣列：每個動作一個小物件。
        'exercises': [
          for (final e in exercises) {'name': e.name, 'sets': e.sets},
        ],
        if (rankedUp) 'rankFrom': rankFrom,
        if (rankedUp) 'rankTo': rankTo,
        if (abilityGains.isNotEmpty)
          'abilityGains': {
            for (final e in abilityGains.entries) e.key.name: e.value,
          },
        'achievements': achievements,
      };

  /// 讀回。**格式不對就回空值**，畫面退回只有一行字的舊樣子，不讓一則貼文拖垮動態牆。
  static WorkoutCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['planName'];
    if (name is! String) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).round() : 0;
    final gains = <Dim, int>{};
    final g = raw['abilityGains'];
    if (g is Map) {
      for (final d in Dim.values) {
        final v = g[d.name];
        if (v is num && v > 0) gains[d] = v.round();
      }
    }
    return WorkoutCard(
      planName: name,
      volumeKg: raw['volumeKg'] is num ? (raw['volumeKg'] as num).toDouble() : 0,
      doneSets: n('doneSets'),
      plannedSets: n('plannedSets'),
      durationMinutes: n('durationMinutes'),
      streakDays: n('streakDays'),
      exercises: [
        for (final e in (raw['exercises'] as List? ?? const []))
          if (e is Map && e['name'] is String)
            WorkoutCardExercise(
              e['name'] as String,
              e['sets'] is num ? (e['sets'] as num).round() : 0,
            ),
      ],
      rankFrom: raw['rankFrom'] is num ? (raw['rankFrom'] as num).round() : null,
      rankTo: raw['rankTo'] is num ? (raw['rankTo'] as num).round() : null,
      abilityGains: gains,
      achievements: [
        for (final a in (raw['achievements'] as List? ?? const []))
          if (a is String) a,
      ],
    );
  }
}

class WorkoutCardExercise {
  final String name;
  final int sets;
  const WorkoutCardExercise(this.name, this.sets);
}
