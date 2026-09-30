import '../domain/ability.dart';
import 'platform_plans.g.dart';
import '../domain/models.dart';
import '../domain/platform_plan.dart';
import 'platform_exercises.g.dart';
import '../domain/commerce.dart';
import '../domain/rewards.dart';

/// 平台動作庫 —— 527 筆，由 tools/import_exercises.py 自 CSV 產生。
/// 其中 15 筆保留了原本調過的相對強度係數與預設組間休息秒數
/// （CSV 沒有這兩欄，前者是能力值的輸入，後者是模型明訂的動作層級屬性）。
const kExercises = kPlatformExercises;


/// 有氧分頁的內容 —— **所屬肌群為空值**者全數在此，不混入肌群分頁。
/// 包含器材類有氧，以及自 CSV 匯入後判定為有氧的動作
/// （活動度／呼吸／伸展 18 筆、體能訓練 4 筆，2026-09-02 裁決）。
List<Exercise> get kCardioExercises => [
      ...kCardioMachines,
      ...kPlatformExercises.where((e) => e.type == ExerciseType.cardio),
    ];

const kCardioMachines = <Exercise>[
  Exercise(id: 'treadmill', name: '跑步機', dim: null, type: ExerciseType.cardio, relativeIntensity: 0, equipment: '有氧器材'),
  Exercise(id: 'rower', name: '划船機', dim: null, type: ExerciseType.cardio, relativeIntensity: 0, equipment: '有氧器材'),
  Exercise(id: 'spin', name: '飛輪', dim: null, type: ExerciseType.cardio, relativeIntensity: 0, equipment: '有氧器材'),
  Exercise(id: 'elliptical', name: '橢圓機', dim: null, type: ExerciseType.cardio, relativeIntensity: 0, equipment: '有氧器材'),
  Exercise(id: 'rope', name: '跳繩', dim: null, type: ExerciseType.cardio, relativeIntensity: 0, equipment: '有氧器材'),
];

/// 自建動作 —— 僅建立者本人可見，且不計入能力值。
const kCustomExercises = <Exercise>[
  Exercise(
      id: 'c_erx',
      name: '彈力帶外旋',
      dim: Dim.shoulders,
      relativeIntensity: 0,
      isCustom: true,
      equipment: '彈力繩',
      defaultRestSeconds: 45),
  Exercise(
      id: 'c_farmer',
      name: '農夫走路',
      dim: Dim.core,
      relativeIntensity: 0,
      isCustom: true,
      equipment: '啞鈴',
      defaultRestSeconds: 120),
];

/// 動作庫的全部來源 —— 平台動作（含有氧）與自建。
List<Exercise> get kAllExercises => [...kExercises, ...kCustomExercises];

Exercise ex(String id) => kExercises.firstWhere((e) => e.id == id);

List<PlannedSet> _sets(int n, double w, int reps) =>
    List.generate(n, (_) => PlannedSet(w, reps));

