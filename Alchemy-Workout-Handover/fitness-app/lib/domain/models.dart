import 'ability.dart';
import 'commerce.dart' show kPlanUnlockCoins;
import 'rewards.dart';

/// 動作類型。所屬肌群為空值當且僅當類型為有氧。
enum ExerciseType { strength, cardio }

const exerciseTypeNames = <ExerciseType, String>{
  ExerciseType.strength: '重訓',
  ExerciseType.cardio: '有氧',
};

/// 徒手動作的體重係數（暫行規則）。
///
/// 規格：**徒手動作代入重量 ＝ 實際體重 × 該動作的體重係數 ＋ 外加負重**
/// （伏地挺身 0.6、引體向上 1.0）。規格只給了這兩個例子，其餘 135 個徒手動作的係數
/// 沒有人給過；之前程式一律當 1.0，伏地挺身等於整個體重都在推，單組分數比 60 kg 槓鈴臥推還高
/// （2026-10-16 使用者回報「練個徒手動作加分超多」）。
///
/// 使用者裁決 B（2026-10-16）：先用簡單規則止血 —— 引體向上類 1.0，其餘徒手動作 0.6。
/// **這是暫行值，不是逐動作校準過的**；逐動作的係數表待內容團隊給（見 PROGRESS `[QA-04]`）。
const double kBodyweightFactorPullUp = 1.0;
const double kBodyweightFactorDefault = 0.6;

/// 動作庫的一筆動作。相對強度係數將不同動作拉到同一尺度。
class Exercise {
  final String id;
  final String name;
  /// **所屬肌群 —— 能力值歸屬**。單一值，有氧動作為空值。
  /// 「能力值的提升依動作所屬肌群，只提升該動作對應的維度」。
  final Dim? dim;

  /// **訓練部位 —— 分頁與篩選歸屬**。複選，一個動作可練到多個部位。
  ///
  /// 與 [dim] 分開兩個欄位，而非把 [dim] 改成複選：模型明訂
  /// 「所屬肌群欄位同時承載能力值歸屬與分頁歸屬 —— 一個欄位兩種語意，
  /// 日後必然衝突」。本欄只服務動作庫分頁、器材篩選與部位統計，
  /// **不參與能力值計算**。空集合時退回 [dim] 單值。
  final Set<Dim> parts;
  final double relativeIntensity;
  final bool isBodyweight;

  /// 重訓 / 有氧。有氧不進六維能力值、不計耐力值、不計總訓練量。
  final ExerciseType type;

  /// 所需器材 —— 動作庫的每筆項目欄位之一，供器材篩選比對。
  final String equipment;

  /// 自建動作。僅建立者本人可見，且不計入能力值。
  final bool isCustom;

  /// 預設組間休息秒數 —— 動作層級屬性，不逐組設定。
  /// 平台動作庫由管理員於後台設定，自建動作由建立者設定；未設定者退回全站預設。
  final int? defaultRestSeconds;

  /// 體重係數：算能力值時，徒手動作拿 `體重 × 這個係數` 當作推的重量（再加外加負重）。
  /// 非徒手動作不用體重，固定 1.0 只是不讓它被誤用。暫行規則見 [kBodyweightFactorDefault]。
  double get bodyweightFactor => !isBodyweight
      ? 1.0
      : (name.contains('引體向上')
          ? kBodyweightFactorPullUp
          : kBodyweightFactorDefault);

  /// 重量欄填的是「每手」重量嗎？啞鈴是 —— 使用者習慣的是啞鈴上寫的那個數字（單顆）。
  ///
  /// 相對強度係數是照單顆重量校準的（2026-10-17 使用者裁決：啞鈴填每手）；
  /// 若填兩手加總，重量多一倍，分數直接爆表（啞鈴臥推 28 kg ＝ 999）。
  /// 畫面要把「每手」寫出來，不然使用者無從知道。
  bool get weightIsPerHand => equipment.split(' ＋ ').first.contains('啞鈴');

  /// 這個動作會出現在哪些肌群分頁。未指定訓練部位者退回所屬肌群。
  Set<Dim> get tabs => parts.isNotEmpty ? parts : (dim == null ? const {} : {dim!});

  const Exercise({
    required this.id,
    required this.name,
    required this.dim,
    required this.relativeIntensity,
    this.isBodyweight = false,
    this.parts = const {},
    this.type = ExerciseType.strength,
    this.equipment = '徒手',
    this.isCustom = false,
    this.defaultRestSeconds,
  });
}

/// 一組的計量單位 —— 次數或秒數。
///
/// **這個值原本只活在 `PlatformPlanSpec.PlanItemSpec` 裡，轉成
/// [WorkoutPlan] 時就被丟掉了。** 於是畫面只能靠「目標重量是 0」來猜
/// 那個數字是次數還是秒數 —— 而平台課表的目標重量**一律是 0**
/// （以 RPE 開處方，不指定公斤數），徒手動作也是。
/// 結果是「引體向上 3 組 × 8 下」被顯示成「8 秒」。
///
/// 猜不出來的東西就不要猜：把單位一路帶著走。
///
/// 值域是 per-plan-item 而非 per-exercise —— 資料來源的 27 份課表裡
/// 有 21 個動作同時以兩種單位出現（棒式既有「40 秒」也有「12 下」）。
enum PlanUnit { reps, seconds }

