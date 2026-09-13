import '../domain/ability.dart';
import '../domain/models.dart';
import '../domain/platform_config.dart';
import '../domain/platform_plan.dart';
import '../domain/task_pool.dart';
import '../mock/mock_data.dart';
import '../mock/mock_extra.dart';
import '../mock/platform_plans.g.dart';

/// 平台公用唯讀資料的來源。
///
/// App 其餘部分只認這個介面，不知道動作庫、課表、成就、任務池、平台設定
/// 究竟來自打包在本地的生成檔（[BundledPlatformData]），還是 Firestore 上
/// 管理員維護的即時內容（[FirestorePlatformData]）—— 這正是 [BE-12] 要解的
/// 問題：管理員在後台改了東西，使用者端要真的看得到。
///
/// 與 `store.dart` 的 [Store] 是對等的兩條邊界：[Store] 管「使用者私有資料」，
/// 本介面管「平台公用資料」。兩者都讓 [AppState] 不必知道資料放在哪。
abstract class PlatformDataSource {
  /// 載入六類平台資料的當前快照。
  ///
  /// 正式環境失敗（離線、權限、格式不符）時**不該讓 App 起不來** ——
  /// 實作應自行退回本地後備，回傳一份可用的 [PlatformData]。
  Future<PlatformData> load();
}

/// 六類平台資料的一份快照。
///
/// 課表帶的是 [PlatformPlanSpec]（含詳情頁的長文內容），而非已經攤平成
/// 訓練用的 [WorkoutPlan] —— 攤平交給 [AppState.applyPlatformData]，
/// 這樣同一份 spec 既能驅動訓練流程，也能餵課表詳情頁。
class PlatformData {
  final List<Exercise> exercises;
  final List<PlatformPlanSpec> planSpecs;
  final List<Achievement> achievements;
  final List<TaskPoolItem> taskPool;

  /// 平台設定：groupId → (paramKey → value)。
  /// 獎勵定義亦在此（`reward` 群組），不另立集合。
  final Map<String, Map<String, num>> config;

  const PlatformData({
    required this.exercises,
    required this.planSpecs,
    required this.achievements,
    required this.taskPool,
    required this.config,
  });
}

/// 打包在本地的平台資料 —— 預設來源。
///
/// 測試與離線皆走這條：直接回傳生成檔與 build function 的內容，
/// 與既有 `AppState` 建構時的種子完全一致，因此不注入任何來源的測試
/// 行為一個位元都不變（比照 [BE-05] 的 mock 邊界）。
class BundledPlatformData implements PlatformDataSource {
  const BundledPlatformData();

  @override
  Future<PlatformData> load() async => PlatformData(
        exercises: List.of(kExercises),
        planSpecs: List.of(kPlatformPlans),
        achievements: buildAchievements(),
        taskPool: buildTaskPool(),
        config: {
          for (final g in platformConfig.groups)
            g.id: {for (final p in g.params) p.key: p.value},
        },
      );
}

// ===========================================================================
// 序列化 / 反序列化
//
// Firestore 文件形狀的唯一權威定義。tools/ 的上傳腳本（Python 與 Dart 匯出）
// 必須產生與此處 `*FromDoc` 相符的形狀。命名沿用 Firestore-Schema設計.md §3：
// 欄位 camelCase、enum 存 `.name`。
// ===========================================================================

Map<String, dynamic> exerciseToMap(Exercise e) => {
      'name': e.name,
      'dim': e.dim?.name,
      'parts': [for (final p in e.parts) p.name],
      'relativeIntensity': e.relativeIntensity,
      'isBodyweight': e.isBodyweight,
      'type': e.type.name,
      'equipment': e.equipment,
      if (e.defaultRestSeconds != null)
        'defaultRestSeconds': e.defaultRestSeconds,
    };