/// 〈Read Model：課表選擇頁〉涵蓋的四類入口。
///
/// **「上次訓練」與「上次完成度」不寫在這裡。**
/// 那兩個是「**我**上次練這份課表是什麼時候」—— 每個使用者各自不同，
/// 而這份清單是平台提供給所有人的目錄。寫在這裡的後果是：一個從來
/// 沒練過「拉日」的人，打開課表選擇頁看到「上次訓練 5 天前　完成度 70%」。
/// 使用者 2026-09-26 實測回報的正是這個。
///
/// 改由 `AppState.lastTrainedOf()` 依訓練歷史推導（見 PROGRESS 第 5 節 0k）。
/// 四份官方課表的規格。
///
/// ## 為什麼這一份是手寫的，而不是 `platform_plans.g.dart` 產生的
///
/// 生成檔的來源是《健身計劃.csv》，那 27 份是課表作者寫的內容。
/// 這四份不在 CSV 裡 —— 它們是專案早期直接寫死在 `kPlans` 的程式碼，
/// 比雲端早太多，2026-09-28 平台資料上雲時沒有一起搬。
///
/// 後果是使用者 2026-09-29 撞到的：**後台改得動它們，但存不住** ——
/// 雲端沒有它們的位置。改完只改到記憶體，重新整理就打回原形。
///
/// 2026-09-29 使用者裁決 B：搬上雲，讓後台改得動。
///
/// ## 內容一字未改
///
/// 重量、組數、次數、休息秒數、階級門檻、解鎖價格、適用經驗與目標
/// **全部照抄原本 `kPlans` 的值**。為此 `PlanItemSpec` 補了 `weight`、
/// `PlatformPlanSpec` 補了 `memberUnlockable` —— 規格裝不下就等於搬家時
/// 把處方改掉，而**訓練處方不是我該替使用者決定的**（CLAUDE.md 第 7 條）。
///
/// ## 六段說明性內容是空的，這是刻意的
///
/// CSV 那 27 份帶著介紹、怎麼練、負荷、訓練效果、技術重點與**學理依據**。
/// 這四份從來沒有過那些內容，而我不編 —— 尤其是依據那一欄：
/// 一份說得出依據的課表與一份憑空編的，對使用者是兩件不同的東西
/// （見 [PlatformPlanSpec.reference]）。
///
/// 空著的代價是課表詳情頁少一段；編一段假的的代價是使用者以為它有根據。
/// **課表詳情頁已改為內容全空時整段不呈現**，不會出現空白卡片。
/// 補內容是人的工作，已記入待辦。
final kLegacyPlanSpecs = <PlatformPlanSpec>[
  PlatformPlanSpec(
    id: 'p_push',
    name: '推日：胸肩三頭',
    level: '戰士級',
    requiredRank: null,
    equipmentTier: '健身房',
    suitableExperience: const ['中階（6 個月–2 年）', '進階（2 年以上）'],
    suitableGoals: const ['增肌', '提升體能'],
    duration: '',
    intro: '',
    howTo: '',
    load: '',
    effect: '',
    technique: '',
    reference: '',
    items: const [
      // 課表指定值蓋過動作預設（150 秒）—— 取值優先序的第一順位。
      PlanItemSpec('bench', 4, 8, PlanUnit.reps, 120, weight: 60),
      PlanItemSpec('db_press', 3, 10, PlanUnit.reps, 90, weight: 22),
      PlanItemSpec('ohp', 3, 8, PlanUnit.reps, 90, weight: 35),
      PlanItemSpec('pushdown', 3, 12, PlanUnit.reps, 90, weight: 25),
    ],
  ),
  PlatformPlanSpec(
    id: 'p_pull',
    name: '拉日：背二頭',
    level: '戰士級',
    requiredRank: null,
    equipmentTier: '健身房',
    suitableExperience: const ['中階（6 個月–2 年）', '進階（2 年以上）'],
    suitableGoals: const ['增肌', '提升體能'],
    duration: '',
    intro: '',
    howTo: '',
    load: '',
    effect: '',
    technique: '',
    reference: '',
    items: const [
      PlanItemSpec('row', 4, 8, PlanUnit.reps, 90, weight: 50),
      PlanItemSpec('latpull', 3, 10, PlanUnit.reps, 90, weight: 45),
      PlanItemSpec('curl', 3, 12, PlanUnit.reps, 90, weight: 15),
    ],
  ),
  PlatformPlanSpec(
    id: 'p_leg',
    name: '腿日：深蹲主導',
    level: '戰士級',
    requiredRank: 12,
    equipmentTier: '健身房',
    suitableExperience: const ['中階（6 個月–2 年）', '進階（2 年以上）'],
    suitableGoals: const ['增肌', '提升體能'],
    duration: '',
    intro: '',
    howTo: '',
    load: '',
    effect: '',
    technique: '',
    reference: '',
    items: const [
      PlanItemSpec('squat', 5, 5, PlanUnit.reps, 90, weight: 80),
      PlanItemSpec('legpress', 3, 10, PlanUnit.reps, 90, weight: 120),
      PlanItemSpec('crunch', 3, 15, PlanUnit.reps, 90, weight: 10),
    ],
  ),
  // 未解鎖的進階計畫一併呈現、不隱藏 —— 它是三種解鎖方式的唯一曝光點。
  PlatformPlanSpec(
    id: 'p_power',
    name: '進階：爆發力週期',
    level: '精銳級',
    requiredRank: 55,
    // 進階訓練計畫統一定價，不逐計畫區分（〈虛擬商品購買流程〉2026-08-20）。
    unlockCoins: kPlanUnlockCoins,
    memberUnlockable: true,
    equipmentTier: '健身房',
    suitableExperience: const ['進階（2 年以上）'],
    suitableGoals: const ['提升體能'],
    duration: '',
    intro: '',
    howTo: '',
    load: '',
    effect: '',
    technique: '',
    reference: '',
    items: const [
      PlanItemSpec('deadlift', 5, 3, PlanUnit.reps, 90, weight: 100),
      PlanItemSpec('squat', 4, 4, PlanUnit.reps, 90, weight: 85),
      PlanItemSpec('ohp', 4, 5, PlanUnit.reps, 90, weight: 40),
    ],
  ),
];