/// 本次訓練課表快照中的一組目標。
class PlannedSet {
  final double targetWeight;
  final int targetReps;
  const PlannedSet(this.targetWeight, this.targetReps);
}

/// 各組完成狀態（6 值列舉，取自訓練紀錄 Aggregate 的組紀錄）。
enum SetState { pending, active, resting, done, cancelled, skipped }

/// 一筆已取消的組紀錄，連同它屬於哪一組。
class CancelledSet {
  final int exerciseIndex;
  final int setIndex;
  final SetRecord record;
  final DateTime at;
  const CancelledSet({
    required this.exerciseIndex,
    required this.setIndex,
    required this.record,
    required this.at,
  });
}

/// 一組的實際紀錄。已取消的組紀錄不產生獨立列，畫面不呈現取消痕跡。
class SetRecord {
  double weight;
  int reps;
  SetState state;
  SetRecord({required this.weight, required this.reps, this.state = SetState.pending});
}

class PlanExercise {
  final Exercise exercise;
  final List<PlannedSet> planned;
  /// 該動作為「AI 已替換動作」的結果時有值，可展開檢視原動作。
  final Exercise? replacedFrom;

  /// 原動作的逐組目標。**還原時要一併還原它** ——
  /// 規格明訂「還原為原動作，**含其各組的目標重量與次數**」
  /// （〈訓練紀錄流程〉的還原路徑 Postcondition）。
  /// 只存 `replacedFrom` 的話，還原回去的是替代動作的重量，
  /// 那個重量是為了另一個動作算的。
  final List<PlannedSet>? replacedPlanned;

  /// 課表指定的組間休息秒數 —— 取值優先序的第一順位，空值則退回動作層級預設。
  final int? restSeconds;

  /// 這個動作的組以什麼計量。預設次數 —— 絕大多數動作是。
  final PlanUnit unit;

  const PlanExercise({
    required this.exercise,
    required this.planned,
    this.replacedFrom,
    this.replacedPlanned,
    this.restSeconds,
    this.unit = PlanUnit.reps,
  });

  bool get isTimed => unit == PlanUnit.seconds;
}

class WorkoutPlan {
  final String id;
  final String name;
  final PlanSource source;
  final int? requiredRank; // 所需階級；空值為初階
  final List<PlanExercise> exercises;
  final DateTime? lastTrainedAt;
  final double? lastCompletion;
  final bool hasOptimizationSuggestion;
  final String equipmentTier;

  /// 這份計畫開不開放金幣提前購買。建構時給的數字只當「開放」的記號，**價格不讀它**。
  final int? _unlockMarker;

  /// 金幣提前購買的解鎖價格。空值者不呈現該解鎖方式（〈未解鎖進階計畫的呈現〉）。
  ///
  /// **價格一律讀全站統一定價**（`kPlanUnlockCoins`，平台設定「進階訓練計畫解鎖價格」）。
  /// 規格是統一定價、不逐計畫區分；原本每份課表各存一個數字，管理員改了平台設定，
  /// 課表的實際售價卻不動（2026-10-15 實測，使用者裁決 A）。
  int? get unlockCoins => _unlockMarker == null ? null : kPlanUnlockCoins;

  /// 雲端與規格上存的那個記號值（寫回雲端用，**不是售價**）。
  int? get unlockMarker => _unlockMarker;

  /// 會員身分可直接解鎖。
  final bool memberUnlockable;

  /// 適用條件：適用的健身經驗與常見目標。
  /// 兩者引用註冊問卷的同一份值域清單，供〈訓練計畫已推薦〉比對。
  /// 空集合代表不限。
  final Set<String> suitableExperience;
  final Set<String> suitableGoals;

  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.source,
    required this.exercises,
    this.requiredRank,
    this.lastTrainedAt,
    this.lastCompletion,
    this.hasOptimizationSuggestion = false,
    this.equipmentTier = '徒手',
    int? unlockCoins,
    this.memberUnlockable = false,
    this.suitableExperience = const {},
    this.suitableGoals = const {},
  }) : _unlockMarker = unlockCoins;

  int get totalSets => exercises.fold(0, (a, e) => a + e.planned.length);

  /// 自訂訓練（含已公開者）須呈現來源免責標示。
  String? get disclaimer =>
      (source == PlanSource.publishedCustom || source == PlanSource.privateCustom)
          ? '本課表由使用者提供，平台不對其安全性負責'
          : null;
}

/// 訓練進行中的可變狀態。
class WorkoutSession {
  /// 來源課表。快照產生後即與它脫鉤 —— 來源課表事後被修改或下架，
  /// 進行中的訓練不受影響。
  final WorkoutPlan plan;
  /// 本次訓練開始的時點。
  ///
  /// **不是 final，只為了測試**（`@visibleForTesting` 的
  /// `AppState.backdateSession`）。獎勵有「不到 5 分鐘不發」的門檻，
  /// 而測試是開始之後立刻結束的 —— 真實時間幾乎沒走，每一場都會被
  /// 判成太短。正式流程從頭到尾不會改它。
  DateTime startedAt;

