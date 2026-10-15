import '../domain/ability.dart';
import '../domain/admin.dart';
import '../domain/models.dart';
import '../domain/platform_config.dart';
import '../domain/platform_plan.dart';
import '../domain/task_pool.dart';
import '../mock/mock_data.dart';
import '../mock/mock_admin.dart';
import '../mock/mock_extra.dart';

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
  /// 管理端改了一筆，寫回去。
  ///
  /// **在此之前 `[BE-12]` 只做了讀的那一半** —— 後台改完只改記憶體，
  /// 下次登入就從雲端重新載入、打回原形。使用者 2026-09-28 測 P123
  /// 當場撞到（「改的值變回原本的」）。
  ///
  /// 失敗就讓它拋 —— 呼叫端要把「沒寫上去」講給管理員聽，
  /// 而不是吞掉之後讓他以為存好了。
  Future<void> put(String collection, String docId, Map<String, dynamic> data);

  /// 管理端刪了一筆（目前只有每日任務池用得到）。
  Future<void> remove(String collection, String docId);

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

  /// 商城商品（含已下架者，後台要看得到）。**打包的內建商品與雲端按 id 合併**：
  /// 雲端有的以雲端為準（包括被下架），沒有的沿用內建。空清單＝這次不更動目前的商品。
  final List<AdminProduct> products;

  const PlatformData({
    required this.exercises,
    required this.planSpecs,
    required this.achievements,
    required this.taskPool,
    required this.config,
    this.products = const [],
  });
}

/// 打包在本地的平台資料 —— 預設來源。
///
/// 測試與離線皆走這條：直接回傳生成檔與 build function 的內容，
/// 與既有 `AppState` 建構時的種子完全一致，因此不注入任何來源的測試
/// 行為一個位元都不變（比照 [BE-05] 的 mock 邊界）。
class BundledPlatformData implements PlatformDataSource {
  /// **後備來源是唯讀的。** 它就是打包在 App 裡的那份常數，寫不進去。
  ///
  /// 不拋例外而是靜靜什麼都不做：它同時是「沒接雲端」時的來源，
  /// 而既有的一千多個測試都走這條 —— 在那裡拋例外等於把測試全部弄紅，
  /// 而它們本來就不在驗雲端寫入。
  @override
  Future<void> put(String c, String id, Map<String, dynamic> d) async {}

  @override
  Future<void> remove(String c, String id) async {}

  const BundledPlatformData();

  @override
  Future<PlatformData> load() async => PlatformData(
        exercises: List.of(kExercises),
        planSpecs: List.of(kAllPlanSpecs),
        achievements: buildAchievements(),
        taskPool: buildTaskPool(),
        config: {
          for (final g in platformConfig.groups)
            g.id: {for (final p in g.params) p.key: p.value},
        },
        products: buildAdminProducts(),
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

/// 商品的雲端文件形狀（`products/{id}`）。
///
/// 庫存只是**上架條件與顯示用**：使用者買東西不會改這個數字（使用者端沒有被信任的寫入權，
/// 共用庫存得靠伺服器，使用者 2026-10-15 裁決 A）。
Map<String, dynamic> productToMap(AdminProduct p) => {
      'name': p.name,
      'emoji': p.emoji,
      'images': p.images,
      'subtype': p.subtype?.name,
      'unlockTarget': p.unlockTarget,
      'listing': p.listing.name,
      'aiCredits': p.aiCredits,
      'note': p.note,
      'specs': [
        for (final s in p.specs)
          {'name': s.name, 'price': s.price, 'stock': s.stock},
      ],
    };

AdminProduct productFromDoc(String id, Map<String, dynamic> m) => AdminProduct(
      id: id,
      name: m['name'] as String,
      emoji: m['emoji'] as String? ?? '🛒',
      images: [for (final v in (m['images'] as List? ?? const [])) v as String],
      subtype: m['subtype'] == null
          ? null
          : VirtualSubtype.values.byName(m['subtype'] as String),
      unlockTarget: m['unlockTarget'] as String?,
      listing: ListingState.values.byName(m['listing'] as String? ?? 'delisted'),
      aiCredits: (m['aiCredits'] as num?)?.toInt() ?? 0,
      note: m['note'] as String?,
      specs: [
        for (final s in (m['specs'] as List? ?? const []))
          AdminProductSpec((s as Map)['name'] as String,
              (s['price'] as num).toInt(), (s['stock'] as num).toInt()),
      ],
    );

Map<String, dynamic> planSpecToMap(PlatformPlanSpec s) => {
      'name': s.name,
      'level': s.level,
      'requiredRank': s.requiredRank,
      // **2026-09-29 補上三個一直沒被序列化的欄位。**
      //
      // `unlockCoins` 是 `[BE-12b]`：後台「設定訓練計畫」改的就是它，
      // 而它原本只活在 `WorkoutPlan` 上，寫回雲端時無處可放。
      //
      // `suitableExperience`／`suitableGoals` 更嚴重 —— 那是 `[QA-02l]`
      // 補的兩欄（27 份課表逐一判定、使用者 2026-09-18 逐列審核通過），
      // 而 `recommendPlan` **把空集合視為「全部符合」**。於是 2026-09-28
      // 平台資料上雲之後，雲端那 27 筆兩欄皆空 → 每一份課表又重新宣稱
      // 適合所有人，推薦退回只靠器材篩，`[QA-02l]` 等於被默默撤銷。
      //
      // 失敗方向是**寬鬆**的，所以不會有任何地方報錯。
      // 舊的往返測試沒抓到，是因為它的夾具兩欄剛好都是預設空值。
      'unlockCoins': s.unlockCoins,
      'memberUnlockable': s.memberUnlockable,
      'suitableExperience': s.suitableExperience,
      'suitableGoals': s.suitableGoals,
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
            'weight': it.weight,
          },
      ],
    };