/// 示範用的課表 —— **只有示範模式看得到**。
///
/// 這兩份是假資料，而且是**假的「使用者自己的東西」**：
/// 「我的核心日」的來源標成私人自訂，「社群熱門：全身循環」標成別人分享的。
/// 它們原本混在 `kPlans` 裡而沒有任何開關，於是**一個全新的真帳號一打開
/// App，就有一份他從來沒建過的自訂課表，和一份來自還沒有任何人的社群的
/// 熱門課表**（2026-09-29 以 `AppState(demo: false)` 實測確認）。
///
/// 這是「假資料撐著功能」的第六次。`[QA-02]` 當初清假資料的那個開關
/// 只管集合，課表目錄沒有被納入，所以它活到今天。
///
/// **不刪除**：它們撐著自訂課表與社群分享課表那兩條流程的示範
/// （真帳號要等到真的有人建了課表、有人分享了課表才看得到那些畫面）。
final kDemoPlans = <WorkoutPlan>[
  WorkoutPlan(
    id: 'p_custom',
    name: '我的核心日',
    suitableExperience: const {'新手（未滿 6 個月）'},
    suitableGoals: const {'培養運動習慣'},
    source: PlanSource.privateCustom,
    equipmentTier: '徒手',
    // **這裡本來寫著 `hasOptimizationSuggestion: true`。**
    //
    // 那是「**我**有一份待看的優化建議」—— 每個人各自不同，不該長在
    // 共用的課表目錄上。寫死的結果是每一位真實使用者一開啟 App
    // 就看到一張不是自己的課表掛著「新的優化建議」，點進去卻什麼也沒有。
    //
    // 與 0k③ 的 `lastTrainedAt`／`lastCompletion` 同一個家族：
    // **使用者的資料寫進了平台目錄。** 現在那件事記在
    // `AppState.optimizedPlanId`，存在使用者自己的存檔裡。
    exercises: [
      PlanExercise(
          exercise: ex('plank'),
          planned: _sets(3, 0, 60),
          unit: PlanUnit.seconds),
      PlanExercise(exercise: ex('crunch'), planned: _sets(4, 8, 15)),
    ],
  ),
  WorkoutPlan(
    id: 'p_shared',
    name: '社群熱門：全身循環',
    suitableExperience: const {'新手（未滿 6 個月）', '中階（6 個月–2 年）'},
    suitableGoals: const {'減重', '培養運動習慣'},
    source: PlanSource.publishedCustom,
    equipmentTier: '居家',
    exercises: [
      PlanExercise(exercise: ex('pullup'), planned: _sets(3, 0, 8)),
      PlanExercise(exercise: ex('dip'), planned: _sets(3, 0, 10)),
      PlanExercise(exercise: ex('squat'), planned: _sets(3, 40, 12)),
    ],
  ),
];

/// 不屬於平台資料、但**每個帳號都必須有**的課表。
///
/// 目前只有空白課表 —— 它是**自由訓練的唯一入口**，沒有任何內容可設定，
/// 所以既不上雲（沒東西可存），也不是示範資料（真帳號一樣要有）。
final kPlans = <WorkoutPlan>[
  const WorkoutPlan(
    id: 'p_blank',
    name: '空白課表（自由訓練）',
    source: PlanSource.blank,
    exercises: [],
  ),
];