Exercise exerciseFromDoc(String id, Map<String, dynamic> m) => Exercise(
      id: id,
      name: m['name'] as String,
      dim: m['dim'] == null ? null : Dim.values.byName(m['dim'] as String),
      parts: {
        for (final p in (m['parts'] as List? ?? const []))
          Dim.values.byName(p as String),
      },
      relativeIntensity: (m['relativeIntensity'] as num).toDouble(),
      isBodyweight: m['isBodyweight'] as bool? ?? false,
      type: ExerciseType.values.byName(m['type'] as String? ?? 'strength'),
      equipment: m['equipment'] as String? ?? '徒手',
      defaultRestSeconds: (m['defaultRestSeconds'] as num?)?.toInt(),
    );

Map<String, dynamic> planSpecToMap(PlatformPlanSpec s) => {
      'name': s.name,
      'level': s.level,
      'requiredRank': s.requiredRank,
      'equipmentTier': s.equipmentTier,
      'duration': s.duration,
      'intro': s.intro,
      'howTo': s.howTo,
      'load': s.load,
      'effect': s.effect,
      'technique': s.technique,
      'reference': s.reference,
      'items': [
        for (final it in s.items)
          {
            'exerciseId': it.exerciseId,
            'sets': it.sets,
            'amount': it.amount,
            'unit': it.unit.name,
            'restSeconds': it.restSeconds,
          },
      ],
    };

PlatformPlanSpec planSpecFromDoc(String id, Map<String, dynamic> m) =>
    PlatformPlanSpec(
      id: id,
      name: m['name'] as String,
      level: m['level'] as String,
      requiredRank: (m['requiredRank'] as num?)?.toInt(),
      equipmentTier: m['equipmentTier'] as String,
      duration: m['duration'] as String? ?? '',
      intro: m['intro'] as String? ?? '',
      howTo: m['howTo'] as String? ?? '',
      load: m['load'] as String? ?? '',
      effect: m['effect'] as String? ?? '',
      technique: m['technique'] as String? ?? '',
      reference: m['reference'] as String? ?? '',
      items: [
        for (final it in (m['items'] as List? ?? const []))
          PlanItemSpec(
            (it as Map)['exerciseId'] as String,
            (it['sets'] as num).toInt(),
            (it['amount'] as num).toInt(),
            PlanUnit.values.byName(it['unit'] as String? ?? 'reps'),
            (it['restSeconds'] as num).toInt(),
          ),
      ],
    );

/// 成就定義的 doc id 沿用既有 `category#threshold` 邏輯（見 Schema §2.6）——
/// 用索引的話成就表一改順序，已解鎖紀錄就會套到別的成就上。
String achievementDocId(Achievement a) => '${a.category}#${a.threshold}';

Map<String, dynamic> achievementToMap(Achievement a) => {
      'category': a.category,
      'name': a.name,
      'threshold': a.threshold,
      'rewardCoins': a.rewardCoins,
      'rewardExp': a.rewardExp,
    };

/// 只還原「定義」欄位；unlocked／claimed／unlockedAt 是使用者私有狀態，
/// 不在平台定義裡（那些由 [Store] 那條邊界負責）。
Achievement achievementFromDoc(String id, Map<String, dynamic> m) => Achievement(
      category: m['category'] as String,
      name: m['name'] as String,
      threshold: (m['threshold'] as num).toInt(),
      rewardCoins: (m['rewardCoins'] as num).toInt(),
      rewardExp: (m['rewardExp'] as num).toInt(),
    );

Map<String, dynamic> taskPoolItemToMap(TaskPoolItem t) => {
      'name': t.name,
      'sourceEvent': t.sourceEvent,
      'target': t.target,
      'audience': t.audience.name,
      'rewardId': t.rewardId,
    };

TaskPoolItem taskPoolItemFromDoc(String id, Map<String, dynamic> m) =>
    TaskPoolItem(
      id: id,
      name: m['name'] as String,
      sourceEvent: m['sourceEvent'] as String,
      target: (m['target'] as num).toInt(),
      audience:
          TaskAudience.values.byName(m['audience'] as String? ?? 'personal'),
      rewardId: m['rewardId'] as String? ?? 'daily',
    );