PlatformPlanSpec planSpecFromDoc(String id, Map<String, dynamic> m) =>
    PlatformPlanSpec(
      id: id,
      name: m['name'] as String,
      level: m['level'] as String,
      requiredRank: (m['requiredRank'] as num?)?.toInt(),
      unlockCoins: (m['unlockCoins'] as num?)?.toInt(),
      memberUnlockable: m['memberUnlockable'] as bool? ?? false,
      // 缺鍵時退回空清單，與 `PlatformPlanSpec` 的預設一致 ——
      // 舊文件（2026-09-29 之前上傳的那批）沒有這兩個鍵。
      suitableExperience: [
        for (final v in (m['suitableExperience'] as List? ?? const []))
          v as String,
      ],
      suitableGoals: [
        for (final v in (m['suitableGoals'] as List? ?? const [])) v as String,
      ],
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
            weight: (it['weight'] as num?)?.toDouble() ?? 0,
          ),
      ],
    );

/// 成就定義的 doc id 沿用既有 `category#threshold` 邏輯（見 Schema §2.6）——
/// 用索引的話成就表一改順序，已解鎖紀錄就會套到別的成就上。
/// 成就定義的文件 ID。
///
/// **鍵是「類別＋名稱」，不是「類別＋門檻」。**
///
/// 原本用門檻 —— 而門檻正是管理員在後台會改的東西
/// （〈設定成就定義〉的三個欄位之一）。改了之後寫回雲端會落在**新的**
/// 文件 ID 上，舊那筆留在原地：下次登入讀回來變成兩枚成就，
/// 而且舊門檻那一枚還在。2026-09-29 補上寫回路徑時才看出來。
///
/// **文件 ID 不可以編碼一個會被改的欄位。** 名稱與類別在
/// `settings/成就定義` 那一頁改不了，所以是穩定的；
/// 99 枚的 (類別, 名稱) 已驗證唯一。
String achievementDocId(Achievement a) => '${a.category}#${a.name}';

/// 要上傳到 Firestore 的那一份種子：集合名 → (文件 ID → 內容)。
///
/// **匯出工具與測試共用這一份。** `tools/export_platform_defs.dart` 是
/// `dart run` 的程式，測試 import 不了它的 `main`；各寫一份的話兩邊會
/// 慢慢長歪，而測試就驗不到真正會被上傳的東西了。
///
/// 集合名要與 `FirestorePlatformData.load()` 讀的那五個一致。
Map<String, Map<String, dynamic>> platformSeedMap(PlatformData d) => {
      'exercises': {for (final e in d.exercises) e.id: exerciseToMap(e)},
      'plans': {for (final s in d.planSpecs) s.id: planSpecToMap(s)},
      'achievement_defs': {
        for (final a in d.achievements) achievementDocId(a): achievementToMap(a),
      },
      'daily_task_pool': {
        for (final t in d.taskPool) t.id: taskPoolItemToMap(t),
      },
      'platform_config': {
        for (final e in d.config.entries) e.key: {'params': e.value},
      },
    };

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