  /// **本次訓練課表快照**。加入動作只改這裡，不改來源課表，
  /// 亦不改任何自訂訓練 Aggregate。
  final List<PlanExercise> exercises;

  /// 列的來源為（動作 × 組序），一組永遠只有一列。
  final List<List<SetRecord>> records;

  /// 已取消的組紀錄。**不實體刪除** —— 「使用者已取消該組」已經發生，
  /// 若資料看不出曾經取消過，Event 與 Aggregate 互相矛盾；
  /// 且「取消 → 降重量 → 重做」正是 AI 判讀紀錄合理性最有價值的訊號。
  ///
  /// 它們不進 [records]：畫面不呈現取消痕跡，列的來源仍為（動作 × 組序）。
  /// 同一組因此可有多筆組紀錄 —— 取消後再次勾選時**新建一筆**，
  /// 原筆維持已取消。
  final List<CancelledSet> cancelled = [];
  int exerciseIndex = 0;
  int setIndex = 0;

  WorkoutSession({
    required this.plan,
    required this.startedAt,
    required this.exercises,
    required this.records,
  });

  /// [targets] 為逐動作逐組的快照目標值（帶入或推算的結果）。
  /// 未提供時退回來源課表的目標值 —— 僅供不需要帶入的測試與工具使用。
  factory WorkoutSession.start(
    WorkoutPlan plan,
    DateTime now, {
    List<List<PlannedSet>>? targets,
  }) {
    final planned = [
      for (var i = 0; i < plan.exercises.length; i++)
        (targets != null && i < targets.length)
            ? targets[i]
            : plan.exercises[i].planned,
    ];
    return WorkoutSession(
      plan: plan,
      startedAt: now,
      // 空白課表為合法的初始狀態：總計畫組數 0、來源課表 ID 為空值。
      // 快照持有自己的目標值，來源課表不受影響。
      exercises: [
        for (var i = 0; i < plan.exercises.length; i++)
          PlanExercise(
            exercise: plan.exercises[i].exercise,
            planned: planned[i],
            replacedFrom: plan.exercises[i].replacedFrom,
            restSeconds: plan.exercises[i].restSeconds,
            unit: plan.exercises[i].unit,
          ),
      ],
      records: [
        for (final sets in planned)
          [
            for (final s in sets)
              SetRecord(weight: s.targetWeight, reps: s.targetReps),
          ],
      ],
    );
  }

  /// 空白課表 —— 來源類型為空白課表者無來源課表 ID。
  bool get isBlank => plan.source == PlanSource.blank;

  int get plannedSets =>
      exercises.fold(0, (a, e) => a + e.planned.length);
  int get doneSets => records.fold(
      0, (a, l) => a + l.where((r) => r.state == SetState.done).length);

  /// 進度百分比不要求單調遞增（AI 調整可使分母變動）。
  double get progress => plannedSets == 0 ? 0 : doneSets / plannedSets;

  /// 本次累計訓練量（純呈現用的統計數值，不餵給任何計分機制）。
  double get volume {
    var v = 0.0;
    for (final l in records) {
      for (final r in l) {
        if (r.state == SetState.done) v += r.weight * r.reps;
      }
    }
    return v;
  }
}

// --- 遊戲化外圍 ---

class Achievement {
  final String category;
  final String name;
  final int threshold;
  final int rewardCoins;
  final int rewardExp;
  bool unlocked;
  bool claimed;
  DateTime? unlockedAt;
  Achievement({
    required this.category,
    required this.name,
    required this.threshold,
    required this.rewardCoins,
    required this.rewardExp,
    this.unlocked = false,
    this.claimed = false,
    this.unlockedAt,
  });
}

class DailyTask {
  final String name;
  final String sourceEvent; // 判定來源 Event
  final int target;
  int progress;
  bool claimed;
  DailyTask({
    required this.name,
    required this.sourceEvent,
    required this.target,
    this.progress = 0,
    this.claimed = false,
  });
  bool get done => progress >= target;
}

class LeaderboardEntry {
  final int position;
  final String name;
  final int score;
  final bool isSelf;
  const LeaderboardEntry(this.position, this.name, this.score, {this.isSelf = false});
}

/// 自訂訓練名額隨階級成長：2 → 3（階級 25）→ 4（45）→ 5（70）。
///
/// **沿用進階訓練計畫的階級里程碑**：升到該階時一次取得兩樣東西 ——
/// 解鎖新課表 ＋ 多一個自訂訓練名額，且只需記一組數字。
///
/// 不採固定值：固定 3 個會擋到「在兩個場所訓練」這種生活現實；
/// 固定 5 個則付費牆過弱。會員權益的賣點因此由「你只有 N 個」
/// 轉為「你不必等半年」。
const kCustomPlanMilestones = <int>[25, 45, 70];

int customPlanQuotaForRank(int rank, {required int base, required int max}) {
  var n = base;
  for (final m in kCustomPlanMilestones) {
    if (rank >= m) n += 1;
  }
  return n > max ? max : n;
}
