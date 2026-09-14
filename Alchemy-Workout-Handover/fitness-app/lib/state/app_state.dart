import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';

import '../domain/ability.dart';
import '../domain/clock.dart';
// 換日規則已移入 clock.dart（假資料產生器也要用同一套）。
// 轉出以維持既有呼叫端不變 —— 19 處在本檔、5 個測試檔。
export '../domain/clock.dart' show businessDate;
import '../domain/ai_adjust.dart';
import '../domain/decay.dart';
import '../domain/novice.dart';
import '../domain/novice_wrapup.dart';
import '../domain/task_pool.dart';
import '../domain/models.dart';
import '../domain/registration.dart';
import '../domain/social.dart';
import '../domain/leaderboard.dart';
import '../domain/rank.dart';
import '../domain/rewards.dart';
import '../domain/admin.dart';
import '../domain/platform_config.dart';
import '../domain/commerce.dart';
import '../domain/custom_plan.dart';
import '../domain/carry_forward.dart';
import '../domain/community.dart';
import '../domain/inbound.dart';
import '../domain/platform_plan.dart';
import '../data/store.dart';
import '../data/platform_data.dart';
import '../data/public_profile.dart';
import '../data/follow_data.dart';
import '../data/post_data.dart';
import '../data/chat_data.dart';
import '../data/team_data.dart';
import '../mock/mock_data.dart';
import '../mock/mock_equipment.dart';

import '../mock/mock_admin.dart';
import '../mock/mock_extra.dart';

part 'app_state_snapshot.dart';

/// 讀取存檔的三個階段。載入中不畫主畫面，失敗不靜靜改用假資料。
enum HydrationPhase { loading, ready, failed }

/// 全站預設組間休息秒數。
const int kDefaultRestSeconds = 90;

/// 最小組間間隔（防作弊），不允許連續出現兩個低於此值的間隔。
const int kMinSetIntervalSeconds = 30;

/// 單次訓練逾時中斷門檻：40 分鐘內未完成任何一組。
const int kIdleTimeoutMinutes = 40;

class SettlementResult {
  final WorkoutPlan plan;
  final EndKind kind;
  final SettlementRewards rewards;
  final Map<Dim, int> gains;
  final Map<Dim, int> pointsAfter;

  /// 本次各維的**實測分數**。沒有提升時，唯一能回答「差多少」的就是它 ——
  /// 只說「未推進任何維度」，使用者看到的就是一個沒反應的畫面。
  final Map<Dim, int> measured;
  final int doneSets;
  final int plannedSets;
  final Duration duration;
  final double volume;
  final int calories;
  final int streakDays;
  final int rankBefore;
  final int rankAfter;
  final List<Achievement> newlyUnlocked;
  const SettlementResult({
    required this.plan,
    required this.kind,
    required this.rewards,
    required this.gains,
    required this.pointsAfter,
    required this.measured,
    required this.doneSets,
    required this.plannedSets,
    required this.duration,
    required this.volume,
    required this.calories,
    required this.streakDays,
    required this.rankBefore,
    required this.rankAfter,
    required this.newlyUnlocked,
  });
}

class AppState extends ChangeNotifier {
  // --- 使用者 Aggregate（假資料）---
  String displayName = '你';
  double bodyweightKg = 72;
  bool isMale = true;

  // --- 能力值 Aggregate ---
  final Map<Dim, int> points = {
    Dim.chest: 486,
    Dim.back: 452,
    Dim.legs: 318,
    Dim.shoulders: 274,
    Dim.arms: 305,
    Dim.core: 190,
  };
  final Map<Dim, int> pending = {for (final d in Dim.values) d: 0};
  final Set<Dim> trainedDims = {...Dim.values};

  /// 能力值日快照 —— **每日一筆，於日界保存當下六維值**。
  /// 它是能力值的關聯 Aggregate（一對多），不是欄位。
  ///
  /// 鍵為「幾天前」。假資料先給 30／90 兩筆，其後由 [takeAbilitySnapshot]
  /// 於每個日界補上，不再是永遠不動的兩個寫死數字。
  final Map<int, Map<Dim, int>> snapshots = {
    30: {
      Dim.chest: 402, Dim.back: 388, Dim.legs: 260,
      Dim.shoulders: 230, Dim.arms: 258, Dim.core: 160,
    },
    90: {
      Dim.chest: 300, Dim.back: 262, Dim.legs: 205,
      Dim.shoulders: 180, Dim.arms: 190, Dim.core: 120,
    },
  };
  int snapshotDaysAgo = 0; // 0 ＝ 現在

  // --- 能力值退步：六個各自獨立的計時器 ---

  /// 示範用的時鐘位移。本 App 無後端，不快轉就看不到 240 小時後會發生什麼；
  /// 退步邏輯一律讀 [now]，不直接讀系統時鐘。
  /// 展示時鐘的偏移量。實際存在 [appClockOffset] —— 構不到 AppState 的
  /// 純函式與畫面小工具也要讀得到同一個時鐘，見 domain/clock.dart。
  Duration get demoClockOffset => appClockOffset;
  set demoClockOffset(Duration v) => appClockOffset = v;
  DateTime get now => appNow();

  /// 註冊日 —— 六個退步計時器與連續訓練計時器的初始基準，皆不允許空值。
  /// 非 final：真實使用者的註冊日來自帳號，示範與測試需要換一個近期的日子
  /// 才看得到「補不回註冊日之前」這條界線。
  late DateTime registeredOn =
      businessDate(DateTime.now()).subtract(const Duration(days: 180));

  /// 各維最後訓練日刻意錯開，使六個計時器各自落在不同的門檻上：
  /// 胸今天、背 2 天、腿 5 天（退步預告）、肩 12 天、手 26 天、核心 46 天。
  /// 退步後的點數不寫死，由 [runDecayCheck] 於建構時推導 ——
  /// 上面 [points] 的六個值即為「本次中斷前點數」。
  late final Map<Dim, DimDecay> decayTimers = {
    for (final e in const {
      Dim.chest: 0,
      Dim.back: 2,
      Dim.legs: 5,
      Dim.shoulders: 12,
      Dim.arms: 26,
      Dim.core: 46,
    }.entries)
      e.key: _freshTimer(
          businessDate(DateTime.now()).subtract(Duration(days: e.value))),
  };

  static DimDecay _freshTimer(DateTime lastTrained) =>
      DimDecay(lastTrainedDate: lastTrained)..resetOn(lastTrained);

  /// 「能力值已退步」的流水（供退步狀態頁呈現，非業務欄位）。
  final List<(Dim, DateTime, int)> decayLog = [];

  /// 該維的初始值 —— 亦為退步下限的地板。完成新手任務者腿與核心為 30。
  int initialOf(Dim d) =>
      (noviceFinished && (d == Dim.legs || d == Dim.core))
          ? math.max(kInitialPoints, kNoviceLegCoreInitial)
          : kInitialPoints;

  /// 本次中斷前點數 ＝ 各維點數 ＋ 本次中斷累積退步量（不另設欄位）。
  /// 該值於整段中斷期間恆定，故下限在中斷期間不隨退步下滑。
  int pointsBeforeInterruption(Dim d) =>
      points[d]! + decayTimers[d]!.cumulative;

  int decayFloorFor(Dim d) =>
      decayFloorOf(pointsBeforeInterruption(d), initial: initialOf(d));

  /// Policy：訓練中斷判定。六維各自獨立計時，滿一個退步間隔即退該維。
  ///
  /// 回傳本次實際發生退步的維度。
  List<Dim> runDecayCheck() {
    // 永久停權期間暫停所有計時。平台把訓練與簽到整個關掉，
    // 卻讓退步與連續天數照跑，等於因為「你沒訓練」再罰一次；
    // 而該使用者根本沒有訓練的權限。見 [clocksFrozen]。
    if (clocksFrozen) return const [];
    final t = now;
    // 逾期判定：時限起算時戳為空值者不啟動 —— 沒看過就不會逾期。
    if (returnTaskAssigned &&
        !returnTaskDone &&
        returnTaskViewedAt != null &&
        (returnTaskDaysLeft ?? 1) <= 0) {
      expireReturnTask();
    }
    final fired = <Dim>[];
    for (final d in Dim.values) {
      final td = decayTimers[d]!;
      // 停止後的計時器不再推進，直到該維再次被訓練才重新起算。
      while (!td.floorReached &&
          td.nextDecayAt != null &&
          !t.isBefore(td.nextDecayAt!)) {
        final step =
            decayOnce(current: points[d]!, floor: decayFloorFor(d));
        points[d] = step.newPoints;
        td.cumulative += step.lost;
        decayLog.add((d, td.nextDecayAt!, step.lost));
        // 觸及下限的那一次仍照常產生 Event（回歸任務的唯一觸發源），
        // 其後該維不再產生，且計時器停止。
        if (step.hitFloor) {
          td.floorReached = true;
          td.nextDecayAt = null;
        } else {
          td.nextDecayAt =
              td.nextDecayAt!.add(Duration(hours: kDecayIntervalHours));
        }
        fired.add(d);
        // Postcondition：「能力值已退步」發生後，觸發「回歸任務已指派」。
        _assignReturnTask(d);
      }
    }
    if (fired.isNotEmpty) notifyListeners();
    return fired;
  }

  // ---------------------------------------------------------------------------
  // 連續訓練與連續簽到的中斷判定
  // ---------------------------------------------------------------------------

  /// 已發到哪一個門檻。**只記到過的最高階**，避免同一則預告重複發。
  /// 訓練恢復時歸零，下一次中斷才會重新發。
  DecayStage _trainNoticeStage = DecayStage.normal;

  /// 連簽側用自己的階段列舉 —— 它只有 24／36／48 三道門檻，
  /// 沒有能力值的「已退步」那一階。補簽提醒即為其最高階，
  /// 故不再另設一個布林旗標。
  CheckInStage _checkInNoticeStage = CheckInStage.normal;

  /// Policy：連續訓練中斷判定與連簽中斷判定。
  ///
  /// 四道／三道門檻各自的計時起點一律為**上次那一日的日界**（次日當地 04:00），
  /// 不是上次的時戳 —— 否則警告時點會取決於昨天幾點開 App。
  ///
  /// 這一整段原本只有「能力值退步」做了，前面幾道門檻的判定函式存在、
  /// 卻只被退步狀態頁拿去顯示顏色。結果是連續天數只會加、永遠不會歸零：
  /// 停練一個月，首頁還寫著「連續 12 天」。
  void runStreakCheck() {
    // 永久停權期間暫停所有計時 —— 同 [runDecayCheck]。
    if (clocksFrozen) return;
    var changed = false;
    final t = now;

    // --- 連續訓練 ---
    final trainHours = hoursSinceBoundary(lastTrainedDate, t);
    final trainStage = stageOf(trainHours);
    if (trainStage.index > _trainNoticeStage.index) {
      // 中斷預告（24）／連練中斷通知（36）／退步預告（96）——
      // 逐階補發，一次跨過多階時每一階各發一則。
      for (var i = _trainNoticeStage.index + 1;
          i <= trainStage.index;
          i++) {
        final n = _trainNotice(DecayStage.values[i], trainHours, t);
        if (n != null) notifications.insert(0, n);
      }
      _trainNoticeStage = trainStage;
      changed = true;
    }
    // 連續訓練天數已歸零 → 使用者已失去獎勵加成。
    // 加成不另設欄位：它由連續訓練天數推導，天數歸零加成即為 0。
    if (trainingStreakDays > 0 && !streakContinues(lastTrainedDate, t)) {
      trainingStreakDays = 0;
      changed = true;
    }

    // --- 連續簽到 ---
    // 從未簽到者自註冊日的日界起算，與已簽到者共用同一套規則。
    final checkBase = lastCheckInDate ?? registeredOn;
    final checkHours = hoursSinceBoundary(checkBase, t);
    final checkStage = checkInStageOf(checkHours);
    if (checkStage.index > _checkInNoticeStage.index) {
      // 逐階補發：一次跨過多階時每一階各發一則。
      for (var i = _checkInNoticeStage.index + 1;
          i <= checkStage.index;
          i++) {
        final n = _checkInNotice(CheckInStage.values[i], checkHours, t);
        if (n != null) notifications.insert(0, n);
      }
      _checkInNoticeStage = checkStage;
      changed = true;
    }
    // 連續天數不在這裡歸零 —— 它由簽到紀錄推算，斷了自然就是 0。

    if (changed) notifyListeners();
  }

  AppNotification? _checkInNotice(CheckInStage stage, int hours, DateTime t) =>
      switch (stage) {
        CheckInStage.warned => AppNotification(
            id: newId('n-checkwarn-'),
            sourceEvent: '連簽中斷預告已發送',
            title: '該簽到囉',
            body: '距上次簽到已 $hours 小時，連續 $checkInStreak 天別斷了。',
            at: t,
            kind: NotifyKind.push,
            priority: NotifyPriority.expiring,
          ),
        // 連簽已中斷本身不另發通知：使用者收到的下一則是補簽提醒，
        // 那則才帶得出可以做什麼。
        CheckInStage.broken => null,
        CheckInStage.makeupReminded => AppNotification(
            id: newId('n-makeup-'),
            sourceEvent: '補簽提醒已發送',
            title: '別忘了補簽',
            body: '你有未簽到的日子，補簽券還補得回來。',
            at: t,
            kind: NotifyKind.push,
            // 第 1 級期限即將失效類：回補範圍只有 7 天，過了就補不回來。
            priority: NotifyPriority.expiring,
          ),
        CheckInStage.normal => null,
      };

  AppNotification? _trainNotice(DecayStage stage, int hours, DateTime t) =>
      switch (stage) {
        DecayStage.interruptWarned => AppNotification(
            id: newId('n-trainwarn-'),
            sourceEvent: '中斷預告已發送',
            title: '連續訓練快中斷了',
            body: '距上次訓練已 $hours 小時。',
            at: t,
            kind: NotifyKind.push,
            priority: NotifyPriority.expiring,
          ),
        DecayStage.streakBroken => AppNotification(
            id: newId('n-trainbreak-'),
            sourceEvent: '連練中斷通知已發送',
            title: '連續訓練已中斷',
            body: '連續訓練天數已歸零，獎勵加成一併失去。',
            at: t,
            kind: NotifyKind.push,
            priority: NotifyPriority.guidance,
          ),
        DecayStage.decayWarned => AppNotification(
            id: newId('n-decaywarn-'),
            sourceEvent: '退步預告已發送',
            // 預告訊息須載明實際期限，不得寫為「即將退步」。
            title: '能力值即將退步',
            body: '滿 ${kDecayIntervalHours ~/ 24} 天未訓練即會退步。',
            at: t,
            kind: NotifyKind.push,
            priority: NotifyPriority.expiring,
          ),
        // 已退步另由「能力值已退步」承擔通知，不在此重複。
        DecayStage.decaying || DecayStage.normal => null,
      };

  // --- 示範用的載入與離線 ---

  /// 模擬首次載入的耗時。**預設 0 ＝ 不模擬**：假資料本來就在記憶體裡，
  /// 平白讓每一頁慢 0.9 秒只是折磨人。由設定頁打開才看得到骨架屏。
  int demoLoadMs = 0;

  /// 模擬離線 —— 打開後每一個載入邊界都會走到錯誤頁。
  bool demoOffline = false;

  /// 已載入過的畫面。**骨架屏只給首次載入**（§8.6），
  /// 回到同一頁不該再骨架一次。
  final Set<String> _loadedOnce = {};

  bool hasLoadedOnce(String id) => _loadedOnce.contains(id);
  void markLoadedOnce(String id) => _loadedOnce.add(id);

  void setDemoLoadMs(int ms) {
    demoLoadMs = ms;
    _loadedOnce.clear();
    notifyListeners();
  }

  void setDemoOffline(bool v) {
    demoOffline = v;
    _loadedOnce.clear();
    notifyListeners();
  }

  /// 示範用：把時鐘往前推，讓四道門檻與退步真的發生。
  void advanceDemoClock(Duration by) {
    demoClockOffset += by;
    runDecayCheck();
    runStreakCheck();
    // 兩個系統排程掛在同一個時鐘上：日界產生快照、月初重置 AI 月度額度。
    takeAbilitySnapshot();
    resetMonthlyAiCredits();
    expireMembershipIfDue();
    resetDailyTasksIfDue();
    resetMentorWeekIfDue();
    expirePunishmentIfDue();
    reconcileDailyTasks();
    sendTrainingReminderIfDue();
    settleDueBoards();
    // 申請與邀請的 168 小時逾期判定 —— 同樣是掛在時鐘上的系統排程。
    sweepExpiredRequests();
    notifyListeners();
  }

  // --- 經驗值 / 金幣 / 階級 ---
  // 階級 45 —— 自訂訓練名額為 4（初始 2 ＋ 里程碑 25、45 各 +1），
  // 與這位假使用者手上的四份自訂訓練相符。
  int totalExp = 1700;
  int coins = 640;
  int get rank => rankForExp(totalExp);

  // --- 連續訓練 Aggregate ---
  int trainingStreakDays = 12;

  /// 累積訓練**次數**：一日兩場計 2。三種終止狀態皆計入。
  /// 供教官初審門檻與師徒功能解鎖使用。
  int totalWorkouts = 63;

  /// 累積訓練**天數**：一日兩場計 1。供累積訓練成就使用。
  ///
  /// **與 [totalWorkouts] 並存不合併**（模型明訂）：一日內連開多場訓練
  /// 即可快速推進成就門檻，成就若以次數計會被短時間刷完；
  /// 而教官門檻要的正是實際訓練場次。
  int totalWorkoutDays = 58;
  /// 上次訓練日期的初始值 —— **註冊日**。
  ///
  /// 模型明訂本欄位不允許空值：從未訓練者的四道門檻
  /// （24 / 36 / 96 / 240 小時）自註冊日的日界起算，與已訓練者共用
  /// 同一套規則，不必為「還沒練過」另寫一條分支。
  DateTime get initialLastTrainedDate => registeredOn;

  /// 上次訓練日期。不允許空值。
  ///
  /// 這是〈連續訓練 Aggregate〉的欄位，故可寫 —— 永久停權經申訴撤銷時
  /// 要以撤銷時點重設它，那時並沒有一筆新的訓練紀錄可依據。
  ///
  /// **初始值取自訓練歷史最晚的那一場**，不是「今天」。原本寫死成今天，
  /// 於是狀態說今天練過、訓練歷史最晚卻是昨天，而首頁還擺著一顆
  /// 「開始訓練」—— 三個地方講同一件事，給出兩個答案。
  late DateTime lastTrainedDate = _lastTrainedFromHistory();

