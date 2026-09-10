/// 平台課表的資料規格。
///
/// 由《健身計劃.csv》產生（見 tools/gen_platform_plans.py），
/// 與 [WorkoutPlan] 分開是刻意的：
///
/// [WorkoutPlan] 是**訓練時要用的東西** —— 動作、組數、目標值，
/// 進了訓練流程就只需要這些。這裡多帶的是**課表的說明性內容**：
/// 介紹、使用說明、負荷、訓練效果、技術特點、學理依據。
/// 那些是課表詳情頁要呈現的，訓練中一個字都用不到。
/// 合成一個類別的話，`WorkoutPlan` 會被六段長文字撐大，
/// 而每一次訓練都要拖著它們走。
library;

/// 一組的計量單位。
///
/// 時間型動作（棒式、登山者式、開合跳）以秒計，不是次數。
/// App 的既有慣例是把秒數放在 `PlannedSet.targetReps` —— 見加入動作時的
/// `PlannedSet(0, _seconds)`。這個列舉讓「那個數字是什麼」不必用猜的。
enum PlanUnit { reps, seconds }

/// 課表裡的一個動作。
class PlanItemSpec {
  /// 對應 `kPlatformExercises` 的動作 ID。
  final String exerciseId;
  final int sets;

  /// 每組的次數或秒數，依 [unit] 判讀。
  final int amount;
  final PlanUnit unit;
  final int restSeconds;

  const PlanItemSpec(
    this.exerciseId,
    this.sets,
    this.amount,
    this.unit,
    this.restSeconds,
  );
}

/// 一份平台課表。
class PlatformPlanSpec {
  final String id;
  final String name;

  /// 學員級 / 戰士級 / 精銳級 / 功能重啟級。
  final String level;

  /// 階級門檻。空值為不設限。
  final int? requiredRank;
  final String equipmentTier;

  /// 以下六段為課表詳情頁的內容，原樣取自資料來源。
  final String duration;
  final String intro;
  final String howTo;
  final String load;
  final String effect;
  final String technique;

  /// 學理依據。**這一欄不可為空** —— 一份說得出依據的課表與一份
  /// 憑空編的課表，對使用者是兩件不同的東西。
  final String reference;

  final List<PlanItemSpec> items;

  const PlatformPlanSpec({
    required this.id,
    required this.name,
    required this.level,
    required this.requiredRank,
    required this.equipmentTier,
    required this.duration,
    required this.intro,
    required this.howTo,
    required this.load,
    required this.effect,
    required this.technique,
    required this.reference,
    required this.items,
  });
}