/// 成就 9 類，共 99 枚（互動 36 ＋ 粉絲 9 ＋ 四類各 9 ＋ 新手 1 ＋ 能力值 12 ＋ 階級 5）。數額依〈成就獎勵的數額〉(2026-08-09 定案)，
/// 判準為**該類成就能否靠灌水取得**。
///
/// | 類別 | 枚數 | 金幣 | 經驗值 |
/// |------|------|------|--------|
/// | 互動（分享/發文/按讚/留言 4 種 × 9 門檻） | 36 | 一律 5 | 依門檻遞增 |
/// | 粉絲 | 9 | 一律 5 | 依門檻遞增 |
/// | 連簽 / 累簽 / 連續訓練 / 累積訓練 | 各 9 | 20 → 60 遞增 | 依門檻遞增 |
/// | 新手任務 | 1 | 60 | 90 |
/// | 能力值 | 12 | 100 → 300 遞增 | 依門檻遞增 |
/// | 階級 | 5 | 100 → 500 遞增 | **不給** |
List<Achievement> buildAchievements() {
  final out = <Achievement>[];

  /// [coins] 逐枚的金幣數額，長度須等於門檻數；[baseExp]/[stepExp] 為經驗值。
  void add(
    String cat,
    List<int> ths,
    String Function(int) namer, {
    required List<int> coins,
    int baseExp = 10,
    int stepExp = 10,
  }) {
    assert(coins.length == ths.length, '$cat 的金幣數額與門檻數不符');
    for (var i = 0; i < ths.length; i++) {
      out.add(Achievement(
        category: cat,
        name: namer(ths[i]),
        threshold: ths[i],
        rewardCoins: coins[i],
        rewardExp: baseExp + stepExp * i,
      ));
    }
  }

  /// 自 [from] 遞增至 [to] 的 [n] 檔，端點皆取到。
  List<int> ramp(int from, int to, int n) => [
        for (var i = 0; i < n; i++)
          n == 1 ? from : (from + (to - from) * i / (n - 1)).round(),
      ];

  /// 刷不動的五類：20 → 60 遞增。
  final steady = ramp(20, 60, 9);

  /// 可刷的兩類一律 5 金幣，**不遞增** —— 該類「按讚 1,000 次」與
  /// 「按讚 1 次」的含金量本即相近，遞增反而獎勵刷得多的人。
  const flat5 = [5, 5, 5, 5, 5, 5, 5, 5, 5];

  add('連簽', [1, 3, 5, 7, 10, 15, 20, 25, 30], (t) => '連續簽到 $t 天',
      coins: steady);
  add('累簽', [3, 7, 15, 30, 60, 100, 180, 280, 365], (t) => '累計簽到 $t 天',
      coins: steady);
  add('連續訓練', [1, 3, 5, 7, 14, 21, 30, 60, 100], (t) => '連續訓練 $t 天',
      coins: steady);
  // 門檻計的是**天數**不是次數：一日內連開多場即可快速推進，以次數計會被刷完。
  add('累積訓練', [1, 5, 10, 25, 50, 100, 200, 350, 500], (t) => '累積訓練 $t 天',
      coins: steady);
  // 新手成就只有 1 枚：新手任務為三選一、做一次就結束，
  // 一個一次性的布林事實撐不起 9 個遞增門檻。
  // 金幣取該類上緣 60 —— 本枚不可重複取得，給下緣 20 說不過去。
  add('新手任務', const [1], (_) => '完成新手任務',
      coins: const [60], baseExp: 90, stepExp: 0);

  // 互動成就為 4 種 × 9 門檻，不是單一類 9 枚 ——
  // 「按讚 100 次」與「留言 100 次」是兩件不同的事。
  const interactionThresholds = [1, 10, 25, 50, 100, 250, 500, 1000, 2000];
  for (final kind in kInteractionKinds) {
    add(kind, interactionThresholds, (t) => '$kind $t 次', coins: flat5);
  }
  add('粉絲', [1, 5, 10, 25, 50, 100, 250, 500, 1000], (t) => '粉絲數 $t',
      coins: flat5);

  // 能力值類唯一衡量「真的變強了」且完全刷不動，故給雙倍。
  add('能力值', [100, 150, 200, 250, 315, 385, 450, 515, 585, 650, 785, 850],
      (t) => '任一維達 $t 點',
      coins: ramp(100, 300, 12), baseExp: 50, stepExp: 25);

  // 階級成就 5 枚，門檻沿用進階計畫與自訂訓練名額的同一組里程碑，再加滿等 99。
  // **不給經驗值**：階級本即由經驗值推動，再給經驗值會形成
  // 「升階 → 得經驗值 → 再升階」的循環。
  add('階級', [10, 25, 45, 70, 99], (t) => '達到 $t 階',
      coins: ramp(100, 500, 5), baseExp: 0, stepExp: 0);
  return out;
}

/// 互動成就的四種。與〈獎勵定義〉的四個每日上限一一對應。
const kInteractionKinds = ['分享', '發文', '按讚', '留言'];

/// 每日任務：自任務池隨機抽取 3 項，判定來源為 Event 訂閱。
List<DailyTask> buildDailyTasks() => [
      DailyTask(name: '完成 1 次訓練', sourceEvent: '使用者已完成訓練', target: 1, progress: 0),
      DailyTask(name: '完成 12 組訓練', sourceEvent: '使用者已完成該組', target: 12, progress: 0),
      DailyTask(name: '完成每日簽到', sourceEvent: '使用者已簽到', target: 1, progress: 0),
    ];