  DateTime _lastTrainedFromHistory() {
    if (history.isEmpty) return initialLastTrainedDate;
    return history
        .map((h) => businessDate(h.date))
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  // --- 連續簽到 Aggregate ---

  /// 連續簽到天數。**衍生值，不儲存** ——
  /// 模型明訂「連續天數以逐日推算求得：自上次簽到日期起往回逐日檢視
  /// 每日簽到紀錄，連續有紀錄的天數即為連續天數，遇查無紀錄之日即停止」。
  ///
  /// 原本存成一個獨立欄位，初始值寫死 6，與簽到紀錄無關 ——
  /// 補簽頁的日曆畫出 9/4、9/5 連兩天已簽，首頁卻寫「連續 0 天」，
  /// 同一件事兩個答案。存兩份就會有兩份對不起來的事實。
  int get checkInStreak => _streakFromRecords();
  int checkInTotal = 148;
  int checkInLongest = 21;
  /// 上次簽到日期。**衍生值，不儲存** ——
  /// 它就是每日簽到紀錄裡最晚的那一天。
  ///
  /// 原本是獨立欄位且初始為空值，但假資料的簽到紀錄有 9 天 ——
  /// 一邊說「從來沒簽到過」，另一邊畫出 9 個已簽到的格子。
  DateTime? get lastCheckInDate {
    if (checkInRecords.isEmpty) return null;
    return checkInRecords.keys.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  // --- 個人排行榜分數 Aggregate ---
  int weeklyScore = 640;
  int monthlyScore = 2380;
  DateTime leaderboardUpdatedAt = DateTime.now().subtract(const Duration(minutes: 18));
  /// 所屬組別取**週期起算時點**的階級；週期內升階不改變本週期組別，
  /// 新組別自下一週期起生效。故它是可變欄位，於結算時重新鎖定 ——
  /// 升階即刻轉組會讓人把低組累積的分數整包帶進高組洗名次，
  /// 反之亦可刻意壓階不升穩坐低組第一，兩向皆可操縱。
  /// 本週期所屬的階級分組。**空值代表本週期尚未鎖定** ——
  /// 週期起點時該使用者尚未存在（或還沒得過分），無起點階級可鎖定，
  /// 故改於**首次計分時**鎖定當下階級。
  ///
  /// 這位假使用者在週期起點就存在，故已有值。
  int? lockedRankGroup = rankGroupOf(rankForExp(1700));
  int? lockedMonthlyGroup = rankGroupOf(rankForExp(1700));

  /// 呈現用的組別。尚未鎖定者先以當前階級推導，鎖定後才固定下來。
  int rankGroupNow({required bool weekly}) =>
      (weekly ? lockedRankGroup : lockedMonthlyGroup) ?? rankGroupOf(rank);

  /// 首次計分時鎖定組別。已鎖定者不動 —— 週期內升階不改變本週期的組別。
  void _lockRankGroupsIfNeeded() {
    lockedRankGroup ??= rankGroupOf(rank);
    lockedMonthlyGroup ??= rankGroupOf(rank);
  }

  // --- 每日任務 / 成就 ---
  List<DailyTask> dailyTasks = buildDailyTasks();
  late List<Achievement> achievements = buildAchievements();

  // --- 訓練進行中 ---
  WorkoutSession? session;
  DateTime? restEndsAt;

  /// 本次休息的總秒數 —— 圓環進度需要它才算得出剩餘比例。
  int restTotalSeconds = kDefaultRestSeconds;
  DateTime? lastSetCompletedAt;
  bool _lastIntervalWasFast = false;
  DateTime? blockedUntil;
  SettlementResult? lastSettlement;

  DateTime? _expGrantedOn;

  // --- 獎勵發放紀錄的兩個當日計數（〈02_Aggregate定義〉：不歸使用者） ---
  // 兩者每日 04:00 歸零，性質為機制的暫存計數器而非使用者屬性。
  DateTime? _rewardCounterDay;
  int _coinsGrantedToday = 0;
  int _scoreGrantedToday = 0;
  double _maxCompletionToday = 0;

  /// 當日訓練最高完成度（0 表示今天還沒結算過）。結算畫面用它說明為何只補差額。
  double get maxCompletionToday {
    _rollRewardCounters(businessDate(now));
    return _maxCompletionToday;
  }

  /// 換日即歸零。判定當日的界線為統一換日時點（04:00），與簽到同一條界線。
  void _rollRewardCounters(DateTime today) {
    if (_rewardCounterDay == today) return;
    _rewardCounterDay = today;
    _coinsGrantedToday = 0;
    _scoreGrantedToday = 0;
    _maxCompletionToday = 0;
  }

  // ===========================================================================
  // 持久化
  // ===========================================================================

  /// 產生新實體的識別碼。
  ///
  /// **不單用毫秒時戳**：同一毫秒內連續建立兩筆會撞號，而 id 相同的兩份
  /// 自訂訓練在任何以 id 為鍵的地方都會被當成同一份（Set 會直接吃掉一個）。
  /// 時戳保留可讀性，序號保證唯一。
  int _idSeq = 0;
  String newId(String prefix) =>
      '$prefix${now.millisecondsSinceEpoch}-${_idSeq++}';

  Store? _store;

  /// 是否已讀過存檔。未讀完之前不存 —— 否則第一次啟動時，
  /// 空白的初始狀態會在存檔讀進來之前先把它蓋掉。
  bool _hydrated = false;
  Timer? _saveTimer;

  /// 存檔已寫入的次數。示範頁用它證明「真的有存」。
  int saveCount = 0;

  /// 讀取存檔的三個階段。
  ///
  /// 有這個東西是因為：讀取完成前若讓主畫面畫出來，使用者會對著一份
  /// **假的**畫面操作——他按下的簽到會在存檔讀回來時被整個蓋掉，
  /// 而且沒有任何跡象。這正是骨架屏存在的理由，本 App 的檔案讀取
  /// 是第一個真正的非同步載入，同一條規則適用。
  HydrationPhase hydration = HydrationPhase.ready;

  /// 讀取失敗的原因與備份位置。[hydration] 為 failed 時才有值。
  StoreLoadException? hydrationError;

  /// 接上儲存並讀回上次的狀態。App 啟動時呼叫一次。
  ///
  /// 沒存過就照常開始；**讀不出來則停在錯誤狀態**，交給使用者決定
  /// 要重試還是先用示範資料進去 —— 不替他做「你的進度沒了」這個決定。
  Future<void> hydrate(Store store) async {
    _store = store;
    // 同步設定，讓 initState 之後的第一次 build 就看得到載入中。
    hydration = HydrationPhase.loading;
    hydrationError = null;
    _hydrated = false;
    try {
      final data = await store.load();
      if (data != null) {
        applySnapshot(data);
      } else {
        // **沒存過 ＝ 這台裝置上還沒有帳號。**
        //
        // 建構子給的是示範用的假身分（`signUpCompleted = true`），
        // 那是為了「打開就看得到內容」。但第一次進來的人看到的
        // 不該是別人的暱稱、階級與連續訓練天數 —— 那是誰的進度都不是。
        //
        // 判定寫在這個欄位而不是「有沒有存檔」上，是為了處理
        // **註冊到一半重新整理**：那時已經存過檔了，但註冊還沒完成，
        // 讀回來的 signUpCompleted 仍是 false，照樣回到註冊流程。
        signUpCompleted = false;

        // **當場歸零，不只是翻旗標。**
        //
        // 只翻旗標的話，整個註冊流程進行中，底下的狀態仍然是那位
        // 假使用者 —— 45 階、1700 經驗、12 天連續訓練。使用者只要用
        // 任何方式離開流程（瀏覽器上一頁、手勢返回、流程裡沒走完的岔路），
        // 看到的就是別人的帳號。
        //
        // 讓那個數字**根本不存在**，比在每一條離開的路上補一道防線可靠。
        resetToNewAccount();
      }
    } on StoreLoadException catch (e) {
      hydration = HydrationPhase.failed;
      hydrationError = e;
      // 停在失敗，**不開始存檔** —— 這時候寫下去等於把使用者的
      // 存檔換成一份假資料。
      notifyListeners();
      return;
    } catch (e) {
      hydration = HydrationPhase.failed;
      hydrationError = StoreLoadException('$e');
      notifyListeners();
      return;
    }
    _finishHydration();
  }

  /// 重試讀取。
  Future<void> retryHydration() async {
    final store = _store;
    if (store == null) return;
    hydration = HydrationPhase.loading;
    hydrationError = null;
    notifyListeners();
    await hydrate(store);
  }

  /// 使用者選擇不再等存檔，直接以示範資料進入。
  ///
  /// 這一步之後才開始存檔 —— 是使用者自己決定放棄那份讀不到的存檔的，
  /// 不是系統替他決定的。壞掉的原檔已由 [Store] 改名保留。
  void continueWithoutSave() {
    if (hydration != HydrationPhase.failed) return;
    _finishHydration();
  }

  void _finishHydration() {
    _hydrated = true;
    hydration = HydrationPhase.ready;
    hydrationError = null;
    // 讀回來的時間可能離現在很遠，把掛在時鐘上的排程全部補跑一次。
    runDecayCheck();
    takeAbilitySnapshot();
    resetMonthlyAiCredits();
    expireMembershipIfDue();
    resetDailyTasksIfDue();
    resetMentorWeekIfDue();
    expirePunishmentIfDue();
    runStreakCheck();
    // 存檔裡的進度可能與「今天已經發生過的事」對不起來 —— 補齊。
    reconcileDailyTasks();
    settleDueBoards();
    _syncAchievements();
    notifyListeners();
  }

  /// 每次狀態變動都排一次存檔，300ms 內的連續變動合併成一次。
  ///
  /// 不逐次立刻寫：拖一下步進器就是幾十次 notifyListeners，
  /// 每次都寫檔會讓 UI 卡住。
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_hydrated || _store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), saveNow);
  }

  /// 立即寫入。App 進背景或關閉前呼叫，才不會漏掉最後 300ms 的變動。
  Future<void> saveNow() async {
    final store = _store;
    if (store == null || !_hydrated) return;
    _saveTimer?.cancel();
    try {
      await store.save(toSnapshot());
      saveCount++;
    } catch (_) {
      // 寫不進去就算了 —— 存檔失敗不該中斷使用者正在做的事。
    }
  }

  /// 清除存檔並回到假資料的初始狀態。設定頁的「重設示範資料」用。
  Future<void> clearSaved() async {
    await _store?.clear();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  AppState() {
    _syncAchievements();
    runDecayCheck();
    runStreakCheck();
    // 記下基準日／基準月；排程要跨過一個日界或月初才真的動手。
    takeAbilitySnapshot();
    resetMonthlyAiCredits();
    resetDailyTasksIfDue();
    resetMentorWeekIfDue();
    settleDueBoards();
  }

  // -------------------------------------------------------------------------
  // 每日簽到
  // -------------------------------------------------------------------------

  bool get checkedInToday =>
      lastCheckInDate != null && lastCheckInDate == businessDate(now);

  // --- 簽到畫面一併詢問的兩個週期更新 ---

  /// 週期以「距上次填入滿 N 天」**逐使用者**計算，非全站對齊的雙週一 ——
  /// 避免批次作業，且各使用者的詢問時點自然分散。
  static const int kWeightAskDays = 14;
  static const int kSurveyAskDays = 90;

  DateTime? weightUpdatedAt;
  DateTime? surveyUpdatedAt;

  /// 跳過後，該次詢問週期內不再詢問。記的是「跳過的那一天」——
  /// 下個週期到了照樣要問，跳過不是永久關閉。
  DateTime? _weightAskSkippedAt;
  DateTime? _surveyAskSkippedAt;

  /// 計時基準取「上次填入」與「上次跳過」的較晚者。
  ///
  /// 跳過只結束**這一輪**詢問，不是永久關閉 —— 下個週期到了照樣要問，
  /// 否則跳過一次就等於使用者再也不會被問到體重。
  bool _due(DateTime? last, DateTime? skipped, int days) {
    var base = last ?? DateTime(2000);
    if (skipped != null && skipped.isAfter(base)) base = skipped;
    return now.difference(base).inDays >= days;
  }

  /// 距上次填入體重滿 14 天者，於簽到畫面一併詢問體重。
  bool get weightAskDue => _due(weightUpdatedAt, _weightAskSkippedAt, kWeightAskDays);

  /// 距上次填寫滿 90 天者，一併詢問註冊問卷的四個欄位。
  bool get surveyAskDue => _due(surveyUpdatedAt, _surveyAskSkippedAt, kSurveyAskDays);

  /// 使用者已填入體重（來源＝週期更新）。沿用註冊流程的同一 Command 與 Event。
  void updateWeight(double kg) {
    bodyweightKg = kg;
    weightUpdatedAt = now;
    notifyListeners();
  }

  /// 跳過體重：沿用上次的值，該次詢問週期內不再詢問。
  ///
  /// **不得阻擋簽到** —— 跳過即無法簽到會使連續簽到天數中斷，
  /// 該代價遠大於一筆體重資料；且強迫回報體重對有飲食失調傾向者構成實際傷害。
  void skipWeightAsk() {
    _weightAskSkippedAt = now;
    notifyListeners();
  }

  /// 註冊問卷四欄位的事後更新（來源＝週期更新）。
  ///
  /// 任一欄位更新後**立即重新推薦訓練計畫，並自動替換當前的訓練計畫**。
  /// 進行中的訓練不受影響 —— 本次訓練課表已於選擇課表時產生快照並與來源脫鉤。
  void updateSurvey({
    int? daysPerWeek,
    String? duration,
    String? commonGoal,
    String? experience,
  }) {
    if (daysPerWeek != null) this.daysPerWeek = daysPerWeek;
    if (duration != null) this.duration = duration;
    if (commonGoal != null) this.commonGoal = commonGoal;
    if (experience != null) this.experience = experience;
    surveyUpdatedAt = now;
    // 任一欄位更新即重新推薦並自動替換當前計畫。推薦為單向指派，無拒絕分支。
    currentPlan = recommendCurrentPlan() ?? currentPlan;
    notifyListeners();
  }

  /// 使用者當前的訓練計畫。註冊問卷四欄位更新時由系統自動替換。
  /// 為空值時，首頁退回「解得開的第一份官方課表」。
  WorkoutPlan? currentPlan;

  /// 依現在的器材、經驗與目標重新推薦一份官方計畫。
  ///
  /// 只從解得開的計畫裡挑 —— 自動替換成一份使用者按不下去的計畫，
  /// 等於把他的當前計畫拿走。
  WorkoutPlan? recommendCurrentPlan() {
    return recommendPlan<WorkoutPlan>(
      platformPlans
          .where((p) => p.source == PlanSource.official && planUnlocked(p))
          .toList(),
      equipment: equipmentTier,
      experience: experience,
      commonGoal: commonGoal,
      tierOf: (p) => p.equipmentTier,
      experienceOf: (p) => p.suitableExperience,
      goalsOf: (p) => p.suitableGoals,
    );
  }

  /// 跳過問卷：沿用原值，該詢問週期內不再詢問。同樣不得阻擋簽到。
  void skipSurveyAsk() {
    _surveyAskSkippedAt = now;
    notifyListeners();
  }

  void checkIn() {
    if (checkedInToday) return;
    final today = businessDate(now);

    // 每日簽到紀錄寫入該日一筆，簽到方式＝真實簽到。
    _recordCheckIn(today, CheckInMethod.real);

    // 連續天數一律**自紀錄逐日推算**，與補簽共用同一套算法。
    // 簽到用「距上次滿 36 小時」遞增、補簽用逐日推算的話，同一個數字
    // 會有兩種算法，兩邊遲早給出不同的答案。
    // 累計天數與歷史最長連續天數皆為單調遞增。
    checkInTotal += 1;
    checkInLongest = math.max(checkInLongest, checkInStreak);

    // 簽到獎勵：經驗值 10 ＋ 金幣 10
    totalExp += kCheckInExp;
    coins += kCheckInCoin;

    // 簽到恢復 —— 預告階段歸零，下一次中斷才會重新發。
    _checkInNoticeStage = CheckInStage.normal;
    _bumpTasks('使用者已簽到', 1);
    _syncAchievements();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 每日任務
  // -------------------------------------------------------------------------

  /// 測試用：直接餵一次判定來源 Event。任務項目為可組態的 Event 訂閱，
  /// 從外面推一次 Event 正是它該有的驅動方式。
  @visibleForTesting
  void bumpTaskForTest(String event) {
    _bumpTasks(event, 1);
    notifyListeners();
  }

  void _bumpTasks(String event, int n) {
    for (final t in dailyTasks) {
      if (t.sourceEvent == event && !t.done) {
        t.progress = math.min(t.target, t.progress + n);
        if (t.done) _gainPersonalScore(kDailyTaskScorePerItem);
      }
    }
    if (dailyTasks.every((t) => t.done)) {
      // 全部完成加碼 20 分（僅加一次，以 claimed 之外的旗標避免重複）
      if (!_allTasksBonusGiven) {
        _allTasksBonusGiven = true;
        _gainPersonalScore(kDailyTaskAllBonusScore);
      }
    }
  }

  /// 「個人排行榜分數已增加」的唯一入口。
  ///
  /// **團隊日常分數在這裡同額累加** —— 模型明訂它是團隊自有的計數器，
  /// 於成員每次得分時同額增量累加，而**不是**全體成員月累計分數的加總：
  /// 後者與「重新分隊期不累加」「中途加入者只貢獻加入後的分數」兩條規則
  /// 在數學上無法同時成立。
  ///
  /// 三個來源共用本入口：訓練結算、每日任務進度、每日任務全部完成。
  void _gainPersonalScore(int n, {bool monthly = false}) {
    if (n <= 0) return;
    // 週期中新加入者於**首次計分時**鎖定當下階級 ——
    // 週期起點時他還不存在，沒有起點階級可鎖。
    _lockRankGroupsIfNeeded();
    weeklyScore += n;
    if (monthly) monthlyScore += n;

    // 個人分數本身不受加入或退出影響 —— 上面兩行無論如何都要跑完，
    // 底下的團隊累加才是有條件的。
    final t = myTeam;
    if (t == null) return;
    // 該成員於得分當下須為本團隊成員。
    if (!t.members.any((m) => m.name == displayName)) return;
    // 重新分隊期內兩個團隊分數皆不累加；限制的是隊，不是練。
    if (inRegroupWindow(now)) return;
    // 中途加入者僅能貢獻加入後產生的分數 —— 由「當下累加」自然成立，
    // 加入前的個人分數本就沒有經過這裡。
    t.contributions[displayName] = (t.contributions[displayName] ?? 0) + n;
  }

  bool _allTasksBonusGiven = false;
  bool get allTasksDone => dailyTasks.every((t) => t.done);

  /// 上次重置所屬的業務日。**冪等**：跨時區移動導致同一當地日期
  /// 重複觸發重置時由此擋下，不會重置兩次。
  DateTime? _dailyTaskDay;

  /// 每日任務已重置 —— 當地 04:00，與簽到同一個換日時點。
  /// 模型中不存在第二個換日時點。
  ///
  /// 真實系統由排程觸發；本專案於進入任務相關畫面與示範時鐘推進時呼叫，
  /// 效果相同：使用者看到的一定是已經重置過的狀態。
  /// 回傳 true 表示這次真的重置了。
  bool resetDailyTasksIfDue() {
    final today = businessDate(now);
    if (_dailyTaskDay == null) {
      _dailyTaskDay = today; // 第一次只記日期，不重置
      return false;
    }
    if (_dailyTaskDay == today) return false;
    _dailyTaskDay = today;

    // 重置時當日已完成但未領取的獎勵，一律補發至獎勵信箱，不作廢 ——
    // 完成任務是使用者已付出的行為，因忘記點擊而失去獎勵形同懲罰已完成的人。
    for (final t in dailyTasks) {
      if (!t.done || t.claimed) continue;
      mailbox.insert(
        0,
        MailReward(
          source: '每日任務未領取　「${t.name}」',
          coins: kDailyTaskCoin,
          at: now,
        ),
      );
    }

    // 限時任務的當日有效時窗也在此結束：未領取的獎勵補發至信箱，
    // **不作廢** —— 忘記點擊而失去獎勵，形同懲罰已完成任務的人。
    sweepTimedRewardToMailbox();
    // 限時任務為**每日指派**，每日換一組。指派日往前滾一天，
    // 昨日的完成紀錄與領取旗標一併歸零 —— 前一日的仍可補做的話，
    // 兩組任務會疊在一起，「限時」就失去意義。
    timedTask = TimedTask(
      title: timedTask.title,
      detail: timedTask.detail,
      // 存指派的時點，不存營業日 —— businessDate 會把 00:00 判回前一天，
      // 再包一層就會算出昨天。
      assignedOn: now,
    );
    timedRewardClaimed = false;
    myTeam?.timedCredited.clear();

    // 自任務池隨機抽取指派。允許與前一日重複，不做跨日去重。
    redrawDailyTasks();
    // 進度的計數範圍限當日，隨重置清空；全部完成的加碼旗標同樣歸零。
    _allTasksBonusGiven = false;
    notifyListeners();
    return true;
  }

  void claimTask(DailyTask t) {
    if (!t.done || t.claimed) return;
    t.claimed = true;
    coins += kDailyTaskCoin;
    notifyListeners();
  }

  void claimAllTasks() {
    for (final t in dailyTasks) {
      if (t.done && !t.claimed) {
        t.claimed = true;
        coins += kDailyTaskCoin;
      }
    }
    if (allTasksDone) coins += 4; // 全部完成加碼金幣
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 成就
  // -------------------------------------------------------------------------

  int currentProgressFor(String category) {
    switch (category) {
      case '連簽':
        return checkInStreak;
      case '累簽':
        return checkInTotal;
      case '連續訓練':
        return trainingStreakDays;
      case '累積訓練':
        // 門檻計的是天數不是次數。
        return totalWorkoutDays;
      case '新手任務':
        // 新手任務為三選一，完成即 1。模型的〈成就獎勵的數額〉列本類 9 枚，
        // 但其判定來源寫的是「新手任務完成」——一個一次性的布林事實撐不起
        // 9 個門檻。此處據實回報，其餘 8 枚維持未解鎖，待模型澄清。
        return noviceFinished ? 1 : 0;
      case '粉絲':
        // 粉絲數為使用者 Aggregate 的儲存欄位，不變條件為
        // 「粉絲數 ＝ 關注關係中被關注者為本人的筆數」。
        return followerCount;
      case '能力值':
        return points.values.reduce(math.max);
      case '階級':
        return rank;
      default:
        // 互動四類。**每日上限只擋獎勵發放，不擋成就計數** ——
        // 故這裡讀的是終身累計，不是當日計數。
        return interactionTotals[category] ?? 0;
    }
  }

  /// 互動的終身累計，四種各自計數。
  final Map<String, int> interactionTotals = {
    '分享': 26,
    '發文': 18,
    '按讚': 143,
    '留言': 41,
  };

  /// 存檔套用完畢後補跑一次解鎖判定。供 [applySnapshot] 使用。
  void syncAchievementsAfterLoad() => _syncAchievements();

  /// 全部歸為未解鎖。**只有換帳號時才可以呼叫** ——
  /// 同一個帳號存續期間，解鎖紀錄單調遞增、一經解鎖不可撤銷。
  void _relockAchievements() {
    for (final a in achievements) {
      a.unlocked = false;
      a.claimed = false;
      a.unlockedAt = null;
    }
  }

  List<Achievement> _syncAchievements() {
    final newly = <Achievement>[];
    for (final a in achievements) {
      if (!a.unlocked && currentProgressFor(a.category) >= a.threshold) {
        // 已解鎖紀錄為單調遞增，一經解鎖不可撤銷。
        a.unlocked = true;
        a.unlockedAt = now;
        newly.add(a);
      }
    }
    return newly;
  }

  void claimAchievement(Achievement a) {
    if (!a.unlocked || a.claimed) return;
    a.claimed = true;
    coins += a.rewardCoins;
    totalExp += a.rewardExp;
    _syncAchievements();
    notifyListeners();
  }

  void claimAllAchievements() {
    for (final a in achievements.where((x) => x.unlocked && !x.claimed)) {
      a.claimed = true;
      coins += a.rewardCoins;
      totalExp += a.rewardExp;
    }
    _syncAchievements();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 訓練
  // -------------------------------------------------------------------------

  /// 該動作最近一次的逐組實績 —— 帶入來源。
  ///
  /// 粒度為**組**而非整場：訓練歷史只收已完成的組，故中斷或提前結束的訓練
  /// 中已完成的組仍是合法來源，而未完成的組本就不在裡面。
  /// 不以「整場訓練狀態為已完成」篩選 —— 那會連帶丟棄中斷訓練中確實完成的組。
  List<ActualSet> lastActualSets(String exerciseId) {
    final sorted = history.toList()..sort((a, b) => b.date.compareTo(a.date));
    for (final h in sorted) {
      for (final e in h.exercises) {
        if (e.id != exerciseId || e.sets.isEmpty) continue;
        return [for (final t in e.sets) (weight: t.$1, reps: t.$2)];
      }
    }
    return const [];
  }

  /// 逐組決定快照的目標重量：曾記錄過該動作者帶入最近一次的實際重量，
  /// 未曾記錄者由 Epley ＋ DOTS 依體重與性別推算，**不沿用來源課表的值**。
  List<PlannedSet> _snapshotTargets(PlanExercise pe) {
    final last = lastActualSets(pe.exercise.id);
    final carried = carryForward(last, pe.planned.length);
    if (carried.isNotEmpty) {
      return [
        for (var i = 0; i < pe.planned.length; i++)
          // 帶入的是重量；目標次數仍取自課表。
          PlannedSet(carried[i], pe.planned[i].targetReps),
      ];
    }
    final dim = pe.exercise.dim;
    return [
      for (final s in pe.planned)
        PlannedSet(
          suggestedWeight(
            exercise: pe.exercise,
            dimPoints: dim == null ? kInitialPoints : points[dim]!,
            bodyweightKg: bodyweightKg,
            isMale: isMale,
            targetReps: s.targetReps,
          ),
          s.targetReps,
        ),
    ];
  }

  // --- 本次訓練器材已解鎖 ---

  /// 本次訓練是否已解鎖器材。**預設僅對本次訓練有效，訓練結束即失效。**
  bool sessionEquipmentUnlocked = false;

  /// 3 級器材對應的細層品項 —— 持有器材明細為空值時的退回基準。
  Set<String> _itemsForTier(String tier) {
    final venue = tier.startsWith('健身房')
        ? '健身房'
        : tier.startsWith('居家')
            ? '居家'
            : '徒手';
    return {
      for (final e in kEquipmentItems)
        if (kEquipmentVenues[e]!.contains(venue)) e,
    };
  }

  /// 比對基準：持有器材明細有值時以其為準，為空值者退回註冊填入的 3 級器材。
  Set<String> get availableEquipment {
    if (ownedEquipment.isNotEmpty) return ownedEquipment;
    return _itemsForTier(equipmentTier);
  }

  /// 動作庫與加入動作的器材篩選基準。解鎖期間全部器材視為可用。
  Set<String> get equipmentForFiltering =>
      sessionEquipmentUnlocked ? kEquipmentItems.toSet() : availableEquipment;

  /// 本次訓練課表內做不了的動作 —— 其所需器材明細未為可用器材所涵蓋。
  ///
  /// 比對粒度為細層 8 品項（課表選擇頁的「所需器材」為粗層 3 級，兩者並存）。
  /// 所需器材明細為空值者不參與比對，視為可執行。
  List<PlanExercise> unavailableExercises() {
    final s = session;
    if (s == null || sessionEquipmentUnlocked) return const [];
    final have = availableEquipment;
    return [
      for (final pe in s.exercises)
        if (() {
          final need = requiredEquipment(pe.exercise.equipment);
          return need.isNotEmpty && !need.every(have.contains);
        }())
          pe,
    ];
  }

  /// 本次解鎖會用到、但目前沒有的器材品項。勾選套用至未來時寫回的就是這些。
  Set<String> missingEquipment() {
    final have = availableEquipment;
    return {
      for (final pe in unavailableExercises())
        ...requiredEquipment(pe.exercise.equipment).where((e) => !have.contains(e)),
    };
  }

  /// 系統執行「解鎖本次訓練器材」。
  ///
  /// 解鎖無「否」的分支：使用者選了健身房課表即代表他今天在健身房。
  /// [applyToFuture] 預設不勾 —— 使用者可能只是今天借用場地，系統自行寫回
  /// 會使其後的課表推薦與動作庫篩選全部跟著錯，而且他不會知道系統改過。
  void unlockSessionEquipment({bool applyToFuture = false}) {
    if (session == null) return;
    final missing = missingEquipment();
    sessionEquipmentUnlocked = true;
    if (applyToFuture) {
      // 寫回持有器材明細。為空值者原本走 3 級退回，寫回時須把退回的基準
      // 一併落地，否則寫回一個品項反而讓可用器材變少。
      if (ownedEquipment.isEmpty) ownedEquipment.addAll(availableEquipment);
      ownedEquipment.addAll(missing);
    }
    notifyListeners();
  }

  /// 使用者已選擇訓練課表 → 產生本次訓練課表快照。
  ///
  /// **快照於選擇課表時即產生，非等到開始訓練** —— AI 訓練前調整改的就是它。
  /// 故同一份課表重複呼叫時**不重建快照**：重建會把剛剛調好的內容洗掉，
  /// 使用者按「開始訓練」就會發現 AI 調整白做了。
  void startWorkout(WorkoutPlan plan) {
    if (session != null && session!.plan.id == plan.id) {
      notifyListeners();
      return;
    }
    // 新的一次訓練＝新的一段調整流程。「拒絕後不可重新提出」的範圍是
    // 那一次訓練，不是這個人的餘生。
    aiReset(AiSource.beforeTraining);
    aiReset(AiSource.planAdjust);
    aiReset(AiSource.duringTraining);
    // 帶入只影響快照，不改動來源課表的目標重量。
    session = WorkoutSession.start(
      plan,
      now,
      targets: [for (final pe in plan.exercises) _snapshotTargets(pe)],
    );
    restEndsAt = null;
    lastSetCompletedAt = null;
    _lastIntervalWasFast = false;
    blockedUntil = null;
    sessionEquipmentUnlocked = false;
    notifyListeners();
  }

  /// 休息秒數的取值優先序：課表指定值 → 該動作的預設組間休息秒數 → 全站預設 90 秒。
  /// 休息秒數為動作層級，不逐組設定。
  int restSecondsFor(PlanExercise pe) =>
      pe.restSeconds ??
      exerciseById(pe.exercise.id).defaultRestSeconds ??
      kDefaultRestSeconds;

  int get restRemaining {
    if (restEndsAt == null) return 0;
    final s = restEndsAt!.difference(now).inSeconds;
    return s > 0 ? s : 0;
  }

  /// 防作弊剩餘阻擋秒數，僅於阻擋生效期間有值。
  int get blockRemaining {
    if (blockedUntil == null) return 0;
    final s = blockedUntil!.difference(now).inSeconds;
    return s > 0 ? s : 0;
  }

  /// 逾時中斷判定：40 分鐘內未完成任何一組。
  bool get isIdleTimedOut {
    final s = session;
    if (s == null) return false;
    final since = lastSetCompletedAt ?? s.startedAt;
    return now.difference(since).inMinutes >= kIdleTimeoutMinutes;
  }

  SetRecord? get currentRecord {
    final s = session;
    if (s == null) return null;
    if (s.exerciseIndex >= s.records.length) return null;
    final l = s.records[s.exerciseIndex];
    if (s.setIndex >= l.length) return null;
    return l[s.setIndex];
  }

  /// 改這一組的重量與次數。
  ///
  /// **重量 ≥ 0，精度 0.5 公斤**（0 代表徒手）；**次數為整數且 ≥ 1**
  /// —— 模型明訂不記錄次數為 0 的失敗組，故下限是 1 不是 0。
  void editCurrentSet({double? weight, int? reps}) {
    final r = currentRecord;
    if (r == null) return;
    if (weight != null) {
      final w = math.max(0.0, weight);
      // 收斂到 0.5 的格子上：+/- 0.5 之外，直接輸入的值也走同一條。
      r.weight = (w * 2).roundToDouble() / 2;
    }
    if (reps != null) r.reps = math.max(1, reps);
    notifyListeners();
  }

  /// 記錄該組成績 ＋ 完成該組（模型中由同一次勾選同時產生兩個 Event）。
  /// 回傳 false 表示被防作弊規則擋下。
  bool completeCurrentSet() {
    final s = session;
    final r = currentRecord;
    if (s == null || r == null) return false;
    final now = this.now;

    if (blockRemaining > 0) return false;

    if (lastSetCompletedAt != null) {
      final gap = now.difference(lastSetCompletedAt!).inSeconds;
      final fast = gap < kMinSetIntervalSeconds;
      if (fast && _lastIntervalWasFast) {
        // 阻擋解除時點自前一組的完成時戳起算滿 30 秒。
        blockedUntil = lastSetCompletedAt!.add(const Duration(seconds: kMinSetIntervalSeconds));
        notifyListeners();
        return false;
      }
      // 出現一次 ≥ 30 秒的正常間隔後，快速勾選的額度回復。
      _lastIntervalWasFast = fast;
    }

    r.state = SetState.done;
    lastSetCompletedAt = now;
    blockedUntil = null;
    _bumpTasks('使用者已完成該組', 1);
    _advance(startRest: true);
    notifyListeners();
    return true;
  }

  /// Command「加入動作至本次訓練」—— Actor：使用者。
  ///
  /// 兩種入口共用本路徑：**空白課表取得其第一個動作**、
  /// 一般課表於訓練中臨時加練計畫外的動作。
  ///
  /// 本 Command 對總計畫組數**只增不減**，已加入的動作與組不可再移除；
  /// 不想練的組不勾選即可，該組不計入已完成組數，僅使進度百分比低於 100%。
  void addExerciseToSession(Exercise exercise, List<PlannedSet> planned) {
    final s = session;
    // Precondition：本次訓練狀態為進行中，且尚未結算。
    if (s == null || planned.isEmpty) return;

    // 只改本次訓練課表快照，不改來源課表，亦不改任何自訂訓練 Aggregate。
    s.exercises.add(PlanExercise(exercise: exercise, planned: planned));
    // 加入的組無快照帶入值 —— 目標重量與次數由使用者於加入時指定。
    s.records.add(planned
        .map((p) => SetRecord(weight: p.targetWeight, reps: p.targetReps))
        .toList());

    // 沒有「目前動作」時把游標移到剛加入的這個 ——
    // 空白課表的第一個動作，以及全部做完之後再加練，都走這條。
    if (currentRecord == null) {
      s.exerciseIndex = s.records.length - 1;
      s.setIndex = 0;
    }
    notifyListeners();
  }

  /// 使用者已還原被替換的動作。
  /// 只改本次訓練課表快照，組數與各組目標沿用 —— 換的是動作，不是課表結構。
  void restoreReplacedExercise(int index) {
    final s = session;
    if (s == null || index < 0 || index >= s.exercises.length) return;
    final pe = s.exercises[index];
    final origin = pe.replacedFrom;
    if (origin == null) return;
    s.exercises[index] = PlanExercise(
      exercise: origin,
      planned: pe.planned,
      restSeconds: pe.restSeconds,
    );
    notifyListeners();
  }

  /// 略過目前這一組 —— 不想練的組不勾選即可，該組不計入已完成組數，
  /// 僅使進度百分比低於 100%。這**不是**「使用者已取消該組」：
  /// 那一個的 Precondition 是該組已經完成過，見 [uncheckSet]。
  void cancelCurrentSet() {
    final r = currentRecord;
    if (r == null) return;
    r.state = SetState.skipped;
    _advance(startRest: false);
    notifyListeners();
  }

  /// Command「取消該組」—— Actor：使用者。
  ///
  /// Precondition：該組已發生「使用者已完成該組」，且本次訓練尚未結算。
  /// 健身時單手操作與誤觸是常態；不允許取消會迫使使用者留下錯誤紀錄，
  /// 而那筆紀錄直接餵給能力值與個人排行榜分數。
  ///
  /// Postcondition：原組紀錄標記已取消、**不實體刪除**，移入
  /// [WorkoutSession.cancelled]；該組回到未完成，進度條隨之回退。
  /// 再次勾選時**新建一筆**組紀錄 —— 此處即把該列換成新的一筆。
  bool uncheckSet(int exerciseIndex, int setIndex) {
    final s = session;
    if (s == null) return false;
    if (exerciseIndex < 0 || exerciseIndex >= s.records.length) return false;
    final l = s.records[exerciseIndex];
    if (setIndex < 0 || setIndex >= l.length) return false;
    final r = l[setIndex];
    if (r.state != SetState.done) return false;

    r.state = SetState.cancelled;
    s.cancelled.add(CancelledSet(
      exerciseIndex: exerciseIndex,
      setIndex: setIndex,
      record: r,
      at: now,
    ));
    // 新建一筆：目標值取自快照，不沿用被取消那筆改過的實績。
    final target = s.exercises[exerciseIndex].planned[setIndex];
    l[setIndex] = SetRecord(
      weight: target.targetWeight,
      reps: target.targetReps,
    );
    // 游標移到該組，使用者才改得了重量再重做。
    s.exerciseIndex = exerciseIndex;
    s.setIndex = setIndex;
    restEndsAt = null;
    notifyListeners();
    return true;
  }

  /// 「組間休息已結束」為多對一 —— 跳過由使用者觸發。
  void skipRest() => _endRest();

  /// 「組間休息已結束」為多對一 —— 計時結束由系統觸發。
  void endRestByTimer() => _endRest();

  void _endRest() {
    if (restEndsAt == null) return;
    restEndsAt = null;
    notifyListeners();
  }

  void _advance({required bool startRest}) {
    final s = session!;
    // 休息屬於「剛完成的那一組」所在的動作 —— 索引推進前先取。
    final justCompleted = s.exercises[s.exerciseIndex];
    final l = s.records[s.exerciseIndex];
    final isLastSetOfExercise = s.setIndex >= l.length - 1;
    final isLastExercise = s.exerciseIndex >= s.records.length - 1;

    if (isLastSetOfExercise) {
      if (!isLastExercise) {
        s.exerciseIndex += 1;
        s.setIndex = 0;
      } else {
        // 最後一組做完了，游標往界外推一格。
        //
        // 原本停在最後一組上不動，於是 [currentRecord] 一直回傳那筆已完成的
        // 紀錄：畫面在 13/13 組、完成度 100% 的情況下，還是顯示
        // 「目前動作　第 3/3 組」與一整組可編輯的步進器，
        // 而「所有組皆已處理，可以結束訓練了」那句永遠不會出現。
        s.setIndex = l.length;
      }
    } else {
      s.setIndex += 1;
    }

    // 最後一組之後沒有休息。
    final finished = isLastSetOfExercise && isLastExercise;
    if (startRest && !finished) {
      restTotalSeconds = restSecondsFor(justCompleted);
      restEndsAt = now.add(Duration(seconds: restTotalSeconds));
    } else {
      restEndsAt = null;
    }
  }

  bool get allSetsHandled {
    final s = session;
    if (s == null) return false;
    return s.records.every((l) => l.every((r) => r.state != SetState.pending));
  }

  // -------------------------------------------------------------------------
  // 訓練結算
  // -------------------------------------------------------------------------

  SettlementResult finishWorkout(EndKind kind) {
    final s = session!;
    // 走示範時鐘，不是系統時鐘 —— 退步、簽到、冷卻、會員到期全都掛在
    // 示範時鐘上，訓練結算若用系統時鐘，快轉一天再練會被當成同一天，
    // 連續訓練天數與累積訓練天數都不會動。
    final now = this.now;
    final today = businessDate(now);
    final rankBefore = rank;

    // --- 能力值：依該組實際重量與次數估算 1RM，不受終止方式影響 ---
    final bestByDim = <Dim, int>{};
    // 重設退步計時的維度。**與加分的維度不同**：
    // 自建動作不加分，卻是使用者確實訓練過該肌群的證據，足以證明其未中斷；
    // 有氧的所屬肌群為空值，不重設任何維度。
    final touchedDims = <Dim>{};
    for (var i = 0; i < s.records.length; i++) {
      final pe = s.exercises[i];
      for (final r in s.records[i]) {
        if (r.state != SetState.done) continue;
        final w = pe.exercise.isBodyweight ? bodyweightKg + r.weight : r.weight;
        final score = measuredScore(
          weightKg: w,
          reps: r.reps,
          relativeIntensity: pe.exercise.relativeIntensity,
          bodyweightKg: bodyweightKg,
          isMale: isMale,
        );
        // 有氧（肌群為空值）與自建動作皆不產生「能力值已提升」。
        final d = pe.exercise.dim;
        if (d == null) continue;
        touchedDims.add(d);
        if (pe.exercise.isCustom) continue;
        bestByDim[d] = math.max(bestByDim[d] ?? 0, score);
      }
    }

    final gains = <Dim, int>{};
    bestByDim.forEach((d, measured) {
      final g = applySessionGain(
        current: points[d]!,
        measured: measured,
        pending: pending[d]!,
        isFirstSessionForDim: !trainedDims.contains(d),
      );
      points[d] = g.newPoints;
      pending[d] = g.newPending;
      trainedDims.add(d);
      if (g.delta > 0) gains[d] = g.delta;
    });

    // --- 退步計時器：被訓練的維度重設計時，累積退步量歸零 ---
    for (final d in touchedDims) {
      decayTimers[d]!.resetOn(today);
    }
    // 一旦產生任何一筆訓練紀錄，回歸任務的逾期連續計數歸零，指派機制重新啟動。
    // 計數為衍生值，故歸零的做法是切斷連續 —— 記一筆非逾期的界樁，
    // 而不是改寫一個計數器。
    if (touchedDims.isNotEmpty && returnTaskOverdueStreak > 0) {
      returnTaskLog.add((assignedAt: today, overdue: false));
    }

    // --- 連續訓練天數 ---
    // 次數每場都加；天數與連續天數只在該日第一場加。
    totalWorkouts += 1;
    if (lastTrainedDate != today) {
      // 距上次訓練日的日界未超過 36 小時者續計 —— 與 [runStreakCheck]
      // 的中斷判定共用同一條規則，兩邊各寫一份就會對不起來。
      trainingStreakDays =
          streakContinues(lastTrainedDate, now) ? trainingStreakDays + 1 : 1;
      // 訓練恢復 —— 預告階段歸零，下一次中斷才會重新發。
      _trainNoticeStage = DecayStage.normal;
      lastTrainedDate = today;
      totalWorkoutDays += 1;
    }

    // --- 獎勵 ---
    _rollRewardCounters(today);
    final rewards = computeSettlement(
      kind: kind,
      source: s.plan.source,
      doneSets: s.doneSets,
      plannedSets: s.plannedSets,
      streakDays: trainingStreakDays,
      expAlreadyGrantedToday: _expGrantedOn == today,
      coinsGrantedToday: _coinsGrantedToday,
      scoreGrantedToday: _scoreGrantedToday,
    );
    if (rewards.exp > 0) _expGrantedOn = today;
    totalExp += rewards.exp;
    coins += rewards.coins;
    // 當日計數只增不減 —— 上限是「當日最高完成度所對應的額度」，
    // 今天先練完整場、再隨便練一場，第二場不會把額度往下拉。
    _coinsGrantedToday += rewards.coins;
    _maxCompletionToday = math.max(_maxCompletionToday, rewards.completion);
    if (rewards.leaderboardScore != null) {
      _scoreGrantedToday += rewards.leaderboardScore!;
      if (rewards.leaderboardScore! > 0) {
        _gainPersonalScore(rewards.leaderboardScore!, monthly: true);
        leaderboardUpdatedAt = now;
      }
    }

    _bumpTasks('使用者已完成訓練', 1);
    final newly = _syncAchievements();

    final duration = now.difference(s.startedAt);
    final result = SettlementResult(
      plan: s.plan,
      kind: kind,
      rewards: rewards,
      gains: gains,
      pointsAfter: Map.of(points),
      measured: Map.of(bestByDim),
      doneSets: s.doneSets,
      plannedSets: s.plannedSets,
      duration: duration,
      volume: s.volume,
      calories: estimateCalories(
        minutes: math.max(1, duration.inMinutes),
        bodyweightKg: bodyweightKg,
      ),
      streakDays: trainingStreakDays,
      rankBefore: rankBefore,
      rankAfter: rank,
      newlyUnlocked: newly,
    );

    // AI 自動優化的每 3 次計數。三種終止方式皆計入；
    // 一組都沒完成的訓練不構成歷史訓練資料，故不計。
    _bumpAutoOptimize(anySetDone: s.doneSets > 0);

    // 訓練紀錄於結算時凍結，寫入訓練歷史。
    // **只收已完成的組** —— 未完成的組不產生實績，也不得成為下次的帶入來源。
    final logged = <HistoryExercise>[];
    for (var i = 0; i < s.exercises.length; i++) {
      final pe = s.exercises[i];
      final done = [
        for (final r in s.records[i])
          if (r.state == SetState.done) (r.weight, r.reps),
      ];
      if (done.isEmpty) continue;
      logged.add(HistoryExercise(
        pe.exercise.name,
        done,
        id: pe.exercise.id,
        isTimed: pe.exercise.isBodyweight,
      ));
    }
    if (logged.isNotEmpty) {
      history.insert(
        0,
        HistoryEntry(
          now,
          s.plan.name,
          s.volume,
          math.max(1, duration.inMinutes),
          result.calories,
          logged,
        ),
      );
    }

    // 自訂訓練的「上次訓練日期／上次完成度」——
    // 課表選擇頁要講得出這份課表我上次練得怎麼樣。
    for (final p in customPlans) {
      if (p.id != s.plan.id) continue;
      p.lastTrainedAt = now;
      p.lastCompletion = result.plannedSets == 0
          ? null
          : result.doneSets / result.plannedSets;
    }

    lastSettlement = result;
    session = null;
    restEndsAt = null;
    // 解鎖僅對本次訓練有效，訓練結束即失效。
    sessionEquipmentUnlocked = false;
    notifyListeners();
    return result;
  }

  void abandonWorkout() {
    session = null;
    restEndsAt = null;
    sessionEquipmentUnlocked = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 排行榜（假資料，名次視窗為自己上下各 10 名）
  // -------------------------------------------------------------------------

  List<LeaderboardEntry> leaderboardWindow({required bool weekly}) {
    final myScore = weekly ? weeklyScore : monthlyScore;
    final rnd = math.Random(weekly ? 7 : 30);
    final myPos = 11 + rnd.nextInt(40);
    final out = <LeaderboardEntry>[];
    for (var off = -10; off <= 10; off++) {
      final pos = myPos + off;
      if (pos < 1) continue;
      if (off == 0) {
        out.add(LeaderboardEntry(pos, displayName, myScore, isSelf: true));
      } else {
        final delta = (-off) * (18 + rnd.nextInt(14));
        final sc = math.max(0, myScore + delta);
        out.add(LeaderboardEntry(pos, kOpponentNames[(pos * 3) % kOpponentNames.length], sc));
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // 排行榜週期結算
  // -------------------------------------------------------------------------

  /// 排行榜歷史紀錄 Aggregate。一經寫入不可修改 —— 沒有它，
  /// 「我第 3 名卻沒拿到獎勵」就無從查證，排行獎勵成為不可稽核的發放。
  final List<LeaderboardHistory> leaderboardHistory = [];

  /// 我在個人榜上的名次。沿用畫面那份名次視窗，兩者不會對不起來。
  int myPlace({required bool weekly}) =>
      leaderboardWindow(weekly: weekly).firstWhere((e) => e.isSelf).position;

  /// 結算一個榜別：寫歷史 → 達獎勵名次者補發至信箱 → 歸零該榜的計數器。
  ///
  /// 獎勵**不於結算時自動入帳**：三個排行獎勵採點擊領取，領取位置為獎勵信箱
  /// —— 它們產生於週一／每月 1 日 04:00，當下使用者不在 App。
  LeaderboardHistory? settleBoard(Board board) {
    final (from, to) = periodOf(board, now);
    final String group;
    final String subject;
    final int place;
    final int score;

    switch (board) {
      case Board.personalWeekly:
      case Board.personalMonthly:
        final weekly = isWeekly(board);
        group = rankGroupLabel(rankGroupNow(weekly: weekly));
        subject = displayName;
        place = myPlace(weekly: weekly);
        score = weekly ? weeklyScore : monthlyScore;
      case Board.teamDaily:
      case Board.teamTimed:
        final mine = myTeamOnBoard;
        if (mine == null) return null;
        // 本週期自始至終未達人數下限者，排除於排行榜與獎勵之外。
        if (!mine.rankEligible) return null;
        final tb = board == Board.teamDaily ? TeamBoard.daily : TeamBoard.timed;
        final ranked = teamRanking(boardTeams, tb, mine.groupSize);
        final places = placesOf(
            [for (final t in ranked) teamScoreOf(t, tb)]);
        final i = ranked.indexWhere((t) => t.id == mine.id);
        if (i < 0) return null;
        group = '${mine.groupSize} 人組';
        subject = mine.name;
        place = places[i];
        score = teamScoreOf(mine, tb);
    }

    final prize = prizeFor(place);
    final row = LeaderboardHistory(
      board: board,
      periodFrom: from,
      periodTo: to,
      group: group,
      subject: subject,
      place: place,
      score: score,
      prize: prize,
    );
    leaderboardHistory.insert(0, row);

    if (!prize.isEmpty) {
      mailbox.insert(
        0,
        MailReward(
          source: '${boardMailSources[board]}　'
              '$group 第 $place 名',
          coins: prize.coins,
          exp: prize.exp,
          at: now,
        ),
      );
    }

    // 重置一次只歸零該榜別對應的計數器；經驗值不受影響，兩者是不同數值。
    switch (board) {
      case Board.personalWeekly:
        weeklyScore = 0;
        lockedRankGroup = rankGroupOf(rank);
      case Board.personalMonthly:
        monthlyScore = 0;
        lockedMonthlyGroup = rankGroupOf(rank);
      case Board.teamDaily:
        // 兩個團隊榜的週期同為每月，次月 1 日 04:00 結算並重置。
        // 歸零前的最終名次與分數已寫入歷史紀錄。
        myTeam?.contributions.clear();
      case Board.teamTimed:
        myTeam?.timedCredited.clear();
    }
    return row;
  }

  /// 週榜結算（每週一 04:00）。
  /// 各榜上次結算所屬的週期起點。冪等：同一個週期只結算一次。
  final Map<Board, DateTime> _settledPeriod = {};

  /// 系統排程：把已經跨過週期界線的榜結算掉。
  ///
  /// 週榜每週一 04:00、月榜與兩個團隊榜每月 1 日 04:00。
  /// 真實系統由排程觸發；本專案於進入排行榜相關畫面與示範時鐘推進時呼叫，
  /// 效果相同 —— 使用者看到的一定是已經結算過的狀態。
  ///
  /// 回傳這次真的結算了哪些榜。
  List<Board> settleDueBoards() {
    final done = <Board>[];
    for (final b in Board.values) {
      final (from, _) = periodOf(b, now);
      final last = _settledPeriod[b];
      if (last == null) {
        _settledPeriod[b] = from; // 第一次只記基準週期，不憑空結算一次
        continue;
      }
      if (!from.isAfter(last)) continue; // 還在同一個週期內
      _settledPeriod[b] = from;
      settleBoard(b);
      done.add(b);
    }
    if (done.isNotEmpty) {
      // 團隊限時的當日完成紀錄不跨週期保留。
      if (done.contains(Board.teamTimed)) myTeam?.timedCredited.clear();
      notifyListeners();
    }
    return done;
  }

  void settleWeekly() => settleWeekly1();

  /// 同上，另回傳寫入的那筆歷史紀錄。
  LeaderboardHistory? settleWeekly1() {
    final row = settleBoard(Board.personalWeekly);
    notifyListeners();
    return row;
  }

  /// 月結（每月 1 日 04:00）：個人月榜與兩個團隊排行榜同時結算。
  void settleMonthly() {
    settleBoard(Board.personalMonthly);
    settleBoard(Board.teamDaily);
    settleBoard(Board.teamTimed);
    // 團隊分數的週期結算：全部欄位歸零，歸零前已寫入歷史紀錄。
    final t = myTeam;
    if (t != null) t.timedCredited.clear();
    notifyListeners();
  }

  /// 上次產生日快照的業務日。
  DateTime? _lastSnapshotOn;

  /// 系統排程：產生能力值日快照。於日界保存當下的六維值。
  ///
  /// 冪等：同一個業務日只會產生一筆。
  bool takeAbilitySnapshot() {
    final today = businessDate(now);
    if (_lastSnapshotOn == today) return false;
    final base = _lastSnapshotOn;
    _lastSnapshotOn = today;
    if (base == null) return false; // 第一次只記基準日，不憑空造一筆
    // 既有快照整體往前推，今天的存為「0 天前」的前一天。
    final shifted = <int, Map<Dim, int>>{};
    final days = today.difference(base).inDays.clamp(1, 3650);
    snapshots.forEach((k, v) => shifted[k + days] = v);
    shifted[days] = {for (final d in Dim.values) d: points[d]!};
    snapshots
      ..clear()
      ..addAll(shifted);
    notifyListeners();
    return true;
  }

  /// 系統排程：重置 AI 點數月度額度。
  ///
  /// **只重置月度額度，永久點數不動** —— 永久點數不重置不過期。
  /// 非會員的月度額度歸零，會員回到當期權益值。
  DateTime? _aiResetMonth;

  bool resetMonthlyAiCredits() {
    final month = DateTime(now.year, now.month);
    if (_aiResetMonth == month) return false;
    final first = _aiResetMonth == null;
    _aiResetMonth = month;
    if (first) return false; // 第一次只記月份，不動點數
    final before = aiMonthly;
    aiMonthly = isMember ? kMonthlyAiCredits : 0;
    // 每月 1 號全站統一配發，非自訂閱日起算的個人月週期。
    _logCredit(CreditChange.monthlyGrant, aiMonthly - before, '每月配發');
    notifyListeners();
    return true;
  }

  /// 手上有的快照年齡，由新到舊。
  List<int> get snapshotAges => snapshots.keys.toList()..sort();

  /// 最接近 [target] 天前的那一筆快照的**實際**年齡；一筆都沒有時為 null。
  ///
  /// 不能用 `snapshots[30]` 直接查：快照的鍵是「幾天前」，會隨著日子往前漂，
  /// `[30, 90]` 過一天就變成 `[31, 91]`。查不到又默默退回 [points] 的話，
  /// 畫面會在「90 天前」的標籤底下給出現在的數字 —— 三個檔位長得一模一樣。
  int? snapshotAgeNear(int target) {
    if (snapshots.isEmpty) return null;
    var best = snapshotAges.first;
    for (final a in snapshotAges) {
      if ((a - target).abs() < (best - target).abs()) best = a;
    }
    return best;
  }

  /// 時間維度的檔位：現在，加上最接近 30 天與 90 天前的**實際**年齡。
  ///
  /// 標籤跟著資料走，不是資料跟著標籤走 —— 新帳號只有幾天歷史時，
  /// 檔位就只有那幾天，不會謊稱給得出 90 天前。
  List<int> get snapshotOptions {
    final out = <int>[0];
    for (final target in [30, 90]) {
      final a = snapshotAgeNear(target);
      if (a != null && a > 0 && !out.contains(a)) out.add(a);
    }
    return out;
  }

  /// 目前顯示的六維值。[snapshotDaysAgo] 一律是實際存在的鍵，
  /// 由 [setSnapshot] 保證。
  Map<Dim, int> get displayedPoints =>
      snapshotDaysAgo == 0 ? points : (snapshots[snapshotDaysAgo] ?? points);

  /// 切到某一個檔位。**吃不到的年齡會被收斂到最接近的實際快照** ——
  /// 不讓 [snapshotDaysAgo] 停在一個查無此鍵的值上。
  void setSnapshot(int daysAgo) {
    snapshotDaysAgo = daysAgo <= 0
        ? 0
        : (snapshots.containsKey(daysAgo)
            ? daysAgo
            : (snapshotAgeNear(daysAgo) ?? 0));
    notifyListeners();
  }

  // ===========================================================================
  // 社群
  // ===========================================================================

  late List<Post> posts = buildPosts();

  /// 關注關係。單向，唯一鍵為 關注者 ID ＋ 被關注者 ID ——
  /// 用集合表達，重複關注不會產生第二筆。
  final Set<String> following = {'深蹲王', 'CoreMax', '早鳥訓練'};

  /// 社群裡的人。關注／粉絲清單要呈現階級與綜合能力等級。
  late List<SocialUser> socialUsers = buildSocialUsers();

  SocialUser userOf(String name) => socialUsers.firstWhere(
        (u) => u.name == name,
        orElse: () => SocialUser(name: name, rank: 1, grade: 'E'),
      );

  /// 我的粉絲。粉絲數為使用者 Aggregate 的**儲存欄位**，非即時彙總 ——
  /// 不變條件：粉絲數 ＝ 關注關係中被關注者為本人的筆數。
  late List<String> followers = buildFollowers();
  int get followerCount => followers.length;

  /// 歷史最高粉絲數。粉絲成就依它判定 ——
  /// 粉絲數下降不撤銷任何已解鎖的粉絲成就。
  late int peakFollowerCount = followers.length;

  int get followerMilestones => followerMilestonesReached(peakFollowerCount);

  /// 他人的粉絲數。我關注／取消關注時 +1 / −1。
  late Map<String, int> otherFollowerCounts = {
    for (final u in socialUsers) u.name: 40 + u.rank * 3,
  };

  // --- 公開檔案（[BE-11] 批次 1）---

  /// uid → 暱稱。跨使用者資料在雲端以 uid 為鍵，畫面上要顯示的是暱稱，
  /// 這張表就是兩者之間的翻譯。批次 2 起的關注／貼文都靠它把
  /// 雲端的 uid 還原成畫面認得的暱稱。
  final Map<String, String> nameByUid = {};

  /// 我自己要公開出去的那一份。
  ///
  /// 可見度由 [PublicProfile.of] 依兩個開關決定，**教官身分會讓兩者失效**
  /// —— 那是規格的規定，不是這裡的判斷。
  PublicProfile myPublicProfile(String uid) => PublicProfile.of(
        uid: uid,
        displayName: displayName,
        rank: rank,
        points: points,
        abilityPublic: abilityPublic,
        overallGradePublic: overallGradePublic,
        isInstructor: isInstructor,
        followers: followerCount,
        reputation: instructorReputation,
        specialties: instructorSpecialties.toList(),
      );

  /// 把雲端讀到的其他使用者併進來（[BE-11] 批次 1）。
  ///
  /// **是併入而不是取代。** 現階段動態牆上的貼文、對話、教官清單仍指向
  /// 示範用的那幾位；直接換掉會讓那些畫面指到不存在的人。
  /// 等批次 2–4 把貼文與師徒也搬上雲，示範資料才有辦法整批退場。
  void applyPublicProfiles(List<PublicProfile> others) {
    for (final p in others) {
      nameByUid[p.uid] = p.displayName;
      if (socialUsers.any((u) => u.name == p.displayName)) continue;
      socialUsers.add(SocialUser(
        name: p.displayName,
        rank: p.rank,
        // 對方關閉了綜合等級的對外可見時，畫面顯示最低階 ——
        // 不猜、也不留空白造成版面破洞。
        grade: p.grade ?? 'E',
      ));
      otherFollowerCounts.putIfAbsent(p.displayName, () => p.followers);
    }
    notifyListeners();
  }

  /// 暱稱 → uid。[nameByUid] 的反查 —— 畫面上拿得到的是暱稱，
  /// 而雲端要的是 uid。
  String? uidOf(String name) {
    for (final e in nameByUid.entries) {
      if (e.value == name) return e.key;
    }
    return null;
  }

  // --- 關注關係上雲（[BE-11] 批次 2）---

  /// 雲端的關注關係。**空值代表不同步** —— 既有測試走這條，行為與上雲前一樣。
  FollowSource? followSource;

  /// 把 [toggleFollow] 的結果送上雲。
  ///
  /// **即發即忘，而且吞掉錯誤**：關注是樂觀更新，記憶體與畫面已經改了。
  /// 這裡失敗就讓它失敗 —— 下次登入 [applyFollows] 會以雲端為準重新對齊。
  /// 為了一次網路失敗把畫面倒回去，比晚一點才一致更難解釋。
  void _pushFollow(String name, {required bool nowFollowing}) {
    final src = followSource;
    if (src == null) return;
    final target = uidOf(name);
    // 對方不在公開檔案裡（示範用的假使用者就是這種）—— 只在本地生效。
    if (target == null) return;
    (nowFollowing ? src.follow(target) : src.unfollow(target))
        .catchError((_) {});
  }

  /// 以雲端的關注關係為準重新對齊（[BE-11] 批次 2）。
  ///
  /// **只處理認得出暱稱的 uid**：對方若還沒發布公開檔案，
  /// 這裡沒有暱稱可以填進 [following]，略過即可 —— 下次它發布了自然會出現。
  void applyFollows(Set<String> followingUids, Set<String> followerUids) {
    for (final uid in followingUids) {
      final name = nameByUid[uid];
      if (name != null) following.add(name);
    }
    for (final uid in followerUids) {
      final name = nameByUid[uid];
      if (name != null && !followers.contains(name)) followers.insert(0, name);
    }
    // 粉絲數的不變條件：等於關注關係中被關注者為本人的筆數。
    peakFollowerCount = math.max(peakFollowerCount, followers.length);
    notifyListeners();
  }

  // --- 貼文上雲（[BE-11] 批次 3）---

  /// 雲端的貼文。**空值代表不同步** —— 既有測試走這條。
  PostSource? postSource;

  /// 我自己的 uid。雲端寫入要帶作者身分；空值代表沒登入或不同步。
  String? myUid;

  /// 即發即忘地把一次社群寫入送上雲。
  ///
  /// 與關注同一套理由：畫面已經改了，這裡失敗就讓它失敗 ——
  /// 下次載入會以雲端為準。社群互動不是金流。
  void _pushSocial(Future<void> Function(PostSource src, String uid) job) {
    final src = postSource;
    final uid = myUid;
    if (src == null || uid == null) return;
    job(src, uid).catchError((_) {});
  }

  /// 把雲端的貼文併進動態牆（[BE-11] 批次 3）。
  ///
  /// **併入而非取代**：示範用的貼文還撐著「動態牆長什麼樣」這件事，
  /// 全新的平台上一篇真的貼文都沒有。同一個 ID 以雲端那份為準 ——
  /// 它帶著別人的按讚與留言，本地那份沒有。
  void applyCloudPosts(List<Post> cloud) {
    for (final p in cloud) {
      final i = posts.indexWhere((x) => x.id == p.id);
      if (i >= 0) {
        posts[i] = p;
      } else {
        posts.add(p);
      }
    }
    // 動態牆依時間由新到舊。
    posts.sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();
  }

  // --- 封鎖（獨立 Aggregate，不附屬於對話）---

  late List<BlockedUser> blockedUsers = buildBlockedUsers();

  bool isBlocked(String name) => blockedUsers.any((b) => b.name == name);

  /// 不能封鎖的理由；null 表示可以封鎖。
  ///
  /// **雙方不得為同一團隊的成員** —— 欲封鎖同隊成員者須先退出團隊。
  /// 採「禁止封鎖」而非「自動退隊」：自動退隊會使一次封鎖操作
  /// 連帶改變第三方（其餘隊友）的團隊組成。
  ///
  /// 已知代價：騷擾者為同隊隊友時，受害者須先退出團隊才能自保。
  /// 這是模型明示接受的代價，而它成立的前提正是這條 Precondition 真的擋住 ——
  /// 不擋的話，使用者付了退隊的代價卻換不到任何東西。
  String? blockBlockedReason(String name) {
    if (isBlocked(name)) return '已經封鎖過這個人了。';
    final t = myTeam;
    if (t != null && t.members.any((m) => m.name == name)) {
      return '同隊的人不能封鎖。要先退出「${t.name}」，'
          '退出後 12 小時換隊冷卻期照常適用。';
    }
    return null;
  }

  /// 使用者已封鎖對象。可封鎖從未與其對話過的對象，故不掛在對話之下。
  /// 封鎖為單向且唯一 —— 重複封鎖同一人不產生第二筆。
  ///
  /// 封鎖**不受社群功能停權限制**：功能對照表列的是發文、私訊、關注這些
  /// 對外互動，封鎖是自保。停權中的人一樣會被騷擾。
  bool blockUser(String name) {
    if (blockBlockedReason(name) != null) return false;
    blockedUsers.insert(0, BlockedUser(name, now));

    // Postcondition：自動解除**雙方**的關注關係。
    _unfollow(name);
    followers.remove(name);

    // Postcondition：自動解除師徒關係，未完成的師徒任務作廢。
    // 封鎖後該關係只剩空殼，且會繼續佔用教官的帶徒名額。
    if (myInstructor?.name == name) {
      releaseMentor(MentorReleaseReason.blocked);
    }
    notifyListeners();
    return true;
  }

  /// 取消關注的帳務處理。粉絲數為儲存欄位，非即時彙總，故得逐處維護。
  void _unfollow(String name) {
    if (!following.remove(name)) return;
    otherFollowerCounts[name] = (otherFollowerCounts[name] ?? 1) - 1;
  }

  /// 使用者已解除封鎖。
  void unblockUser(String name) {
    final before = blockedUsers.length;
    blockedUsers.removeWhere((b) => b.name == name);
    if (blockedUsers.length != before) notifyListeners();
  }

  // --- 通知 ---

  late List<AppNotification> notifications = buildNotifications();

  /// 待回應類的推播。**寫為既有 Event 的 Postcondition，不另立通知 Event** ——
  /// 這三者有明確的觸發事實（有人送出了申請），再造一個 Event 只是把同一件事記兩次。
  ///
  /// 歸第 1 級期限即將失效類：三者皆已定案有逾期機制，不處理就失效。
  void _pushPending(String sourceEvent, String title, String body) {
    notifications.insert(
      0,
      AppNotification(
        id: newId('n-pending-'),
        sourceEvent: sourceEvent,
        title: title,
        body: body,
        at: now,
        kind: NotifyKind.push,
        priority: NotifyPriority.expiring,
      ),
    );
  }

  /// 未讀數。紅點看的是這個。
  int get unreadNotifications => notifications.where((n) => !n.read).length;

  /// 今日實際會送出的推播 —— 超出同日總量上限者依優先序由低至高捨棄。
  List<AppNotification> get todaysPushes =>
      pushesWithinLimit(notifications, now);

  /// 今日被上限擋掉的推播。做成可查詢的清單而非默默丟掉：
  /// 「為什麼我沒收到提醒」要答得出來。
  List<AppNotification> get suppressedPushes {
    final sent = todaysPushes.map((n) => n.id).toSet();
    final t = now;
    return notifications
        .where((n) =>
            n.kind == NotifyKind.push &&
            n.at.year == t.year &&
            n.at.month == t.month &&
            n.at.day == t.day &&
            !sent.contains(n.id))
        .toList();
  }

  void markNotificationRead(AppNotification n) {
    if (n.read) return;
    n.read = true;
    notifyListeners();
  }

  void markAllNotificationsRead() {
    var changed = false;
    for (final n in notifications) {
      if (!n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// 發布前的內容過濾（App Store 1.2）——判定三值。
  /// Demo：以關鍵字模擬，實際由系統的自動過濾執行。
  FilterVerdict screenContent(String text) {
    const blocked = ['詐騙', '賣藥', '加賴'];
    const flagged = ['類固醇', '禁藥'];
    if (blocked.any(text.contains)) return FilterVerdict.blocked;
    if (flagged.any(text.contains)) return FilterVerdict.flagged;
    return FilterVerdict.pass;
  }

  /// 發布貼文。回傳過濾判定：
  /// 明顯違規當場攔截、不寫入任何 Aggregate；疑似違規照常發布並自動送審。
  FilterVerdict publishPost(
    String text,
    PostVisibility visibility, {
    List<String> images = const [],
  }) {
    if (communityBlocked) return FilterVerdict.blocked;
    final v = screenContent(text);
    if (v == FilterVerdict.blocked) return v;
    final post = Post(
      id: newId('p'),
      author: displayName,
      authorRank: rank,
      text: text,
      images: images,
      at: now,
      visibility: visibility,
      pendingReview: v == FilterVerdict.flagged,
    );
    posts.insert(0, post);
    _pushSocial((src, uid) => src.publish(post, authorUid: uid));
    if (v == FilterVerdict.flagged) {
      // 疑似違規者照常送出，並**自動開立檢舉案件** ——
      // 只標記不開案的話，那則內容永遠不會有人看。
      _openAutoFlagCase(
        targetKey: reportKey(ReportTarget.post, posts.first.id),
        target: ReportTarget.post,
        content: text,
        accused: displayName,
      );
    }
    coins += 5; // 發文獎勵
    _bumpTasks('發文者已發布貼文', 1);
    notifyListeners();
    return v;
  }

  // --- 互動獎勵 ---
  //
  // 四種互動獎勵**只發放經驗值，不發放金幣**，且各有每日發放次數上限：
  // 發文 1、分享 3、按讚 10、留言 5。**超過上限仍可正常操作，只是不再發放**
  // —— 擋住按讚與留言會使社群變冷清，而社群活躍本身即為平台所欲。
  //
  // 上限存在的理由：互動獎勵的經驗值推動階級，而階級解鎖進階訓練計畫、
  // 自訂訓練名額、階級成就與教官初審門檻 —— 無上限則按讚數百次即可繞過。

  final Map<String, int> _interactCounts = {};
  DateTime? _interactDay;

  /// 獎勵定義的英文鍵 → 成就類別名。兩者不同名，這張表是唯一的對應點。
  static const _interactionCategory = {
    'Share': '分享',
    'Post': '發文',
    'Like': '按讚',
    'Comment': '留言',
  };

  void _rollInteractionDay() {
    final today = businessDate(now);
    if (_interactDay == today) return;
    _interactDay = today;
    _interactCounts.clear();
  }

  int interactionsToday(String kind) {
    _rollInteractionDay();
    return _interactCounts[kind] ?? 0;
  }

  /// 已發過獎勵的互動請求識別碼。
  ///
  /// 按讚獎勵的識別碼為 **貼文 ID ＋ 互動者 ID**；互動者恆為自己，故存貼文 ID。
  /// 模型指名這就是防刷的那道防線 ——「防刷由『同一貼文只發一次』承擔，
  /// 非由回收機制承擔」。沒有它，按讚 → 取消 → 再按即可反覆領經驗值，
  /// 而每日上限 10 次擋得住總量、擋不住同一篇刷滿那 10 次。
  ///
  /// 留言的識別碼為**留言 ID**：刪除後重新留言是新的 ID，屬新的一次互動，
  /// 故留言不進本集合。
  final Set<String> _rewardedRequests = {};

  /// 供存檔讀寫 —— 這份集合必須跟著存檔走。
  Set<String> get rewardedRequests => _rewardedRequests;

  /// 發放一次互動獎勵。回傳實際發出的經驗值（達上限時為 0）。
  ///
  /// 終身計數**先於**上限判定累加：每日上限只擋獎勵發放，不擋成就計數。
  ///
  /// [requestId] 有值者採請求識別碼去重：同一識別碼只發一次獎勵，
  /// 但**成就計數照常累加** —— 成就計的是行為次數，與獎勵發放與否無關。
  int _grantInteraction(String kind, {String? requestId}) {
    _rollInteractionDay();
    final cat = _interactionCategory[kind]!;
    interactionTotals[cat] = (interactionTotals[cat] ?? 0) + 1;
    _syncAchievements();
    if (requestId != null && !_rewardedRequests.add('$kind:$requestId')) {
      return 0;
    }
    final cap = platformConfig.i('reward', 'cap$kind');
    final used = _interactCounts[kind] ?? 0;
    if (used >= cap) return 0;
    _interactCounts[kind] = used + 1;
    final exp = platformConfig.i(
        'reward', '${kind[0].toLowerCase()}${kind.substring(1)}Exp');
    totalExp += exp;
    return exp;
  }

  /// 使用者已按讚 / 已取消按讚。
  ///
  /// **取消按讚不回收已發放的獎勵** —— 按讚當下互動已經發生，
  /// 獎勵是那一刻掙得的；回收會讓人不敢按。
  void toggleLike(Post p) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    p.likedByMe = !p.likedByMe;
    p.likes += p.likedByMe ? 1 : -1;
    // 只有按讚才計任務進度；取消不倒扣。
    if (p.likedByMe) {
      _bumpTasks('使用者已按讚', 1);
      // **自己的貼文不計**：對自身貼文的按讚與留言不發放任何獎勵。
      if (!_mine(p.author)) _grantInteraction('Like', requestId: p.id);
    }
    final liked = p.likedByMe;
    _pushSocial((src, _) => src.setLike(p.id, liked: liked));
    _syncAchievements();
    notifyListeners();
  }

  int addComment(Post p, String text) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return 0;
    if (text.trim().isEmpty) return 0;
    final c = Comment(displayName, text.trim(), now);
    p.comments.add(c);
    _pushSocial((src, uid) => src.addComment(p.id, c, authorUid: uid));
    final exp = _mine(p.author) ? 0 : _grantInteraction('Comment');
    _syncAchievements();
    notifyListeners();
    return exp;
  }

  /// 發文者已分享訓練成果 → 貼文已發布 → 分享獎勵已發放。
  ///
  /// 分享出去的貼文同樣先過內容過濾（本規則同樣適用於分享至站內的貼文）。
  ({Post post, int exp})? shareWorkout(SettlementResult r, String text) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return null;
    if (screenContent(text) == FilterVerdict.blocked) return null;
    final post = Post(
      id: newId('share-'),
      author: displayName,
      authorRank: rank,
      text: text.trim().isEmpty ? '今天練完了。' : text.trim(),
      at: now,
      // 分享類貼文附帶訓練成果 —— 動態牆會把它畫成成果卡。
      attachedWorkout: '${r.plan.name}　·　'
          '${r.volume.round()} kg　·　${r.doneSets} 組',
      pendingReview: screenContent(text) == FilterVerdict.flagged,
    );
    posts.insert(0, post);
    _pushSocial((src, uid) => src.publish(post, authorUid: uid));
    _bumpTasks('使用者已發布貼文', 1);
    final exp = _grantInteraction('Share');
    _syncAchievements();
    notifyListeners();
    return (post: post, exp: exp);
  }

  bool _mine(String author) => author == displayName;

  /// 貼文已編輯。編輯前的內容與時戳寫入編輯歷史，**保留完整歷史版本**；
  /// 已編輯旗標設為真，讀者看得到「已編輯」。
  bool editPost(Post p, String text) {
    if (!_mine(p.author) || p.deleted || text.trim().isEmpty) return false;
    if (text.trim() == p.text) return false;
    p.edits.add((p.text, now));
    p.text = text.trim();
    notifyListeners();
    return true;
  }

  /// 貼文已刪除。**軟刪除**：資料保留，因為貼文可被檢舉。
  /// 已刪除貼文的按讚與留言一併隱藏但保留，供獎勵回收與成就計數判定使用。
  bool deletePost(Post p) {
    if (!_mine(p.author) || p.deleted) return false;
    p.deleted = true;
    notifyListeners();
    return true;
  }

  /// 動態牆看得到的貼文。
  List<Post> get visiblePosts => posts.where((p) => !p.deleted).toList();

  /// 留言已編輯。規則比照貼文，不另定義。
  bool editComment(Comment c, String text) {
    if (!_mine(c.author) || c.deleted || text.trim().isEmpty) return false;
    if (text.trim() == c.text) return false;
    c.edits.add((c.text, now));
    c.text = text.trim();
    notifyListeners();
    return true;
  }

  /// 留言已刪除。同樣是軟刪除，且不回收已發放的獎勵 ——
  /// 刪除後重新留言是新的留言 ID，屬新的一次互動。
  bool deleteComment(Comment c) {
    if (!_mine(c.author) || c.deleted) return false;
    c.deleted = true;
    notifyListeners();
    return true;
  }

  /// 使用者已關注帳號 / 已取消關注。
  /// Postcondition：被關注者的粉絲數 +1 / −1。
  void toggleFollow(String name) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    if (following.contains(name)) {
      _unfollow(name);
      _pushFollow(name, nowFollowing: false);
    } else {
      following.add(name);
      otherFollowerCounts[name] = (otherFollowerCounts[name] ?? 0) + 1;
      // 歷史行為計數，取消關注不扣回去。
      followTotal += 1;
      _pushFollow(name, nowFollowing: true);
    }
    notifyListeners();
  }

  /// 對方取消關注我 —— 粉絲數減少，但已解鎖的粉絲成就不撤銷。
  void loseFollower(String name) {
    if (!followers.remove(name)) return;
    notifyListeners();
  }

  void gainFollower(String name) {
    if (followers.contains(name)) return;
    followers.insert(0, name);
    peakFollowerCount = math.max(peakFollowerCount, followers.length);
    notifyListeners();
  }

  // ===========================================================================
  // 團隊
  // ===========================================================================

  Team? myTeam = buildMyTeam();

  // --- 團隊上雲（[BE-14]）---

  /// 雲端的團隊。**空值代表不同步** —— 既有測試走這條。
  TeamSource? teamSource;

  /// 即發即忘地把一次團隊異動送上雲。與其他社群寫入同一套。
  void _pushTeam(Future<void> Function(TeamSource src, String uid) job) {
    final src = teamSource;
    final uid = myUid;
    if (src == null || uid == null) return;
    job(src, uid).catchError((_) {});
  }

  /// 這位成員的 uid。示範用的假隊友不在公開檔案裡，回傳空值。
  String? _memberUid(String name) =>
      name == displayName ? myUid : uidOf(name);

  CloudMember _asCloudMember(TeamMember m) => CloudMember(
        name: m.name,
        rank: m.rank,
        role: m.role,
        joinedAt: now,
      );

  /// 以雲端的隊伍為準（[BE-14]）。
  ///
  /// **雲端有隊就以它為準、沒有就不動本機**：登入時雲端那份才是真的，
  /// 但「查不到」可能只是還沒建過隊，不該把示範用的隊伍清掉 ——
  /// 那會讓沒接後端的流程示範整個消失。
  void applyCloudTeam(CloudTeam? t) {
    if (t == null || t.disbanded) return;

    myTeam = Team(
      id: t.id,
      name: t.name,
      isPublic: t.isPublic,
      capacity: t.capacity,
      members: [
        for (final e in t.members.entries)
          TeamMember(e.value.name, e.value.rank, e.value.role),
      ],
      lockedGroupSize: t.peakSize,
    );
    notifyListeners();
  }

  bool get iAmLeader =>
      myTeam?.members.any((m) => m.name == displayName &&
          m.role == TeamRole.leader) ??
      false;

  /// 隊長已踢除成員。隊長不得踢除自己 —— 隊長離隊須經轉讓或解散。
  /// 被踢除者**不適用 12 小時換隊冷卻期**（該次離隊非其本人所為）。
  void kickMember(TeamMember m) {
    final t = myTeam;
    if (t == null || !iAmLeader) return;
    if (m.role == TeamRole.leader) return;
    if (!t.members.contains(m)) return;
    t.members.remove(m);
    final who = _memberUid(m.name);
    if (who != null) _pushTeam((src, _) => src.removeMember(t.id, who));
    notifyListeners();
  }

  /// 隊長已核准加入申請 → 使用者已加入團隊。
  ///
  /// Precondition：團隊人數未達上限（待回應的申請不佔名額，
  /// 超收由本 Command 當下擋下）。
  bool approveApplication(PendingRequest r) {
    final t = myTeam;
    if (t == null || !iAmLeader || t.isFull) return false;
    if (!t.applications.remove(r)) return false;
    final m = TeamMember(r.name, r.rank, TeamRole.member);
    t.members.add(m);
    // 加入成員與清掉那筆申請是同一件事的兩半。
    final who = _memberUid(r.name);
    if (who != null) {
      _pushTeam((src, _) async {
        await src.putMember(t.id, who, _asCloudMember(m));
        await src.dropRequest(t.id, who);
      });
    }
    notifyListeners();
    return true;
  }

  /// 隊長已拒絕加入申請。拒絕後該筆失效，使用者可再次申請。
  void rejectApplication(PendingRequest r) {
    final t = myTeam;
    if (t == null || !iAmLeader) return;
    t.applications.remove(r);
    final who = _memberUid(r.name);
    if (who != null) _pushTeam((src, _) => src.dropRequest(t.id, who));
    notifyListeners();
  }

  /// 取消一封尚未回應的邀請。失效後隊長可再次邀請。
  void cancelInvite(PendingRequest r) {
    final t = myTeam;
    if (t == null || !iAmLeader) return;
    t.invites.remove(r);
    final who = _memberUid(r.name);
    if (who != null) _pushTeam((src, _) => src.dropRequest(t.id, who));
    notifyListeners();
  }

  /// 逾期的申請與邀請 —— 送出起算 168 小時未回應即失效。
  bool expired(PendingRequest r) => !now.isBefore(r.expiresAt);

  /// 隊長已轉讓。主動轉讓與退出時的自動轉讓為多對一，此處是主動的那條。
  bool transferLeader(TeamMember to) {
    final t = myTeam;
    if (t == null || !iAmLeader || to.role == TeamRole.leader) return false;
    if (!t.members.contains(to)) return false;
    final i = t.members.indexWhere((m) => m.role == TeamRole.leader);
    final old = t.members[i];
    t.members[i] = TeamMember(old.name, old.rank, TeamRole.member);
    final j = t.members.indexOf(to);
    t.members[j] = TeamMember(to.name, to.rank, TeamRole.leader);
    // 兩個人的角色一起換。只寫一邊的話雲端會同時有兩位隊長、或一位都沒有。
    final oldUid = _memberUid(old.name);
    final newUid = _memberUid(to.name);
    if (oldUid != null && newUid != null) {
      _pushTeam((src, _) async {
        await src.putMember(t.id, oldUid, _asCloudMember(t.members[i]));
        await src.putMember(t.id, newUid, _asCloudMember(t.members[j]));
      });
    }
    notifyListeners();
    return true;
  }

  /// 使用者已領取限時任務獎勵。
  ///
  /// Precondition：「成員已完成一次限時任務」已發生，且該筆尚未領取。
  /// 「當日有效」管的是**完成任務**的期限，不是**領取獎勵**的期限 ——
  /// 任務已完成，獎勵即為使用者掙得的，故未領取者於當日結束補發至信箱。
  bool timedRewardClaimed = false;

  bool get canClaimTimedReward =>
      timedTask.doneBy(displayName) && !timedRewardClaimed;

  ({int exp, int coins})? claimTimedReward() {
    if (!canClaimTimedReward) return null;
    timedRewardClaimed = true;
    totalExp += kTimedRewardExp;
    coins += kTimedRewardCoin;
    _syncAchievements();
    notifyListeners();
    return (exp: kTimedRewardExp, coins: kTimedRewardCoin);
  }

  /// 當日結束仍未領取者補發至獎勵信箱，不作廢 ——
  /// 因忘記點擊而失去獎勵，形同懲罰已完成任務的人。
  void sweepTimedRewardToMailbox() {
    if (!canClaimTimedReward) return;
    timedRewardClaimed = true;
    mailbox.insert(
      0,
      MailReward(
        source: '限時任務未領取',
        coins: kTimedRewardCoin,
        exp: kTimedRewardExp,
        at: now,
      ),
    );
    notifyListeners();
  }

  /// 隊長已邀請成員。Precondition：團隊人數未達上限 5 人（含隊長）。
  /// 邀請自送出起算 168 小時（7 天）未回應即逾期。
  bool inviteMember(String name, int rank) {
    final t = myTeam;
    if (t == null || !iAmLeader || t.isFull) return false;
    if (t.invites.any((i) => i.name == name)) return false;
    final expiresAt = now.add(const Duration(hours: 168));
    t.invites.add(PendingRequest(name, rank, expiresAt));
    final who = _memberUid(name);
    if (who != null) {
      _pushTeam((src, _) => src.sendRequest(TeamRequest(
            teamId: t.id,
            teamName: t.name,
            uid: who,
            name: name,
            rank: rank,
            isInvite: true,
            expiresAt: expiresAt,
          )));
    }
    _pushPending('隊長已邀請成員', '已邀請 $name',
        '對方有 7 天可以回應，逾期未回應即失效。');
    notifyListeners();
    return true;
  }

  /// 限時任務 —— 全平台統一，有效時窗為指派當日。
  TimedTask timedTask = buildTimedTask();

  bool get timedTaskExpired =>
      businessDate(now) != businessDate(timedTask.assignedOn);

  /// 今日限時任務在**目前這支隊伍**上的成績。
  ///
  /// 名單一律向團隊要，不從任務裡拿 —— 換隊或重建之後，
  /// 這張卡列的必須是現在的隊友。
  TimedTaskTally get timedTally => TimedTaskTally(
        members: myTeam?.members ?? const [],
        credited: myTeam?.timedCredited ?? const {},
      );

  /// 我今天完成了，但分數記在別支隊伍帳上（完成後才換隊或重建）。
  bool get timedDoneElsewhere =>
      timedTask.doneBy(displayName) &&
      myTeam != null &&
      !myTeam!.timedCredited.contains(displayName);

  /// Demo：把自己標記為完成。完成判定實際由系統訂閱 Event 自動累計，
  /// 不採自行回報 —— 可自行按鈕加分的排行榜不成立。
  void completeTimedTask() {
    if (timedTaskExpired || timedTask.doneBy(displayName)) return;
    timedTask.completedBy.add(displayName);
    // 完成的當下記在當時所屬的隊帳上。中途加入者僅能貢獻加入後產生的分數，
    // 轉隊也不帶走舊團隊已貢獻的分數 —— 與團隊日常分數同一條規則。
    myTeam?.timedCredited.add(displayName);
    notifyListeners();
  }
  late List<PublicTeam> publicTeams = buildPublicTeams();

  /// 上次退出團隊的時戳。冷卻期由它推導，**不存一個固定的 Duration** ——
  /// 存 Duration 不會自己倒數，那不是冷卻期，是到重開 App 為止的封鎖。
  DateTime? teamLeftAt;

  /// 申請當下鎖住的冷卻長度。管理員改參數不延長已在冷卻中的人。
  Duration? _cooldownAtLeave;

  /// 換隊冷卻剩餘。與重新分隊期並存不互相取代 ——
  /// 冷卻期防同一人反覆跳隊，重新分隊期給所有人一個對齊的換隊窗口。
  Duration get switchCooldownLeft {
    if (teamLeftAt == null) return Duration.zero;
    final left =
        (_cooldownAtLeave ?? kTeamSwitchCooldown) - now.difference(teamLeftAt!);
    return left.isNegative ? Duration.zero : left;
  }

  /// **加入**本隊的時戳。加入後一小段時間內退出不觸發冷卻期 ——
  /// 誤入團隊是真實情境，冷卻期不該懲罰誤觸。
  ///
  /// **自己建立的團隊為空值**：無懲罰窗口的理由是「誤入」，
  /// 自己開的隊不是誤入，解散它也不是。
  DateTime? teamJoinedAt = DateTime.now().subtract(const Duration(days: 20));

  /// 我送出、尚待回應的加入申請（方向＝使用者申請）。
  /// 與隊長邀請共用同一個〈團隊成員資格申請 Aggregate〉，以方向欄位區分。
  final List<PendingRequest> sentApplications = [];

  /// 我的團隊在排行榜上的投影。兩個榜共用同一份分組與資格判定。
  PublicTeam? get myTeamOnBoard {
    final t = myTeam;
    if (t == null) return null;
    return PublicTeam(
      t.name,
      t.members.length,
      t.capacity,
      id: t.id,
      isPublic: t.isPublic,
      members: t.members,
      dailyScore: t.dailyScore,
      timedScore: t.timedScore,
      peakSize: t.lockedGroupSize,
    );
  }

  /// 排行榜的參賽名單 —— 我的隊也在裡面，否則看不到自己的名次。
  List<PublicTeam> get boardTeams =>
      [...publicTeams, ?myTeamOnBoard];

  /// 不能申請加入的理由。回傳 null 代表可以申請 ——
  /// 把 Precondition 做成一句話，畫面才講得出為什麼按鈕是暗的。
  String? joinBlockedReason(PublicTeam t) {
    if (!t.isPublic) return '私密團隊不接受加入申請，只能由隊長邀請。';
    if (t.isFull) return '團隊已滿 ${t.capacity} 人（含隊長）。';
    if (myTeam != null) return '一次只能屬於一個團隊，要先退出 ${myTeam!.name}。';
    final cd = switchCooldownLeft;
    if (cd > Duration.zero) return '換隊冷卻中，還要等 ${_hm(cd)}。';
    if (sentApplications.any((a) => a.name == t.name)) {
      return '已送出申請，等隊長回應。';
    }
    return null;
  }

  /// 使用者已申請加入團隊。自送出起算 168 小時（7 天）未回應即逾期。
  /// 待回應的申請**不佔用 5 人名額**。
  bool applyToTeam(PublicTeam t) {
    if (joinBlockedReason(t) != null) return false;
    final expiresAt = now.add(const Duration(hours: 168));
    sentApplications.add(PendingRequest(t.name, rank, expiresAt));
    // 申請是我自己送出的，所以帶的是我的 uid（雲端規則也只允許這樣）。
    _pushTeam((src, uid) => src.sendRequest(TeamRequest(
          teamId: t.id,
          teamName: t.name,
          uid: uid,
          name: displayName,
          rank: rank,
          isInvite: false,
          expiresAt: expiresAt,
        )));
    _pushPending('使用者已申請加入團隊', '加入申請已送出',
        '「${t.name}」的隊長有 7 天可以回應，逾期未回應即失效。');
    notifyListeners();
    return true;
  }

  /// 撤回申請 —— 申請逾期或被拒後皆可再次申請。
  void withdrawApplication(String teamName) {
    sentApplications.removeWhere((a) => a.name == teamName);
    // 本機的申請只記隊名，雲端要的是隊伍 ID —— 從公開隊伍清單反查。
    // 查不到就只在本機撤回（那筆雲端申請會自行逾期，168 小時後失效）。
    final id = publicTeams
        .where((t) => t.name == teamName && t.id.isNotEmpty)
        .map((t) => t.id)
        .firstOrNull;
    if (id != null) _pushTeam((src, uid) => src.dropRequest(id, uid));
    notifyListeners();
  }

  // ── 收件匣：對方發起、等我回應的請求 ──────────────────────────
  //
  // 先前只實作了「我送出、對方回應」的那一半，另一半停在空氣裡。
  // 模型不是這樣寫的：〈團隊組隊流程〉加入路徑 1 的「使用者已接受邀請 /
  // 使用者已拒絕邀請」，Actor 就是使用者本人；〈師徒申請 Aggregate〉的
  // 「申請方角色」欄位值域為學徒 / 教官，明載申請雙向皆可。
  // 這兩條都是**我的** Command，缺席的是它們，不只是缺一個 demo 開關。

  /// 等我回應的請求。逾期者仍留在清單裡，由 [sweepExpiredRequests] 移除 ——
  /// 畫面要列的是 [liveInbox]。
  final List<InboundRequest> inbox = [];

  /// 尚未逾期、真的還能回應的請求。
  List<InboundRequest> get liveInbox =>
      inbox.where((r) => !r.expiredAt(now)).toList();

  int get inboxCount => liveInbox.length;

  /// 收下一筆請求。同一送件方針對同一對象的重複請求不疊加 ——
  /// 對方按兩次送出不該在我這裡變成兩筆。
  bool receiveInbound(InboundRequest r) {
    if (inbox.any((x) =>
        x.kind == r.kind && x.from == r.from && x.subject == r.subject)) {
      return false;
    }
    inbox.insert(0, r);
    _pushPending(
      switch (r.kind) {
        InboundKind.teamInvite => '隊長已邀請成員',
        InboundKind.mentorInvite => '使用者已申請師徒關係',
        InboundKind.apprenticeApply => '使用者已申請師徒關係',
      },
      switch (r.kind) {
        InboundKind.teamInvite => '${r.from} 邀你加入「${r.subject}」',
        InboundKind.mentorInvite => '${r.from} 想收你為徒',
        InboundKind.apprenticeApply => '${r.from} 想拜你為師',
      },
      '你有 7 天可以回應，逾期未回應即失效。',
    );
    notifyListeners();
    return true;
  }

  /// 不能接受這筆請求的理由。回傳 null 代表可以接受 ——
  /// 把 Precondition 做成一句話，畫面才講得出為什麼按鈕是暗的。
  String? inboundBlockedReason(InboundRequest r) {
    if (r.expiredAt(now)) return '這筆請求已經逾期了。';
    // 社群功能停權者不得執行社群互動 Command。
    if (communityBlocked) return '社群功能停權中，不能回應。';
    switch (r.kind) {
      case InboundKind.teamInvite:
        if (myTeam != null) {
          return '一次只能屬於一個團隊，要先退出 ${myTeam!.name}。';
        }
        final cd = switchCooldownLeft;
        if (cd > Duration.zero) return '換隊冷卻中，還要等 ${_hm(cd)}。';
        final t = publicTeams.where((x) => x.name == r.subject).firstOrNull;
        if (t == null) return '這支團隊已經不在了。';
        // 待回應的邀請不佔名額，超收由接受當下的這一行擋下。
        if (t.isFull) return '團隊已滿 ${t.capacity} 人（含隊長）。';
        return null;
      case InboundKind.mentorInvite:
        if (myInstructor != null) {
          return '一位學徒同時只能有一位教官，要先解除與 ${myInstructor!.name} 的師徒關係。';
        }
        return null;
      case InboundKind.apprenticeApply:
        if (!isInstructor) return '你不是教官，收不了徒。';
        if (apprentices.length >= apprenticeCap) {
          return '帶徒名額已滿（$apprenticeCap 位）。';
        }
        return null;
    }
  }

  /// 使用者已接受邀請 / 對方已接受申請。
  bool acceptInbound(InboundRequest r) {
    if (!inbox.contains(r)) return false;
    if (inboundBlockedReason(r) != null) return false;
    switch (r.kind) {
      case InboundKind.teamInvite:
        final t = publicTeams.firstWhere((x) => x.name == r.subject);
        _joinPublicTeam(t);
      case InboundKind.mentorInvite:
        final i = instructors.where((x) => x.name == r.from).firstOrNull ??
            Instructor(
              name: r.from,
              rank: r.fromRank,
              reputation: 0,
              apprentices: 0,
              apprenticeCap: 1,
              ability: const {},
              specialties: const [],
              avgRating: 0,
              ratingCount: 0,
            );
        // 我這一側只能有一位教官，接受一筆即作廢其餘我送出的申請。
        mentorApplications.clear();
        myInstructor = i;
      case InboundKind.apprenticeApply:
        apprentices.add(Apprentice(
          name: r.from,
          rank: r.fromRank,
          ability: const {},
          recentWorkouts: const [],
        ));
    }
    inbox.remove(r);
    notifyListeners();
    return true;
  }

  /// 使用者已拒絕邀請 / 對方已拒絕申請。
  /// 拒絕後該筆失效，對方可再次送出，無冷卻期（承既有裁決）。
  void declineInbound(InboundRequest r) {
    if (!inbox.remove(r)) return;
    notifyListeners();
  }

  /// 使用者已加入團隊（經邀請路徑）。
  ///
  /// 加入的是一支既有的隊，本週期最高成員數要接續對方的紀錄 ——
  /// 從 1 重算會把一支滿編的隊降到「本月從未成局」，白送它一次免罰。
  void _joinPublicTeam(PublicTeam t) {
    myTeam = Team(
      id: t.id.isEmpty ? newId('t') : t.id,
      name: t.name,
      isPublic: t.isPublic,
      members: [
        ...t.members,
        TeamMember(displayName, rank, TeamRole.member),
      ],
      // 這支隊已經掙到的分數要帶過來 —— 不帶的話我一加入，
      // 它的日常分數就從 12540 掉成 0，畫面上是一支剛開的新隊。
      contributions: _seedContributions(t),
      dailyRankPos: 0,
      timedScore: t.timedScore,
      lockedGroupSize: math.max(t.peakSize, t.members.length + 1),
    );
    publicTeams.removeWhere((x) => x.name == t.name);
    teamJoinedAt = now;
    sentApplications.removeWhere((a) => a.name == t.name);
    // 只能屬於一個團隊 —— 其餘還掛著的邀請與申請一併作廢。
    inbox.removeWhere((x) => x.kind == InboundKind.teamInvite);
  }

  /// 加入一支既有團隊時，把它的日常分數攤回各成員名下。
  ///
  /// **逐人的貢獻數字是編的，總額不是。** 公開團隊的 Read Model 只投影
  /// 團隊總分，沒有逐人明細；[Team.contributions] 卻是逐人的子集合。
  /// 這裡按人數均分、餘數給隊長 —— 唯一必須成立的是
  /// 「加總 ＝ 原本的團隊分數」，那條在下面是結構上成立的。
  Map<String, int> _seedContributions(PublicTeam t) {
    if (t.members.isEmpty) return {};
    final each = t.dailyScore ~/ t.members.length;
    final out = <String, int>{for (final m in t.members) m.name: each};
    final leader = t.members
        .firstWhere((m) => m.role == TeamRole.leader,
            orElse: () => t.members.first)
        .name;
    out[leader] = out[leader]! + t.dailyScore - each * t.members.length;
    return out;
  }

  // ── 對方對我送出的請求給出的答覆 ──────────────────────────────

  /// 隊長已核准 / 已拒絕我的加入申請。
  ///
  /// 先前 [sentApplications] 只進不出：送出去的申請永遠掛在那裡，
  /// 「隊長已核准加入申請 → 使用者已加入團隊」這條線走不完。
  bool resolveTeamApplication(String teamName, RequestVerdict verdict) {
    final a =
        sentApplications.where((x) => x.name == teamName).firstOrNull;
    if (a == null) return false;
    sentApplications.remove(a);
    if (verdict == RequestVerdict.accepted) {
      final t = publicTeams.where((x) => x.name == teamName).firstOrNull;
      // 核准當下才擋超收：待回應期間名額可能已被別人佔走。
      if (t == null || t.isFull || myTeam != null ||
          switchCooldownLeft > Duration.zero) {
        _pushPending('隊長已核准加入申請', '「$teamName」核准了，但你加不進去',
            '核准當下你已經在別隊、還在冷卻，或名額已被佔滿。');
        notifyListeners();
        return false;
      }
      _joinPublicTeam(t);
      _pushPending('使用者已加入團隊', '你加入了「$teamName」', '隊長核准了你的申請。');
    } else {
      _pushPending(
        verdict == RequestVerdict.rejected ? '隊長已拒絕加入申請' : '加入申請已逾期',
        '「$teamName」${requestVerdictNames[verdict]}',
        '這筆申請已失效，你可以再次申請。',
      );
    }
    notifyListeners();
    return true;
  }

  /// 對方已接受 / 已拒絕 / 逾期我送出的師徒申請。
  ///
  /// 三個終止狀態皆釋放所佔用的帶徒名額（〈師徒申請 Aggregate〉）。
  bool resolveMentorApplication(String name, RequestVerdict verdict) {
    final a = mentorApplications.where((x) => x.name == name).firstOrNull;
    if (a == null) return false;
    if (verdict == RequestVerdict.accepted) {
      final i = instructors.where((x) => x.name == name).firstOrNull;
      if (i == null || myInstructor != null) return false;
      // 接受一筆即作廢其餘 —— 一位學徒同時只能有一位教官。
      mentorApplications.clear();
      myInstructor = i;
      _pushPending('對方已接受申請', '$name 收你為徒了', '師徒關係已建立。');
    } else {
      mentorApplications.remove(a);
      _pushPending(
        verdict == RequestVerdict.rejected ? '對方已拒絕申請' : '師徒申請已逾期',
        '$name ${requestVerdictNames[verdict]}你的拜師申請',
        '沒有冷卻期，你可以再次申請。',
      );
    }
    notifyListeners();
    return true;
  }

  /// 逾期判定 —— 系統排程，掛在同一個示範時鐘上。
  ///
  /// 三處各自 168 小時：我送出的加入申請、我送出的師徒申請、我收到的請求。
  /// 回傳這一輪真的逾期掉的筆數，讓呼叫端知道有沒有發生事情。
  int sweepExpiredRequests() {
    var n = 0;

    for (final a in [...sentApplications]) {
      if (!now.isBefore(a.expiresAt)) {
        resolveTeamApplication(a.name, RequestVerdict.expired);
        n++;
      }
    }
    for (final a in [...mentorApplications]) {
      if (!now.isBefore(a.expiresAt)) {
        resolveMentorApplication(a.name, RequestVerdict.expired);
        n++;
      }
    }
    for (final r in [...inbox]) {
      if (r.expiredAt(now)) {
        inbox.remove(r);
        n++;
      }
    }

    // 我這一側的團隊：待回應的申請與邀請同樣會逾期。
    final t = myTeam;
    if (t != null) {
      final before = t.applications.length + t.invites.length;
      t.applications.removeWhere(expired);
      t.invites.removeWhere(expired);
      n += before - t.applications.length - t.invites.length;
    }

    if (n > 0) notifyListeners();
    return n;
  }

  // ── 別人那一側 ────────────────────────────────────────────────
  //
  // 以下每一個方法，在真實系統裡都是**另一個使用者的 Command**，
  // 由後端推過來；這個 demo 只有一位使用者，所以由控制台代打。
  //
  // 它們一律不繞過我這一側的規則：對方按讚就是 +1，不會替我發獎勵；
  // 對方回訊息一樣要過內容過濾。差別只在誰按下送出。

  /// 對方已發送訊息。
  ///
  /// 內容過濾對雙方一視同仁 —— 對方的違規訊息同樣自動送審，
  /// 差別只在被記名的是對方，不是我。
  FilterVerdict peerReplies(Conversation c, String text) {
    final body = text.trim();
    if (body.isEmpty) return FilterVerdict.pass;
    final v = screenContent(body);
    if (v == FilterVerdict.blocked) return v;

    c.messages.add(ChatMessage(
      false,
      body,
      now,
      category: c.category,
      pendingReview: v == FilterVerdict.flagged,
    ));
    if (v == FilterVerdict.flagged) {
      _openAutoFlagCase(
        targetKey: 'msg:${c.id}:${c.messages.length}',
        target: ReportTarget.message,
        content: body,
        accused: c.peer,
      );
    }
    notifyListeners();
    return v;
  }

  /// 他人已按讚。獎勵發給按讚的那個人，不是被按讚的我 ——
  /// 承 [toggleLike]「自己的貼文不計」的同一條裁決的另一面。
  ///
  /// 不收按讚者的名字：貼文只存讚數與「我按了沒」，沒有按讚者名單，
  /// 收一個存不進去的參數只會讓呼叫端以為它被記下來了。
  void peerLikesPost(Post p) {
    if (p.deleted) return;
    p.likes += 1;
    notifyListeners();
  }

  /// 他人已留言。
  void peerCommentsPost(Post p, String who, String text) {
    if (p.deleted || text.trim().isEmpty) return;
    p.comments.add(Comment(who, text.trim(), now));
    notifyListeners();
  }

  /// 成員已完成一次限時任務。
  ///
  /// 完成記在**當時所屬的隊**帳上，與我自己完成時同一條規則。
  bool teammateCompletesTimedTask(String name) {
    final t = myTeam;
    if (t == null || timedTaskExpired) return false;
    if (!t.members.any((m) => m.name == name)) return false;
    if (!timedTask.completedBy.add(name)) return false;
    t.timedCredited.add(name);
    notifyListeners();
    return true;
  }

  /// 他人已檢舉我的貼文。
  ///
  /// 走的是與 [fileReport] 同一個佇列與同一組併案規則，差別只在檢舉者
  /// 是別人、被檢舉的是我 —— 「檢舉 → 管理員審核 → 處罰 → 申訴」這條線
  /// 先前只能從施方走，被處罰的那一端永遠是空的。
  bool peerReportsMe(Post p, String who, String reason) {
    final key = 'post:${p.id}';
    final r = Reporter(name: who, reason: reason, at: now);
    final open = reports
        .where((c) => c.targetKey == key && c.state == CaseState.pending);
    if (open.isNotEmpty) {
      final c = open.first;
      c.reporters.add(r);
      c.reporterCount += 1;
      notifyListeners();
      return false;
    }
    reports.insert(
      0,
      ReportCase(
        id: newId('R-'),
        targetKey: key,
        reporters: [r],
        target: ReportTarget.post,
        origin: CaseOrigin.userReport,
        content: p.text,
        reason: reason,
        reporterCount: 1,
        accused: displayName,
        accusedViolations: violationsOf(displayName),
        enteredAt: now,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 使用者已申請加入我的團隊。
  bool peerAppliesToMyTeam(String name, int rank) {
    final t = myTeam;
    if (t == null || !t.isPublic || t.isFull) return false;
    if (t.applications.any((a) => a.name == name)) return false;
    if (t.members.any((m) => m.name == name)) return false;
    t.applications.add(PendingRequest(
      name,
      rank,
      now.add(kInboundTtl),
    ));
    _pushPending('使用者已申請加入團隊', '$name 想加入「${t.name}」', '你有 7 天可以回應。');
    notifyListeners();
    return true;
  }

  static String _hm(Duration d) =>
      d.inHours > 0 ? '${d.inHours} 小時 ${d.inMinutes % 60} 分' : '${d.inMinutes} 分';

  /// 不能建立團隊的理由。回傳 null 代表可以建立。
  ///
  /// **建立本身無門檻**，任何使用者皆可建立。擋人的只有「一人一隊」。
  ///
  /// **本專案刻意偏離模型**（2026-09-03 使用者裁示）：〈團隊組隊流程〉原文為
  /// 「退出團隊後 12 小時內不可再**加入或建立**任何團隊」，此處只保留「加入」。
  /// 冷卻期的職責是避免同一日內反覆進出造成的成員名單與分數抖動，
  /// 而自己開一支新隊不會動到任何既有團隊的名單或分數。
  /// 加入路徑的冷卻維持不變，見 [joinBlockedReason]。
  String? createBlockedReason() {
    if (myTeam != null) return '一次只能屬於一個團隊，要先退出 ${myTeam!.name}。';
    return null;
  }

  /// 使用者已建立團隊。建立者預設為隊長；可見性依建立時的指定值，預設公開。
  bool createTeam(String name, {bool isPublic = true}) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return false;
    if (createBlockedReason() != null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    myTeam = Team(
      id: newId('t'),
      name: trimmed,
      isPublic: isPublic,
      members: [TeamMember(displayName, rank, TeamRole.leader)],
      // 新隊本週期的最高成員數就是 1，未達下限 3 人 —— 分數照常累積，
      // 但這個月不參與排名也不領獎勵。
      lockedGroupSize: 1,
    );
    // 建立者沒有 teamJoinedAt —— 無懲罰退出窗口是給誤入團隊的人。
    teamJoinedAt = null;
    final created = myTeam!;
    _pushTeam((src, uid) => src.create(CloudTeam(
          id: created.id,
          name: created.name,
          isPublic: created.isPublic,
          capacity: created.capacity,
          members: {uid: _asCloudMember(created.members.first)},
        )));
    notifyListeners();
    return true;
  }

  /// 隊長已變更團隊可見性。
  ///
  /// 改為私密時，**既有待處理的加入申請一律保留**，隊長仍可核准或拒絕 ——
  /// 申請已送出為既成事實，申請者不會知道隊長改了設定，無聲作廢的體驗差。
  void setTeamVisibility(bool isPublic) {
    final t = myTeam;
    if (t == null || !iAmLeader || t.isPublic == isPublic) return;
    _pushTeam((src, _) => src.setVisibility(t.id, isPublic));
    myTeam = Team(
      id: t.id,
      name: t.name,
      isPublic: isPublic,
      members: t.members,
      capacity: t.capacity,
      contributions: t.contributions,
      timedScore: t.timedScore,
      dailyRankPos: t.dailyRankPos,
      timedRankPos: t.timedRankPos,
      lockedGroupSize: t.lockedGroupSize,
      invites: t.invites,
      applications: t.applications,
      timedCredited: t.timedCredited,
    );
    notifyListeners();
  }

  /// 退出團隊的結果 —— 畫面要講得出「這一按是解散還是轉讓」。
  ({bool disbanded, String? newLeader}) leaveTeamOutcome() {
    final t = myTeam;
    if (t == null || !iAmLeader) return (disbanded: false, newLeader: null);
    // 僅剩隊長一人時，隊長退出即解散，不進入無隊長狀態。
    if (t.members.length <= 1) return (disbanded: true, newLeader: null);
    // 未指定接任者即退出者，自動轉讓給最早加入的成員。
    final next = t.members.firstWhere((m) => m.role != TeamRole.leader);
    return (disbanded: false, newLeader: next.name);
  }

  /// 團隊已解散。**軟刪除**：排行榜歷史紀錄存有團隊 ID 與最終名次，
  /// 實體刪除會使歷史紀錄指向不存在的 ID。
  final List<String> disbandedTeams = [];

  void leaveTeam() {
    final t = myTeam;
    final outcome = leaveTeamOutcome();
    if (outcome.disbanded && t != null) disbandedTeams.add(t.name);

    // 無懲罰退出窗口只給「加入」的人。自己建立的團隊 teamJoinedAt 為空值，
    // 故建立後隨即退出或解散一律適用冷卻期 —— 那不是誤入。
    // 隊長轉讓後退出同樣適用，不因其為隊長而豁免。
    final grace =
        teamJoinedAt != null && now.difference(teamJoinedAt!) < kTeamLeaveGrace;
    if (t != null) {
      // 最後一人離開＝解散（軟刪除）；否則只是把自己移出成員。
      final id = t.id;
      if (outcome.disbanded) {
        _pushTeam((src, _) => src.disband(id));
      } else {
        _pushTeam((src, uid) => src.removeMember(id, uid));
      }
    }
    myTeam = null;
    teamJoinedAt = null;
    teamLeftAt = grace ? null : now;
    _cooldownAtLeave = grace ? null : kTeamSwitchCooldown;
    notifyListeners();
  }

  // ===========================================================================
  // 師徒 / 教官
  // ===========================================================================

  late List<Instructor> instructors = buildInstructors();
  Instructor? myInstructor;
  late List<MentorTask> mentorTasks = buildMentorTasks();

  /// 教官已指派師徒任務。
  /// Precondition：該教官的「已確認指導責任聲明版本」為現行版本。
  void assignMentorTask(String title, String detail) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    if (instructorDutyNeeded) return;
    mentorTasks.insert(
      0,
      MentorTask(title: title, detail: detail),
    );
    notifyListeners();
  }
  late List<MentorQuestion> questions = buildQuestions();
  late List<Apprentice> apprentices = buildApprentices();

  /// 師徒功能的解鎖條件：**集滿五個社群行為各一次**
  /// —— 使用者已關注帳號、發文者已發布貼文、互動者已按讚貼文、
  /// 互動者已留言、發文者已分享訓練成果。
  ///
  /// 以**歷史行為**計數：行為刪除不影響計數，取消關注、刪貼文都不會扣回去。
  /// 門檻為各一次，用意在確認「此人使用過社群功能」，非評量活躍度。
  Map<String, int> get mentorUnlockProgress => {
        '關注': followTotal,
        for (final k in kInteractionKinds) k: interactionTotals[k] ?? 0,
      };

  /// 已解鎖的旗標。**單調遞增、不可撤銷** —— 一旦集滿就永久保留。
  bool _mentorUnlocked = false;

  bool get mentorUnlocked {
    if (_mentorUnlocked) return true;
    if (mentorUnlockProgress.values.every((v) => v > 0)) {
      _mentorUnlocked = true;
    }
    return _mentorUnlocked;
  }

  /// 曾經關注過幾次。歷史計數，取消關注不扣。
  ///
  /// **初始值取自已關注的人數**，不是 0 —— 這個帳號一開始就關注著三個人，
  /// 計數卻從零起算的話，個人頁寫「關注 3」、師徒解鎖清單寫「關注 尚未做過」，
  /// 同一件事兩個答案。不變條件：曾經關注的次數不會少於現在關注中的人數。
  late int followTotal = following.length;

  /// 存檔還原用：解鎖旗標一經設定不可撤銷。
  void markMentorUnlocked() => _mentorUnlocked = true;

  bool isInstructor = false;
  InstructorStage instructorStage = InstructorStage.notApplied;

  /// AI 訓練品質評分的加權平均，與其中的「紀錄合理性」單項。
  /// 兩者皆為初審讀取的值 —— 加權平均比對通過／折抵門檻，
  /// 單項另受一票否決門檻檢核，兩者並存。
  int qualityScore = 72;
  int sanityScore = 68;

  /// 教官資格初審的判定。門檻取自〈教官初審設定〉，管理員調整後即時反映。
  InstructorGate get instructorGate => evaluateInstructorGate(
        rank: rank,
        workouts: totalWorkouts,
        quality: qualityScore,
        sanity: sanityScore,
      );
  int weeklyQuestionCount = 2;
  int weeklyAnswerCount = 1;
  int weeklyAssigned = 2;
  int weeklyCompleted = 1;
  bool ratedThisWeek = false;

  /// 本週是否與教官有私訊往來。週互動評分的前提為
  /// 「問答、師徒任務進度、**或私訊往來**」三者之一。
  bool _messagedInstructorThisWeek = false;

  /// 我送出、尚待回應的師徒申請（申請方角色＝學徒）。
  ///
  /// 一位學徒可同時向多位教官送出申請 —— 名額限制在教官那一側。
  final List<PendingRequest> mentorApplications = [];

  /// **已確認師徒免責聲明的版本**。僅首次建立師徒關係時呈現一次；
  /// 已確認過者其後更換教官不再重複呈現。
  String? mentorDisclaimerVersion;

  /// 不能向這位教官申請的理由。回傳 null 代表可以申請。
  ///
  /// 名額佔用數 ＝ 已建立的師徒關係數 ＋ 狀態為申請中的師徒申請數 ——
  /// **待回應的申請佔名額**，與團隊邀請刻意不一致：教官的帶徒上限來自聲望、
  /// 是掙來的稀缺獎勵，佔名額是在保護教官不被灌爆。
  /// 某位教官已佔用的帶徒名額。
  ///
  /// 模型：**名額佔用數 ＝ 該教官已建立的師徒關係數 ＋ 狀態為申請中的
  /// 師徒申請數**，三個終止狀態（接受／拒絕／逾期）各自釋放所佔名額。
  ///
  /// [Instructor.apprentices] 只是那位教官**與別人**的關係數，是一個
  /// 存下來就不動的數字。先前直接拿它當佔用數，於是我送出申請不佔名額、
  /// 拜師成功之後他的「帶徒 3 / 5」也還是 3 —— 程式碼註解寫著
  /// 「待回應的申請佔名額」，實際上一格都沒佔。
  int slotsUsedOf(Instructor i) =>
      i.apprentices +
      (myInstructor?.name == i.name ? 1 : 0) +
      (mentorApplications.any((a) => a.name == i.name) ? 1 : 0);

  String? mentorApplyBlockedReason(Instructor i) {
    if (myInstructor != null) {
      return '一位學徒同時只能有一位教官，要先解除與 ${myInstructor!.name} 的師徒關係。';
    }
    // 先講「你已經送出了」再講「滿了」——
    // 我自己的申請本身就佔一格，順序反過來的話，送出之後看到的會是
    // 「對方的帶徒名額已滿」，而那一格正是我佔的。
    if (mentorApplications.any((a) => a.name == i.name)) {
      return '已送出申請，等對方回應。';
    }
    if (slotsUsedOf(i) >= i.apprenticeCap) return '對方的帶徒名額已滿。';
    return null;
  }

  /// 使用者已申請師徒關係。申請 7 天未回應即逾期，逾期釋放所佔用的帶徒名額。
  bool applyMentor(Instructor i) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return false;
    if (mentorApplyBlockedReason(i) != null) return false;
    mentorApplications.add(PendingRequest(
      i.name,
      i.rank,
      now.add(const Duration(hours: 168)),
    ));
    _pushPending('使用者已申請師徒關係', '拜師申請已送出',
        '${i.name} 有 7 天可以回應，逾期未回應即失效。');
    notifyListeners();
    return true;
  }

  void withdrawMentorApplication(String name) {
    mentorApplications.removeWhere((a) => a.name == name);
    notifyListeners();
  }

  /// 對方已接受申請 → 師徒關係已建立。
  ///
  /// 與拒絕、逾期走同一條 [resolveMentorApplication] —— 三個終止狀態
  /// 若各走各的，釋放帶徒名額這件事就會有三份實作。
  void acceptMentorApplication(Instructor i) =>
      resolveMentorApplication(i.name, RequestVerdict.accepted);

  /// 學徒已確認師徒免責聲明。
  ///
  /// 不阻擋關係的建立本身，而是**阻擋學徒端的互動 Command**：
  /// 關係由教官接受申請觸發，該時點學徒未必在場，設為建立的 Precondition
  /// 會使關係卡在無人可推進的狀態。
  void confirmMentorDisclaimer() {
    mentorDisclaimerVersion ??= kMentorDisclaimerVersion;
    notifyListeners();
  }

  /// 未確認免責聲明者不得提問，也不得完成師徒任務。
  bool get mentorDisclaimerNeeded =>
      myInstructor != null && mentorDisclaimerVersion == null;

  void askQuestion(String text) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    if (text.trim().isEmpty) return;
    // 未確認免責聲明者不得提問。
    if (mentorDisclaimerNeeded) return;
    questions.add(MentorQuestion(from: displayName, text: text.trim(), at: now));
    weeklyQuestionCount += 1;
    notifyListeners();
  }

  void answerQuestion() {
    weeklyAnswerCount += 1;
    notifyListeners();
  }

  /// 本週已發放的師徒任務獎勵次數。**每週最多 3 次** ——
  /// 超過上限任務仍可正常完成，只是不再發經驗值與金幣。
  int mentorRewardsThisWeek = 0;

  bool get mentorRewardCapReached =>
      mentorRewardsThisWeek >= kMentorTaskRewardWeeklyCap;

  ({int exp, int coins})? claimMentorTask(MentorTask t) {
    if (t.state != MentorTaskState.done) return null;
    t.state = MentorTaskState.claimed;
    if (mentorRewardCapReached) {
      notifyListeners();
      return (exp: 0, coins: 0);
    }
    mentorRewardsThisWeek += 1;
    totalExp += kMentorTaskExp;
    coins += kMentorTaskCoin;
    _syncAchievements();
    notifyListeners();
    return (exp: kMentorTaskExp, coins: kMentorTaskCoin);
  }

  void completeMentorTask(MentorTask t) {
    if (t.state != MentorTaskState.assigned) return;
    // 未確認免責聲明者不得完成師徒任務。
    if (mentorDisclaimerNeeded) return;
    t.state = MentorTaskState.done;
    weeklyCompleted += 1;
    notifyListeners();
  }

  /// 師徒的週期計數器上次歸零所屬的週。空值表示尚未定基準。
  DateTime? _mentorWeek;

  /// 師徒週期計數器已重置。**週期基準為統一每週一 04:00**，
  /// 與週榜共用 [periodOf] —— 兩處若各自算週界，跨週那一刻會對不起來。
  ///
  /// 不重置的話，五個「每週最多 N 次」的上限會靜靜變成終身上限：
  /// 領滿 3 次師徒任務獎勵之後，這個帳號再也領不到。
  bool resetMentorWeekIfDue() {
    final (from, _) = periodOf(Board.personalWeekly, now);
    final last = _mentorWeek;
    if (last == null) {
      _mentorWeek = from; // 第一次只記基準，不憑空重置一次
      return false;
    }
    if (!from.isAfter(last)) return false;
    _mentorWeek = from;
    weeklyQuestionCount = 0;
    weeklyAnswerCount = 0;
    weeklyAssigned = 0;
    weeklyCompleted = 0;
    ratedThisWeek = false;
    taskRatingsThisWeek = 0;
    mentorRewardsThisWeek = 0;
    // 學徒評我的那一側同樣按週重置 —— 少了這兩行，
    // 每位學徒的評分次數會一路累加到永遠，第二週起就再也評不動聲望。
    apprenticeTaskRatings.clear();
    apprenticeWeeklyRated.clear();
    notifyListeners();
    return true;
  }

  // --- 教官聲望與帶徒上限 ---

  /// 教官初始聲望為 15，於「使用者已成為教官」時給予。
  ///
  /// 15 的職責是**讓新教官前幾次差評不致觸及地板 0** ——
  /// 自 0 起算的話第一個一星就貼著地板，這層緩衝等於不存在。
  int instructorReputation = 0;

  /// 歷史最高聲望。帶徒上限**單調遞增**，聲望下降時不隨之降低，
  /// 故上限看的是歷史最高，不是當下值。模型無「帶徒上限已降低」Event。
  int peakReputation = 0;

  int get apprenticeCap => apprenticeCapFor(peakReputation);

  /// 本週已計入聲望的任務評分次數。每位學徒每週最多 2 次。
  int taskRatingsThisWeek = 0;

  /// 我的聲望變動 —— 只有**我的學徒評我**才會走這裡。
  void _bumpReputation(int delta) {
    instructorReputation = applyReputation(instructorReputation, delta);
    peakReputation = math.max(peakReputation, instructorReputation);
  }

  /// 我的學徒本週已計入聲望的任務評分次數，逐人計。
  /// 上限是**每位學徒**每週 2 次，不是全部學徒合計 2 次。
  final Map<String, int> apprenticeTaskRatings = {};

  /// 我的學徒本週是否已評過週互動。每位學徒每週一次。
  final Set<String> apprenticeWeeklyRated = {};

  /// 學徒已評分 → 教官聲望已變動。**這是唯一會動到我的聲望的來源。**
  ///
  /// 先前我的聲望只由「我評我的教官」推動 —— 方向整個反了，
  /// 而收徒那一側從來沒有人評過我。
  ///
  /// [weekly] 為該週互動評分（每人每週一次、幅度較大）；
  /// 否則為單次師徒任務評分（每人每週最多 2 次計入聲望）。
  bool apprenticeRatesMe(String who, int stars, {bool weekly = false}) {
    if (!isInstructor || !isValidStars(stars)) return false;
    if (!apprentices.any((a) => a.name == who)) return false;

    if (weekly) {
      if (!apprenticeWeeklyRated.add(who)) return false;
      _bumpReputation(kWeeklyInteractionReputationDelta[stars - 1]);
    } else {
      final n = apprenticeTaskRatings[who] ?? 0;
      // 超出上限者仍可評分，只是不計入聲望 ——
      // 該擋的是計分，不是行為。
      apprenticeTaskRatings[who] = n + 1;
      if (n < kMentorTaskRatingWeeklyCap) {
        _bumpReputation(kMentorTaskReputationDelta[stars - 1]);
      }
    }
    notifyListeners();
    return true;
  }

  /// 我的教官的聲望變動 —— 我評他的時候走這裡。
  ///
  /// 先前兩者共用 [_bumpReputation]，於是我以學徒身分給教官五顆星，
  /// **我自己的**聲望與帶徒上限跟著往上跳。聲望是被評者的數字，
  /// 不是評分者的。
  void _bumpInstructorReputation(int delta) {
    final i = myInstructor;
    if (i == null) return;
    i.reputation = applyReputation(i.reputation, delta);
  }

  /// 學徒已評分該次師徒任務 → 教官聲望已變動。
  ///
  /// 每位學徒每週最多 2 次任務評分計入聲望；超出者仍可評分並領獎，只是不計分。
  /// 該擋的是計分，不是行為 —— 教官為教學需要多指派屬正當行為。
  bool rateMentorTask(MentorTask t, int stars) {
    if (!isValidStars(stars)) return false;
    // 沒有師徒關係就沒有可評的對象。
    if (myInstructor == null) return false;
    if (t.state == MentorTaskState.assigned) return false;
    final first = t.rating == null;
    t.rating = stars;
    if (first && taskRatingsThisWeek < kMentorTaskRatingWeeklyCap) {
      taskRatingsThisWeek += 1;
      _bumpInstructorReputation(kMentorTaskReputationDelta[stars - 1]);
    }
    notifyListeners();
    return true;
  }

  /// 學徒已評分該週互動。每位學徒每週最多一次；**未評分時聲望無變動，
  /// 不視為差評**。幅度遠大於單次任務評分，直接連動教官聲望。
  bool rateWeeklyInteraction([int stars = 4]) {
    if (ratedThisWeek || !isValidStars(stars)) return false;
    // 沒有教官就沒有「該週互動」可評 —— 先前這裡評得下去，
    // 而且憑空給自己加聲望。
    if (myInstructor == null) return false;
    // 該週內雙方須有互動（問答、任務進度**或私訊往來**）方可評分。
    if (weeklyQuestionCount == 0 &&
        weeklyAssigned == 0 &&
        !_messagedInstructorThisWeek) {
      return false;
    }
    ratedThisWeek = true;
    _bumpInstructorReputation(kWeeklyInteractionReputationDelta[stars - 1]);
    notifyListeners();
    return true;
  }

  // --- 終止路徑：解除、恢復 ---

  DateTime? mentorReleasedAt;
  MentorReleaseReason? mentorReleaseReason;

  /// 對方（或我）提出的恢復提議尚待回應。
  bool mentorRestorePending = false;

  /// 解除後 3 天內雙方皆不得與其他對象建立師徒關係，也是可挽回的窗口。
  Duration get mentorCooldownLeft {
    if (mentorReleasedAt == null) return Duration.zero;
    final left = kMentorReleaseCooldown - now.difference(mentorReleasedAt!);
    return left.isNegative ? Duration.zero : left;
  }

  /// 封鎖中的對象不得恢復師徒關係 —— 那是一段自相矛盾的關係。
  /// **解除封鎖亦不自動恢復**任何已解除的關注或師徒關係（模型明訂）；
  /// 解除封鎖後若冷卻期還沒過，雙方仍須各自重新同意。
  bool get canRestoreMentor =>
      mentorCooldownLeft > Duration.zero &&
      !(myInstructor != null && isBlocked(myInstructor!.name));

  /// 師徒關係已解除。**任一方皆可單方面解除，不需對方同意。**
  void releaseMentor(MentorReleaseReason reason) {
    if (myInstructor == null) return;
    mentorReleasedAt = now;
    mentorReleaseReason = reason;
    mentorRestorePending = false;
    // 未完成的師徒任務作廢（終止狀態）。
    for (final t in mentorTasks) {
      if (t.state == MentorTaskState.assigned) {
        t.state = MentorTaskState.voided;
      }
    }
    notifyListeners();
  }

  bool get mentorReleased => mentorReleasedAt != null && myInstructor != null;

  /// 使用者已提出恢復師徒關係。
  bool proposeRestore() {
    if (!mentorReleased || !canRestoreMentor) return false;
    mentorRestorePending = true;
    notifyListeners();
    return true;
  }

  /// 對方已同意恢復 → 師徒關係已恢復。
  ///
  /// **同一筆關係轉回生效中，不新建一筆** —— 既有任務與問答的關係 ID
  /// 仍指向原筆，那些紀錄屬同一段關係。
  bool acceptRestore() {
    if (!mentorRestorePending || !canRestoreMentor) return false;
    mentorReleasedAt = null;
    mentorReleaseReason = null;
    mentorRestorePending = false;
    notifyListeners();
    return true;
  }

  /// 對方已拒絕恢復。該筆提議失效，3 天內可再次提出。
  void rejectRestore() {
    mentorRestorePending = false;
    notifyListeners();
  }

  /// 冷卻期滿仍未恢復 —— 關係就此結束，教官欄位清空。
  void finalizeMentorRelease() {
    if (!mentorReleased || canRestoreMentor) return;
    myInstructor = null;
    mentorReleasedAt = null;
    mentorReleaseReason = null;
    notifyListeners();
  }

  /// 申請教官時填寫的專長。通過後寫入使用者 Aggregate 的「教官專長」欄位。
  final Set<String> instructorSpecialties = {};

  void toggleSpecialty(String v) {
    if (instructorSpecialties.contains(v)) {
      instructorSpecialties.remove(v);
    } else if (instructorSpecialties.length < kSpecialtyMax) {
      instructorSpecialties.add(v);
    }
    notifyListeners();
  }

  /// Precondition：申請時須填寫專長，至少 1 項至多 3 項。
  String? get specialtyBlockedReason {
    if (instructorSpecialties.length < kSpecialtyMin) {
      return '請至少選 $kSpecialtyMin 項教學專長。';
    }
    return null;
  }

  // --- 教官測驗與指導責任聲明 ---

  /// 上次作答教官測驗的時戳。**重考間隔 14 天，無次數上限** ——
  /// 題目每次隨機抽取，背題無效，14 天本身已是足夠的節流。
  DateTime? lastExamAt;

  /// 本次作答的選擇題成績。簡答題由管理員人工審核，不在此判定。
  int? examMcScore;

  Duration get examRetakeLeft {
    if (lastExamAt == null) return Duration.zero;
    final left = const Duration(days: 14) - now.difference(lastExamAt!);
    return left.isNegative ? Duration.zero : left;
  }

  /// 使用者已作答教官測驗。
  ///
  /// 選擇題由系統即時判定，簡答題送管理員人工審核（時限 7 個工作天）——
  /// 故作答後停在「待人工審核」，不是當場放行。
  bool submitExam(int correctCount) {
    if (instructorStage != InstructorStage.screenPassed &&
        instructorStage != InstructorStage.testing) {
      return false;
    }
    if (examRetakeLeft > Duration.zero) return false;
    lastExamAt = now;
    final total = platformConfig.i('exam', 'mcCount');
    examMcScore = (correctCount * 100 / total).round();

    // 及格採雙門檻：選擇題 ≥ 80% **且**簡答題全數通過。
    // 選擇題由系統即時判定 —— 這一關就沒過的，不必送人工審核。
    if (!examMcPassed) {
      instructorStage = InstructorStage.rejected;
      instructorRejectStage = '測驗';
      notifyListeners();
      return true;
    }

    instructorStage = InstructorStage.pendingReview;
    instructorRejectStage = null;
    // 簡答題送管理員人工審核 —— 先前這一步沒有產生任何案件，
    // 於是「待人工審核」等的是一個不存在的人，只能靠按鈕自己放行。
    instructorCases.insert(
      0,
      InstructorCase(
        id: newId('IC-'),
        applicant: displayName,
        aiScores: const {'訓練完成率': 78, '訓練規律性': 84, '紀錄合理性': 71},
        weighted: 77.9,
        concerns: const [],
        answers: const [
          ('學員深蹲膝蓋內夾，你會怎麼處理？',
              '先確認是活動度還是肌力不足。降到能全程膝蓋外推的重量，'
              '加側走彈力帶與腳踝背屈暖身，兩週後再評估。'),
          ('學員說想一個月瘦 10 公斤，你怎麼回應？',
              '說明這個速度多半會掉肌肉，改建議每週 0.5–1%，'
              '並問清楚他的期限從哪裡來。'),
        ],
        enteredAt: now,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 被駁回後再次申請。
  ///
  /// 模型：任何重試皆產生新的一筆教官申請，並重跑 AI 訓練品質評分；
  /// 距上次作答滿 14 天方可再次申請，無次數上限。
  /// 先前駁回是走不到的狀態，所以也沒有走出來的路。
  bool reapplyInstructor() {
    if (instructorStage != InstructorStage.rejected) return false;
    if (examRetakeLeft > Duration.zero) return false;
    instructorStage = InstructorStage.screening;
    instructorRejectStage = null;
    examMcScore = null;
    notifyListeners();
    return true;
  }

  /// 教官資格已駁回時攜帶的**駁回階段**：初審 / 測驗 / 管理員審核。
  ///
  /// 申訴機制未設時效上限，被駁回者申訴時管理員要看得出當初卡在哪一關。
  String? instructorRejectStage;

  int get examPassMark => platformConfig.i('exam', 'mcPass');
  bool get examMcPassed => (examMcScore ?? 0) >= examPassMark;

  /// **已確認的指導責任聲明版本。** 未確認現行版本者不得回答提問、
  /// 不得指派師徒任務 —— 聲明會改版，而「誰確認了哪一版」是爭議發生時的判定依據。
  String? instructorDutyVersion;

  bool get instructorDutyNeeded =>
      isInstructor && instructorDutyVersion != kInstructorDutyVersion;

  void confirmInstructorDuty() {
    instructorDutyVersion = kInstructorDutyVersion;
    notifyListeners();
  }

  /// 管理員已撤銷教官資格。撤銷因違規而發生，**既有師徒關係一併解除** ——
  /// 讓剛被判定違規者繼續帶徒，處罰就沒有效果。
  void revokeInstructor({bool byAdmin = true}) {
    // 管理員執行時須具內容審核權限；因處罰而連帶撤銷者為系統，不受此限。
    if (byAdmin && !canReview) return;
    if (!isInstructor) return;
    isInstructor = false;
    instructorStage = InstructorStage.rejected;
    instructorDutyVersion = null;
    if (myInstructor != null) {
      releaseMentor(MentorReleaseReason.revoked);
    }
    notifyListeners();
  }

  /// 使用者已成為教官。給予初始聲望，並將申請時填寫的專長
  /// 寫入使用者 Aggregate 的「教官專長」欄位。
  void _becomeInstructor() {
    if (isInstructor) return;
    isInstructor = true;
    instructorReputation = kInstructorInitialReputation;
    peakReputation = math.max(peakReputation, instructorReputation);
  }

  void advanceInstructorApplication() {
    const order = [
      InstructorStage.notApplied,
      InstructorStage.screening,
      InstructorStage.screenPassed,
      InstructorStage.testing,
      InstructorStage.pendingReview,
      InstructorStage.approved,
    ];
    // **停在「待人工審核」**：最後一步是管理員的 Command，不是我的。
    // 先前這裡一路走到「已通過」，等於申請人可以自己核准自己。
    final i = order.indexOf(instructorStage);
    if (i < 0 || i >= order.length - 1) return;
    final next = order[i + 1];
    if (next == InstructorStage.approved) return;

    if (next == InstructorStage.pendingReview) {
      // 走 [submitExam]，不是直接改狀態 —— 待人工審核只該有一條路進得去，
      // 否則會出現一個「等待審核」卻沒有案件可審的狀態。
      lastExamAt = null; // 示範用捷徑不受 14 天重考間隔限制
      submitExam(platformConfig.i('exam', 'mcCount'));
      return;
    }
    instructorStage = next;
    notifyListeners();
  }

  // ===========================================================================
  // 私訊
  // ===========================================================================

  late List<Conversation> conversations = buildConversations();

  /// 我這一側看得到的對話。
  List<Conversation> get visibleConversations =>
      conversations.where((c) => !c.deletedByMe).toList();

  // --- 私訊上雲（[BE-14]）---

  /// 雲端的私訊。**空值代表不同步** —— 既有測試走這條。
  ChatSource? chatSource;

  /// 這段對話在雲端的 ID。對方不在公開檔案裡（示範用的假使用者就是這種）
  /// 時回傳空值 —— 那段對話只存在本機。
  String? _cloudConvId(String peerName) {
    final src = chatSource;
    final me = myUid;
    final peer = uidOf(peerName);
    if (src == null || me == null || peer == null) return null;
    return src.conversationIdOf(me, peer);
  }

  /// 把雲端的對話併進清單（[BE-14]）。
  ///
  /// **依對方的暱稱合併**：本機那份可能是示範資料，雲端那份帶著真的訊息。
  /// 同一個人只該有一段對話 —— 雲端那份優先。
  void applyCloudConversations(List<CloudConversation> cloud) {
    final me = myUid;
    if (me == null) return;

    for (final c in cloud) {
      final peerUid = c.peerOf(me);
      if (peerUid == null) continue;
      final peerName = c.names[peerUid];
      // 認不出對方是誰的對話畫不出來，略過。
      if (peerName == null) continue;

      final conv = Conversation(
        id: c.id,
        peer: peerName,
        peerRank: c.ranks[peerUid] ?? 1,
        peerIsInstructor: c.instructors[peerUid] ?? false,
        deletedByMe: c.deletedBy.contains(me),
        messages: [
          for (final m in c.messages)
            ChatMessage(
              // **fromMe 在這裡才算得出來** —— 它是每位讀者各自的狀態，
              // 雲端存的是 senderUid。
              m.fromMeFor(me),
              m.text,
              m.at,
              read: m.readBy.containsKey(me),
              category: m.category,
              pendingReview: m.pendingReview,
            ),
        ],
      );

      final i = conversations.indexWhere((x) => x.peer == peerName);
      if (i >= 0) {
        conversations[i] = conv;
      } else {
        conversations.add(conv);
      }
    }
    notifyListeners();
  }

  /// 使用者已刪除對話。單方刪除，對方仍可見；訊息本身不可刪除。
  void deleteConversation(Conversation c) {
    if (c.deletedByMe) return;
    c.deletedByMe = true;
    final id = _cloudConvId(c.peer);
    if (id != null) chatSource?.deleteForMe(id).catchError((_) {});
    notifyListeners();
  }

  /// 使用者已發送私訊。
  ///
  /// 送出前經自動過濾：**明顯違規當場攔截**，不寫入私訊 Aggregate、
  /// 本 Event 不發生、對話的最後訊息時戳不變；**疑似違規照常送出**，
  /// 同時自動開立檢舉案（內容已標記待審）。
  ///
  /// 分類於**發送當下**依雙方關係判定並寫入，其後關係變化不回溯改寫。
  FilterVerdict sendMessage(Conversation c, String text) {
    // 社群功能停權（與永久停權）者不得發送私訊。
    if (communityBlocked) return FilterVerdict.blocked;
    final body = text.trim();
    if (body.isEmpty) return FilterVerdict.pass;

    final v = screenContent(body);
    if (v == FilterVerdict.blocked) {
      // 被攔截的私訊不寫入，對話的最後訊息時戳不變。
      return v;
    }

    if (myInstructor?.name == c.peer) _messagedInstructorThisWeek = true;

    final category = classifyMessage(
      mutualFollow: following.contains(c.peer) && followers.contains(c.peer),
      mentorBond: myInstructor?.name == c.peer ||
          apprentices.any((a) => a.name == c.peer),
      sameTeam: myTeam?.members.any((m) => m.name == c.peer) ?? false,
    );

    c.messages.add(ChatMessage(
      true,
      body,
      now,
      category: category,
      pendingReview: v == FilterVerdict.flagged,
    ));

    // 送上雲。與其他社群寫入同一套：樂觀更新、即發即忘、吞掉錯誤。
    // **訊息的 ID 在這裡才產生** —— ChatMessage 本身沒有 ID 欄位
    // （本機以位置辨識就夠），但雲端的每則訊息需要一個文件 ID。
    final peerUid = uidOf(c.peer);
    final src = chatSource;
    if (peerUid != null && src != null) {
      src
          .send(
            peerUid,
            CloudMessage(
              id: newId('msg'),
              senderUid: myUid ?? '',
              text: body,
              at: now,
              category: category,
              pendingReview: v == FilterVerdict.flagged,
            ),
            myName: displayName,
            peerName: c.peer,
          )
          .catchError((_) {});
    }

    if (v == FilterVerdict.flagged) {
      _openAutoFlagCase(
        targetKey: 'msg:${c.id}:${c.messages.length}',
        target: ReportTarget.message,
        content: body,
        accused: displayName,
      );
    }
    notifyListeners();
    return v;
  }

  /// 內容已標記待審 → 系統自動開立檢舉案。
  ///
  /// 與使用者檢舉走同一個佇列，以「來源」欄位區分 ——
  /// 管理員審視的是同一件事：這則內容有沒有違規。
  void _openAutoFlagCase({
    required String targetKey,
    required ReportTarget target,
    required String content,
    required String accused,
  }) {
    if (reports.any(
        (r) => r.targetKey == targetKey && r.state == CaseState.pending)) {
      return;
    }
    reports.insert(
      0,
      ReportCase(
        id: newId('A-'),
        targetKey: targetKey,
        reporters: const [],
        target: target,
        origin: CaseOrigin.autoFlag,
        content: content,
        reason: '自動過濾命中疑似違規',
        reporterCount: 0,
        accused: accused,
        accusedViolations: violationsOf(accused),
        enteredAt: now,
      ),
    );
  }

  void markRead(Conversation c) {
    final id = _cloudConvId(c.peer);
    if (id != null) chatSource?.markRead(id).catchError((_) {});
    final updated = c.messages
        .map((m) => m.fromMe ? m : ChatMessage(m.fromMe, m.text, m.at, read: true))
        .toList();
    c.messages
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  // ===========================================================================
  // 商城 / 訂單 / 金幣
  // ===========================================================================

  late List<Product> products = buildProducts();
  late List<Order> orders = buildOrders();

  /// 上次填寫的收貨資訊。購買時預帶 ——
  /// 實體訂單有 5 個必填欄位，每次重填為純粹的摩擦。
  ShippingInfo? lastShipping = const ShippingInfo(
    name: '王小明',
    phone: '0912345678',
    zip: '110',
    address: '台北市信義區松高路 1 號 5 樓',
  );

  void setShipping(ShippingInfo info) {
    lastShipping = info;
    notifyListeners();
  }

  /// 確認購買 → 訂單成立為**待付款**，並**預扣庫存**。
  ///
  /// 預扣而非支付成功後才扣減：實體商品超賣的後果是須向真實顧客道歉退款。
  /// 預扣保留 [kStockHold]，逾時未付款由 [releaseExpiredHolds] 釋放。
  /// 回傳失敗原因；null 表示成功，成立的訂單為 [orders.first]。
  FailReason? confirmPurchase(
    Product p,
    ProductSpec spec,
    int qty, {
    ShippingInfo? shipping,
  }) {
    if (spec.stock < qty) return FailReason.soldOut;

    // 支付明細拆分：金幣扣到不足為止，其餘以法幣補差額。
    final total = spec.coinPrice * qty;
    final coinPart = coins >= total ? total : coins;
    final cashPart = cashForShortfall(total - coinPart);

    // 實體商品的收貨資訊為必要條件。
    if (p.kind == ProductKind.physical && shipping == null) {
      return FailReason.other;
    }

    spec.stock -= qty; // 預扣
    coins -= coinPart;
    final now = this.now;
    orders.insert(
      0,
      Order(
        id: newId('O-'),
        productName: p.name,
        spec: spec.name,
        qty: qty,
        kind: p.kind,
        placedAt: now,
        coinPaid: coinPart,
        cashPaid: cashPart,
        state: OrderState.pendingPayment,
        shipping: shipping,
        // 每筆訂單於確認購買當下鎖定自己的到期時點 ——
        // 事後調整保留時間不影響已成立的訂單。
        holdUntil: p.kind == ProductKind.physical ? now.add(kStockHold) : null,
      ),
    );
    if (shipping != null) lastShipping = shipping;
    notifyListeners();
    return null;
  }

  // --- 權限解鎖類虛擬商品：進階訓練計畫 ---

  /// 已購買計畫清單。**以金幣永久解鎖**的進階訓練計畫 ID，永久保存 ——
  /// 由「商品已發放」（權限解鎖類）寫入，不因會員權益失效而回退。
  final Set<String> purchasedPlanIds = {};

  /// 三種解鎖方式為 OR 關係，任一成立即解鎖。
  /// 方式 1（階級達標）與方式 3（會員身分）皆為推導值，不另存 ——
  /// 階級單調遞增故達標不回退；會員權益失效時本式自動回到 false，
  /// 即〈進階訓練計畫已鎖定〉所要的效果，且僅鎖定「只靠會員解鎖」的那些。
  bool planUnlocked(WorkoutPlan p) {
    if (p.requiredRank == null) return true; // 初階計畫
    if (rank >= p.requiredRank!) return true; // 方式 1
    if (purchasedPlanIds.contains(p.id)) return true; // 方式 2
    return isMember && p.memberUnlockable; // 方式 3
  }

  /// 僅靠會員身分解鎖者 —— 權益失效即回鎖，故仍可購買轉為永久取得。
  bool planMemberOnly(WorkoutPlan p) =>
      p.requiredRank != null &&
      rank < p.requiredRank! &&
      !purchasedPlanIds.contains(p.id) &&
      isMember &&
      p.memberUnlockable;

  /// 不得購買的理由；null 表示可以買。
  String? planPurchaseBlockedReason(WorkoutPlan p) {
    if (p.requiredRank == null) return '初階計畫本來就可以直接使用。';
    if (p.unlockCoins == null) return '這份計畫不開放金幣購買。';
    // 已以階級達標或金幣購買**永久**取得者，不得重複購買。
    // 解鎖是冪等狀態，不是可累加的資源。
    if (rank >= p.requiredRank!) return '你的階級已達標，不需要購買。';
    if (purchasedPlanIds.contains(p.id)) return '你已經買過這份計畫了。';
    return null;
  }

  /// 成立虛擬商品交易 → 商品已發放 → 進階訓練計畫已解鎖（解鎖方式＝金幣購買）。
  ///
  /// 金幣不足時以現金補差額（併用支付），兩邊須同時成功方可完成購買 ——
  /// 本專案的假金流恆成功，故此處直接走完三個狀態。
  FailReason? purchasePlan(WorkoutPlan p) {
    if (planPurchaseBlockedReason(p) != null) return FailReason.other;
    final price = p.unlockCoins!;
    final coinPart = coins >= price ? price : coins;
    final cashPart = cashForShortfall(price - coinPart);
    coins -= coinPart;
    final now = this.now;
    orders.insert(
      0,
      Order(
        id: newId('O-'),
        productName: p.name,
        spec: '永久解鎖',
        qty: 1,
        kind: ProductKind.virtual,
        placedAt: now,
        coinPaid: coinPart,
        cashPaid: cashPart,
        // 權限解鎖類不適用庫存，故無預扣、無 holdUntil。
        // 交易成立為已付款；發放是另一個事實，緊接著發生但不合併。
        state: OrderState.paid,
      ),
    );
    // 商品已發放（權限解鎖類）：將解鎖標的寫入已購買計畫清單，永久保存。
    orders.first.state = OrderState.delivered;
    purchasedPlanIds.add(p.id);
    notifyListeners();
    return null;
  }

  /// 使用者已支付 —— Actor 為外部系統（第三方金流回呼）。
  /// 實體：待付款 → 已付款；虛擬：待付款 → 已付款，再由發放轉為已發放。
  ///
  /// 虛擬訂單不再直接跳到已發放：「使用者已購買虛擬商品」與「商品已發放」
  /// 是兩個不同事實，模型明訂不合併，且**發放可為非同步**。
  void payOrder(Order o) {
    if (o.state != OrderState.pendingPayment) return;
    o.state = OrderState.paid;
    if (o.kind == ProductKind.virtual) {
      deliverOrder(o);
    } else {
      // 實體訂單付款後進出貨佇列。**先前完全沒有這一步** ——
      // 後台的假訂單與我的訂單是兩份不相干的清單，
      // 我買的東西永遠不會出現在後台，[shipOrder] 裡那段
      // 「同一筆訂單在使用者端亦轉為已出貨」也就永遠對不到。
      _enqueueForFulfilment(o);
    }
    notifyListeners();
  }

  /// 把一筆已付款的實體訂單送進出貨佇列，**沿用同一個訂單 ID**。
  ///
  /// 兩側是同一筆訂單的兩個投影，不是兩筆訂單 —— ID 一致，
  /// 後台出貨才找得到使用者那一側該更新哪一筆。
  void _enqueueForFulfilment(Order o) {
    if (o.kind != ProductKind.physical) return;
    if (adminOrders.any((a) => a.id == o.id)) return;
    final sh = o.shipping;
    adminOrders.insert(
      0,
      AdminOrder(
        id: o.id,
        product: o.productName,
        spec: o.spec,
        qty: o.qty,
        coinAmount: o.coinPaid,
        placedAt: o.placedAt,
        paidAt: now,
        address: sh == null
            ? ''
            : '${sh.zip} ${sh.address}　${sh.name}　${sh.phone}',
        state: '已付款',
      ),
    );
  }

  /// 商品已發放。虛擬訂單自已付款轉入已發放（終止狀態）。
  ///
  /// [fails] 為真時走失敗路徑 —— 供示範與測試觸發，真實情境由發放服務回報。
  void deliverOrder(Order o, {bool fails = false, String reason = '道具入庫逾時'}) {
    if (!o.awaitingDelivery) return;
    if (fails) {
      failDelivery(o, reason);
      return;
    }
    o.state = OrderState.delivered;
    o.deliveryManual = false;
    o.deliveryFailReason = null;
    notifyListeners();
  }

  /// 商品發放已失敗〔攜帶資訊：已重試次數、失敗原因〕。
  ///
  /// Postcondition：系統自動重試，上限 [kDeliveryMaxRetries] 次；
  /// 達上限仍失敗者轉人工處理；**不改變訂單狀態**，
  /// 訂單於發放成功前維持已付款。不自動退款。
  void failDelivery(Order o, String reason) {
    if (!o.awaitingDelivery) return;
    o.deliveryFailReason = reason;
    if (o.deliveryRetries >= kDeliveryMaxRetries) {
      o.deliveryManual = true;
    } else {
      o.deliveryRetries += 1;
    }
    notifyListeners();
  }

  /// 待人工處理的發放 —— 達重試上限仍失敗者。
  List<Order> get manualDeliveryOrders =>
      orders.where((o) => o.deliveryManual).toList();

  /// 尚未發放的虛擬訂單。已付款、貨還沒到手。
  List<Order> get undeliveredOrders =>
      orders.where((o) => o.awaitingDelivery).toList();

  /// 支付已失敗 → 已失敗（終止狀態），並一併釋放預扣庫存。
  void failPayment(Order o, FailReason reason) {
    if (o.state != OrderState.pendingPayment) return;
    _releaseHold(o);
    _replaceOrder(o, OrderState.failed, failReason: reason);
    notifyListeners();
  }

  /// 使用者已取消訂單 → 已取消，並釋放預扣庫存與已扣的金幣。
  void cancelOrder(Order o) {
    if (!o.cancellable) return;
    _releaseHold(o);
    o.state = OrderState.cancelled;
    notifyListeners();
  }

  /// 預扣逾時 → 系統釋放庫存並取消訂單。回傳被取消的訂單 ID。
  ///
  /// 真實系統由排程觸發；本專案於進入訂單相關畫面時呼叫，
  /// 效果相同：使用者看到的一定是已經結算過的狀態。
  List<String> releaseExpiredHolds() {
    final now = this.now;
    final out = <String>[];
    for (final o in orders) {
      final until = o.holdUntil;
      if (o.state != OrderState.pendingPayment || until == null) continue;
      if (now.isBefore(until)) continue;
      _releaseHold(o);
      o.state = OrderState.cancelled;
      o.cancelledBySystem = true;
      out.add(o.id);
    }
    if (out.isNotEmpty) notifyListeners();
    return out;
  }

  /// 庫存已釋放：所預扣的庫存回補至該商品規格，已扣的金幣一併退回。
  void _releaseHold(Order o) {
    coins += o.coinPaid;
    for (final p in products) {
      if (p.name != o.productName) continue;
      for (final spec in p.specs) {
        if (spec.name == o.spec) spec.stock += o.qty;
      }
    }
  }

  /// 失敗原因為 final 欄位，故以整筆替換而非就地改值。
  void _replaceOrder(Order o, OrderState state, {FailReason? failReason}) {
    final i = orders.indexOf(o);
    if (i < 0) return;
    orders[i] = Order(
      id: o.id,
      productName: o.productName,
      spec: o.spec,
      qty: o.qty,
      kind: o.kind,
      placedAt: o.placedAt,
      coinPaid: o.coinPaid,
      cashPaid: o.cashPaid,
      state: state,
      failReason: failReason,
      shipping: o.shipping,
      trackingNo: o.trackingNo,
      cancelledBySystem: o.cancelledBySystem,
    );
  }

  /// 尚未查看的出貨通知（我的訂單頁紅點）。
  final Set<String> unreadShipped = {};

  void markOrderSeen(Order o) {
    if (unreadShipped.remove(o.id)) notifyListeners();
  }

  // ===========================================================================
  // AI 點數
  // ===========================================================================

  int aiMonthly = 14; // 月度額度，會員每月 20 點
  int aiPermanent = 6; // 永久點數，不重置不過期
  late List<CreditEntry> creditHistory = buildCreditHistory();

  // --- 金幣儲值（App Store 應用內購買，本系統被動接收通知）---
  /// 回傳 false 表示儲值失敗，金幣餘額不變。
  bool topUpCoins(CoinPack pack) {
    coins += pack.coins;
    notifyListeners();
    return true;
  }

  int get aiTotal => aiMonthly + aiPermanent;

  /// 記一筆 AI 點數異動。
  ///
  /// **不變條件：最新一筆的「異動後餘額」須等於當前的兩個餘額欄位。**
  /// 故餘額改動一律經由這裡記帳 —— 有幾處改了餘額卻沒記，
  /// 使用者就會看到一份跟餘額對不起來的流水（餘額多了 20 點、紀錄裡卻沒有）。
  void _logCredit(CreditChange kind, int delta, String source) {
    if (delta == 0) return;
    creditHistory.insert(
      0,
      CreditEntry(
        at: now,
        kind: kind,
        delta: delta,
        monthlyAfter: aiMonthly,
        permanentAfter: aiPermanent,
        source: source,
      ),
    );
  }

  /// 扣點順序：先扣月度額度、後扣永久點數。
  bool spendAiCredit(String source) {
    if (aiTotal <= 0) return false; // AI 調整已拒絕：點數不足
    if (aiMonthly > 0) {
      aiMonthly -= 1;
    } else {
      aiPermanent -= 1;
    }
    _logCredit(CreditChange.deduct, -1, source);
    notifyListeners();
    return true;
  }

  // ===========================================================================
  // AI 調整對話
  // ===========================================================================

  /// 對話以本次訓練課表為錨點，一對多；同一次訓練可有訓練前與訓練中兩段對話。
  /// 對話內容永久保存，不設清除期限。
  final Map<AiSource, List<AiTurn>> aiConversations = {
    for (final s in AiSource.values) s: <AiTurn>[],
  };
  final Map<AiSource, AiStage> aiStage = {
    for (final s in AiSource.values) s: AiStage.idle,
  };
  AiFailReason? aiLastFailReason;
  int aiRetryCount = 0;

  void _say(AiSource src, AiTurnRole role, String text) {
    aiConversations[src]!.add(AiTurn(role, text, now));
  }

  // --- 訓練前調整的名額分流 ---

  /// 名額是否還有空位。**這不是 Precondition，是分流條件** ——
  /// 名額足夠與否皆可請 AI 調整，差別在調整結果落在哪裡。
  bool get customPlanSlotFree =>
      customPlanQuota >= kUnlimitedPlans || myPlanCount < customPlanQuota;

  /// 使用者已確認「本次調整將佔用一個自訂訓練名額」。
  ///
  /// **意願確認，非當下即扣除名額** —— 名額於「AI 已替換動作」成功發生
  /// 之後才被佔用。先扣再跑，失敗時會留下一份與來源官方課表完全相同的
  /// 無用副本，還得另寫一條釋放名額的補救規則。
  bool aiQuotaConsent = false;

  void setAiQuotaConsent(bool v) {
    aiQuotaConsent = v;
    notifyListeners();
  }

  /// 器材解鎖後的課表調整不能提出的理由；null 表示可以提。
  ///
  /// **只適用於 [AiSource.planAdjust]** —— 使用者主動要求的訓練前微調
  /// 不落地為自訂訓練，與名額無關。
  ///
  /// 名額已滿時**不擋**：擋下等於因為額度問題讓使用者練一份器材不合的課表。
  String? aiPlanQuotaBlockedReason() {
    if (!customPlanSlotFree) return null; // 名額滿：不擋，改走快照
    if (!aiQuotaConsent) {
      return '本次調整將佔用一個自訂訓練名額（目前 $myPlanCount / $customPlanQuota），'
          '確認後才能請 AI 調整。';
    }
    return null;
  }

  /// 這一次的課表調整會落在哪裡。畫面要講得出來。
  String get aiPlanQuotaScope => customPlanSlotFree
      ? '調整結果會落地為一份新的自訂訓練，佔用一個名額'
      : '名額已滿，本次調整只改這一次的訓練，不佔名額';

  /// 「AI 已替換動作」成功後才落地為自訂訓練，此時方佔用名額 1 個。
  ///
  /// 名額已滿者不佔名額、只改快照；其仍可事後於訓練歷史將該次訓練紀錄
  /// 另存為自訂訓練 —— 那是本路徑的補救出口。
  void _landAdjustedPlan() {
    final sess = session;
    if (sess == null || !customPlanSlotFree) return;
    customPlans.add(CustomPlan(
      id: newId('cp'),
      name: '${sess.plan.name}（AI 調整）',
      // 落地的是本次訓練課表快照的**內容本身**，不是它的摘要 ——
      // 使用者接下來要能直接拿這份課表訓練。
      exercises: [
        for (final e in sess.exercises)
          PlanExercise(
            exercise: e.exercise,
            planned: [...e.planned],
            replacedFrom: e.replacedFrom,
            restSeconds: e.restSeconds,
          ),
      ],
      myUses: 0,
      state: CustomPlanState.saved,
    ));
    aiQuotaConsent = false;
  }

  /// 提出調整要求。
  /// Precondition：AI 點數餘額足夠。不足者產生「AI 調整已拒絕」——
  /// **不扣點**、維持原訓練內容、導向 AI 點數購買頁。
  /// 這與「AI 調整已失敗」（已扣點後退還）的 Postcondition 相反，兩者不合併。
  void aiRequest(AiSource src, String demand) {
    if (aiStage[src] == AiStage.rejected) return; // 拒絕後不可重新提出
    // 名額足夠者須先確認意願；名額已滿者直接放行（改走快照）。
    // **只有器材解鎖後的課表調整走這條** —— 主動要求微調強度不佔名額。
    if (aiUsesPlanQuota(src) && aiPlanQuotaBlockedReason() != null) {
      return;
    }
    if (aiCostsCredit(src) && aiTotal <= 0) {
      aiStage[src] = AiStage.denied;
      _say(src, AiTurnRole.system, 'AI 點數不足，本次調整已拒絕。未扣點，維持原訓練內容。');
      notifyListeners();
      return;
    }
    _say(src, AiTurnRole.user, demand);
    // AI 已再次確認需求。選項寫死是刻意的：本專案不接外部 LLM，
    // 追問的作用是取得一個明確的意圖，讓建議產得出來。
    _say(src, AiTurnRole.ai,
        '了解。${switch (src) {
          AiSource.beforeTraining => '這份課表',
          AiSource.planAdjust => '這份課表的動作',
          AiSource.duringTraining => '剩下的動作',
          AiSource.autoOptimize => '這份課表範本',
        }}要怎麼調？'
        '（${AdjustIntent.values.map((i) => adjustIntentNames[i]).join('／')}）');
    aiStage[src] = AiStage.clarifying;
    notifyListeners();
  }

  /// 從使用者的回答解析出意圖。認不出來時取「整體降強度」——
  /// 這是三者中最保守的一個，猜錯的代價最小。
  static AdjustIntent parseIntent(String answer) {
    final a = answer.trim();
    for (final i in AdjustIntent.values) {
      if (a.contains(adjustIntentNames[i]!)) return i;
    }
    if (a.contains('升') || a.contains('加重') || a.contains('難')) {
      return AdjustIntent.harder;
    }
    if (a.contains('少') || a.contains('減') || a.contains('組')) {
      return AdjustIntent.trim;
    }
    return AdjustIntent.easier;
  }

  /// 本次調整的意圖與建議，逐來源各一份。
  final Map<AiSource, AdjustIntent> aiIntent = {};
  final Map<AiSource, AdjustSuggestion> aiSuggestion = {};

  /// 該來源要調整的那份課表。
  ///
  /// 訓練前／訓練中調整看的是**本次訓練課表快照**；自動優化看的是
  /// **來源課表範本** —— 兩者作用範圍不同，讀的東西也不同。
  List<PlanExercise> _aiTarget(AiSource src) {
    if (src == AiSource.autoOptimize) {
      return aiOptimizePlan?.exercises ?? const [];
    }
    return session?.exercises ?? const [];
  }

  /// 自動優化的對象課表範本 —— 掛著優化建議標記的那一份。
  WorkoutPlan? get aiOptimizePlan =>
      platformPlans.where((p) => p.hasOptimizationSuggestion).firstOrNull;

  // --- AI 自動優化的觸發 Policy ---

  /// 距上次優化後累計的合格訓練次數。
  ///
  /// 合格＝已完成 / 提前結束 / 逾時中斷三者之一，且**已完成組數不為 0**
  /// —— 一組都沒完成者不構成歷史訓練資料。
  int autoOptimizeCount = 0;

  /// 每幾次觸發一次。
  static const int kAutoOptimizeEvery = 3;

  /// 一次訓練結算後推進計數，並在達標時嘗試觸發。
  ///
  /// **非會員期間照常累計** —— 訂閱當下若已達 3 次，立即觸發一次，
  /// 但**不補跑期間錯過的多份**；關閉自動優化期間同樣照常累計，
  /// 重新啟用後也不補跑。兩者處理完全一致。
  void _bumpAutoOptimize({required bool anySetDone}) {
    if (!anySetDone) return;
    autoOptimizeCount += 1;
    tryAutoOptimize();
  }

  /// 條件全部成立時產生一份新的優化建議。回傳是否真的產生。
  ///
  /// **同一課表範本同時只保留最新一份建議，後者覆蓋前者**；
  /// 建議不設有效期限，只會被下一份取代。
  bool tryAutoOptimize() {
    if (autoOptimizeCount < kAutoOptimizeEvery) return false;
    if (!aiAutoOptimize) return false; // 開關為關：照常累計，不觸發
    if (!isMember) return false; // 僅會員收得到
    final plan = _autoOptimizeTarget();
    if (plan == null) return false;

    // 達標即觸發一次，計數歸零 —— 累積再多次也只產生一份，不補跑。
    autoOptimizeCount = 0;
    _markOptimization(plan);
    return true;
  }

  /// 要優化哪一份範本：最近練過的官方課表。
  /// 已經掛著建議的那一份優先 —— 後者覆蓋前者，不會同時存在兩份。
  WorkoutPlan? _autoOptimizeTarget() {
    final existing = aiOptimizePlan;
    if (existing != null) return existing;
    final official =
        platformPlans.where((p) => p.source == PlanSource.official && p.exercises.isNotEmpty);
    if (official.isEmpty) return null;
    final used = official.where((p) => p.lastTrainedAt != null).toList()
      ..sort((a, b) => b.lastTrainedAt!.compareTo(a.lastTrainedAt!));
    return used.isNotEmpty ? used.first : official.first;
  }

  /// 掛上常駐標記。**不另發通知，亦不彈出對話框** ——
  /// 建議於課表選擇頁呈現，使用者選課表時順帶看到。
  void _markOptimization(WorkoutPlan plan) {
    final i = platformPlans.indexOf(plan);
    if (i < 0 || plan.hasOptimizationSuggestion) return;
    // 新的一份建議＝新的一段流程。上一輪若以「拒絕」結束，狀態機停在
    // rejected；不重設的話這一份建議按不動，等於白產出。
    aiReset(AiSource.autoOptimize);
    platformPlans[i] = _copyPlan(plan, suggestion: true);
    if (currentPlan?.id == plan.id) currentPlan = platformPlans[i];
  }

  WorkoutPlan _copyPlan(
    WorkoutPlan p, {
    required bool suggestion,
    List<PlanExercise>? exercises,
  }) =>
      WorkoutPlan(
        id: p.id,
        name: p.name,
        source: p.source,
        exercises: exercises ?? p.exercises,
        requiredRank: p.requiredRank,
        lastTrainedAt: p.lastTrainedAt,
        lastCompletion: p.lastCompletion,
        hasOptimizationSuggestion: suggestion,
        equipmentTier: p.equipmentTier,
        unlockCoins: p.unlockCoins,
        memberUnlockable: p.memberUnlockable,
        suitableExperience: p.suitableExperience,
        suitableGoals: p.suitableGoals,
      );

  /// 使用者已確認需求 → 系統呼叫 AI API 分析（AI 僅產出建議，不套用）。
  void aiConfirmDemand(AiSource src, String answer) {
    if (aiStage[src] != AiStage.clarifying) return;
    _say(src, AiTurnRole.user, answer);
    aiIntent[src] = parseIntent(answer);
    aiStage[src] = AiStage.analyzing;
    notifyListeners();
  }

  /// AI 已產出建議。**依使用者眼前的那份課表產生**，不是一段固定文字。
  ///
  /// 模型把 LLM 放在軟體邊界之外（「AI 為系統呼叫的外部 API」），
  /// 只規範呼叫時點、扣點、失敗退點與「僅產出建議、不套用」。
  /// 本專案不接外部 API，改以端內規則產生建議 —— 邊界內的規則照做，
  /// 邊界外的實作用一組看得懂的規則代替。
  void aiProduceSuggestion(AiSource src) {
    if (aiStage[src] != AiStage.analyzing) return;

    final target = _aiTarget(src);
    if (target.isEmpty) {
      _say(src, AiTurnRole.system, '這份課表還沒有動作，沒有東西可以調整。未扣點。');
      aiStage[src] = AiStage.idle;
      notifyListeners();
      return;
    }

    // 訓練中調整只動**尚未完成**的剩餘動作。
    final from = src == AiSource.duringTraining ? (session?.exerciseIndex ?? 0) : 0;
    final intent = aiIntent[src] ?? AdjustIntent.easier;
    final suggestion = buildSuggestion(target, intent, onlyFrom: from);
    if (suggestion.changes.isEmpty || suggestion.isEmpty) {
      _say(src, AiTurnRole.system, '以目前的內容，這個方向沒有可調的空間。未扣點。');
      aiStage[src] = AiStage.idle;
      notifyListeners();
      return;
    }

    // 扣點時點為 AI 呼叫成功產出建議時。
    if (aiCostsCredit(src)) spendAiCredit(aiSourceNames[src]!);
    aiSuggestion[src] = suggestion;
    _say(src, AiTurnRole.ai,
        '建議如下（${adjustIntentNames[intent]}）：\n'
        '${suggestion.changes.map((c) => '· ${c.summary}').join('\n')}\n'
        '作用範圍：${aiSourceScope[src]}');
    aiStage[src] = AiStage.proposed;
    notifyListeners();
  }

  /// Demo：模擬 AI 逾時或服務錯誤。
  /// 失敗為已扣點後退還，與「拒絕」（根本未扣）不同。
  void aiFail(AiSource src, AiFailReason reason) {
    aiLastFailReason = reason;
    aiRetryCount += 1;
    if (aiCostsCredit(src)) {
      // 退還不另立 Event
      aiMonthly += 1;
      _logCredit(CreditChange.refund, 1, aiSourceNames[src]!);
    }
    _say(src, AiTurnRole.system,
        'AI 調整已失敗（${aiFailReasonNames[reason]}，已重試 $aiRetryCount 次）。'
        '維持原本次訓練課表，不套用任何調整。已扣的點數已退還，請稍後再試。');
    aiStage[src] = AiStage.failed;
    notifyListeners();
  }

  /// 接受 → 使用者已確認使用新訓練強度 → **系統套用**（AI 不執行套用）。
  ///
  /// 三條路徑的作用對象不同：
  /// - 訓練前 / 訓練中調整 → 只改**本次訓練課表快照**，來源課表不動
  /// - 自動優化 → 只改**來源課表範本**，往後所有訓練適用
  void aiAccept(AiSource src) {
    if (aiStage[src] != AiStage.proposed) return;
    final suggestion = aiSuggestion[src];
    if (suggestion == null) return;

    switch (src) {
      case AiSource.beforeTraining:
        // 只改本次快照，不落地、不佔名額。
        _applyToSession(suggestion);
      case AiSource.planAdjust:
        _applyToSession(suggestion);
        // 名額足夠者於此刻才落地並佔用名額；名額已滿者只改快照。
        _landAdjustedPlan();
      case AiSource.duringTraining:
        _applyToSession(suggestion);
      case AiSource.autoOptimize:
        _applyToTemplate(suggestion);
    }

    _say(src, AiTurnRole.system,
        '訓練課表已套用新強度。作用範圍：${aiSourceScope[src]}');
    aiStage[src] = AiStage.applied;
    notifyListeners();
  }

  /// 套用至本次訓練課表快照。
  ///
  /// **已完成的組不動** —— 那些是實績，不是計畫；改掉等於竄改紀錄。
  /// 組數變動時進度百分比隨之重算（分母變了），允許下降。
  void _applyToSession(AdjustSuggestion suggestion) {
    final s = session;
    if (s == null) return;
    final updated = applySuggestion(s.exercises, suggestion);
    for (var i = 0; i < updated.length; i++) {
      final planned = updated[i].planned;
      final records = s.records[i];
      // 目標組數變少：砍掉尾端多餘的組紀錄，但**保留已完成的**。
      while (records.length > planned.length &&
          records.last.state != SetState.done) {
        records.removeLast();
      }
      // 目標組數變多：補上新的待做組。
      while (records.length < planned.length) {
        final p = planned[records.length];
        records.add(SetRecord(weight: p.targetWeight, reps: p.targetReps));
      }
      // 尚未完成的組才跟著改目標值。
      for (var j = 0; j < records.length && j < planned.length; j++) {
        if (records[j].state == SetState.done) continue;
        records[j].weight = planned[j].targetWeight;
        records[j].reps = planned[j].targetReps;
      }
      s.exercises[i] = updated[i];
    }
    // 游標可能落在被砍掉的組上，收回合法範圍。
    if (s.exerciseIndex < s.records.length) {
      final n = s.records[s.exerciseIndex].length;
      if (s.setIndex >= n) s.setIndex = n > 0 ? n - 1 : 0;
    }
  }

  /// 套用至來源課表範本。自動優化的作用範圍是往後所有訓練。
  void _applyToTemplate(AdjustSuggestion suggestion) {
    final plan = aiOptimizePlan;
    if (plan == null) return;
    final i = platformPlans.indexOf(plan);
    if (i < 0) return;
    // 建議已處理，常駐標記隨之清除 —— 未處理前一直存在，處理後就不該還在。
    platformPlans[i] = _copyPlan(plan,
        suggestion: false, exercises: applySuggestion(plan.exercises, suggestion));
    if (currentPlan?.id == plan.id) currentPlan = platformPlans[i];
  }

  /// 拒絕 → 維持原訓練內容，流程結束，**不可重新提出調整要求**。
  void aiReject(AiSource src) {
    if (aiStage[src] != AiStage.proposed) return;
    _say(src, AiTurnRole.system, '已拒絕調整，維持原訓練內容。本次流程結束。');
    aiStage[src] = AiStage.rejected;
    // 自動優化：拒絕後維持原範本強度，但這一份建議已經處理過，
    // 常駐標記不該還掛著 —— 「未處理前一直存在」講的是未處理。
    if (src == AiSource.autoOptimize) _clearOptimizationFlag();
    notifyListeners();
  }

  void _clearOptimizationFlag() {
    final plan = aiOptimizePlan;
    if (plan == null) return;
    final i = platformPlans.indexOf(plan);
    if (i < 0) return;
    platformPlans[i] = _copyPlan(plan, suggestion: false);
    if (currentPlan?.id == plan.id) currentPlan = platformPlans[i];
  }

  void aiReset(AiSource src) {
    aiConversations[src]!.clear();
    aiStage[src] = AiStage.idle;
    aiIntent.remove(src);
    aiSuggestion.remove(src);
    aiRetryCount = 0;
    notifyListeners();
  }

  // ===========================================================================
  // 會員訂閱
  // ===========================================================================

  MembershipState membership = MembershipState.none;
  DateTime? membershipExpiry;

  /// 使用者已訂閱會員。「已失效」非終止狀態 —— 重新訂閱時沿用同一筆
  /// 會員權益，狀態轉回生效中。
  void subscribe({required bool yearly}) {
    membership = MembershipState.active;
    membershipExpiry = now.add(Duration(days: yearly ? 365 : 30));
    final before = aiMonthly;
    aiMonthly = kMonthlyAiCredits;
    _logCredit(CreditChange.monthlyGrant, aiMonthly - before, '會員權益已生效');
    // 訂閱當下計數若已達 3 次，立即觸發一次；但**不補跑**期間錯過的多份。
    tryAutoOptimize();
    notifyListeners();
  }

  /// 使用者已取消訂閱 → 已取消待到期。**權益不立即失效** ——
  /// 使用者已支付整個當期的費用，立即收回等同沒收已付款的服務。
  /// 取消僅停止自動續約，權益維持至當期到期日。
  void cancelSubscription() {
    if (membership != MembershipState.active) return;
    membership = MembershipState.cancelledPending;
    notifyListeners();
  }

  /// 會員權益已失效 —— 於**當期到期時點**才發生。
  ///
  /// 真實系統由 App Store 的到期通知觸發（扣款失敗與寬限期在系統邊界之外，
  /// 本系統不建模）。此處由示範時鐘推進到期日時觸發，效果相同。
  ///
  /// 回傳被鎖定的訓練計畫 ID —— 沒有它，「我的課表莫名消失」就無從查證。
  List<String> expireMembershipIfDue() {
    if (membership == MembershipState.none ||
        membership == MembershipState.expired) {
      return const [];
    }
    final until = membershipExpiry;
    if (until == null || now.isBefore(until)) return const [];

    // 先算出「僅以會員身分解鎖」的那些。
    // 不能用 [planMemberOnly] —— 它讀 [isMember]，而 isMember 是純時間判定，
    // 走到這裡時已經回 false 了，算出來會是空的。這裡要問的是
    // 「失效前靠會員解著的是哪些」，故直接檢查另外兩條路徑都不成立。
    final locked = [
      for (final p in platformPlans)
        if (p.requiredRank != null &&
            p.memberUnlockable &&
            rank < p.requiredRank! &&
            !purchasedPlanIds.contains(p.id))
          p.id,
    ];
    membership = MembershipState.expired;
    // 非會員的月度額度歸零；永久點數不動。
    final beforeCredits = aiMonthly;
    aiMonthly = 0;
    _logCredit(CreditChange.deduct, -beforeCredits, '會員權益已失效');
    // 已取得的補簽券不作廢 —— 那是已發放給使用者的物品，不是訂閱期間的服務。

    // 進階訓練計畫已鎖定：僅改變可選用性，不刪除任何資料。
    // 訓練紀錄、快照與統計全數保留，續訂後回復原狀，不從零開始。
    if (locked.isNotEmpty) membershipLockedPlanIds = locked;
    // 當前計畫若正好是被鎖掉的那份，換一份解得開的 ——
    // 留一份按不下去的計畫在首頁，比換掉它更難解釋。
    if (currentPlan != null && locked.contains(currentPlan!.id)) {
      currentPlan = recommendCurrentPlan();
    }
    notifyListeners();
    return locked;
  }

  /// 上次失效時鎖回去的計畫。供會員頁說明「續訂就會回來」。
  List<String> membershipLockedPlanIds = const [];

  /// 「權益有效」涵蓋生效中與已取消待到期兩值 ——
  /// 已取消待到期者仍享有全部權益至當期到期日。
  ///
  /// **純判定，不改狀態**：本 getter 於 build 中被大量讀取，
  /// 在裡面 notifyListeners 會在建構期間觸發重繪。過了到期日但
  /// [expireMembershipIfDue] 還沒跑到的那一小段，這裡也回 false ——
  /// 權益的有無看的是時間，不是排程跑了沒。
  bool get isMember {
    if (membership == MembershipState.none ||
        membership == MembershipState.expired) {
      return false;
    }
    final until = membershipExpiry;
    if (until != null && !now.isBefore(until)) return false;
    return true;
  }

  /// 自訂訓練名額：**會員不受限制**，非會員隨階級自 2 成長至 5
  /// （里程碑 25 / 45 / 70，沿用進階訓練計畫的同一組數字）。
  int get customPlanQuota => isMember
      ? kUnlimitedPlans
      : customPlanQuotaForRank(
          rank,
          base: platformConfig.i('commerce', 'customPlanBase'),
          max: platformConfig.i('commerce', 'customPlanMax'),
        );

  /// 會員的「無限」。用一個具名常數而非散落的 999 ——
  /// 判斷「是不是無限」的地方不只一處。
  static const int kUnlimitedPlans = 999;

  // ===========================================================================
  // 獎勵信箱
  // ===========================================================================

  late List<MailReward> mailbox = buildMailbox();
  int get unclaimedMail => mailbox.where((m) => !m.claimed).length;

  /// 使用者已領取信箱獎勵 → 該來源的「⋯獎勵已發放」。
  ///
  /// **照那一筆實際記著的數額發放**。原本一律發一個寫死的數字，
  /// 於是信箱上寫「金幣 300 ＋ 經驗值 120」、領到的卻是 50 金幣 0 經驗值。
  void claimMail(MailReward m) {
    if (m.claimed) return;
    m.claimed = true;
    _payOut(m);
    notifyListeners();
  }

  /// 一鍵全部領取。信箱不設容量上限、會無上限累積，
  /// 逐筆點擊 500 次不是設計，是懲罰。
  void claimAllMail() {
    for (final m in mailbox.where((x) => !x.claimed)) {
      m.claimed = true;
      _payOut(m);
    }
    notifyListeners();
  }

  void _payOut(MailReward m) {
    totalExp += m.exp;
    coins += m.coins;
    if (m.makeupTickets > 0) grantMakeupTickets(m.makeupTickets);
    if (m.aiCredits > 0) {
      aiPermanent += m.aiCredits;
      _logCredit(CreditChange.gift, m.aiCredits, m.source);
    }
    _syncAchievements();
  }

  // ===========================================================================
  // 補簽
  // ===========================================================================

  int makeupTickets = 2;

  /// 持有上限，無有效期限。〈補簽設定 Aggregate〉的平台級可調參數。
  int get makeupTicketCap => platformConfig.i('makeup', 'ticketCap');

  /// 補簽券的金幣售價。
  int get makeupTicketPrice => platformConfig.i('makeup', 'ticketPrice');

  /// 補簽券入手。達持有上限者不再入手 —— 回傳實際入手的張數。
  ///
  /// 上限只擋新入手，**不沒收已持有的** —— 管理員把上限調低，
  /// 手上多出來的券照樣用得完。
  int grantMakeupTickets(int n) {
    final room = makeupTicketCap - makeupTickets;
    final got = n < room ? n : (room > 0 ? room : 0);
    if (got <= 0) return 0;
    makeupTickets += got;
    notifyListeners();
    return got;
  }

  /// 以金幣購買補簽券。回傳失敗原因；null 表示成功。
  String? buyMakeupTicket() {
    if (makeupTickets >= makeupTicketCap) {
      return '補簽券最多持有 $makeupTicketCap 張，用掉幾張才買得了。';
    }
    if (coins < makeupTicketPrice) {
      return '金幣不足，需要 $makeupTicketPrice 金幣。';
    }
    coins -= makeupTicketPrice;
    makeupTickets += 1;
    notifyListeners();
    return null;
  }

  /// 每日簽到紀錄 Aggregate —— **只存已簽到的日子**，鍵為使用者當地日期。
  ///
  /// 未簽到之日不存在對應紀錄，「查無此筆」即代表該日未簽到。
  /// 存成一份固定的日曆清單的話，簽到不會進去、日子也不會長出來：
  /// 時鐘往前推幾天，中間那幾天既不顯示未簽到、也補不了 —— 它們根本不存在。
  late Map<DateTime, CheckInMethod> checkInRecords = buildCheckInRecords();

  /// 寫入一筆每日簽到紀錄。同一使用者同一日期至多一筆。
  void _recordCheckIn(DateTime date, CheckInMethod method) {
    checkInRecords[DateTime(date.year, date.month, date.day)] = method;
  }

  /// 該日是否已簽到。補簽 Precondition「該日確實未簽到」的驗證來源。
  CheckInMethod? checkInMethodOn(DateTime date) =>
      checkInRecords[DateTime(date.year, date.month, date.day)];

  /// 回補範圍（〈補簽設定 Aggregate〉，由管理員 Command「設定補簽回補範圍」維護）。
  int get makeupRangeDays => platformConfig.i('makeup', 'days');

  /// 距今天數 ＝ 今日當地日期 − 補簽日期（date 相減，不涉時戳）。
  int daysAgo(DateTime d) {
    final now = this.now;
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
  }

  /// 補簽頁的日曆 —— 距今 1 至 N 天，不含今日。**由紀錄推導**，
  /// 逐日走過整個範圍，查得到紀錄的是已簽／已補，查無此筆的就是未簽。
  /// 回補範圍縮短的當下，超出範圍者即刻補不回來（判定式含端點）。
  List<MakeupDay> get makeupDaysInRange {
    final today = businessDate(now);
    return [
      for (var i = makeupRangeDays; i >= 1; i--)
        () {
          final d = today.subtract(Duration(days: i));
          return MakeupDay(d, makeupStateOf(checkInMethodOn(d)));
        }(),
    ];
  }

  /// 可補簽＝未簽到、在回補範圍內、不早於註冊日、且尚有補簽券。
  bool canMakeUp(MakeupDay d) => makeupBlockedReason(d) == null;

  /// 不可補簽的理由；null 表示可以補。
  ///
  /// 每一次「使用補簽券」為獨立的操作單位，Precondition 於每一次各自檢核。
  String? makeupBlockedReason(MakeupDay d) {
    if (d.state != MakeupDayState.missed) return '那天已經簽到了。';
    if (daysAgo(d.date) > makeupRangeDays) {
      return '只補得回最近 $makeupRangeDays 天。';
    }
    // 補簽日期 ≥ 註冊日 —— 註冊日當日可補，註冊日之前不可補。
    // 沒有這一條，使用者可以補回「他還不存在的那些天」。
    if (d.date.isBefore(registeredOn)) return '那時你還沒註冊。';
    if (makeupTickets <= 0) return '沒有補簽券了。';
    return null;
  }

  /// 補簽後可恢復的連續天數（對所選日期試算）。
  /// 補簽後可恢復的連續天數（對所選日期試算）。
  int simulateStreakAfterMakeup(MakeupDay d) =>
      _streakFromRecords(alsoSigned: d.date);

  /// 連續簽到已恢復：**逐日推算**。
  ///
  /// 自今日往回逐日檢視每日簽到紀錄，連續有紀錄的天數即為連續天數，
  /// 遇查無紀錄之日即停止。
  ///
  /// 不採「中斷前連續天數 ＋ 補回的天數」的加法：同一次中斷用第二張券時，
  /// 中斷前連續天數已被前一張清為 0，加法會算出比前一張更小的值；
  /// 未補齊時又會把被斷點切開的兩段相加，得出偏大的錯誤值。
  ///
  /// 本函式可重入：每次皆由當前紀錄重算，重複執行不改變結果。
  int _streakFromRecords({DateTime? alsoSigned}) {
    final extra = alsoSigned == null
        ? null
        : DateTime(alsoSigned.year, alsoSigned.month, alsoSigned.day);
    var run = 0;
    var d = businessDate(now);
    // 今天沒簽到不算斷 —— 今天還沒過完，自昨天起算。
    if (checkInMethodOn(d) == null && d != extra) {
      d = d.subtract(const Duration(days: 1));
    }
    while (checkInMethodOn(d) != null || d == extra) {
      run += 1;
      d = d.subtract(const Duration(days: 1));
    }
    return run;
  }

  void useMakeupTicket(MakeupDay d) {
    if (!canMakeUp(d)) return;
    makeupTickets -= 1;
    // 每日簽到紀錄寫入該日一筆，簽到方式＝補簽。
    // 日曆由紀錄推導，寫進去它自然就變成已補簽。
    _recordCheckIn(d.date, CheckInMethod.makeup);
    d.state = MakeupDayState.madeUp;
    checkInTotal += 1;
    checkInLongest = math.max(checkInLongest, checkInStreak);
    // 補簽當日的簽到獎勵補發至信箱，於領取時才入帳。
    mailbox.insert(
      0,
      MailReward(
        source: '補簽當日簽到獎勵',
        coins: kCheckInCoin,
        exp: kCheckInExp,
        at: now,
      ),
    );
    _syncAchievements();
    notifyListeners();
  }

  // ===========================================================================
  // 處罰與申訴
  // ===========================================================================

  Punishment? punishment = buildPunishment();

  /// 累計違規次數。「使用者已受處罰」時 +1，「處罰已撤銷」時 −1。
  /// **不隨時間清零** —— 清零會出現「固定間隔違規一次即永遠停在警告」的漏洞。
  int myViolations = 0;

  /// 處罰對某類功能的封鎖理由；未被封鎖時為空值。
  ///
  /// 表格見 02_Aggregate定義.md〈各處罰級距的功能對照〉。集中在這一個
  /// 函式，是為了讓「哪一級距擋哪些功能」只有一份定義 —— 散在各個
  /// Command 裡的 if 會各自長歪，而級距表本身就是驗收標準。
  String? punishmentBlockedReason(PunishedFeature f) {
    final p = punishment;
    if (p == null || !punishmentBlocks(p.kind, f)) return null;
    // **純判定，不改狀態**：本函式於 build 期間被讀取，
    // 在這裡讓處罰到期會在畫面繪製途中觸發 notifyListeners。
    // 已到期者視同無處罰，實際的解除由掛在展示時鐘上的
    // [expirePunishmentIfDue] 完成。
    if (p.isExpiredAt(now)) return null;
    if (p.kind == PunishmentKind.permanent) {
      return '你的帳號已永久停權，僅可提出申訴。';
    }
    final at = p.expiresAt;
    final days = at == null ? null : at.difference(now).inDays + 1;
    return '你目前處於社群功能停權'
        '${days == null ? '' : '，$days 天後解除'}。'
        '訓練與所有累積不受影響。';
  }

  /// 社群互動（發文／留言／按讚、私訊、關注、團隊、師徒）的封鎖理由。
  String? get communityBlockedReason =>
      punishmentBlockedReason(PunishedFeature.community);

  bool get communityBlocked => communityBlockedReason != null;

  /// 訓練與所有累積的封鎖理由 —— 僅永久停權者為非空值。
  String? get trainingBlockedReason =>
      punishmentBlockedReason(PunishedFeature.training);

  /// 商城購買與會員訂閱的封鎖理由 —— 僅永久停權者為非空值。
  String? get commerceBlockedReason =>
      punishmentBlockedReason(PunishedFeature.commerce);

  /// 使用者已申訴。同一處罰限申訴一次，不論成立與否；距受處罰未滿 30 天。
  void fileAppeal(String reason) {
    final p = punishment;
    final at = now;
    if (p == null || !p.canAppealAt(at)) return;
    p.appealed = true;
    p.appealState = AppealState.pending;
    // 申訴為獨立 Aggregate，且進管理員的待審佇列。
    appeals.add(AppealCase(
      id: newId('AP-'),
      appellant: displayName,
      target: AppealTarget.punishment,
      subject: punishmentKindNames[p.kind]!,
      reason: reason,
      filedAt: at,
      daysSinceIncident: at.difference(p.issuedAt).inDays,
    ));
    notifyListeners();
  }

  // ===========================================================================
  // 檢舉 → 處罰 → 申訴
  // ===========================================================================

  /// 使用者已檢舉內容。
  ///
  /// 多人檢舉同一標的合併為同一案件；**合併只在案件仍為待審視時有效** ——
  /// 已結案者若沿用終止狀態，該對象其後的新違規將再也無法被檢舉。
  /// 回傳 true 表示新開案件，false 表示併入既有案件。
  bool fileReport({
    required ReportTarget target,
    required String targetKey,
    required String content,
    required String accused,
    required String reason,
    String? note,
  }) {
    final r = Reporter(
        name: displayName, reason: reason, note: note, at: now);

    final existing = reports.where((c) =>
        c.targetKey == targetKey && c.state == CaseState.pending);
    if (existing.isNotEmpty) {
      final c = existing.first;
      // 併入時新增一筆檢舉者紀錄，不覆蓋既有紀錄。
      c.reporters.add(r);
      c.reporterCount += 1;
      notifyListeners();
      return false;
    }

    reports.insert(
      0,
      ReportCase(
        id: newId('R-'),
        targetKey: targetKey,
        reporters: [r],
        target: target,
        origin: CaseOrigin.userReport,
        content: content,
        reason: reason,
        reporterCount: 1,
        accused: accused,
        accusedViolations: violationsOf(accused),
        enteredAt: now,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 各使用者的累計違規次數。自己的存在 [myViolations]。
  /// 初值取自佇列中既有案件所記的累計次數 —— 級距一律依它決定，
  /// 若不灌入，所有人都會從 0 起跳而算成「警告」。
  late final Map<String, int> _violations = {
    for (final c in reports) c.accused: c.accusedViolations,
  };

  int violationsOf(String user) =>
      user == displayName ? myViolations : (_violations[user] ?? 0);

  void _setViolations(String user, int v) {
    if (user == displayName) {
      myViolations = v;
    } else {
      _violations[user] = v;
    }
  }

  /// 管理員已審視檢舉。待審視 → 審視中，寫入處理中的管理員 ID。
  /// 審視中**不自動退回待審視** —— 未下判定即離開者，案件留在審視中。
  void reviewReport(ReportCase c) {
    if (!canReview) return;
    if (c.state != CaseState.pending) return;
    c.state = CaseState.reviewing;
    c.handlerName = admin.name;
    notifyListeners();
  }

  /// 檢舉成立 → 管理員已下架違規內容（帳號類除外）＋ 使用者已受處罰。
  /// 管理員僅判斷檢舉是否成立，**不裁量處罰種類與時長** —— 級距由階梯累犯制決定。
  void upholdReport(ReportCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing) return;
    c.state = CaseState.upheld;
    c.handlerName = null; // 案件轉入終止狀態時清空

    // 管理員已下架違規內容。**帳號類不走下架路徑** ——
    // 帳號不是一則內容，沒有可下架的標的。
    if (canTakeDownContent(c.target)) _takeDown(c);

    final after = violationsOf(c.accused) + 1;
    _setViolations(c.accused, after);
    if (c.accused == displayName) _issuePunishment(c, after);
    notifyListeners();
  }

  /// 管理員已下架違規內容。僅適用貼文 / 留言 / 私訊。
  ///
  /// 一律為**軟刪除**，資料保留 —— 內容本身是案件的證據，
  /// 硬刪除會使其後的申訴無從調閱當時被判違規的是什麼。
  void _takeDown(ReportCase c) {
    final id = reportedId(c.targetKey);
    switch (c.target) {
      case ReportTarget.post:
        for (final p in posts) {
          if (p.id == id) p.deleted = true;
        }
      case ReportTarget.comment:
        for (final p in posts) {
          for (final m in p.comments) {
            if (m.id == id) m.deleted = true;
          }
        }
      case ReportTarget.message:
        // 檢舉入口在對話層級，鍵為對話 ID；下架的是**被檢舉的那一則**，
        // 不是整段對話 —— 一句違規不該連帶抹掉雙方所有往來。
        for (final conv in conversations) {
          if (conv.id != id) continue;
          for (final m in conv.messages) {
            if (m.text == c.content) m.deleted = true;
          }
        }
      case ReportTarget.account:
        break; // 帳號不走下架路徑，由 [upholdReport] 擋在前面
    }
  }

  void _issuePunishment(ReportCase c, int after) {
    final tier = tierForViolations(after);
    punishment = Punishment(
      kind: _kindOf(tier),
      reason: c.reason,
      evidence: c.content,
      issuedAt: now,
      violationCount: after,
      nextConsequence: tierForViolations(after + 1).label,
      // 限期處罰須一併寫入到期時戳；警告與永久停權為空值。
      expiresAt: tier.days == null
          ? null
          : now.add(Duration(days: tier.days!)),
    );
    // 已填電子郵件者，另以電子郵件通知處罰內容與 **30 天申訴期限**。
    _email('你的帳號已受處罰',
        '處罰：${punishmentKindNames[punishment!.kind]}\n'
        '事由：${c.reason}\n'
        '你可於收到本通知起 30 天內提出申訴，同一處罰限申訴一次。');
    // 受處罰者具教官身分且處罰為**停權以上**者，教官資格一併撤銷；
    // 警告不撤銷 —— 讓剛被判定違規者繼續帶徒，處罰就沒有效果。
    if (isInstructor && isSuspension(punishment!.kind)) {
      revokeInstructor(byAdmin: false);
    }
  }

  /// 處罰級距三級：警告 / 社群功能停權（7 與 30 天）/ 永久停權。
  /// 「帳號停權」級距已移除。
  PunishmentKind _kindOf(PunishmentTier t) {
    if (t.label == '警告') return PunishmentKind.warning;
    if (t.days != null) return PunishmentKind.communitySuspended;
    return PunishmentKind.permanent;
  }

  /// 檢舉已駁回。駁回後**不對檢舉者做任何處置**，不記點亦不處罰。
  void dismissReport(ReportCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing) return;
    c.state = CaseState.dismissed;
    c.handlerName = null;
    notifyListeners();
  }

  /// 管理員已審視申訴。待審視 → 審視中。
  void reviewAppeal(AppealCase c) {
    if (!canReview) return;
    if (c.state != CaseState.pending) return;
    c.state = CaseState.reviewing;
    c.handlerName = admin.name;
    notifyListeners();
  }

  /// 申訴成立 → 處罰已撤銷。處罰狀態回復為無、到期時戳清空、累計違規 −1。
  void upholdAppeal(AppealCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing) return;
    c.state = CaseState.upheld;
    c.handlerName = null;
    if (c.appellant == displayName) {
      final wasFrozen = clocksFrozen;
      punishment = null;
      // 該次違規視為不成立。
      myViolations = myViolations > 0 ? myViolations - 1 : 0;
      _email('申訴成立，處罰已撤銷',
          '你的申訴經審視成立，該筆處罰已撤銷，累計違規次數一併回復。');
      // 永久停權經申訴撤銷者，**以撤銷時點重設所有計時基準**。
      // 不重設的話，停權那段期間會在解除的瞬間一次結清 ——
      // 連續天數當場歸零、能力值當場退好幾階，正是暫停計時要避免的事。
      if (wasFrozen) rebaseClocks();
    }
    notifyListeners();
  }

  /// 計時是否凍結。**永久停權期間暫停逾時中斷、能力值退步、
  /// 連續訓練天數與連續簽到四個計時器**；期間連續天數、連續簽到天數
  /// 與獎勵加成一律保留，不歸零。
  ///
  /// 社群功能停權**不**凍結：模型明訂其不影響訓練與所有累積。
  bool get clocksFrozen {
    final p = punishment;
    return p != null &&
        p.kind == PunishmentKind.permanent &&
        !p.isExpiredAt(now);
  }

  /// 以當下為所有計時器的新起點。永久停權撤銷時呼叫。
  void rebaseClocks() {
    final today = businessDate(now);
    lastTrainedDate = today;
    for (final d in Dim.values) {
      final td = decayTimers[d]!;
      // 只移動計時基準，**不動 cumulative 與 floorReached** ——
      // 停權前若已有一段中斷，那段的累積退步量是回歸任務回復 50% 的依據，
      // 撤銷處罰不該把它一併抹掉。
      td.lastTrainedDate = today;
      td.nextDecayAt = td.floorReached
          ? null
          : dayBoundaryAfter(today).add(Duration(hours: kDecayIntervalHours));
    }
    _trainNoticeStage = DecayStage.normal;
    _checkInNoticeStage = CheckInStage.normal;
    // 訓練中的逾時中斷計時同樣自撤銷時點起算。
    lastSetCompletedAt = session == null ? null : now;
  }

  /// 申訴已駁回。原處罰維持不變，**累計違規次數不變**（僅撤銷才 −1）。
  void dismissAppeal(AppealCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing) return;
    c.state = CaseState.dismissed;
    c.handlerName = null;
    if (c.appellant == displayName) {
      punishment?.appealState = AppealState.dismissed;
      _email('申訴已駁回', '你的申訴經審視不成立，原處罰維持不變。');
    }
    notifyListeners();
  }

  /// 申訴的判定入口，供既有畫面沿用。
  void decideAppeal(AppealCase c, bool upheld) =>
      upheld ? upholdAppeal(c) : dismissAppeal(c);

  /// 審核案件已接手。Precondition：狀態為審視中且已發生「審核已逾期」，
  /// 且執行者不為目前的處理中管理員。不重設審核時限的起算點。
  void takeOverReport(ReportCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing || !c.overdue) return;
    if (c.handlerName == admin.name) return;
    c.handlerName = admin.name;
    notifyListeners();
  }

  void takeOverAppeal(AppealCase c) {
    if (!canReview) return;
    if (c.state != CaseState.reviewing || !c.overdue) return;
    if (c.handlerName == admin.name) return;
    c.handlerName = admin.name;
    notifyListeners();
  }

  /// 處罰已到期解除。限期處罰且已達到期時戳方可發生；
  /// 永久停權無到期解除，警告為一次性記錄亦無。
  void expirePunishmentIfDue() {
    final p = punishment;
    if (p == null || !p.isExpiredAt(now)) return;
    punishment = null;
    notifyListeners();
  }

  // ===========================================================================
  // 訓練歷史
  // ===========================================================================

  late List<HistoryEntry> history = buildHistory();

  // ===========================================================================
  // 新手任務 / 回歸任務
  // ===========================================================================

  /// 新手任務為三選一，非三項待辦。候選項目由管理員於後台維護的範本提供。
  final noviceCandidates = kNoviceTemplate;

  /// 「新手任務已指派」與「使用者已開始新手任務」是兩個獨立 Event ——
  /// 由使用者主動點擊開始，非系統自動觸發。分開才分得出漏斗卡在哪一關。
  bool noviceStarted = false;

  /// 已選定的動作 ID。選定與開始是兩個不同時點的決定，故不併為同一個欄位。
  String? noviceSelected;
  bool noviceChecked = false;
  bool noviceFinished = false;
  bool noviceRewardClaimed = false;

  /// 社群互動功能（發文、按讚、留言、分享、關注）的解鎖。
  /// 單調遞增，一經解鎖永久不可撤銷 —— 管理員處罰不改變本狀態。
  bool socialUnlocked = false;

  NoviceTaskItem? get noviceSelectedItem => noviceSelected == null
      ? null
      : noviceCandidates.firstWhere((c) => c.id == noviceSelected);

  /// 使用者已開始新手任務。
  void startNovice() {
    if (noviceStarted || noviceFinished) return;
    noviceStarted = true;
    notifyListeners();
  }

  /// 使用者已選擇候選動作。選定後未勾選完成前可改選，本 Event 重複發生並覆蓋原值。
  void selectNovice(String id) {
    if (!noviceStarted || noviceFinished || noviceChecked) return;
    noviceSelected = id;
    notifyListeners();
  }

  /// 使用者已完成單項新手任務。**勾選可取消** —— 健身時單手操作與誤觸為常態，
  /// 而新手任務是引導，誤觸而失去引導正好違背它存在的目的。
  ///
  /// 不記錄實際次數，也不驗證執行量：獎勵固定，做幾下不影響任何結果；
  /// 目標次數的作用是告知「做這麼多」，不是用來擋人。
  void toggleNoviceCheck() {
    if (noviceSelected == null || noviceFinished) return;
    noviceChecked = !noviceChecked;
    notifyListeners();
  }

  /// 使用者已完成新手任務。由使用者**手動按下完成**導致，非勾選後自動發生 ——
  /// 勾選與完成是兩個決定，中間留一個可反悔的位置。
  ///
  /// 本 Command **不發獎**：領取是另一個 Command，未領取者一直掛在新手任務清單頁。
  void finishNovice() {
    if (!noviceChecked || noviceFinished) return;
    noviceFinished = true;

    // 拉高的是**初始值（地板）**，不是點數紀錄 —— 故不產生「能力值已提升」。
    // 點數為單調遞增且取歷史最高，憑空的 30 會蓋住其後第一次實際訓練算出的真實值。
    // 地板抬高後點數不得低於地板，畫面上的效果即為腿與核心由 E 變 E+。
    points[Dim.legs] = math.max(points[Dim.legs]!, kNoviceLegCoreInitial);
    points[Dim.core] = math.max(points[Dim.core]!, kNoviceLegCoreInitial);

    // 使用者已解鎖社群互動功能。
    socialUnlocked = true;
    _syncAchievements();
    notifyListeners();
  }

  // --- 引導收尾：偏好訓練時段 ---

  /// 偏好訓練時段。**跳過者維持空值**（七天的區間集合皆為空）。
  PreferredTimes preferredTimes = PreferredTimes.empty();

  /// 使用者已選擇偏好訓練時段。可跳過，跳過不阻擋任何後續 Command，
  /// 也不產生本 Event。其後仍可於設定頁補填。
  void setPreferredTimes(PreferredTimes v) {
    preferredTimes = v;
    notifyListeners();
  }

  /// 最近 4 週的訓練筆數。
  int get recentWorkoutsIn4Weeks {
    final since = now.subtract(const Duration(days: 28));
    return history.where((h) => h.date.isAfter(since)).length;
  }

  /// 訓練提醒已發送。**每日一則，第 2 級行動引導類。**
  ///
  /// 兩段式時段來源：最近 4 週累積滿門檻筆訓練紀錄者依訓練時戳推算，
  /// 未滿者依註冊時填的偏好時段。**兩者皆無者不發送** ——
  /// 跳過偏好時段是明示接受的代價：強迫填寫換來的是猜測性的資料，
  /// 其提醒品質未必優於不發。
  bool sendTrainingReminderIfDue() {
    if (!reminderAvailable) return false;
    final today = businessDate(now);
    if (_trainingRemindedOn == today) return false; // 同一當地日期只發一則
    _trainingRemindedOn = today;
    notifications.insert(
      0,
      AppNotification(
        id: newId('n-trainremind-'),
        sourceEvent: '訓練提醒已發送',
        title: '今天練嗎？',
        body: reminderSource,
        at: now,
        kind: NotifyKind.push,
        priority: NotifyPriority.guidance,
      ),
    );
    notifyListeners();
    return true;
  }

  DateTime? _trainingRemindedOn;

  /// 是否有可用的提醒時段來源。
  bool get reminderAvailable =>
      recentWorkoutsIn4Weeks >= kReminderInferMinWorkouts ||
      !preferredTimes.isEmpty;

  /// 訓練提醒的時段來源。
  ///
  /// 跳過偏好時段者，在累積足夠訓練紀錄前**完全收不到訓練提醒** ——
  /// 這是明示接受的代價：強迫填寫換來的是猜測性的資料，
  /// 其提醒品質未必優於不發。
  String get reminderSource {
    if (recentWorkoutsIn4Weeks >= kReminderInferMinWorkouts) {
      return '依你最近 4 週的訓練時戳推算';
    }
    if (preferredTimes.isEmpty) return '無 —— 尚未填寫偏好時段，目前不發送訓練提醒';
    return '依你填的偏好時段，共 ${preferredTimes.filledDays} 天';
  }

  // --- 引導收尾：訓練體驗評分 ---

  /// 訓練體驗評分。獨立 Aggregate，唯一鍵為 評分者 ＋ 對象類型 ＋ 對象 ID。
  final List<ExperienceRating> experienceRatings = [];

  ExperienceRating? ratingFor(RatingTarget target, String targetId) {
    for (final r in experienceRatings) {
      if (r.rater == displayName &&
          r.target == target &&
          r.targetId == targetId) {
        return r;
      }
    }
    return null;
  }

  ExperienceRating? get noviceRating =>
      ratingFor(RatingTarget.noviceTask, kNoviceTaskId);

  /// 使用者已評分訓練體驗。
  ///
  /// 每人每個對象**終身僅一筆**，但**可修改**（覆蓋原值，修改不另立 Event）——
  /// 不可修改的話，誤觸即永久寫入一筆錯誤資料且無從更正。
  /// 評分不連動任何獎勵或聲望，無操縱誘因，故不設防刷機制。
  bool rateExperience(
    RatingTarget target,
    String targetId,
    int stars, {
    String? feedback,
  }) {
    if (!isValidStars(stars)) return false;
    final existing = ratingFor(target, targetId);
    if (existing != null) {
      existing.stars = stars;
      existing.feedback = feedback;
      existing.at = now;
    } else {
      experienceRatings.add(ExperienceRating(
        target: target,
        targetId: targetId,
        rater: displayName,
        stars: stars,
        feedback: feedback,
        at: now,
      ));
    }
    notifyListeners();
    return true;
  }

  /// 使用者已領取新手任務獎勵 → 新手任務獎勵已發放。
  ///
  /// AI 點數為**永久點數**，不重置不過期。
  ({int exp, int coins, int ai})? claimNoviceReward() {
    if (!noviceFinished || noviceRewardClaimed) return null;
    noviceRewardClaimed = true;
    totalExp += kNoviceExp;
    coins += kNoviceCoin;
    aiPermanent += kNoviceAiCredits;
    _logCredit(CreditChange.gift, kNoviceAiCredits, '新手任務獎勵');
    _syncAchievements();
    notifyListeners();
    return (exp: kNoviceExp, coins: kNoviceCoin, ai: kNoviceAiCredits);
  }

  /// 回歸任務：能力值退步後指派，完成或逾期即結束。
  bool returnTaskAssigned = false;
  DateTime? returnTaskAssignedAt;
  DateTime? returnTaskViewedAt; // 時限自「已查看」起算 7 天
  bool returnTaskDone = false;

  /// 觸發本筆回歸任務的維度 —— 文案要講得出是哪一維退了。
  Dim? returnTaskDim;

  /// 已結束的回歸任務紀錄，依指派時戳由舊到新。
  ///
  /// 存的是紀錄而非一個計數器：模型明訂**「連續逾期次數」為衍生值、不新增欄位**，
  /// 以紀錄倒序掃描累計連續為「已逾期」者，遇「已完成」即停止。
  /// 存計數器的話，它與紀錄是兩份可能對不起來的事實。
  final List<({DateTime assignedAt, bool overdue})> returnTaskLog = [];

  /// 連續逾期次數 —— 倒序掃描到第一筆「已完成」為止。
  int get returnTaskOverdueStreak {
    var n = 0;
    for (final r in returnTaskLog.reversed) {
      if (!r.overdue) break;
      n++;
    }
    return n;
  }

  /// Postcondition：「能力值已退步」發生後，觸發「回歸任務已指派」。
  void _assignReturnTask(Dim d) {
    // 一次只跑一筆；未完成的那筆還在，不重複指派。
    if (returnTaskAssigned && !returnTaskDone) return;
    if (returnTaskOverdueStreak >= 3) return;
    // 距前一次指派滿 7 天方可再次指派。
    if (returnTaskAssignedAt != null &&
        now.difference(returnTaskAssignedAt!).inDays < 7) {
      return;
    }
    returnTaskAssigned = true;
    returnTaskAssignedAt = now;
    returnTaskViewedAt = null;
    returnTaskDone = false;
    returnRewardClaimed = false;
    returnTaskDim = d;
    // Postcondition：發送推播，優先序為第 2 級行動引導類 ——
    // 時限自首次查看起算，未看見即不逾期，故非第 1 級。
    notifications.insert(
      0,
      AppNotification(
        id: newId('return-'),
        sourceEvent: '回歸任務已指派',
        title: '回歸任務已指派',
        body: '你的${dimNames[d]}已超過 ${kDecayIntervalHours ~/ 24} 天未訓練並發生退步。',
        at: now,
        kind: NotifyKind.push,
        priority: NotifyPriority.guidance,
      ),
    );
  }

  void viewReturnTask() {
    // 本 Read Model 的載入不寫入時限起算時戳，由 Event 寫入。
    returnTaskViewedAt ??= now;
    notifyListeners();
  }

  int? get returnTaskDaysLeft {
    if (returnTaskViewedAt == null) return null;
    return 7 - now.difference(returnTaskViewedAt!).inDays;
  }

  /// 使用者已完成回歸任務 → 能力值已部分回復。
  ///
  /// 六維各自回復「本次中斷累積退步量」的 50%，**不論該維是否於任務中被訓練**：
  /// 被訓練的那一維本身已產生「能力值已提升」，再對它回復即重複計酬。
  Map<Dim, int> completeReturnTask() {
    if (!returnTaskAssigned || returnTaskDone) return const {};
    returnTaskDone = true;
    returnTaskLog.add((assignedAt: returnTaskAssignedAt ?? now, overdue: false));
    final recovered = <Dim, int>{};
    for (final d in Dim.values) {
      final td = decayTimers[d]!;
      final r = recoveryFor(td.cumulative);
      if (r <= 0) continue;
      points[d] = points[d]! + r;
      // 累積退步量同步扣除，維持「中斷前點數 ＝ 點數 ＋ 累積退步量」的推導式；
      // 回復比例 < 100% 已保證回復後不超過退步前水準。
      td.cumulative -= r;
      if (td.floorReached) {
        // 已離開下限，計時器重新啟動。停止期間計時器不推進，
        // 故自解除的當下起算，而非把停掉的那段時間補算回來。
        td.floorReached = false;
        td.nextDecayAt = now.add(Duration(hours: kDecayIntervalHours));
      }
      recovered[d] = r;
    }
    notifyListeners();
    return recovered;
  }

  /// 回歸任務的獎勵是否已領取。**獎勵不於完成時自動發放**，
  /// 須由使用者主動點擊領取 —— 承每日任務「保留領取這一步」的既有裁決：
  /// 領取的點擊本身即為回饋體驗的一環。
  bool returnRewardClaimed = false;

  /// Precondition：「使用者已完成回歸任務」已發生，且該筆獎勵尚未領取。
  bool get returnRewardClaimable =>
      returnTaskAssigned && returnTaskDone && !returnRewardClaimed;

  /// 使用者已領取回歸任務獎勵 → 回歸任務獎勵已發放。
  ///
  /// 領取位置為回歸任務卡，**不進獎勵信箱** ——
  /// 回歸任務已定案 7 天逾期即消失且不發放獎勵，維持原樣。
  ({int exp, int coins, int credit})? claimReturnReward() {
    if (!returnRewardClaimable) return null;
    returnRewardClaimed = true;
    totalExp += kReturnTaskExp;
    coins += kReturnTaskCoin;
    aiPermanent += kReturnTaskCredit;
    _logCredit(CreditChange.gift, kReturnTaskCredit, '回歸任務獎勵');
    _syncAchievements();
    notifyListeners();
    return (
      exp: kReturnTaskExp,
      coins: kReturnTaskCoin,
      credit: kReturnTaskCredit
    );
  }

  /// 回歸任務已逾期：該筆消失、不發放獎勵，逾期連續計數 +1。
  void expireReturnTask() {
    if (!returnTaskAssigned || returnTaskDone) return;
    returnTaskAssigned = false;
    returnTaskViewedAt = null;
    returnTaskLog.add((assignedAt: returnTaskAssignedAt ?? now, overdue: true));
    notifyListeners();
  }

  // ===========================================================================
  // 管理員後台
  // ===========================================================================

  /// 管理員與使用者為兩個不同的 Aggregate —— 管理員不必是平台使用者。
  Admin admin = kCurrentAdmin;
  bool adminMode = false;

  late List<ReportCase> reports = buildReports();
  late List<AppealCase> appeals = buildAppeals();
  late List<InstructorCase> instructorCases = buildInstructorCases();
  // ===========================================================================
  // 自訂訓練 Aggregate —— 使用者端的管理頁與管理員端的待審佇列讀同一份
  // ===========================================================================

  late List<CustomPlan> customPlans = buildCustomPlans();

  /// 待審的公開課表 —— 佇列的來源即為自訂訓練，不另存一份案件清單。
  List<CustomPlan> get pendingPublicPlans => customPlans
      .where((p) => p.state == CustomPlanState.pendingPublic)
      .toList();

  /// 使用者已發布自訂訓練。已儲存 → 已發布；發布後方可自己選用於訓練。
  /// 已儲存 → 已發布（啟用）。
  ///
  /// 超出名額而鎖定者不可啟用 —— 鎖定的定義就是「不可選用於訓練」。
  void publishPlan(CustomPlan p) {
    if (planQuotaLocked(p)) return;
    if (p.state != CustomPlanState.saved) return;
    p.state = CustomPlanState.published;
    notifyListeners();
  }

  /// 使用者已取消發布。已發布 → 已儲存（退回未啟用）。
  void unpublishPlan(CustomPlan p) {
    if (p.state != CustomPlanState.published) return;
    p.state = CustomPlanState.published == p.state
        ? CustomPlanState.saved
        : p.state;
    notifyListeners();
  }

  /// 使用者已申請公開訓練。已發布 → 已申請公開，審核時限自此起算。
  void applyPublic(CustomPlan p) {
    if (p.state != CustomPlanState.published) return;
    p.state = CustomPlanState.pendingPublic;
    p.appliedAt = now;
    p.rejectReason = null;
    notifyListeners();
  }

  /// 管理員已審核公開訓練。已申請公開 → 已公開。
  void approvePublicPlan(CustomPlan p) {
    if (!canReview) return;
    if (p.state != CustomPlanState.pendingPublic) return;
    p.state = CustomPlanState.public;
    p.appliedAt = null;
    notifyListeners();
  }

  /// 公開訓練審核未通過。已申請公開 → **退回已發布**（自己仍可使用）。
  /// 可修改後重新申請公開，不限次數。
  void rejectPublicPlan(CustomPlan p, String reason) {
    if (!canReview) return;
    if (p.state != CustomPlanState.pendingPublic) return;
    p.state = CustomPlanState.rejected;
    p.rejectReason = reason;
    p.appliedAt = null;
    notifyListeners();
  }

  /// 審核未通過後退回已發布，可再次送審。
  void resumePublished(CustomPlan p) {
    if (p.state != CustomPlanState.rejected) return;
    p.state = CustomPlanState.published;
    p.rejectReason = null;
    notifyListeners();
  }

  /// 使用者已下架自訂訓練。已公開 → 已儲存（未啟用），為軟刪除，資料保留。
  void takeDownPlan(CustomPlan p) {
    if (p.state != CustomPlanState.public) return;
    p.state = CustomPlanState.saved;
    notifyListeners();
  }

  /// 使用者已修改自訂訓練。已公開者的修改觸發**重新審核**；
  /// 其餘狀態下的修改為自由編輯，不產生該 Event。
  void editPlan(CustomPlan p,
      {required String name, required List<PlanExercise> exercises}) {
    p.name = name;
    p.exercises = exercises;
    if (p.state == CustomPlanState.public) {
      p.state = CustomPlanState.pendingPublic;
      p.appliedAt = now;
    }
    notifyListeners();
  }

  /// 課表選擇頁可選用的自訂訓練。
  ///
  /// 三類：自己**已發布以上**的（已儲存為未啟用，不可選用）、
  /// 全平台**已公開**的、以及我所關注的人開了「對關注者可見」的。
  ///
  /// 已公開者不再看「對關注者可見」開關 —— 全平台已涵蓋關注者，
  /// 該開關於已公開時不生效。
  List<CustomPlan> get selectableCustomPlans => [
        for (final p in customPlans)
          if (_selectable(p)) p,
      ];

  bool _selectable(CustomPlan p) {
    if (p.state == CustomPlanState.public) return true;
    if (p.isMine) {
      // 已儲存（未啟用）與被名額鎖定者不可選用。
      return (p.state == CustomPlanState.published ||
              p.state == CustomPlanState.pendingPublic) &&
          !planQuotaLocked(p);
    }
    // 他人的：須開了對關注者可見，且我確實關注了作者。
    return p.visibleToFollowers && following.contains(p.author);
  }

  /// 刪除為釋放名額的唯一手段；已刪除為終止狀態，不再出現。
  void deletePlan(CustomPlan p) {
    customPlans.remove(p);
    notifyListeners();
  }

  /// 使用者已將訓練紀錄另存為自訂訓練。落地狀態為**已儲存**（需自行發布後方可選用）。
  ///
  /// 適用於**任何一次**訓練紀錄，不限於曾被 AI 調整者。
  /// 本路徑亦是「名額已滿時 AI 調整改走快照」的補救出口。
  /// 回傳 false 表示名額已滿 —— 此時使用者位於訓練歷史頁，本即有空間先行刪除。
  bool saveHistoryAsPlan(HistoryEntry h) {
    if (customPlanQuota < kUnlimitedPlans && myPlanCount >= customPlanQuota) {
      return false;
    }
    customPlans.add(CustomPlan(
      id: newId('cp'),
      name: h.planName,
      myUses: 0,
      state: CustomPlanState.saved,
      // 內容來源為該次訓練的實績：每一組的實際重量與次數即為新課表的目標。
      // 練過什麼就存什麼 —— 這正是「另存為課表」該有的語意。
      exercises: [
        for (final e in h.exercises)
          PlanExercise(
            exercise: _exerciseOf(e),
            planned: [
              for (final st in e.sets) PlannedSet(st.$1, st.$2),
            ],
          ),
      ],
    ));
    notifyListeners();
    return true;
  }

  /// 自訓練紀錄取回動作定義。歷史只存了名稱與 ID，
  /// 動作的其餘欄位（肌群、器材、相對強度）一律回動作庫取當前值。
  Exercise _exerciseOf(HistoryExercise e) {
    final all = [...platformExercises, ...kAllExercises, ...myExercises];
    final id = e.id;
    if (id != null) {
      for (final x in all) {
        if (x.id == id) return x;
      }
    }
    for (final x in all) {
      if (x.name == e.name) return x;
    }
    // 動作已自動作庫消失（管理員下架）—— 保留名稱，其餘欄位不猜。
    return Exercise(
      id: id ?? e.name,
      name: e.name,
      dim: null,
      type: e.isTimed ? ExerciseType.cardio : ExerciseType.strength,
      relativeIntensity: 0,
    );
  }

  void addPlan(String name, List<PlanExercise> exercises) {
    customPlans.add(CustomPlan(
      id: newId('cp'),
      name: name,
      exercises: exercises,
      myUses: 0,
      state: CustomPlanState.saved,
    ));
    notifyListeners();
  }

  /// 使用者已變更自訂訓練可見範圍。與狀態正交，
  /// 僅已發布 / 已申請公開者可設為真；已公開時不生效。
  void setVisibleToFollowers(CustomPlan p, bool v) {
    if (!p.canToggleVisibility) return;
    p.visibleToFollowers = v;
    notifyListeners();
  }

  /// 名額使用量的分子只算自己的課表。
  int get myPlanCount => customPlans.where((p) => p.isMine).length;

  /// 我的自訂訓練，**建立順序由舊到新**。超額鎖定要有一個穩定的順序，
  /// 否則每次重算被鎖住的是不同幾份。
  List<CustomPlan> get myPlans =>
      customPlans.where((p) => p.isMine).toList();

  /// 因超出免費名額而**鎖定**的自訂訓練。
  ///
  /// 會員權益失效後，超出的部分「**鎖定但不刪除**」——不可選用於訓練，
  /// 但資料完整保留，重新訂閱即回復可用。比照進階計畫的同一裁決：
  /// 自訂訓練是使用者自行投入時間編寫的內容，刪除的代價遠高於鎖定。
  ///
  /// 為**推導值**而非儲存欄位：續訂或升階使名額變多時自動解鎖，
  /// 不必另寫一條解鎖規則，也不會有一份跟名額對不起來的鎖定清單。
  /// 鎖定的是**最新的幾份** —— 舊的先保住，那是他最久以前就在用的。
  Set<String> get quotaLockedPlanIds {
    final quota = customPlanQuota;
    if (quota >= kUnlimitedPlans) return const {};
    final mine = myPlans;
    if (mine.length <= quota) return const {};
    return mine.sublist(quota).map((p) => p.id).toSet();
  }

  bool planQuotaLocked(CustomPlan p) => quotaLockedPlanIds.contains(p.id);


  late List<PublicPlanCase> publicPlanCases = buildPublicPlanCases();
  late List<AdminProduct> adminProducts = buildAdminProducts();
  late List<AdminOrder> adminOrders = buildAdminOrders();
  late List<RatingSummary> ratingSummaries = buildRatingSummaries();

  void toggleAdminMode() {
    adminMode = !adminMode;
    notifyListeners();
  }

  void setAdminScopes(Set<AdminScope> scopes) {
    admin = Admin(
      id: admin.id,
      name: admin.name,
      scopes: scopes.isEmpty ? {AdminScope.contentReview} : scopes,
      status: admin.status,
    );
    notifyListeners();
  }

  void setAdminStatus(AdminStatus st) {
    admin = Admin(
        id: admin.id, name: admin.name, scopes: admin.scopes, status: st);
    notifyListeners();
  }

  // ===========================================================================
  // 平台設定維護（16 個管理員 Command）
  //
  // Precondition 三條，全部 16 個 Command 共用：
  // 一、管理員狀態為生效中；
  // 二、權限組涵蓋「平台設定」；
  // 三、該組參數的不變條件成立。
  // Postcondition 一律不追溯既有紀錄。
  // ===========================================================================

  /// 平台設定的 Precondition：狀態生效中，且權限組涵蓋平台設定。
  bool get canConfigure => admin.can(AdminScope.platformConfig);

  /// 內容審核的 Precondition：狀態生效中，且權限組涵蓋內容審核。
  ///
  /// **每個管理員 Command 的 Precondition 一律增列**，本 Aggregate
  /// 為權限判定的唯一依據。畫面擋不算數 —— 模型於補簽處已裁決過
  /// 「不採由 UI 保證：Precondition 的意義即在於後端須擋」。
  bool get canReview => admin.can(AdminScope.contentReview);

  List<SettingChange> get settingLog =>
      platformConfig.log.reversed.toList(growable: false);

  void _logSetting(String event, String item, String before, String after) {
    platformConfig.log.add(SettingChange(
      event: event,
      item: item,
      before: before,
      after: after,
      at: now,
      by: admin.id,
    ));
  }

  /// 套用一組參數。回傳不變條件的違反訊息；null 為成功。
  ///
  /// 只有真正變動的參數才寫入變更紀錄 —— Event 攜帶「變更前的值、變更後的值」，
  /// 前後相同者不是一次變更。
  String? applySettings(String groupId, Map<String, num> next) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    final g = platformConfig.group(groupId);
    final merged = {...g.values, ...next};
    final violation = g.invariant?.call(merged);
    if (violation != null) return violation;

    var changed = 0;
    for (final p in g.params) {
      final v = merged[p.key];
      if (v == null || v == p.value) continue;
      final before = p.display;
      p.value = p.isInt ? v.round() : v;
      _logSetting(g.event, p.label, before, p.display);
      changed += 1;
    }
    if (changed > 0) notifyListeners();
    return null;
  }

  /// 設定成就定義 —— 門檻調整不改動既有解鎖紀錄。
  String? setAchievementDefinition(Achievement a,
      {required int threshold, required int coins, required int exp}) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (threshold < 1) return '達成門檻須至少為 1。';
    if (coins < 0 || exp < 0) return '獎勵數額不得為負。';
    const event = '管理員已設定成就定義';
    if (a.threshold != threshold) {
      _logSetting(event, '${a.name}．達成門檻', '${a.threshold}', '$threshold');
    }
    if (a.rewardCoins != coins) {
      _logSetting(event, '${a.name}．獎勵金幣', '${a.rewardCoins}', '$coins');
    }
    if (a.rewardExp != exp) {
      _logSetting(event, '${a.name}．獎勵經驗值', '${a.rewardExp}', '$exp');
    }
    final i = achievements.indexOf(a);
    achievements[i] = Achievement(
      category: a.category,
      name: a.name,
      threshold: threshold,
      rewardCoins: coins,
      rewardExp: exp,
      // 不追溯：已解鎖與已領取的狀態原樣保留，即使新門檻更高。
      unlocked: a.unlocked,
      claimed: a.claimed,
      unlockedAt: a.unlockedAt,
    );
    notifyListeners();
    return null;
  }

  /// 設定每日任務池 —— 任務池為當日隨機抽取的來源，調整不改動今日已指派的任務。
  String? setDailyTaskTarget(DailyTask t, int target) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (target < 1) return '任務目標須至少為 1。';
    if (t.target == target) return null;
    _logSetting('管理員已設定每日任務池', '${t.name}．目標', '${t.target}', '$target');
    final i = dailyTasks.indexOf(t);
    dailyTasks[i] = DailyTask(
      name: t.name,
      sourceEvent: t.sourceEvent,
      target: target,
      progress: t.progress,
      claimed: t.claimed,
    );
    notifyListeners();
    return null;
  }

  /// 設定新手任務範本 —— 新手任務為三選一，本 Command 維護可選的三個選項。
  late List<String> noviceTemplates = [
    '完成第一次訓練',
    '建立第一份自訂訓練',
    '追蹤第一位使用者',
  ];

  String? setNoviceTemplate(int index, String text) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (text.trim().isEmpty) return '範本內容不得為空。';
    final before = noviceTemplates[index];
    if (before == text.trim()) return null;
    _logSetting('管理員已設定新手任務範本', '選項 ${index + 1}', before, text.trim());
    noviceTemplates[index] = text.trim();
    notifyListeners();
    return null;
  }

  /// 設定限時任務 —— 全平台統一，一個指派日只有一組。
  /// 調整不改動已指派當日的任務內容。
  String? setTimedTask({required String title, required String detail}) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (title.trim().isEmpty) return '任務名稱不得為空。';
    const event = '管理員已設定限時任務';
    if (timedTask.title != title.trim()) {
      _logSetting(event, '任務名稱', timedTask.title, title.trim());
    }
    if (timedTask.detail != detail.trim()) {
      _logSetting(event, '任務說明', timedTask.detail, detail.trim());
    }
    timedTask = TimedTask(
      title: title.trim(),
      detail: detail.trim(),
      assignedOn: timedTask.assignedOn,
      completedBy: timedTask.completedBy,
    );
    notifyListeners();
    return null;
  }

  /// 設定平台動作 —— 組間休息為動作層級屬性，由管理員於後台設定。
  /// 相對強度係數調整不追溯既有點數。
  String? setPlatformExercise(Exercise e,
      {required double relativeIntensity, required int? restSeconds}) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (e.isCustom) return '自建動作由建立者維護，不屬平台動作庫。';
    if (relativeIntensity <= 0) return '相對強度係數須大於 0。';
    if (restSeconds != null && restSeconds <= 0) return '組間休息秒數須大於 0。';
    const event = '管理員已設定平台動作';
    if (e.relativeIntensity != relativeIntensity) {
      _logSetting(event, '${e.name}．相對強度係數', '${e.relativeIntensity}',
          '$relativeIntensity');
    }
    if (e.defaultRestSeconds != restSeconds) {
      _logSetting(event, '${e.name}．預設組間休息',
          e.defaultRestSeconds == null ? '未設定' : '${e.defaultRestSeconds}',
          restSeconds == null ? '未設定' : '$restSeconds');
    }
    final i = platformExercises.indexWhere((x) => x.id == e.id);
    if (i < 0) return '找不到該動作。';
    platformExercises[i] = Exercise(
      id: e.id,
      name: e.name,
      dim: e.dim,
      relativeIntensity: relativeIntensity,
      isBodyweight: e.isBodyweight,
      parts: e.parts,
      type: e.type,
      equipment: e.equipment,
      isCustom: e.isCustom,
      defaultRestSeconds: restSeconds,
    );
    notifyListeners();
    return null;
  }

  /// 設定訓練計畫 —— 調整不影響已產生的快照與已解鎖者。
  String? setPlanConfig(WorkoutPlan p,
      {required int? requiredRank, required int? unlockCoins}) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (requiredRank != null && (requiredRank < 1 || requiredRank > 99)) {
      return '所需階級須介於 1 與 99 之間。';
    }
    if (unlockCoins != null && unlockCoins < 0) return '解鎖價格不得為負。';
    const event = '管理員已設定訓練計畫';
    String show(int? v) => v == null ? '未設定' : '$v';
    if (p.requiredRank != requiredRank) {
      _logSetting(event, '${p.name}．所需階級', show(p.requiredRank),
          show(requiredRank));
    }
    if (p.unlockCoins != unlockCoins) {
      _logSetting(event, '${p.name}．解鎖價格', show(p.unlockCoins),
          show(unlockCoins));
    }
    final i = platformPlans.indexWhere((x) => x.id == p.id);
    if (i < 0) return '找不到該計畫。';
    platformPlans[i] = WorkoutPlan(
      id: p.id,
      name: p.name,
      source: p.source,
      exercises: p.exercises,
      requiredRank: requiredRank,
      lastTrainedAt: p.lastTrainedAt,
      lastCompletion: p.lastCompletion,
      hasOptimizationSuggestion: p.hasOptimizationSuggestion,
      equipmentTier: p.equipmentTier,
      unlockCoins: unlockCoins,
      memberUnlockable: p.memberUnlockable,
    );
    notifyListeners();
    return null;
  }

  /// 平台動作庫與平台訓練計畫的當前內容。
  /// 兩者由管理員 Command 維護，故為狀態而非常數。
  late List<Exercise> platformExercises = [...kExercises];
  /// 平台訓練計畫。
  ///
  /// [kPlans] 是七份示範用的假課表；[buildCsvPlans] 是《健身計劃.csv》
  /// 那 27 份真的、有學理依據的課表。兩份並存 ——
  /// 假課表撐著 AI 優化、會員鎖定、自訂課表那幾條流程的示範，
  /// 真課表是使用者真的會照著練的內容。
  late List<WorkoutPlan> platformPlans = [...kPlans, ...buildCsvPlans()];

  /// 課表 ID → 詳情頁的說明性內容。由平台資料維護，故為狀態而非常數。
  late Map<String, PlatformPlanSpec> planSpecById = kPlanSpecById;

  /// 有氧分頁的動作 —— 器材類有氧（本地固定）加上動作庫裡判定為有氧者。
  /// 與 `mock_data.dart` 的 `kCardioExercises` 同義，但改讀 [platformExercises]，
  /// 讓平台資料上雲後有氧分頁也反映雲端內容（[BE-12]）。
  List<Exercise> get cardioExercises => [
        ...kCardioMachines,
        ...platformExercises.where((e) => e.type == ExerciseType.cardio),
      ];

  /// 套用一份平台資料快照（[BE-12]）。
  ///
  /// 把六類平台資料填進既有的可變容器：動作庫、課表（含詳情）、成就、任務池、
  /// 平台設定。來源可能是打包在本地的後備，也可能是 Firestore 上管理員維護的
  /// 即時內容 —— [AppState] 不需要知道是哪個。平台設定沿用管理員編輯路徑
  /// （[applySettings]）的 `isInt` 取整慣例。
  void applyPlatformData(PlatformData d) {
    platformExercises = List.of(d.exercises);
    planSpecById = {for (final s in d.planSpecs) s.id: s};
    platformPlans = [...kPlans, ...buildCsvPlansFrom(d.planSpecs, d.exercises)];
    // 這兩份之後會被改（成就解鎖、管理員增刪任務），必須是可變 list。
    achievements = List.of(d.achievements);
    taskPool = List.of(d.taskPool);
    for (final g in platformConfig.groups) {
      final vals = d.config[g.id];
      if (vals == null) continue;
      for (final p in g.params) {
        final v = vals[p.key];
        if (v == null) continue;
        p.value = p.isInt ? v.round() : v;
      }
    }
    notifyListeners();
  }

  // ===========================================================================
  // 每日任務池（同時承載限時任務）
  // ===========================================================================

  late List<TaskPoolItem> taskPool = buildTaskPool();

  /// 管理員已設定每日任務池 / 管理員已設定限時任務 ——
  /// 兩個 Command 寫的是同一份清單，以「適用對象」區分。
  String _poolEvent(TaskAudience a) =>
      a == TaskAudience.team ? '管理員已設定限時任務' : '管理員已設定每日任務池';

  String? addTaskPoolItem(TaskPoolItem item) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (item.name.trim().isEmpty) return '任務名稱不得為空。';
    if (item.target < 1) return '目標次數至少為 1。';
    taskPool.add(item);
    _logSetting(_poolEvent(item.audience), '新增項目', '—', item.name);
    notifyListeners();
    return null;
  }

  String? updateTaskPoolItem(
    TaskPoolItem item, {
    String? name,
    String? sourceEvent,
    int? target,
    TaskAudience? audience,
  }) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (name != null && name.trim().isEmpty) return '任務名稱不得為空。';
    if (target != null && target < 1) return '目標次數至少為 1。';
    final event = _poolEvent(audience ?? item.audience);
    if (name != null && name.trim() != item.name) {
      _logSetting(event, '任務名稱', item.name, name.trim());
      item.name = name.trim();
    }
    if (sourceEvent != null && sourceEvent.trim() != item.sourceEvent) {
      _logSetting(event, '判定來源', item.sourceEvent, sourceEvent.trim());
      item.sourceEvent = sourceEvent.trim();
    }
    if (target != null && target != item.target) {
      _logSetting(event, '目標次數', '${item.target}', '$target');
      item.target = target;
    }
    if (audience != null && audience != item.audience) {
      _logSetting(event, '適用對象', taskAudienceNames[item.audience]!,
          taskAudienceNames[audience]!);
      item.audience = audience;
    }
    notifyListeners();
    return null;
  }

  String? removeTaskPoolItem(TaskPoolItem item) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    taskPool.remove(item);
    _logSetting(_poolEvent(item.audience), '移除項目', item.name, '—');
    notifyListeners();
    return null;
  }

  /// 每日重置：自任務池隨機抽取指派。
  /// **任務池調整不改動任何使用者當日已指派的任務** —— 要重抽才會換。
  void redrawDailyTasks() {
    final picked = drawDaily(taskPool, kDailyDrawCount);
    dailyTasks = [
      for (final t in picked)
        DailyTask(
          name: t.name,
          sourceEvent: t.sourceEvent,
          target: t.target,
        ),
    ];
    // 進度自「今天已經發生過的事」起算，不是一律從 0。
    reconcileDailyTasks();
    notifyListeners();
  }

  /// 每日任務進度**不得低於今天已知已發生的次數**。
  ///
  /// 這是一條不變條件，不是重抽時順手做的事 —— 進度會經由三條路徑
  /// 進到當前狀態：每日重置抽出、日中重抽、自存檔還原。三條都可能
  /// 留下一份與「今天已經發生過的事」對不起來的進度，
  /// 而使用者看到的是同一個畫面上兩個互相矛盾的數字：
  /// 上面寫「今日已簽到」，下面的「今日簽到」卻是 0/1。
  ///
  /// 只往上補、不往下砍：進度可能來自本來就沒有逐日計數的來源（如組數），
  /// 砍下去會把使用者真的做過的事抹掉。
  bool reconcileDailyTasks() {
    var changed = false;
    for (final t in dailyTasks) {
      final known = math.min(t.target, _doneTodayFor(t.sourceEvent));
      if (known > t.progress) {
        t.progress = known;
        changed = true;
      }
    }
    return changed;
  }

  /// 今天已經發生過幾次該 Event。
  ///
  /// 只回答**狀態問得出來**的那幾個：簽到與訓練各自有當日旗標，
  /// 四類互動有當日計數（獎勵上限本來就要用）。
  /// 組數這類沒有逐日計數的，回 0 —— 猜一個數字比從 0 起算更糟。
  int _doneTodayFor(String event) {
    _rollInteractionDay();
    return switch (event) {
      '使用者已簽到' => checkedInToday ? 1 : 0,
      '使用者已完成訓練' ||
      '訓練已結算' =>
        lastTrainedDate == businessDate(now) ? 1 : 0,
      '互動者已按讚貼文' => interactionsToday('Like'),
      '互動者已留言' => interactionsToday('Comment'),
      '發文者已發布貼文' => interactionsToday('Post'),
      '發文者已分享訓練成果' => interactionsToday('Share'),
      _ => 0,
    };
  }

  /// 管理員已設定限時任務：自任務池中適用對象為團隊的項目指派一組。
  String? assignTimedTaskFrom(TaskPoolItem item) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (item.audience != TaskAudience.team) return '該項目的適用對象不是團隊。';
    _logSetting('管理員已設定限時任務', '本日指派', timedTask.title, item.name);
    timedTask = TimedTask(
      title: item.name,
      detail: '判定來源：${item.sourceEvent}，目標 ${item.target} 次。'
          '訓練類項目照常走訓練紀錄流程，連續天數與能力值全部照常累計。',
      assignedOn: now,
      completedBy: timedTask.completedBy,
    );
    notifyListeners();
    return null;
  }

  // ===========================================================================
  // 教官測驗題庫
  // ===========================================================================

  late List<ExamQuestion> examBank = buildExamBank();

  /// 題庫是否抽得出一份考卷。抽不出來時後台要講，不是等考生撞牆。
  String? get examBankWarning => examBankShortage(
        examBank,
        platformConfig.i('exam', 'mcCount'),
        platformConfig.i('exam', 'saCount'),
      );

  String? addExamQuestion(ExamQuestion q) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (q.text.trim().isEmpty) return '題目內容不得為空。';
    if (q.type == ExamQuestionType.multipleChoice && q.options.length < 2) {
      return '選擇題至少要有兩個選項。';
    }
    examBank.add(q);
    _logSetting('管理員已設定教官測驗', '新增題目', '—', q.text.trim());
    notifyListeners();
    return null;
  }

  String? removeExamQuestion(ExamQuestion q) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    examBank.remove(q);
    // 設定調整不改動任何已完成作答的既有測驗結果。
    _logSetting('管理員已設定教官測驗', '移除題目', q.text, '—');
    notifyListeners();
    return null;
  }

  // --- 自建動作 ---

  /// 我的動作。**必須存在狀態裡**：原本動作庫直接讀 const 的 [kCustomExercises]，
  /// 新建立的動作只被回傳給呼叫端用在當下那場訓練，從來沒有寫回任何地方 ——
  /// 所以「我的動作」分頁永遠只有假資料那兩筆。
  late List<Exercise> myExercises = [...kCustomExercises];

  /// 使用者已建立自訂動作。
  ///
  /// 僅建立者本人可見，不進平台動作庫，且練它不提升六維能力值 ——
  /// 它未經平台驗證動作定義，不得用於加分；但仍重設所屬肌群的退步計時。
  bool createCustomExercise(Exercise e) {
    if (myExercises.any((x) => x.name == e.name)) return false;
    myExercises.insert(0, e);
    notifyListeners();
    return true;
  }

    /// 依 ID 取當前的平台動作。找不到者（自建動作）回傳原物件。
  Exercise exerciseById(String id) =>
      platformExercises.firstWhere((e) => e.id == id,
          orElse: () => [...kAllExercises, ...myExercises]
              .firstWhere((e) => e.id == id,
              orElse: () => kCardioMachines.first));

  // --- 管理員本身的維護（3 個 Command，權限組為平台設定）---

  late List<Admin> admins = buildAdmins();

  /// 內容審核組的**另一位**管理員。
  ///
  /// 審我的案子的不會是我自己。案件的處理人欄位要留下那個人的名字，
  /// 而「接手審核案件」的 Precondition（執行者不為目前的處理中管理員）
  /// 也只有在真的換了人的時候才驗得到。
  Admin get otherReviewer => admins.firstWhere(
        (a) => a.id != admin.id && a.can(AdminScope.contentReview),
        orElse: () => admin,
      );

  /// 以 [who] 的身分執行一段管理員 Command，執行完換回來。
  ///
  /// 權限一條都不放寬 —— [who] 沒有的權限組照樣擋下，
  /// 換的只是「是誰按的」。
  T runAsAdmin<T>(Admin who, T Function() body) {
    final prev = admin;
    admin = who;
    try {
      return body();
    } finally {
      admin = prev;
    }
  }

  /// 新增管理員。權限組至少 1 項。
  String? addAdmin(String name, Set<AdminScope> scopes) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (name.trim().isEmpty) return '管理員名稱不得為空。';
    if (scopes.isEmpty) return '權限組至少 1 項。';
    final id = 'A-${(admins.length + 1).toString().padLeft(3, '0')}';
    admins.add(Admin(id: id, name: name.trim(), scopes: scopes));
    _logSetting('管理員已新增', id, '不存在',
        '${name.trim()}（${scopes.map((x) => adminScopeNames[x]).join('、')}）');
    notifyListeners();
    return null;
  }

  /// 停用管理員。已停用者不得執行任何管理員 Command。
  /// 不實體刪除 —— 其既往的判定紀錄仍須可稽核。
  String? disableAdmin(Admin a) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (a.status == AdminStatus.disabled) return null;
    // 不得停用自己：停用當下即失去平台設定權限，將無人能把自己救回來。
    if (a.id == admin.id) return '不得停用自己 —— 請由另一位具平台設定權限者執行。';
    if (admins
            .where((x) =>
                x.id != a.id &&
                x.status == AdminStatus.active &&
                x.scopes.contains(AdminScope.platformConfig))
            .isEmpty) {
      return '不得停用最後一位具平台設定權限的生效中管理員。';
    }
    _replaceAdmin(a, status: AdminStatus.disabled);
    _logSetting('管理員已停用', a.id, '生效中', '已停用');
    notifyListeners();
    return null;
  }

  String? enableAdmin(Admin a) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (a.status == AdminStatus.active) return null;
    _replaceAdmin(a, status: AdminStatus.active);
    _logSetting('管理員已新增', a.id, '已停用', '生效中');
    notifyListeners();
    return null;
  }

  /// 調整管理員權限組。
  String? setAdminScopesOf(Admin a, Set<AdminScope> scopes) {
    if (!canConfigure) return '權限不足：本 Command 需要「平台設定」權限組。';
    if (scopes.isEmpty) return '權限組至少 1 項。';
    if (a.scopes.length == scopes.length && a.scopes.containsAll(scopes)) {
      return null;
    }
    String show(Set<AdminScope> x) {
      final ordered =
          AdminScope.values.where(x.contains).map((v) => adminScopeNames[v]);
      return ordered.join('、');
    }

    _logSetting('管理員權限組已調整', a.id, show(a.scopes), show(scopes));
    _replaceAdmin(a, scopes: scopes);
    if (a.id == admin.id) {
      admin = Admin(
          id: admin.id, name: admin.name, scopes: scopes, status: admin.status);
    }
    notifyListeners();
    return null;
  }

  void _replaceAdmin(Admin a, {Set<AdminScope>? scopes, AdminStatus? status}) {
    final i = admins.indexWhere((x) => x.id == a.id);
    if (i < 0) return;
    admins[i] = Admin(
      id: a.id,
      name: a.name,
      scopes: scopes ?? a.scopes,
      status: status ?? a.status,
    );
  }

  void decideInstructor(InstructorCase c, bool pass) {
    if (!canReview) return;
    if (c.state == CaseState.upheld || c.state == CaseState.dismissed) return;
    c.state = pass ? CaseState.upheld : CaseState.dismissed;
    // 判定的若是我的申請，我這一側的狀態也要跟著走完 ——
    // 先前這裡只改案件狀態，申請人永遠停在「待人工審核」。
    if (c.applicant == displayName &&
        instructorStage == InstructorStage.pendingReview) {
      if (pass) {
        instructorStage = InstructorStage.approved;
        instructorRejectStage = null;
        _becomeInstructor();
      } else {
        instructorStage = InstructorStage.rejected;
        instructorRejectStage = '管理員審核';
      }
    }
    notifyListeners();
  }



  // ===========================================================================
  // 商品管理（〈管理員商品上架流程〉）
  //
  // 商品為單一 Aggregate，其下含「商品規格」子聚合 ——
  // 價格與庫存皆屬規格層級，商品層級無單一價格與庫存。
  // ===========================================================================

  bool get canManageProducts => admin.can(AdminScope.productManage);

  /// 新增商品。新商品一律自「已下架」起算 ——
  /// 上架另有 Precondition，不能靠新增繞過。
  String? addProduct({
    required String name,
    required bool physical,
    required VirtualSubtype? subtype,
  }) {
    if (!canManageProducts) return '權限不足：本 Command 需要「商品管理」權限組。';
    if (name.trim().isEmpty) return '商品名稱不得為空。';
    if (!physical && subtype == null) return '虛擬商品須指定子類型。';
    final id = '${physical ? 'g' : 'v'}${adminProducts.length + 1}';
    adminProducts.add(AdminProduct(
      id: id,
      name: name.trim(),
      emoji: physical ? '📦' : '✨',
      physical: physical,
      subtype: physical ? null : subtype,
      listing: ListingState.delisted,
      // 實體商品的規格為尺寸；虛擬商品僅有一個預設規格。
      specs: physical
          ? [AdminProductSpec('單一尺寸', 0, 0)]
          // 庫存一律自 0 起算。權限解鎖類根本不適用庫存
          // （見 AdminProduct.stockApplies），道具類則由管理員上架前自行設定。
          // 原本這裡寫 `subtype == unlock ? 0 : 0` —— 兩個分支同值，
          // 那個判斷讀起來像有差別，實際上什麼都沒做。
          : [AdminProductSpec('預設規格', 0, 0)],
      unshippedOrders: 0,
    ));
    notifyListeners();
    return null;
  }

  /// 設定商品資訊。Postcondition：寫入商品資訊（含類型、名稱、圖片）；
  /// 價格與庫存屬商品規格層級，逐規格設定。
  String? setProductInfo(
    AdminProduct p, {
    required String name,
    required List<String> images,
    required List<AdminProductSpec> specs,
    VirtualSubtype? subtype,
    String? unlockTarget,
  }) {
    if (!canManageProducts) return '權限不足：本 Command 需要「商品管理」權限組。';
    if (name.trim().isEmpty) return '商品名稱不得為空。';
    if (specs.isEmpty) return '至少須有一個規格。';
    if (!p.physical && specs.length > 1) return '虛擬商品僅有一個預設規格。';
    if (specs.any((x) => x.name.trim().isEmpty)) return '規格名稱不得為空。';
    final names = specs.map((x) => x.name.trim()).toSet();
    if (names.length != specs.length) return '規格名稱不得重複。';
    if (specs.any((x) => x.price < 0)) return '價格不得為負。';
    if (specs.any((x) => x.stock < 0)) return '庫存不得為負值。';

    p.name = name.trim();
    p.images = [...images];
    if (!p.physical) {
      p.subtype = subtype ?? p.subtype;
      // 解鎖標的僅權限解鎖類有值，其餘一律清空 —— 欄位不留舊值。
      p.unlockTarget =
          p.subtype == VirtualSubtype.unlock ? unlockTarget?.trim() : null;
    }
    p.specs
      ..clear()
      ..addAll(specs.map((x) =>
          AdminProductSpec(x.name.trim(), x.price, x.stock)));

    // 已上架商品被改到「商品資訊不完整」者，當場退回已下架 ——
    // 否則商品頁會出現一個沒有名稱或沒有圖片的品項。
    //
    // 只看資訊完整度，不看庫存：庫存 > 0 是**上架時**的 Precondition，
    // 不是維持上架的條件 —— 模型明訂「售完不自動下架」。
    if (p.listing == ListingState.listed && !p.infoComplete) {
      p.listing = ListingState.delisted;
    }
    notifyListeners();
    return null;
  }

  /// 上架商品。Precondition：已設定完商品資訊，且至少一個規格的庫存 > 0。
  String? listProduct(AdminProduct p) {
    if (!canManageProducts) return '權限不足：本 Command 需要「商品管理」權限組。';
    if (p.listing == ListingState.listed) return null;
    if (!p.infoComplete) return '尚未設定完商品資訊（名稱、圖片、解鎖標的）。';
    if (!p.hasStock) return '所有規格皆無庫存，不得上架。';
    p.listing = ListingState.listed;
    notifyListeners();
    return null;
  }

  /// 下架商品。
  ///
  /// 下架僅停止新訂單成立，不影響已成立的訂單：
  /// 待付款訂單自動取消並釋放庫存，已付款而未出貨者照常履行。
  /// 回傳被連帶取消的訂單 ID —— 管理員要看得到自己按下去發生了什麼。
  List<String> delistProduct(AdminProduct p) {
    if (!canManageProducts || p.listing == ListingState.delisted) {
      return const [];
    }
    p.listing = ListingState.delisted;
    final cancelled = <String>[];
    for (final o in adminOrders) {
      if (o.product != p.name || o.state != '待付款') continue;
      // 「訂單已因商品下架取消」—— Actor 為系統，非使用者。
      o.state = '已因商品下架取消';
      cancelled.add(o.id);
      // 連帶「庫存已釋放」：待付款期間佔用的庫存還回該規格。
      for (final spec in p.specs) {
        if (spec.name == o.spec) spec.stock += o.qty;
      }
    }
    // 使用者那一側的同一筆訂單也要跟著取消 ——
    // 後台顯示已取消、使用者的訂單頁卻還停在待付款，是兩份互相矛盾的紀錄。
    for (final u in orders) {
      if (u.state != OrderState.pendingPayment) continue;
      if (!cancelled.contains(u.id) && u.productName != p.name) continue;
      _releaseHold(u);
      u.state = OrderState.cancelled;
      u.cancelledBySystem = true;
    }
    notifyListeners();
    return cancelled;
  }

  /// 待付款訂單佔用的庫存筆數 —— 下架前的告知依據。
  int pendingOrdersOf(AdminProduct p) =>
      adminOrders.where((o) => o.product == p.name && o.state == '待付款').length;

  /// 商品已出貨 —— 記錄物流單號，系統不再追蹤後續物流狀態。
  /// 同一筆訂單在使用者端亦轉為已出貨，並於我的訂單頁標紅點。
  void shipOrder(AdminOrder o, {String? trackingNo}) {
    if (!canManageProducts) return;
    if (o.state != '已付款') return;
    o.state = '已出貨';
    final no = trackingNo ??
        'TW${now.millisecondsSinceEpoch % 1000000000}';
    o.trackingNo = no;
    for (final u in orders) {
      if (u.id == o.id && u.state == OrderState.paid) {
        u.state = OrderState.shipped;
        u.trackingNo = no;
        unreadShipped.add(u.id);
      }
    }
    // App 內通知（我的訂單頁紅點）為主；已填電子郵件者另以信件通知。
    _email('你的訂單已出貨', '${o.product}　物流單號 $no');
    notifyListeners();
  }

  void refundOrder(AdminOrder o) {
    if (!canManageProducts) return;
    if (o.state != '待退款') return;
    o.state = '已退款';
    notifyListeners();
  }

  int get pendingReviewCount =>
      reports.where((c) => c.state == CaseState.pending || c.state == CaseState.reviewing).length +
      appeals.where((c) => c.state == CaseState.pending || c.state == CaseState.reviewing).length +
      instructorCases.where((c) => c.state == CaseState.pending).length +
      pendingPublicPlans.length;

  // ===========================================================================
  // 註冊
  // ===========================================================================

  /// 未填完即離開者，資料保留於此，下次自未完成的欄位續填。
  final SignUpDraft signUpDraft = SignUpDraft();

  // --- 註冊問卷的四個欄位（已落地的值，非草稿） ---
  // 註冊完成後這四項屬使用者 Aggregate；signUpDraft 只是填寫過程的暫存。
  // 兩者分開，否則週期更新一改就會把一份「已完成」的草稿改回未完成。
  int daysPerWeek = 4;
  String duration = '60–90 分鐘';
  String commonGoal = '增肌';
  String experience = '中階（6 個月–2 年）';

  /// 註冊填入的 3 級器材。持有器材明細為空值時的比對基準。
  String equipmentTier = '健身房（全器材）';
  /// 是否已完成註冊。
  ///
  /// 預設 true 是**示範用身分**的一部分：直接 `AppState()` 建出來的是
  /// 那位假使用者，已經註冊過。真正的第一次啟動由 [hydrate] 判定 ——
  /// 讀不到存檔就把它設為 false，走完整的註冊流程。
  bool signUpCompleted = true;

  /// 9 項全數填畢方可完成註冊；獎勵為金幣 100 ＋ 補簽券 ×1，無經驗值。
  /// 使用者帳號已建立的 Postcondition —— 把帳號層級的計數器一次歸位。
  ///
  /// 模型明訂帳號建立時**一併產生**連續訓練 Aggregate（上次訓練日期＝註冊日）
  /// 與能力值 Aggregate（六維點數 10、各維最後訓練日皆為註冊日）。
  ///
  /// 這些欄位不歸位的話，「從未訓練者」那條路徑就演不出來 ——
  /// 模型花了不少篇幅定義它（四道門檻自註冊日起算、六維卡在下限、
  /// 仍要收得到回歸任務），而那正是它最需要被看見的地方。
  ///
  /// **會清掉示範資料**，故由呼叫端先徵詢使用者。
  void resetToNewAccount() {
    registeredOn = businessDate(now);

    // 連續訓練 Aggregate。
    lastTrainedDate = initialLastTrainedDate;
    trainingStreakDays = 0;
    totalWorkouts = 0;
    totalWorkoutDays = 0;

    // 能力值 Aggregate：六維點數為初始值，各維最後訓練日皆為註冊日。
    //
    // **[trainedDims] 與 [pending] 一起清**：漏掉的話，新帳號會宣稱
    // 六個維度全都練過了，於是每一維真正的第一場都走不到「首場」那條路
    // —— 首場可直接跳到實測值（上限 450），非首場只能爬到下一個節點的上緣。
    // 實測 296 分的第一場，會因此只給到 69。
    trainedDims.clear();
    for (final d in Dim.values) {
      points[d] = initialOf(d);
      pending[d] = 0;
      decayTimers[d] = _freshTimer(registeredOn);
    }
    decayLog.clear();
    snapshots.clear();

    // 連續簽到 Aggregate。
    checkInTotal = 0;
    checkInLongest = 0;

    // 使用者 Aggregate 的其餘計數器。新帳號一律自零起算 ——
    // 只歸位兩個 Aggregate 會做出「階級 45、六維 10、零次訓練」這種
    // 自相矛盾的帳號。
    totalExp = 0;
    coins = 0;
    weeklyScore = 0;
    monthlyScore = 0;
    lockedRankGroup = null;
    lockedMonthlyGroup = null;
    makeupTickets = 0;
    myViolations = 0;
    punishment = null;
    followTotal = 0;
    interactionTotals.clear();
    mailbox.clear();

    // 中斷預告階段跟著歸零，否則新帳號一開就收到上一個帳號的預告。
    _trainNoticeStage = DecayStage.normal;
    _checkInNoticeStage = CheckInStage.normal;

    // 回歸任務：新帳號沒有任何紀錄。
    returnTaskAssigned = false;
    returnTaskDone = false;
    returnRewardClaimed = false;
    returnTaskAssignedAt = null;
    returnTaskViewedAt = null;
    returnTaskLog.clear();

    // --- 屬於這個帳號的內容與關係，一併清掉 ---
    //
    // 只歸零計數器而留著集合，會做出一個「階級 1、零次訓練，卻有 5 筆
    // 訓練歷史、7 份自訂訓練、2 個學徒、還在某支隊伍裡」的帳號 ——
    // 訓練歷史頁列出 5 場，累積訓練天數寫 0，同一件事兩個答案。
    //
    // 保留的是「這個世界」：別人的貼文、別人開放的自訂訓練、商城的商品。
    // 清掉的是「我在這個世界留下的東西」。
    posts.removeWhere((p) => p.author == displayName);
    customPlans.removeWhere((c) => c.isMine);
    history.clear();
    orders.clear();
    conversations.clear();
    notifications.clear();
    checkInRecords.clear();
    followers.clear();
    following.clear();
    blockedUsers.clear();
    sentApplications.clear();
    inbox.clear();
    myTeam = null;
    myInstructor = null;
    apprentices.clear();
    peakFollowerCount = 0;
    purchasedPlanIds.clear();
    leaderboardHistory.clear();
    emailOutbox.clear();
    rewardedRequests.clear();

    // --- 新手 / 回歸任務 ---
    // 零次訓練的帳號當然沒做過新手任務。漏掉的話還會連帶讓
    // 「新手任務」那一枚成就在下面的 _syncAchievements() 又被解開。
    noviceStarted = false;
    noviceSelected = null;
    noviceChecked = false;
    noviceFinished = false;
    noviceRewardClaimed = false;
    socialUnlocked = false;
    returnTaskDim = null;

    // --- 師徒與教官 ---
    // 教官資格、聲望、專長，以及五個週期計數器。
    isInstructor = false;
    instructorStage = InstructorStage.notApplied;
    instructorRejectStage = null;
    instructorReputation = 0;
    peakReputation = 0;
    instructorSpecialties.clear();
    instructorDutyVersion = null;
    mentorDisclaimerVersion = null;
    markMentorLocked();
    mentorTasks.clear();
    questions.clear();
    weeklyQuestionCount = 0;
    weeklyAnswerCount = 0;
    weeklyAssigned = 0;
    weeklyCompleted = 0;
    ratedThisWeek = false;
    taskRatingsThisWeek = 0;
    mentorRewardsThisWeek = 0;
    apprenticeTaskRatings.clear();
    apprenticeWeeklyRated.clear();

    // --- 會員與 AI 點數 ---
    // 永久點數是買來的，月度額度是會員權益 —— 新帳號兩者都沒有。
    membership = MembershipState.none;
    membershipExpiry = null;
    membershipLockedPlanIds = const [];
    aiMonthly = 0;
    aiPermanent = 0;
    autoOptimizeCount = 0;

    // --- 自建動作 ---
    // 「我的動作」是使用者自己建的，跟自訂訓練同一個道理。
    myExercises.clear();

    // --- 帳號本身 ---
    // 上一個帳號的刪除申請不該跟著新帳號走 —— 歸零多半正是從那條路來的。
    email = null;
    deletionRequestedAt = null;
    deletionCoolingDays = null;

    // --- 問卷與提醒的時戳 ---
    // 問卷答案保留（那是「你是誰」），但「上次更新於何時」要重新起算，
    // 且上一個帳號按過的「以後再說」不該讓新帳號也不被問。
    weightUpdatedAt = registeredOn;
    surveyUpdatedAt = registeredOn;
    clearAskSkips();

    // --- 今日互動計數 ---
    resetInteractionDay();

    // 成就一併歸零。新帳號沒有任何成就 —— 少了這一步，
    // 新帳號一開就是「階級 1，但成就頁寫著『達到 45 階 ✓』」，
    // 而且那 43 枚的獎勵金幣可以直接領走。
    // 這正是上面那段註解要避免的「自相矛盾的帳號」，只是漏了成就這一項。
    _relockAchievements();
    _syncAchievements();

    // 問卷答案留著，所以照樣推薦得出一份計畫 —— 註冊流程的最後一步。
    currentPlan = recommendCurrentPlan();
  }

  /// 清掉「以後再說」的紀錄。私有欄位，只有這裡與提醒判定用得到。
  void clearAskSkips() {
    _weightAskSkippedAt = null;
    _surveyAskSkippedAt = null;
  }

  /// 今日互動計數歸零。
  void resetInteractionDay() {
    _interactDay = null;
    _interactCounts.clear();
  }

  /// 師徒功能重新上鎖。
  void markMentorLocked() => _mentorUnlocked = false;

  void completeSignUp() {
    if (!signUpDraft.complete) return;
    signUpCompleted = true;
    // 使用者帳號已建立 —— 兩個 Aggregate 一併產生，計時自註冊日起算。
    resetToNewAccount();
    coins += kSignUpCoins;
    grantMakeupTickets(kSignUpMakeupTickets);
    if (signUpDraft.weightKg != null) bodyweightKg = signUpDraft.weightKg!;
    if (signUpDraft.heightCm != null) heightCm = signUpDraft.heightCm!;
    if (signUpDraft.gender != null) isMale = signUpDraft.gender == '男';
    // 草稿落地為使用者屬性；其後由〈簽到畫面的週期更新〉維護。
    if (signUpDraft.daysPerWeek != null) daysPerWeek = signUpDraft.daysPerWeek!;
    if (signUpDraft.duration != null) duration = signUpDraft.duration!;
    if (signUpDraft.commonGoal != null) commonGoal = signUpDraft.commonGoal!;
    if (signUpDraft.experience != null) experience = signUpDraft.experience!;
    if (signUpDraft.equipment.isNotEmpty) {
      equipmentTier = signUpDraft.equipment.first;
    }
    weightUpdatedAt = now;
    surveyUpdatedAt = now;
    // 剛註冊的人不存在於本週期起點，組別留待首次計分時鎖定。
    lockedRankGroup = null;
    lockedMonthlyGroup = null;
    currentPlan = recommendCurrentPlan();
    notifyListeners();
  }

  // ===========================================================================
  // 設定
  // ===========================================================================

  /// 持有器材明細（選填，預設空）。值域見〈器材設定 Aggregate〉的 8 品項。
  /// 有值時優先於註冊填入的 3 級器材，並作為動作庫器材篩選的預設值。
  final Set<String> ownedEquipment = {'徒手', '啞鈴', '槓鈴', '繩索（滑輪）'};
  bool aiAutoOptimize = true;
  bool abilityPublic = true;
  bool overallGradePublic = true;
  /// 電子郵件。**選填** —— 第三方登入者於授權時帶入，手機註冊者可自願填寫。
  ///
  /// 僅供三類通知使用：出貨、處罰與申訴結果、帳號刪除排程。
  /// 未填者由推播與 App 內通知承擔，不因此少收到任何權益相關的訊息。
  String? email;

  /// 是否為合法的電子郵件格式。空字串視為「清空」，合法。
  static bool isValidEmail(String v) {
    final t = v.trim();
    if (t.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
  }

  /// 使用者已填入電子郵件。回傳錯誤訊息；null 為成功。
  String? setEmail(String v) {
    if (!isValidEmail(v)) return '電子郵件格式不正確。';
    final t = v.trim();
    email = t.isEmpty ? null : t;
    notifyListeners();
    return null;
  }

  /// 已填電子郵件者，三類通知另以電子郵件發送。
  bool get emailNotifiable => email != null;

  /// 已寄出的電子郵件。**只有三類**：出貨、處罰與申訴結果、帳號刪除排程。
  ///
  /// 寄送本身在系統邊界外，此處記錄「寄了什麼給誰」——
  /// 沒有這份紀錄，「另以電子郵件通知」這條 Postcondition 無從驗收。
  final List<EmailNotice> emailOutbox = [];

  /// 寄一封信。未填電子郵件者不寄，且**不因此少收到任何權益相關的訊息**
  /// —— 那些由推播與 App 內通知承擔，本函式不是它們的替代品。
  void _email(String subject, String body) {
    final to = email;
    if (to == null) return;
    emailOutbox.insert(0, EmailNotice(to: to, subject: subject, body: body, at: now));
  }

  bool metricUnits = true;

  // --- 單位偏好：僅影響顯示，不影響儲存 ---
  //
  // 身高與體重一律以公制儲存，英制只是換算後的呈現。
  // 英制範圍由公制換算，不另設一套：身高 20–98 in、體重 44–661 lb。

  /// 體重的顯示值與單位。
  (String, String) weightDisplay(double kg) => metricUnits
      ? (kg.toStringAsFixed(1), 'kg')
      : ((kg * 2.20462).toStringAsFixed(1), 'lb');

  /// 身高的顯示值與單位。
  (String, String) heightDisplay(double cm) => metricUnits
      ? (cm.round().toString(), 'cm')
      : ((cm / 2.54).toStringAsFixed(1), 'in');

  /// 訓練重量的顯示值與單位。0 為徒手，不帶單位。
  (String, String) loadDisplay(double kg) {
    if (!metricUnits) return ((kg * 2.20462).toStringAsFixed(1), 'lb');
    return (
      kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1),
      'kg'
    );
  }

  String weightText(double kg) {
    final (v, u) = weightDisplay(kg);
    return '$v $u';
  }

  String heightText(double cm) {
    final (v, u) = heightDisplay(cm);
    return '$v $u';
  }

  /// 訓練量的顯示值與單位（同為重量，四捨五入至整數）。
  (String, String) volumeDisplay(double kg) => metricUnits
      ? (kg.round().toString(), 'kg')
      : ((kg * 2.20462).round().toString(), 'lb');

  String loadText(double kg) {
    if (kg == 0) return '徒手';
    final (v, u) = loadDisplay(kg);
    return '$v $u';
  }
  double heightCm = 176;
  DateTime? deletionRequestedAt;

  void toggleEquipment(String e) {
    ownedEquipment.contains(e) ? ownedEquipment.remove(e) : ownedEquipment.add(e);
    notifyListeners();
  }

  void setFlag({
    bool? autoOptimize,
    bool? ability,
    bool? overall,
    bool? metric,
  }) {
    if (autoOptimize != null) {
      aiAutoOptimize = autoOptimize;
      // 關閉期間照常累計；重新啟用後不補跑期間錯過的優化，
      // 與訂閱當下的處理完全一致 —— 達標即觸發一次，只有一份。
      if (autoOptimize) tryAutoOptimize();
    }
    if (ability != null) abilityPublic = ability;
    if (overall != null) overallGradePublic = overall;
    if (metric != null) metricUnits = metric;
    notifyListeners();
  }

  /// 申請當下的冷靜期長度。**不隨參數調整而變** ——
  /// 已在冷靜期中的申請依申請當時的長度計算，否則管理員改個數字就能延長別人的期限。
  int? deletionCoolingDays;

  /// 使用者已申請刪除帳號 → 帳號狀態 正常 → 待刪除。
  ///
  /// 進行中的訂單與生效中的訂閱**一律不阻擋**：Apple 的措辭是「請求使用者取消訂閱」，
  /// 不是授權平台擋下刪除；以未取消訂閱為由拒絕刪除屬附加不合理條件。
  void requestDeletion() {
    if (deletionRequestedAt != null) return;
    deletionRequestedAt = now;
    deletionCoolingDays = kDeletionCoolingDays;
    _email('帳號刪除已排程',
        '你的帳號將於 $kDeletionCoolingDays 天後刪除。'
        '在此之前於 App 內取消申請即可保留帳號與全部資料。');
    notifyListeners();
  }

  /// 使用者已取消刪除帳號申請 → 待刪除 → 正常。
  ///
  /// **不重設任何計時基準、不補償期間的損失**：冷靜期間所有計時與排程照常，
  /// 申請刪除是使用者自願，其未訓練是自己的選擇。
  void cancelDeletion() {
    deletionRequestedAt = null;
    deletionCoolingDays = null;
    notifyListeners();
  }

  /// 帳號狀態為待刪除。**語意是「帳號停用」＝可登入，但僅能使用
  /// 「取消刪除帳號申請」**，其餘功能一律不可用 —— 不是登不進去。
  bool get pendingDeletion => deletionRequestedAt != null;

  /// 冷靜期剩餘天數。
  int? get deletionDaysLeft => deletionRequestedAt == null
      ? null
      : (deletionCoolingDays ?? kDeletionCoolingDays) -
          now.difference(deletionRequestedAt!).inDays;
}

/// 極簡的狀態注入，不引入任何外部套件。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