const kOpponentNames = [
  '鐵人阿凱', 'Ashley', '深蹲王', '林小美', 'CoreMax', '週三練胸',
  '硬舉狂魔', 'Yuki', '增肌中', '不練會死', 'Ryan', '核心怪物',
  '早鳥訓練', 'Mia', '推拉腿', '一週五練', 'Leo', '槓片收藏家',
  '減脂期', 'Nina',
];

/// 把《健身計劃.csv》的 27 份課表轉成 App 的 [WorkoutPlan]。
///
/// **每組目標重量一律為 0**：資料以 RPE（自覺強度）開處方，不指定公斤數。
/// 徒手動作本來就不需要；器械動作由使用者依 RPE 自行決定 ——
/// 替一個沒見過的人填一個具體重量，比留白危險。
///
/// 時間型動作把秒數放在 `targetReps`，沿用 App 加入有氧動作時的既有慣例
/// （`PlannedSet(0, _seconds)`）。判讀依據是動作本身的 [ExerciseType]。
/// 打包在本地的全部平台課表規格 = CSV 產生的 27 份 ＋ 手寫的 4 份。
///
/// 兩份都是平台資料、都上雲、後台都改得動。差別只在**來源**：
/// 前者由 `gen_platform_plans.py` 自 CSV 產生（不可手改），
/// 後者是 2026-09-29 從 `kPlans` 搬過來的（見 [kLegacyPlanSpecs]）。
/// **順序有意義**：四份手寫的官方課表排在 27 份 CSV 課表前面，
/// 因為在 2026-09-29 搬家之前它們就是目錄的開頭。順序一改，
/// 「目錄的第一份是什麼」跟著改，而好幾處（畫面預設、測試夾具）
/// 都靠那個。搬家不該順手改動使用者看到的排列。
final kAllPlanSpecs = <PlatformPlanSpec>[
  ...kLegacyPlanSpecs,
  ...kPlatformPlans,
];

List<WorkoutPlan> buildCsvPlans() =>
    buildCsvPlansFrom(kAllPlanSpecs, kPlatformExercises);

/// 打包狀態下一個帳號看得到的全部課表 —— 比照 [kAllExercises]。
///
/// 2026-09-29 之前這件事等於 `kPlans`，所以到處都直接寫 `kPlans.firstWhere(...)`。
/// 四份官方課表搬上雲之後 `kPlans` 只剩空白課表，那些查詢會撈不到東西
/// （`Bad state: No element`）—— 它們要的其實一直是「目錄裡的那一份」，
/// 不是「寫死在程式裡的那一份」。
List<WorkoutPlan> get kAllPlans =>
    [...buildCsvPlans(), ...kDemoPlans, ...kPlans];

/// 同 [buildCsvPlans]，但課表規格與動作庫由呼叫端提供 ——
/// 平台資料上雲（[BE-12]）後，這兩份來源可能是 Firestore 的即時內容
/// 而非打包在本地的常數。動作查不到時退回本地動作庫，確保雲端缺一筆
/// 不會讓整份課表炸掉（離線後備哲學）。
List<WorkoutPlan> buildCsvPlansFrom(
        List<PlatformPlanSpec> specs, List<Exercise> exercises) =>
    [
      for (final s in specs)
        WorkoutPlan(
          id: s.id,
          name: s.name,
          source: PlanSource.official,
          requiredRank: s.requiredRank,
          // 後台改得動的欄位都要一路帶著走，否則「已設定」下次載入
          // 就消失（`[BE-12b]`）。`memberUnlockable` 不是後台改的，
          // 但同樣要帶 —— 掉了就等於少一條解鎖途徑，而那是無聲的。
          unlockCoins: s.unlockCoins,
          memberUnlockable: s.memberUnlockable,
          equipmentTier: s.equipmentTier,
          suitableExperience: s.suitableExperience.toSet(),
          suitableGoals: s.suitableGoals.toSet(),
          exercises: [
            for (final it in s.items)
              PlanExercise(
                exercise: exercises.firstWhere(
                  (e) => e.id == it.exerciseId,
                  orElse: () => kPlatformExercises
                      .firstWhere((e) => e.id == it.exerciseId),
                ),
                planned: List.generate(
                    it.sets, (_) => PlannedSet(it.weight, it.amount)),
                restSeconds: it.restSeconds,
                // **單位要一路帶著走。** 丟在這裡的話，下游只剩「重量是 0」
                // 可以猜 —— 而這 27 份課表的重量全部是 0。
                unit: it.unit,
              ),
          ],
        ),
    ];

/// 課表 ID → 它的說明性內容。課表詳情頁要用，訓練流程用不到。
final kPlanSpecById = {for (final s in kAllPlanSpecs) s.id: s};
