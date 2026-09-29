import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';

import '../domain/ability.dart';
import '../domain/endurance.dart';
import '../domain/exercise_stats.dart';
import '../domain/clock.dart';
// 換日規則已移入 clock.dart（假資料產生器也要用同一套）。
// 轉出以維持既有呼叫端不變 —— 19 處在本檔、5 個測試檔。
export '../domain/clock.dart' show businessDate;
import '../data/ai_suggestion.dart';
import '../data/instructor_case_data.dart';
import '../data/report_data.dart';
import '../data/appeal_data.dart';
import '../data/punishment_data.dart';
import '../data/quality_score_data.dart';
import '../data/violation_data.dart';
import '../domain/ai_adjust.dart';
import '../domain/decay.dart';
import '../domain/novice.dart';
import '../domain/novice_wrapup.dart';
import '../domain/task_pool.dart';
import '../domain/training_quality.dart';
import '../domain/models.dart';
import '../domain/registration.dart';
import '../domain/social.dart';
import '../domain/leaderboard.dart';
import '../domain/rank.dart';
import 'dart:typed_data';

import '../data/photo_data.dart';
import '../data/rating_data.dart';
import '../design/image_library.dart' show PhotoScope;
import '../domain/photo.dart';
import '../domain/plan_duration.dart';
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
import '../data/mentor_data.dart';
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

  // --- 改名（暱稱重構階段五，使用者裁決 A：30 天一次）---

  /// 上次改名的時點。**空值代表從來沒改過。**
  DateTime? lastRenamedAt;

  /// 曾用名，新的在前。**只給管理員看，不對一般使用者呈現。**
  ///
  /// 規格說暱稱是顯示名稱不是識別碼 —— 把一個人的改名史公開出去
  /// 等於替他做了一次他沒同意的揭露。管理端的用途見
  /// `review_queue_screen`：那裡呈現的是**案件建立當下**的名字，
  /// 而那一份本來就跟著案件存著（`ReportCase.accused`）。
  final List<String> formerNames = [];

  /// 現在不能改名的理由；null 表示可以改。
  ///
  /// **規格沒有規定改名頻率**（〈註冊流程〉只說「可於設定頁事後更新」）。
  /// 30 天是使用者 2026-09-28 的裁決 A —— 理由是管理員的待審佇列
  /// 靠名字認人（`02_Aggregate定義.md`：顯示名稱「供待審佇列與稽核呈現」），
  /// 不限次數的話，被檢舉的人改個名字就換了一張臉。
  String? renameBlockedReason() {
    final at = lastRenamedAt;
    if (at == null) return null;
    final days = businessDate(now).difference(businessDate(at)).inDays;
    if (days >= kRenameCooldownDays) return null;
    return '暱稱每 $kRenameCooldownDays 天只能改一次，'
        '還要等 ${kRenameCooldownDays - days} 天。';
  }

  /// 開發者模式：解除改名冷卻鎖。**只清時間鎖，曾用名不動。**
  ///
  /// 與教官重考鎖同一個理由：30 天是給真實使用者的節流，
  /// 而測試的人一按下去就把自己鎖住一個月，那條路從此驗不了
  /// （重考鎖那次就是這樣，見 `clearExamRetakeLock`）。
  void clearRenameCooldown() {
    lastRenamedAt = null;
    notifyListeners();
  }

  /// 使用者已更新暱稱。回傳失敗的理由；null 表示成功。
  String? rename(String to) {
    final blocked = renameBlockedReason();
    if (blocked != null) return blocked;
    final next = to.trim();
    if (!isValidNickname(next)) {
      return '暱稱要 1–$kNicknameMaxLength 個字。';
    }
    if (next == displayName) return '這就是你現在的暱稱。';

    formerNames.insert(0, displayName);
    displayName = next;
    lastRenamedAt = now;
    // **立刻重寫公開檔案。** 不然別人看到的還是舊名字 ——
    // 而整個暱稱重構的前提就是「顯示名稱一律去查現值」，
    // 現值沒更新的話那一整套白做。
    publishMyProfile();
    notifyListeners();
    return null;
  }
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
  ///
  /// **非示範帳號取今天。** 寫死 180 天前是示範身分的一部分 ——
  /// 與 `posts`／`socialUsers` 那些一樣，只是它是純量，2026-09-16 那次
  /// 假資料清查（`[QA-02a]`–`[QA-02e]`）清的是集合，把它漏掉了。
  late DateTime registeredOn = demo
      ? businessDate(DateTime.now()).subtract(const Duration(days: 180))
      : businessDate(DateTime.now());

  /// 各維最後訓練日。
  ///
  /// **示範身分**刻意錯開，使六個計時器各自落在不同的門檻上：
  /// 胸今天、背 2 天、腿 5 天（退步預告）、肩 12 天、手 26 天、核心 46 天。
  /// 退步後的點數不寫死，由 [runDecayCheck] 於建構時推導 ——
  /// 上面 [points] 的六個值即為「本次中斷前點數」。
  ///
  /// **非示範帳號一律自註冊日起算**，六個都一樣。在此之前這裡沒有
  /// `demo` 開關，於是真實使用者一建出來就帶著 7 筆「能力值已退步」
  /// 的假紀錄（肩累積 14、手 31、核心 37）—— 使用者 2026-09-24 回報。
  ///
  /// `resetToNewAccount()` 會修正它們，但那只在完成註冊流程時跑；
  /// 存檔缺 `decayTimers` 這個鍵時（舊存檔）那份假資料就會留著。
  late final Map<Dim, DimDecay> decayTimers = {
    for (final e in const {
      Dim.chest: 0,
      Dim.back: 2,
      Dim.legs: 5,
      Dim.shoulders: 12,
      Dim.arms: 26,
      Dim.core: 46,
    }.entries)
      e.key: _freshTimer(demo
          ? businessDate(DateTime.now()).subtract(Duration(days: e.value))
          : registeredOn),
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
  int _totalExp = 1700;

  /// 累計經驗值。**寫入這裡會順手偵測升階**（見下方 setter）。
  int get totalExp => _totalExp;

  /// 經驗值一改就比對階級有沒有跨過門檻，跨過就把公開檔案重寫上雲。
  ///
  /// **為什麼掛在這裡，不是掛在每個加經驗值的地方**：全專案有十一處會動
  /// `totalExp`（簽到、結算、成就、師徒任務、新手任務、回歸任務、管理員歸零
  /// ……）。逐一去加「記得同步」的話，漏掉一處就是一個查不出來的陳舊階級，
  /// 而且之後每新增一個經驗值來源都要再記得一次。收斂到 setter 就不會漏。
  ///
  /// 在此之前公開檔案**只在登入那一刻寫一次**（`AuthGate._syncProfile`），
  /// 所以這個 session 內升的階，別人一律要等到我下次登入才看得到。
  set totalExp(int v) {
    final before = rankForExp(_totalExp);
    _totalExp = v;
    if (rankForExp(v) != before) publishMyProfile();
  }

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
        // **一定要檢查回傳值。**
        //
        // applySnapshot 對不上存檔格式版本時「整份忽略並回傳 false」。
        // 不檢查的後果不是「少讀到一點東西」，而是這一串：
        //   ① 使用者拿到一個全新的 AppState；
        //   ② `signUpCompleted` 是欄位預設的 **true**，所以他**看不到註冊流程**；
        //   ③ 所有集合都是空的（接了後端時 `demo` 為 false），
        //      所以他的訓練紀錄、簽到、貼文全部「歸零」；
        //   ④ 300 毫秒後自動存檔把這份空白寫回雲端 —— **真的清掉了**。
        //
        // 那四步沒有任何一步會報錯。使用者只會看到「我的進度不見了，
        // 而且它沒有問我要不要重新註冊」。2026-09-19 由使用者回報。
        //
        // 丟 StoreLoadException 走既有的失敗路徑：停在錯誤畫面、
        // **不呼叫 _finishHydration()**，所以 `_hydrated` 維持 false，
        // saveNow() 會提早返回 —— 雲端那份原始資料一個位元都不會被動到。
        if (!applySnapshot(data)) {
          throw StoreLoadException(
            '存檔格式版本對不上（存檔 v=${data['v']}，本版 v=$kSnapshotVersion）。'
            '這份存檔沒有被套用，也沒有被覆寫。',
          );
        }
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
  /// 最近一次存檔失敗的原因。**開發者模式看得到。**
  ///
  /// 吞掉錯誤是對的 —— 存檔失敗不該中斷使用者正在做的事。但完全不說
  /// 就太過頭了：2026-09-24 我把偏好時段寫成陣列包陣列，Firestore
  /// **整份寫入被拒**，於是那個帳號從那一刻起什麼都存不起來，
  /// 而畫面上唯一的跡象是「填了、刷新還是未填寫」。
  ///
  /// 存的是「為什麼失敗」與「連續失敗幾次」，不是資料本身。
  String? saveError;
  int consecutiveSaveFailures = 0;

  Future<void> saveNow() async {
    final store = _store;
    if (store == null || !_hydrated) return;
    _saveTimer?.cancel();
    try {
      await store.save(toSnapshot());
      saveCount++;
      if (saveError != null) {
        saveError = null;
        consecutiveSaveFailures = 0;
      }
    } catch (e) {
      // 寫不進去不中斷使用者正在做的事，但要留下痕跡。
      consecutiveSaveFailures++;
      saveError = '$e';
      debugPrint('存檔失敗（連續 $consecutiveSaveFailures 次）：$e');
    }
  }

  /// 清除存檔並回到假資料的初始狀態。設定頁的「重設示範資料」用。
  Future<void> clearSaved() async {
    await _store?.clear();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    stopCloudWatch();
    super.dispose();
  }

  /// 是否載入示範資料。
  ///
  /// **判準與 `FitnessApp.auth` 是同一個**：沒接帳號＝沒有後端＝
  /// 這是示範或測試，打開就該看得到內容；接了後端就關掉 ——
  /// 假貼文、假隊伍、假通知混進真資料裡，使用者分不出哪一則是真的，
  /// 而且「別人」根本不存在，點進去是死路。
  ///
  /// 預設 true，所以既有的 1,345 個測試一行都不必改。
  ///
  /// **只管集合，不管純量。** 階級 45、經驗 1700、連續訓練 12 天這些
  /// 寫死的數字由 [resetToNewAccount] 歸零 —— 真使用者走的是
  /// `hydrate()` → 讀不到存檔 → `resetToNewAccount()`，那條路已經處理過了。
  /// 這個開關補的是它**刻意不清**的那一半：「這個世界」（別人的貼文、
  /// 公開隊伍、教官名單）。沒有後端的時候那些該留著，有後端就不該。
  final bool demo;

  AppState({this.demo = true}) {
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

  /// 更新動機類健身目標（選填，可清空）。
  ///
  /// **不重新推薦訓練計畫** —— 動機類不是比對維度，改了它而換掉使用者的
  /// 當前計畫，是拿一個與課表內容無關的欄位去動他正在練的東西。
  void updateMotiveGoal(String? goal) {
    motiveGoal = goal;
    notifyListeners();
  }

  /// 快轉到教官初審門檻（**開發者模式專用**）。
  ///
  /// 使用者要測 T1／T3（師徒關係），而兩者都要求其中一方是教官 ——
  /// 教官初審門檻是階級 ≥20 且累積訓練次數 ≥50，測試帳號到不了。
  ///
  /// **只動階級與累積訓練次數兩個數字，不碰教官身分本身。**
  /// 使用者的疑慮是「後續恢復非教官時會出 Bug」——
  /// 這個做法沒有那個狀態要恢復：教官身分仍然要走完整的
  /// 申請 → 初審 → 測驗 → 人工審核，這裡只是讓他**按得下申請鍵**。
  ///
  /// 階級是由 [totalExp] 推導的（`rankForExp`），不是獨立欄位 ——
  /// 所以推的是經驗值，推到門檻階級的下限即可。
  ///
  /// 快轉前的兩個數字。**存在這裡而不是畫面上** ——
  /// 還原鍵要撐得過換頁，而設定頁是 StatelessWidget。
  (int exp, int workouts)? _beforeFastForward;

  bool get canUndoInstructorFastForward => _beforeFastForward != null;

  void fastForwardToInstructorGate() {
    final gate = instructorGate;
    // 連按兩次不該把「原本的數字」覆蓋成已經快轉過的那一組。
    _beforeFastForward ??= (totalExp, totalWorkouts);
    totalExp = math.max(totalExp, expThresholdForRank(gate.requiredRank));
    totalWorkouts = math.max(totalWorkouts, gate.requiredWorkouts);
    notifyListeners();
  }

  /// 還原成快轉前的兩個數字。沒快轉過就什麼都不做。
  void undoInstructorFastForward() {
    final before = _beforeFastForward;
    if (before == null) return;
    totalExp = before.$1;
    totalWorkouts = before.$2;
    _beforeFastForward = null;
    notifyListeners();
  }

  /// 把累積訓練次數與累積訓練天數校正成訓練歷史算得出來的值。
  ///
  /// **這會讓數字變小，而規格明訂「累積訓練次數為單調遞增，任何情況下
  /// 不減少」**（〈訓練結算流程〉）。所以它不是自動的，也不對一般使用者
  /// 開放 —— 只在開發者模式裡，按下去之前要確認。
  ///
  /// ### 為什麼需要它
  ///
  /// 使用者的帳號上，累積訓練次數比訓練歷史多 12 筆。那 12 筆有兩個來源，
  /// **而它們無法事後區分**：
  ///
  /// 1. 舊行為下「按開始、放著、按結束」的空場次 —— 次數 +1 但不寫歷史。
  ///    依 2026-09-26 的裁決，那些本來就不該算（見 0t）。
  /// 2. 0n–0p 那條寫入缺陷吃掉的真實場次 —— 那是真的練過。
  ///
  /// 校正會把第 2 類也一起抹掉。**這是取捨，不是修好** ——
  /// 換到的是「兩個數字從此相符」，付出的是「真實練過的場次不再被計入」。
  ///
  /// ### 為什麼不自動做
  ///
  /// 對一般使用者而言，歷史遺失（雲端寫入失敗）不該連帶沒收他的教官進度。
  /// 那個單調遞增的不變條件存在的理由正是這個。
  ///
  /// 回傳被扣掉的次數。
  int reconcileWorkoutCount() {
    final removed = totalWorkouts - history.length;
    if (removed <= 0) return 0;
    totalWorkouts = history.length;
    // 累積訓練天數同樣由歷史算得出來，且被同一個原因撐高。
    totalWorkoutDays = {
      for (final h in history) businessDate(h.date),
    }.length;
    notifyListeners();
    return removed;
  }

  /// 補填生日。**只在原本沒有時可用，填了就鎖住。**
  ///
  /// 〈設定頁 Read Model〉明訂生日唯讀，理由是它決定年齡係數，
  /// 「可任意改動將使既有點數失去計算基準⋯⋯如需更正，屬客服範疇」。
  ///
  /// 但規格沒設想到一種狀況：2026-09-26 之前註冊問卷問了生日卻沒有任何
  /// 地方存它（見 [birthday]），那些帳號的生日是空的 —— 唯讀意味著
  /// **永遠填不進去**。
  ///
  /// **「補一個從來沒有的值」與「改一個已有的值」不是同一件事**
  /// （2026-09-26 使用者裁決 B）：前者不會讓任何既有點數失去基準，
  /// 因為在它之前根本沒有基準。後者仍然鎖著。
  ///
  /// 回傳錯誤訊息，成功回空值。
  String? fillBirthday(DateTime date) {
    if (birthday != null) {
      return '生日已填寫，不可修改。如需更正請聯繫客服。';
    }
    final today = DateTime(now.year, now.month, now.day);
    if (date.isAfter(today)) return '生日不能是未來的日期。';
    var age = today.year - date.year;
    if (today.month < date.month ||
        (today.month == date.month && today.day < date.day)) {
      age--;
    }
    // 與註冊流程同一道年齡門檻，不另立一套。
    if (age < kMinAge) return '須滿 $kMinAge 歲才能使用本服務。';
    if (age > 120) return '請確認生日是否正確。';
    birthday = DateTime(date.year, date.month, date.day);
    notifyListeners();
    return null;
  }

  /// 使用者已填入身高。
  ///
  /// 身高不像體重會週週變動，所以沒有週期詢問 —— 但設定頁那一列本來
  /// **點下去什麼都不會發生**（右邊還畫著可點的箭頭）。
  /// 填錯一次就沒有任何地方改得回來。
  void updateHeight(double cm) {
    heightCm = cm;
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
    String? equipmentTier,
  }) {
    if (daysPerWeek != null) this.daysPerWeek = daysPerWeek;
    if (duration != null) this.duration = duration;
    if (commonGoal != null) this.commonGoal = commonGoal;
    if (experience != null) this.experience = experience;
    // 器材是推薦的第一順位比對維度（硬約束），改了不重新推薦的話，
    // 使用者會拿著一份他的器材做不到的當前計畫。
    if (equipmentTier != null) this.equipmentTier = equipmentTier;
    surveyUpdatedAt = now;
    // 任一欄位更新即重新推薦並自動替換當前計畫。推薦為單向指派，無拒絕分支。
    currentPlan = recommendCurrentPlan() ?? currentPlan;
    notifyListeners();
  }

  /// 使用者當前的訓練計畫。註冊問卷四欄位更新時由系統自動替換。
  /// 為空值時，首頁退回「解得開的第一份官方課表」。
  WorkoutPlan? currentPlan;

  /// 推薦的取材範圍：解得開的官方計畫。
  ///
  /// 只從解得開的計畫裡挑 —— 自動替換成一份使用者按不下去的計畫，
  /// 等於把他的當前計畫拿走。
  List<WorkoutPlan> get _recommendablePlans => platformPlans
      .where((p) => p.source == PlanSource.official && planUnlocked(p))
      .toList();

  /// 依現在的器材、經驗、目標與時長，把解得開的官方計畫由適合到不適合排序。
  ///
  /// **2026-09-28 加入**（使用者裁決）。在此之前畫面上只看得到
  /// **一份**推薦 —— 使用者實測的原話是「每次只會看到一個推薦訓練，
  /// 只能練到胸」。推薦本身是單向指派沒有錯，錯在**沒有別的東西可看**。
  ///
  /// 所以單向指派那條規則不動（[recommendCurrentPlan] 仍只回一份，
  /// 且仍是這份排序的第一名），另外開一條「還有哪些也適合」給畫面用。
  List<RankedPlan<WorkoutPlan>> rankedPlans() => recommendPlans<WorkoutPlan>(
        _recommendablePlans,
        equipment: equipmentTier,
        experience: experience,
        commonGoal: commonGoal,
        duration: duration,
        tierOf: (p) => p.equipmentTier,
        experienceOf: (p) => p.suitableExperience,
        goalsOf: (p) => p.suitableGoals,
        durationOf: (p) {
          final d = estimatedDurationOf(p);
          return d == null ? null : planDurationBucket(d, kDurations);
        },
      );

  /// 推薦給使用者看的前幾份。
  ///
  /// **只收「器材做得到」的** —— 排序不篩掉器材不符的（使用者可能正要
  /// 去健身房），但推薦清單要篩：推一份他今天做不到的課表沒有意義。
  List<RankedPlan<WorkoutPlan>> recommendedPlans({int count = 5}) =>
      rankedPlans()
          .where((r) => r.match.equipmentOk)
          .take(count)
          .toList();

  /// 依現在的器材、經驗與目標重新推薦一份官方計畫。
  WorkoutPlan? recommendCurrentPlan() {
    final ranked = rankedPlans();
    return ranked.isEmpty ? null : ranked.first.plan;
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
    if (!t.members.any((m) => sameUser(m.name, m.uid, displayName, myUid))) {
      return;
    }
    // 重新分隊期內兩個團隊分數皆不累加；限制的是隊，不是練。
    if (inRegroupWindow(now)) return;
    // 中途加入者僅能貢獻加入後產生的分數 —— 由「當下累加」自然成立，
    // 加入前的個人分數本就沒有經過這裡。
    // **以 uid 為鍵。** 只用暱稱的話，我改名之後貢獻分數會從 0 重算，
    // 而舊的那一筆變成沒有主人的孤兒。
    final me = personKeyOf(displayName, myUid);
    t.contributions[me] = (t.contributions[me] ?? 0) + n;
    // 送上雲。**累加不是覆寫** —— 見 `TeamSource.addScore`。
    _pushTeam((src, uid) => src.addScore(t.id, uid, n));
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
    // 進度的計數範圍限當日，隨重置清空；全部完成的兩個加碼旗標同樣歸零
    // —— 分數那個在完成當下給，金幣那個在全部領取之後給。
    _allTasksBonusGiven = false;
    _allTasksCoinGiven = false;
    notifyListeners();
    return true;
  }

  /// 全部完成的加碼**金幣**是否已發。
  ///
  /// 與上面的 [_allTasksBonusGiven] 不是同一件事 —— 那個管的是**排行榜
  /// 分數**的加碼，在任務「完成」當下就給；這個管金幣，在三項都**領取**
  /// 之後才給（獎勵須由使用者主動點擊領取，見〈每日任務流程〉）。
  ///
  /// **在此之前那 4 枚金幣只掛在「領取全部」那顆按鈕上**，一項一項點的人
  /// 永遠拿不到，一天只有 6 金幣而不是規格寫的 10
  /// （〈02_Aggregate定義〉每日任務 300／月 ＝ 10／日）。
  bool _allTasksCoinGiven = false;

  /// 三項都領完就給加碼金幣。兩個領取路徑共用這一支，不再各寫一份。
  void _giveAllTasksCoinIfDue() {
    if (_allTasksCoinGiven) return;
    if (!dailyTasks.every((t) => t.claimed)) return;
    _allTasksCoinGiven = true;
    coins += kDailyTaskAllDoneCoin;
  }

  void claimTask(DailyTask t) {
    if (!t.done || t.claimed) return;
    t.claimed = true;
    coins += kDailyTaskCoin;
    _giveAllTasksCoinIfDue();
    notifyListeners();
  }

  void claimAllTasks() {
    for (final t in dailyTasks) {
      if (t.done && !t.claimed) {
        t.claimed = true;
        coins += kDailyTaskCoin;
      }
    }
    _giveAllTasksCoinIfDue();
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

  /// 把互動的終身累計歸零（**開發者模式專用**）。
  ///
  /// 2026-09-28 使用者的帳號上有一組假的互動計數
  /// （`{按讚:145, 留言:41, …}`，來自示範種子漏進真帳號，見 1F）。
  /// 根因修好了，但**那個數字早就被存進雲端**，而它
  /// **沒辦法從證據修補** —— 天數可以從訓練歷史重算，
  /// 「按過幾個讚」沒有一份完整的紀錄可查。
  ///
  /// 所以給一顆自救的按鈕。**已解鎖的成就不動** ——
  /// 規格：一經解鎖不可撤銷（`persistence_test` 也釘著這一條）。
  /// 計數歸零之後會出現「已解鎖但當前值對不上」，那是合法狀態。
  void resetInteractionTotals() {
    interactionTotals.clear();
    notifyListeners();
  }

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

  /// 預估訓練時長（見 `domain/plan_duration.dart`）。
  /// 休息秒數由 [restSecondsFor] 供給 —— 那三層取值優先序只有一份。
  Duration? estimatedDurationOf(WorkoutPlan plan) =>
      estimatePlanDuration(plan, restSecondsOf: restSecondsFor);

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

    // --- 這一場算不算「一次訓練」---
    //
    // **一組都沒完成的訓練不在任何地方留下紀錄**（2026-09-26 使用者裁決）。
    // 按下開始、放著、按結束，不是一次訓練。
    //
    // 這個旗標是**唯一**的判準，下面每一處都讀它 —— 累積訓練次數、
    // 累積訓練天數、連續訓練天數、訓練歷史、AI 自動優化計數。
    // 在此之前它們各自寫一份條件，結果是「累積訓練次數 +1 但訓練歷史
    // 沒有那一筆」：使用者回報「教官申請的累計訓練次數跟訓練清單的不一樣」，
    // 而那個落差**每開關一次就再拉開一格**。
    //
    // **與 [rewardable] 分開**（見下方獎勵那一段）：不到 5 分鐘但做了組的
    // 訓練**算**一次訓練，只是不發獎勵 —— 他確實練了。
    //
    // ### 與規格的關係
    //
    // 〈訓練結算流程〉寫「累積訓練次數 +1；三種終止狀態皆計入」。
    // 這裡的判準不是終止狀態而是「有沒有完成任何一組」，兩者正交：
    // 三種終止狀態在有完成組的前提下**仍然全部計入**。
    //
    // 「不變條件：單調遞增，任何情況下不減少」**沒有被違反** ——
    // 不增加不等於減少。
    //
    // 規格自己也有這條原則：〈AI 自動優化訓練流程〉「已完成組數為 0 的
    // 訓練不計入 —— 一組都沒完成者不構成歷史訓練資料」，理由是
    // 「其無任何實績資料可供分析，且開場即關閉可用來強迫 AI 重新優化課表，
    // 為一條刷新路徑」。同一條刷新路徑對教官初審門檻（累積訓練次數 ≥50）
    // 一樣成立 —— 開關五十次就過門檻。
    final recorded = s.doneSets > 0;

    // --- 連續訓練天數 ---
    // 次數每場都加；天數與連續天數只在該日第一場加。
    //
    // **「今天算過了沒」要問訓練歷史，不能問 [lastTrainedDate]。**
    //
    // `resetToNewAccount()` 把 `lastTrainedDate` 設成 `registeredOn`
    // ＝今天（那個初始值本身是對的，它是給退步門檻用的：「從未訓練者的
    // 四道門檻自註冊日的日界起算」）。但這裡拿它來問「今天是不是第一場」
    // 的話，**註冊當天練的每一場都會被當成不是第一場** ——
    // 天數與連續天數一整天都不動。
    //
    // 2026-09-28 使用者實測：累積訓練次數 3、累積訓練天數 0。
    //
    // 同一個欄位兩種語意，日後必然衝突 —— `Exercise.dim` / `parts`
    // 的註解早就寫過這句話。這裡改用歷史當判準，與
    // `reconcileWorkoutCount()` 的算法同源（那支也是用 history 重算天數）。
    //
    // **這一段跑在 `history.insert` 之前**，所以此刻的歷史還不含這一場。
    if (recorded) {
      totalWorkouts += 1;
      final firstToday =
          !history.any((h) => businessDate(h.date) == today);
      if (firstToday) {
        // 距上次訓練日的日界未超過 36 小時者續計 —— 與 [runStreakCheck]
        // 的中斷判定共用同一條規則，兩邊各寫一份就會對不起來。
        trainingStreakDays =
            streakContinues(lastTrainedDate, now) ? trainingStreakDays + 1 : 1;
        // 訓練恢復 —— 預告階段歸零，下一次中斷才會重新發。
        _trainNoticeStage = DecayStage.normal;
        lastTrainedDate = today;
        totalWorkoutDays += 1;
      }
    }

    // --- 獎勵 ---
    //
    // **一組都沒完成、或不到 5 分鐘的訓練一律不發獎勵**（使用者裁決
    // 2026-09-26）。按下開始、放著、按結束，不該換到經驗值與金幣 ——
    // 那是「打開 App」的獎勵，不是訓練的獎勵。
    //
    // 判準取「**完成的組數**」與「**實際時長**」兩者，缺一不可：
    //   · 只看組數：做一組再結束也能領，而那組可能是隨手勾的
    //   · 只看時長：開著不動十分鐘也能領
    //
    // 排行榜分數、每日任務的「完成訓練」計數一併不給 —— 那些同樣是
    // 獎勵。訓練紀錄本來就有「一組都沒完成不寫入」的判斷，不重複。
    final duration = now.difference(s.startedAt);
    final tooShort = duration < kMinRewardedWorkout;
    // 發獎勵比「算一次訓練」更嚴：還要滿 5 分鐘。
    final rewardable = recorded && !tooShort;

    _rollRewardCounters(today);
    final rewards = rewardable
        ? computeSettlement(
            kind: kind,
            source: s.plan.source,
            doneSets: s.doneSets,
            plannedSets: s.plannedSets,
            streakDays: trainingStreakDays,
            expAlreadyGrantedToday: _expGrantedOn == today,
            coinsGrantedToday: _coinsGrantedToday,
            scoreGrantedToday: _scoreGrantedToday,
          )
        : const SettlementRewards.none();
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

    // 每日任務的「完成訓練」同樣不給 —— 見上方獎勵那一段的理由。
    if (rewardable) _bumpTasks('使用者已完成訓練', 1);
    final newly = _syncAchievements();

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
    // 一組都沒完成的訓練不構成歷史訓練資料，故不計（讀同一個旗標）。
    _bumpAutoOptimize(anySetDone: recorded);

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
    // `logged.isNotEmpty` 與 [recorded] 邏輯上等價（有完成的組 ⟺ 有東西可記），
    // 但**寫成同一個條件**，兩者才不會日後各自漂移 ——
    // 「累積訓練次數 +1 卻沒有那一筆歷史」正是它們曾經漂開的後果。
    // 不變條件由 `test/workout_count_invariant_test.dart` 釘住。
    if (recorded) {
      assert(logged.isNotEmpty, '有完成的組，就一定有東西可以寫進歷史');
      history.insert(
        0,
        HistoryEntry(
          now,
          s.plan.name,
          s.volume,
          math.max(1, duration.inMinutes),
          result.calories,
          logged,
          // 課表卡片的「上次完成度」要讀得到它。空白課表沒有計畫組數。
          completion: result.plannedSets == 0
              ? null
              : result.doneSets / result.plannedSets,
        ),
      );
      // **訓練紀錄變了，品質評分就過期了。** 設成空值，下次有人讀
      // 就重算 —— 不當場算，因為結算這條路上沒有人要看那個分數。
      quality = null;
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
  // 排行榜（名次視窗為自己上下各 10 名）
  // -------------------------------------------------------------------------

  /// 名次視窗。**接了後端就是空的** —— 真正的排行榜要等 `[BE-07]`。
  ///
  /// 這底下整段是捏造的：對手名字從一份固定名單挑、分數由我的分數加減
  /// 一個隨機差值、連我自己的名次都是 `11 + 隨機`。示範時那是對的
  /// （沒有別人，就演不出「名次視窗」這個概念）；接了後端就不是了 ——
  /// 使用者會照著一個不存在的名次判斷自己離獎勵有多遠，
  /// 而 [settleBoard] 還會照那個名次真的發金幣出去。
  ///
  /// 空清單的意思是「這個榜還沒有資料」，畫面據此顯示尚未開放，
  /// 而 [myPlace] 回傳空值讓結算整個跳過。
  /// 雲端讀回來的排行榜視窗。**空值代表還沒讀到**，不是「我是第 1 名」。
  final Map<bool, LeaderboardPage> _cloudBoards = {};
  final Set<bool> _boardsFetched = {};
  final Set<bool> _boardsInFlight = {};

  /// 去雲端讀一次排行榜（使用者裁決 B，2026-09-28）。
  ///
  /// 呼叫端不必 await：讀回來會 [notifyListeners]，畫面自己重畫 ——
  /// 與 [ensureFollowerCount] 同一套。
  ///
  /// **一個榜只讀一次**，除非 [force]。畫面每次重建都讀的話，
  /// 捲一下排行榜就是好幾十次查詢。
  Future<void> ensureLeaderboard({required bool weekly, bool force = false}) async {
    final src = profileSource;
    if (demo || src == null || myUid == null) return;
    if (!force && _boardsFetched.contains(weekly)) return;
    if (!_boardsInFlight.add(weekly)) return;
    try {
      final page = await src.leaderboard(
        weekly: weekly,
        group: rankGroupNow(weekly: weekly),
        // **我手上這份，不是雲端那份。** 公開檔案是即發即忘寫上去的，
        // 雲端可能比我剛剛練完的分數舊。
        myScore: weekly ? weeklyScore : monthlyScore,
      );
      if (page != null) {
        _cloudBoards[weekly] = page;
        _boardsFetched.add(weekly);
        notifyListeners();
      }
    } catch (_) {
      // 讀不到就維持「還沒讀到」——畫面會說「排行榜還在讀取」而不是
      // 宣稱一個名次。
    } finally {
      _boardsInFlight.remove(weekly);
    }
  }

  /// 排行榜讀到了沒有。**「讀到了但只有我一個」與「還沒讀到」是兩件事** ——
  /// 畫面那兩種空狀態要講不一樣的話。
  bool get leaderboardReady =>
      demo || _boardsFetched.isNotEmpty || profileSource == null;

  List<LeaderboardEntry> leaderboardWindow({required bool weekly}) {
    if (!demo) return _cloudWindow(weekly: weekly);
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

  /// 把雲端讀回來的那一頁排成畫面要的樣子。
  ///
  /// **名次以我那一列為錨點。** 我的名次是「同組裡分數比我高的人數 ＋ 1」，
  /// 那正是「同分並列、並列後順延跳號」的定義；其餘各列由視窗內的相對
  /// 名次平移過去。視窗最上面那一列若剛好切在同分群中間，它上面幾列的
  /// 名次會偏低 —— 要完全正確得為每一列各跑一次聚合查詢，不值得。
  List<LeaderboardEntry> _cloudWindow({required bool weekly}) {
    final page = _cloudBoards[weekly];
    if (page == null) return const [];
    final myScore = weekly ? weeklyScore : monthlyScore;

    // **自己那一列用本機的分數重新插進去**，不用雲端那一份 ——
    // 剛練完還沒同步上去的話，畫面會顯示一個比我實際少的數字。
    final rows = <({int score, String name, bool self})>[
      for (final p in page.rows)
        if (p.uid != myUid)
          (
            score: weekly ? p.weeklyScore : p.monthlyScore,
            name: p.displayName,
            self: false
          ),
      (score: myScore, name: displayName, self: true),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final rel = placesOf([for (final r in rows) r.score]);
    final offset = page.place - rel[rows.indexWhere((r) => r.self)];
    return [
      for (var i = 0; i < rows.length; i++)
        LeaderboardEntry(rel[i] + offset, rows[i].name, rows[i].score,
            isSelf: rows[i].self),
    ];
  }

  // -------------------------------------------------------------------------
  // 排行榜週期結算
  // -------------------------------------------------------------------------

  /// 排行榜歷史紀錄 Aggregate。一經寫入不可修改 —— 沒有它，
  /// 「我第 3 名卻沒拿到獎勵」就無從查證，排行獎勵成為不可稽核的發放。
  final List<LeaderboardHistory> leaderboardHistory = [];

  /// 我在個人榜上的名次。沿用畫面那份名次視窗，兩者不會對不起來。
  ///
  /// **空值代表這個榜還沒有資料**（見 [leaderboardWindow]）。
  /// 回傳 0 或 1 都是在宣稱一個名次，而那正是要避免的事。
  int? myPlace({required bool weekly}) {
    final rows = leaderboardWindow(weekly: weekly);
    for (final e in rows) {
      if (e.isSelf) return e.position;
    }
    return null;
  }

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
        final mine = myPlace(weekly: weekly);
        // 沒有名次就沒有結算 —— 沒有排行榜資料的時候硬給一個名次，
        // 等於照著捏造的排名把獎勵金幣發出去。
        if (mine == null) return null;
        group = rankGroupLabel(rankGroupNow(weekly: weekly));
        subject = displayName;
        place = mine;
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

  late List<Post> posts = demo ? buildPosts() : [];

  /// 關注關係。單向，唯一鍵為 關注者 ID ＋ 被關注者 ID ——
  /// 用集合表達，重複關注不會產生第二筆。
  ///
  /// **裡面裝的是 [personKeyOf] 算出來的鍵，不是暱稱**（暱稱重構階段三）。
  /// 認得出 uid 的人以 uid 為鍵：暱稱會改、會撞名，而這份名單要跨改名活著。
  /// 判斷請用 [isFollowing]，要顯示名字請用 [followName]。
  ///
  /// **跟著 [demo] 走。** 在此之前它是無條件帶三個假名字的 `final`，
  /// 真帳號靠 `resetToNewAccount()` 記得清掉才不會看到它們。
  late Set<String> following =
      demo ? {for (final n in _demoFollowing) _nameKey(n)} : {};

  static const _demoFollowing = ['深蹲王', 'CoreMax', '早鳥訓練'];

  /// 社群裡的人。關注／粉絲清單要呈現階級與綜合能力等級。
  late List<SocialUser> socialUsers = demo ? buildSocialUsers() : [];

  SocialUser userOf(String name) => socialUsers.firstWhere(
        (u) => u.name == name,
        orElse: () => SocialUser(name: name, rank: 1, grade: 'E'),
      );

  /// 我的粉絲。粉絲數為使用者 Aggregate 的**儲存欄位**，非即時彙總 ——
  /// 不變條件：粉絲數 ＝ 關注關係中被關注者為本人的筆數。
  ///
  /// 同 [following]，裝的是鍵不是暱稱。順序有意義（新的在前）。
  late List<String> followers =
      demo ? [for (final n in buildFollowers()) _nameKey(n)] : [];
  int get followerCount => followers.length;

  /// 歷史最高粉絲數。粉絲成就依它判定 ——
  /// 粉絲數下降不撤銷任何已解鎖的粉絲成就。
  late int peakFollowerCount = followers.length;

  int get followerMilestones => followerMilestonesReached(peakFollowerCount);

  /// 他人的粉絲數。我關注／取消關注時 +1 / −1。
  ///
  /// **以 [personKeyOf] 的鍵為鍵**，與 [following] 同一套 —— 原本以暱稱為鍵，
  /// 兩個同名的人會共用一個數字，而改名的人會從此對不上自己的舊計數。
  late Map<String, int> otherFollowerCounts = {
    for (final u in socialUsers) personKeyOf(u.name, u.uid): 40 + u.rank * 3,
  };

  /// 關注／粉絲名單上，某個鍵在建立當下看到的暱稱。
  ///
  /// **只是墊底值。** 顯示一律先問 [nameByUid] 拿現值，查不到才用這裡的 ——
  /// 對方還沒發布公開檔案時，名單上至少寫得出一個名字而不是一串 uid。
  /// 同 `apprenticeName`／`mentorName` 那一套（見 [applyCloudBonds]）。
  final Map<String, String> _followNames = {};

  // --- 公開檔案（[BE-11] 批次 1）---

  /// 雲端的公開檔案。**空值代表不同步** —— 既有測試走這條。
  ///
  /// 在此之前這個來源只有 `AuthGate` 自己握著，所以「把我的公開檔案寫上去」
  /// 這件事只在登入那一刻發生得了。升階要即時同步就得讓狀態層也拿得到。
  PublicProfileSource? profileSource;

  /// uid → 暱稱。跨使用者資料在雲端以 uid 為鍵，畫面上要顯示的是暱稱，
  /// 這張表就是兩者之間的翻譯。批次 2 起的關注／貼文都靠它把
  /// 雲端的 uid 還原成畫面認得的暱稱。
  final Map<String, String> nameByUid = {};

  /// 暱稱 → uid。[nameByUid] 的反查。
  ///
  /// **這是退路，不是主路。** 暱稱可以改而 uid 不會，所以拿得到 uid 的
  /// 呼叫端一律直接給 uid（[rankOf] 等幾支都收 `uid:` 具名參數）。
  /// 只有畫面上真的只剩暱稱時才走這裡 —— 對方改過暱稱就查不到了，
  /// 那時候退回示範資料的預設值，不會顯示成 1 階。
  final Map<String, String> _uidByName = {};

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
        // **帶徒人數與名額要公開，「名額已滿」才擋得住。** 少了它們，
        // 別人的拜師頁只能假設我還有空位 —— 他申請下去才發現滿了。
        apprentices: apprentices.length,
        apprenticeCap: apprenticeCap,
        avgRating: myRatingStats.avg,
        ratingCount: myRatingStats.count,
        specialties: instructorSpecialties.toList(),
        // 排行榜要跟別人比，就得讓別人讀得到我的分數（使用者裁決 B）。
        weeklyScore: weeklyScore,
        monthlyScore: monthlyScore,
        weeklyGroup: rankGroupNow(weekly: true),
        monthlyGroup: rankGroupNow(weekly: false),
      );

  /// 把我自己的公開檔案重寫上雲。
  ///
  /// **即發即忘、吞掉錯誤**：與關注、貼文同一套 —— 同步失敗不該擋住
  /// 使用者手上正在做的事，下次升階或下次登入會再寫一次。
  void publishMyProfile() {
    final src = profileSource;
    final uid = myUid;
    if (src == null || uid == null) return;
    src.publish(myPublicProfile(uid)).catchError((_) {});
  }

  /// 把雲端讀到的其他使用者併進來（[BE-11] 批次 1）。
  ///
  /// **是併入而不是取代。** 現階段動態牆上的貼文、對話、教官清單仍指向
  /// 示範用的那幾位；直接換掉會讓那些畫面指到不存在的人。
  void applyPublicProfiles(List<PublicProfile> others) {
    for (final p in others) {
      nameByUid[p.uid] = p.displayName;
      _uidByName[p.displayName] = p.uid;
      // **整份留著**。只取 rank 與 grade 的話，六維明細就在這裡被丟掉了，
      // 而檔案頁上的雷達圖需要它 —— 拿不到就只能顯示我自己的，那是錯的。
      publicProfiles[p.uid] = p;
      // **粉絲數以雲端為準，而且要在下面那個 add 之前寫。**
      // 原本寫在後面用 `putIfAbsent`，但 `socialUsers.add()` 會先觸發
      // `otherFollowerCounts` 這個 late 欄位初始化，那份初始值是用
      // 示範公式 `40 + rank * 3` 算的 —— 等輪到 putIfAbsent 時鍵已經在了，
      // 雲端讀回來的真實數字就這樣被一個假數字蓋掉。
      otherFollowerCounts[p.uid] = p.followers;

      // **把暱稱鍵升級成 uid 鍵。** 我在對方發布公開檔案之前就關注了他
      // （示範資料的人一直都是這樣），那一筆當時只能以暱稱為鍵；
      // 不升級的話他會在名單上變成兩個人 —— 一個舊的按不動、一個新的。
      _upgradeFollowKey(_nameKey(p.displayName), p.uid);

      // 對方關閉了綜合等級的對外可見時，畫面顯示最低階 ——
      // 不猜、也不留空白造成版面破洞。
      final u = SocialUser(
        name: p.displayName,
        uid: p.uid,
        rank: p.rank,
        grade: p.grade ?? 'E',
      );
      // **已經在清單裡的人要更新，不是跳過。**
      //
      // 原本這裡是 `if (socialUsers.any(...)) continue;` —— 只有「第一次
      // 見到這個人」才寫入，之後每次登入從雲端讀回來的新階級全被丟掉。
      // 於是「找人」與關注／粉絲清單顯示的是**我第一次見到他時**的階級，
      // 比貼文上那個凍結值還舊。
      final i = socialUsers.indexWhere((x) => x.name == p.displayName);
      if (i >= 0) {
        socialUsers[i] = u;
      } else {
        socialUsers.add(u);
      }

      _applyInstructor(p);
    }
    notifyListeners();
  }

  /// 把雲端的教官併進 [instructors]。
  ///
  /// **在此之前這份清單對真實帳號永遠是空的**（`demo ? buildInstructors() : []`），
  /// 而拜師頁就是跑這份清單 —— 於是真實使用者打開拜師頁看到一片空白，
  /// **連要拜誰為師都看不到**。師徒功能從入口就是斷的，不只是接受之後不上雲。
  ///
  /// 教官身分被撤銷時要從清單移除，不是留著 —— 留著的話他會一直出現在
  /// 拜師頁上，而申請送出去對方那側會被擋下，使用者只看到一次無聲的失敗。
  void _applyInstructor(PublicProfile p) {
    final at = instructors.indexWhere((i) => i.name == p.displayName);
    if (!p.isInstructor) {
      if (at >= 0) instructors.removeAt(at);
      return;
    }

    final i = Instructor(
      name: p.displayName,
      uid: p.uid,
      rank: p.rank,
      reputation: p.reputation ?? 0,
      apprentices: p.apprentices,
      apprenticeCap: p.apprenticeCap,
      // 教官身分讓兩個可見度開關失效，所以六維一定拿得到；
      // 真的沒有就給空集合，讓畫面把「沒有資料」畫成沒有資料。
      ability: p.ability ?? const {},
      specialties: p.specialties,
      // 星等由教官自己統計自己那些師徒任務上的評分後發布（`[BE-15]`）——
      // 別人算不出來，讀不到那些關係底下的任務。
      // **`ratingCount` 為 0 時畫面要顯示「尚無評分」，不是 0.0 顆星。**
      avgRating: p.avgRating,
      ratingCount: p.ratingCount,
    );
    if (at >= 0) {
      instructors[at] = i;
    } else {
      instructors.add(i);
    }
  }

  /// 別人的公開檔案，**依 uid 索引**（[BE-11] 批次 1）。
  ///
  /// **鍵是 uid 不是暱稱。** 暱稱可以改 —— 以暱稱為鍵的話，對方改名之後
  /// 這份快取就再也對不上，階級與六維一起掉回預設值。
  ///
  /// **只有雲端同步過的人在裡面。** 示範用的那幾位不在 —— 對他們
  /// [abilityOf] 會回空值，而畫面必須把「沒有資料」畫成沒有資料。
  final Map<String, PublicProfile> publicProfiles = {};

  /// 正在路上的 uid。避免同一個人被重複查 —— 動態牆一頁二十篇貼文
  /// 可能全是同一位作者，不擋的話就是二十次相同的查詢。
  final Set<String> _profilesInFlight = {};

  /// 補齊這些 uid 的公開檔案。**已經有的、正在查的都不會再查一次。**
  ///
  /// 登入時的 [PublicProfileSource.others] 只撈得到最近活躍的前 200 位，
  /// 而畫面上會出現的人不一定在那 200 位裡 —— 久未上線的作者、剛加入的
  /// 隊友、三年前那篇貼文的主人都是。在這一支之前，他們的階級與六維
  /// 一律取預設值（階級顯示 1），而且**人越多越常發生**。
  ///
  /// 呼叫端不必 await：查回來會 [notifyListeners]，畫面自己重畫。
  Future<void> ensureProfiles(Iterable<String> uids) async {
    final src = profileSource;
    if (src == null) return;

    final want = {
      for (final u in uids)
        if (u.isNotEmpty &&
            u != myUid &&
            !publicProfiles.containsKey(u) &&
            !_profilesInFlight.contains(u))
          u,
    };
    if (want.isEmpty) return;

    _profilesInFlight.addAll(want);
    try {
      applyPublicProfiles(await src.byUids(want.toList()));
    } catch (_) {
      // 查不到就維持現狀 —— 一次網路失敗不該把畫面上的階級洗成預設值。
    } finally {
      // **查無此人也要移出 in-flight**，否則那個 uid 會被永遠鎖住；
      // 但下次呼叫又會再查一次，這是刻意的：對方可能是稍後才註冊的。
      _profilesInFlight.removeAll(want);
    }
  }

  /// 這個暱稱對應到的公開檔案。拿得到 uid 請直接給 [uid]。
  PublicProfile? _profile(String name, String? uid) {
    final key = uid ?? _uidByName[name];
    return key == null ? null : publicProfiles[key];
  }

  /// 這是不是我自己。有 uid 就以 uid 為準 —— 暱稱可能跟別人撞名。
  bool _isMe(String name, String? uid) =>
      uid != null && myUid != null ? uid == myUid : _mineByName(name);

  // --- 關注名單的鍵（暱稱重構階段三）---

  /// 沒有 uid 的人長什麼樣。定義在 `domain/social.dart`，
  /// 因為不認得 `AppState` 的地方（例如 [TimedTaskTally]）也要用同一份。
  static const _namePrefix = 'name:';

  static String _nameKey(String name) => personKey(name, null);

  static bool _isNameKey(String key) => isNamePersonKey(key);

  /// 這一則師徒問答是不是我自己問的（我在學徒那一側）。
  ///
  /// **看 [MentorQuestion.apprenticeUid] 是不是空的，不比暱稱。**
  /// 雲端的問答掛在特定師徒關係下、帶著提問學徒的 uid；我自己問的那些
  /// 沒有這個欄位（見該欄位的說明）。在此之前這裡比的是
  /// `q.from == displayName` —— 我改個名字，自己問過的問題就全部不見了。
  bool isMyQuestion(MentorQuestion q) => q.apprenticeUid == null;

  /// 兩筆資料指的是不是同一個人。
  ///
  /// **兩邊都有 uid 就只比 uid。** 有一邊沒有（示範資料、還沒發布公開
  /// 檔案的人）就只剩暱稱可比 —— 那是退路，會在撞名與改名時答錯。
  static bool sameUser(String nameA, String? uidA, String nameB, String? uidB) =>
      (uidA != null && uidB != null) ? uidA == uidB : nameA == nameB;

  /// 這個人在關注名單上的鍵。**有 uid 就用 uid。**
  ///
  /// 呼叫端拿不到 uid 時會再走一次 [_uidByName] 反查 —— 那是退路不是主路
  /// （見 [_uidByName] 的說明），查不到才退成暱稱鍵。
  /// 退成暱稱鍵的人日後發布了公開檔案，[applyPublicProfiles] 會把那一筆
  /// 升級成 uid 鍵，名單不會多出一個分身。
  String personKeyOf(String name, String? uid) =>
      uid ?? _uidByName[name] ?? _nameKey(name);

  /// 關注／粉絲名單上這個鍵該顯示的名字。
  ///
  /// 順序有意義：**現在的暱稱優先**，其次是當初記下來的，都沒有才認賠。
  /// 反過來的話，對方改了名字而我這裡永遠顯示舊的。
  String followName(String key) => _isNameKey(key)
      ? key.substring(_namePrefix.length)
      : nameOf(_followNames[key] ?? '（資料載入中）', uid: key);

  /// 名單上這個鍵背後的 uid。暱稱鍵沒有 uid，回空值。
  String? uidOfFollowKey(String key) => _isNameKey(key) ? null : key;

  /// 讀存檔用：把**階段三之前存下來的暱稱**翻成鍵。
  ///
  /// 翻得出 uid 的就此收斂到 uid，翻不出的留成暱稱鍵 —— 而登入時
  /// [applyFollows] 會以雲端為準把 uid 那一半整份換掉，所以翻錯也只錯一次。
  String followKeyFromLegacyName(String name) => personKeyOf(name, null);

  /// 我有沒有關注這個人。
  ///
  /// **拿得到 uid 就給 uid。** 只給暱稱的話，對方改名之後這裡會答錯 ——
  /// 畫面顯示「關注」，按下去卻在雲端建了第二次同樣的關係。
  bool isFollowing(String name, {String? uid}) =>
      following.contains(personKeyOf(name, uid));

  /// 這個人有沒有關注我。
  bool isFollower(String name, {String? uid}) =>
      followers.contains(personKeyOf(name, uid));

  /// 把一個鍵記上它當下的暱稱，供 [followName] 墊底。
  void _rememberFollowName(String key, String name) {
    if (!_isNameKey(key)) _followNames[key] = name;
  }

  /// 已經去數過的人。避免同一頁重複查 —— 與 [_profilesInFlight] 同理。
  final Set<String> _followerCountsInFlight = {};

  /// 去數一次「這個人現在有幾個粉絲」，數完寫進 [otherFollowerCounts]。
  ///
  /// **`follows` 集合才是真相來源。** 公開檔案上那個 `followers` 只有
  /// 本人寫得了，所以我關注某人不會讓它變動 —— 一重新整理，本機的 +1
  /// 就被那個舊值蓋掉。使用者 2026-09-24 回報「重新追蹤刷新後顯示還是 0」。
  ///
  /// 呼叫端不必 await：數回來會 [notifyListeners]，畫面自己重畫。
  /// 數完之後本機的關注／取消關注照樣疊在上面（見 [_unfollow]）——
  /// 那一刻的樂觀更新比剛數回來的值更新。
  Future<void> ensureFollowerCount(String name, String? uid) async {
    final src = followSource;
    if (src == null || uid == null || uid == myUid) return;
    if (!_followerCountsInFlight.add(uid)) return;
    try {
      otherFollowerCounts[uid] = await src.followerCountOf(uid);
      notifyListeners();
    } catch (_) {
      // 數不到就維持現狀 —— 一次網路失敗不該把畫面上的數字洗掉。
    } finally {
      _followerCountsInFlight.remove(uid);
    }
  }

  /// 某人的粉絲數。看自己請用 [followerCount]。
  ///
  /// **以 [otherFollowerCounts] 為先，不是公開檔案上那個數字。** 兩者都是
  /// 雲端來的（`applyPublicProfiles` 每次載入都會把它寫成雲端值），差別是
  /// 前者還帶著我剛剛按下去的那一次關注／取消關注。反過來取的話，
  /// 我關注了某人、他的粉絲數卻紋風不動 —— 那個 +1 被雲端快照蓋掉了。
  int followersOf(String name, {String? uid}) => _isMe(name, uid)
      ? followerCount
      : (otherFollowerCounts[personKeyOf(name, uid)] ??
          _profile(name, uid)?.followers ??
          0);

  /// 某人在檔案頁上該顯示的六維能力值。
  ///
  /// **回空值代表「我這裡沒有他的六維明細」**，可能是對方關掉了對外可見，
  /// 也可能是他根本不在公開檔案裡。兩種情況都不該拿我自己的點數頂上 ——
  /// 那會讓每個人的檔案頁長得跟我一模一樣。
  Map<Dim, int>? abilityOf(String name, {String? uid}) {
    if (_isMe(name, uid)) return points;
    final cloud = _profile(name, uid)?.ability;
    if (cloud != null) return cloud;
    // 教官身分讓兩個可見度開關失效（〈使用者 Aggregate〉的規定），
    // 所以教官一律看得到六維。示範資料的教官只在這份清單裡。
    return instructors.where((i) => i.name == name).firstOrNull?.ability;
  }

  /// 某人的綜合能力等級。回空值代表對方未公開。
  String? gradeOf(String name, {String? uid}) {
    if (_isMe(name, uid)) return overallGrade(points);
    final a = abilityOf(name, uid: uid);
    if (a != null) return overallGrade(a);
    final p = _profile(name, uid);
    if (p != null) return p.grade;
    // 示範用的使用者沒有六維明細，但帶著綜合等級。
    return socialUsers.any((u) => u.name == name) ? userOf(name).grade : null;
  }

  /// 某人的階級。
  ///
  /// **一律回「他現在的階級」，不是任何時點的快照。** 貼文、私訊、團隊
  /// 名冊、收件匣在雲端都各自存了一份發生當下的階級，那些值只是這裡
  /// 查不到時的墊底（見各呼叫端的 `fallback`）—— 顯示的第一順位永遠是
  /// 公開檔案上的現值。2026-09-23 之前反過來：發文當下寫死進 `posts`
  /// 文件，作者從 11 階練到 40 階，那篇貼文永遠寫著 11 階。
  /// [fallback] 是呼叫端手上那份快照（貼文、對話、名冊上存的那個值）。
  /// **只在這裡完全查不到這個人時才用得到** —— 顯示一個他真的曾經有過的
  /// 階級，比顯示 1 階好。
  int rankOf(String name, {String? uid, int? fallback}) {
    if (_isMe(name, uid)) return rank;
    final cloud = _profile(name, uid)?.rank;
    if (cloud != null) return cloud;
    final ins = instructors.where((i) => i.name == name).firstOrNull;
    if (ins != null) return ins.rank;
    final known = socialUsers.where((u) => u.name == name).firstOrNull;
    if (known != null) return known.rank;
    return fallback ?? 1;
  }

  /// 某人**現在**該顯示的名字（暱稱重構階段四）。
  ///
  /// **一律回「他現在的暱稱」，不是任何時點的快照。** 與 [rankOf] 同一套：
  /// 貼文、留言、對話、團隊名冊、收件匣各自存了一份「發生當下的名字」，
  /// 那些值只是這裡查不到人時的墊底。
  ///
  /// [frozen] 就是呼叫端手上那份快照。**改名之後它就過期了** ——
  /// 規格說得很清楚：「暱稱為顯示名稱，不是識別碼」（〈註冊流程〉），
  /// 所以顯示的第一順位永遠是公開檔案上的現值。
  ///
  /// 沒有 uid 就只能原封不動回傳 —— 那不是查詢失敗，是**沒有東西可查**。
  String nameOf(String frozen, {String? uid}) {
    if (_isMe(frozen, uid)) return displayName;
    return uid == null ? frozen : (nameByUid[uid] ?? frozen);
  }

  /// 某人**現在**的教官聲望。非教官回空值。
  ///
  /// [fallback] 是呼叫端手上那份快照（貼文上的 `authorReputation`），
  /// 只在完全查不到這個人時用。
  int? reputationOf(String name, {String? uid, int? fallback}) {
    if (_isMe(name, uid)) return isInstructor ? instructorReputation : null;
    final p = _profile(name, uid);
    // **檔案在手上就以它為準，不可以再退回快照。** 它說不是教官就是不是 ——
    // 退回去的話，被撤銷教官身分的人在舊貼文上會一直掛著那枚徽章。
    if (p != null) return p.reputation;
    final ins = instructors.where((i) => i.name == name).firstOrNull;
    if (ins != null) return ins.reputation;
    return fallback;
  }

  /// 某人**現在**是不是教官。
  ///
  /// 教官身分會被撤銷（`revokeInstructor`），所以這件事跟階級一樣
  /// 不能存快照 —— 對話框上那枚「教官」徽章原本是開對話當下存的。
  bool isInstructorOf(String name, {String? uid, bool fallback = false}) {
    if (_isMe(name, uid)) return isInstructor;
    final p = _profile(name, uid);
    if (p != null) return p.isInstructor;
    if (instructors.any((i) => i.name == name)) return true;
    return fallback;
  }

  /// 某人在檔案頁上該列出的貼文。
  ///
  /// **看別人只列公開的**：僅關注者與私人兩種可見範圍是發文者指定的，
  /// 檔案頁不是繞過它的後門。看自己則三種都列 —— 那本來就是我的東西。
  /// 這個人的貼文，**由新到舊**。
  ///
  /// 排序要在這裡做，不能倚賴 `posts` 本身的順序：`applyCloudPosts` 會排，
  /// 但本機新發的是直接插進去的。在此之前檔案頁只取前兩篇 ——
  /// 順序不對的話，「最新兩篇」拿到的會是別的兩篇。
  /// **不再依可見範圍過濾**（使用者裁決 2026-09-26，貼文一律公開）。
  ///
  /// 過濾掉也沒有用：安全規則那一側是 `allow read: if request.auth != null`，
  /// 任何登入者本來就讀得到每一篇。前端濾掉只是讓自己看不到。
  ///
  /// 2026-09-26 之前標為「私人」「僅關注者」的舊貼文因此會出現在
  /// 檔案頁上 —— 但它們**本來就在所有人的動態牆上**（動態牆從來沒有
  /// 依可見範圍過濾過），所以這不是新的曝光，是把不一致修掉。
  /// [uid] 拿得到就以它為準 —— 暱稱可以改、也會撞名。
  List<Post> postsBy(String name, {String? uid}) => posts
      .where((p) =>
          !p.deleted &&
          (uid != null && p.authorUid != null
              ? p.authorUid == uid
              : p.author == name))
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  /// 我發過幾篇**還在**的貼文。
  ///
  /// **「我的」那個數字原本是自己數的**：
  /// `posts.where((p) => p.author == displayName).length` ——
  /// 沒有排除 `p.deleted`，而貼文是軟刪除（已刪除的仍留在清單裡供
  /// 獎勵回收與成就計數判定）。使用者回報「刪除了 5 篇，貼文顯示 7 篇」。
  ///
  /// 旁邊的 [postsBy] 一直都有排除已刪除的 —— 同一個決定寫在兩個地方，
  /// 只有一處做對。改成走同一支，數字與清單從此不可能對不起來。
  int get myPostCount => postsBy(displayName, uid: myUid).length;

  /// 暱稱 → uid。[nameByUid] 的反查 —— 畫面上拿得到的是暱稱，
  /// 而雲端要的是 uid。
  String? uidOf(String name) => _uidByName[name];

  // --- 關注關係上雲（[BE-11] 批次 2）---

  /// 雲端的關注關係。**空值代表不同步** —— 既有測試走這條，行為與上雲前一樣。
  FollowSource? followSource;

  /// 把 [toggleFollow] 的結果送上雲。
  ///
  /// **即發即忘，而且吞掉錯誤**：關注是樂觀更新，記憶體與畫面已經改了。
  /// 這裡失敗就讓它失敗 —— 下次登入 [applyFollows] 會以雲端為準重新對齊。
  /// 為了一次網路失敗把畫面倒回去，比晚一點才一致更難解釋。
  void _pushFollow(String key, {required bool nowFollowing}) {
    final src = followSource;
    if (src == null) return;
    // 暱稱鍵代表對方不在公開檔案裡（示範用的假使用者就是這種），
    // 雲端沒有這個人可以指 —— 只在本地生效。
    if (_isNameKey(key)) return;
    (nowFollowing ? src.follow(key) : src.unfollow(key)).catchError((_) {});
  }

  /// 把名單上的 [from] 換成 [to]，三份資料一起換。
  ///
  /// 用在「原本只認得暱稱的人，現在拿到 uid 了」。
  void _upgradeFollowKey(String from, String to) {
    if (from == to) return;
    if (following.remove(from)) following.add(to);
    final at = followers.indexOf(from);
    if (at >= 0) followers[at] = to;
    final count = otherFollowerCounts.remove(from);
    // **舊的計數不蓋掉新的。** 上面那一行剛把雲端讀回來的真實數字寫進
    // `otherFollowerCounts[p.uid]`，暱稱鍵底下那個是示範公式算出來的。
    if (count != null) otherFollowerCounts.putIfAbsent(to, () => count);
  }

  /// 以雲端的關注關係為準重新對齊（[BE-11] 批次 2）。
  ///
  /// **uid 那一半整份換掉，不是併入。** 併入的話，我在另一台裝置上取消的
  /// 關注永遠回不來 —— 雲端已經沒有那筆關係，而本機這份留著。
  /// 暱稱鍵那一半留著：那是示範資料的假使用者，雲端本來就沒有他們，
  /// 跟著換掉的話一登入就整批消失。
  ///
  /// **不再要求「認得出暱稱」。** 在此之前查不到暱稱的 uid 會被整筆丟掉，
  /// 於是「對方還沒發布公開檔案」等於「我沒有關注他」—— 名單少人、
  /// 粉絲數也少。現在名單存的是 uid，名字查不到就由 [followName] 墊底。
  void applyFollows(Set<String> followingUids, Set<String> followerUids) {
    following
      ..removeWhere((k) => !_isNameKey(k))
      ..addAll(followingUids);
    followers.removeWhere((k) => !_isNameKey(k));
    // **封鎖過的人不回來。** 我刪不掉他那一筆關係文件（安全規則只讓
    // 建立者刪），雲端於是永遠留著 —— 不擋的話，「封鎖自動解除雙方關注」
    // 這條後置條件每次登入都被推翻一次。
    final blocked = {
      for (final b in blockedUsers) personKeyOf(b.name, b.uid),
    };
    // 反著插，雲端那批彼此的相對順序才跟傳進來的一致。
    for (final uid in followerUids.toList().reversed) {
      if (blocked.contains(uid)) continue;
      if (!followers.contains(uid)) followers.insert(0, uid);
    }
    // 粉絲數的不變條件：等於關注關係中被關注者為本人的筆數。
    peakFollowerCount = math.max(peakFollowerCount, followers.length);
    notifyListeners();
  }

  // --- 貼文上雲（[BE-11] 批次 3）---

  /// 雲端的貼文。**空值代表不同步** —— 既有測試走這條。
  PostSource? postSource;

  /// 使用者上傳的照片（2026-09-28 使用者裁決：存 Firestore，不開 R2）。
  ///
  /// **空值代表不接雲端** —— 既有測試全部走這條，
  /// 行為與加這個功能之前一模一樣（選不到裝置照片，只有內建圖庫）。
  PhotoSource? photoSource;

  bool get canUploadPhoto => photoSource != null;

  /// 壓縮並上傳一張照片。回傳 `(照片 ID, 失敗原因)`，兩者必有其一。
  ///
  /// **壓縮在這裡做，不在存讀層做。** 存讀層只負責存得進去；
  /// 「這個檔案能不能變成一張存得下的照片」是先決條件，
  /// 而它在沒有雲端的環境（測試）也該驗得出來。
  Future<(String?, String?)> uploadPhoto(Uint8List raw) async {
    final src = photoSource;
    if (src == null) return (null, '目前無法上傳照片。');
    final encoded = encodePhoto(raw);
    if (encoded == null) return (null, '這個檔案不是看得懂的圖片。');
    try {
      return (await src.put(encoded.bytes), null);
    } catch (e) {
      return (null, '照片上傳失敗：$e');
    }
  }

  /// 取一張上傳照片的位元組。畫面用（見 `PhotoScope`）。
  Future<Uint8List?> photoBytes(String id) async =>
      isUploadedPhoto(id) ? await photoSource?.get(id) : null;

  /// 動態牆一次讀幾篇。登入時的首次載入與下拉重新整理共用同一個值 ——
  /// 兩邊不一致的話，下拉之後看到的篇數會跟剛登入時不一樣。
  static const kPostFeedLimit = 30;

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

  /// 與 [_pushSocial] 同一件事，但**等它做完並回報成功與否**。
  ///
  /// 給刪除用。沒接後端時回真 —— 那是示範模式與既有測試走的路，
  /// 「沒有雲端可寫」不是失敗。
  Future<bool> _pushSocialTracked(
      Future<void> Function(PostSource src, String uid) job) async {
    final src = postSource;
    final uid = myUid;
    if (src == null || uid == null) return true;
    try {
      await job(src, uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 這則留言掛在哪篇貼文底下。
  ///
  /// 留言本身不帶貼文 ID（雲端是子集合，父層由路徑決定），而寫回雲端
  /// 要指定父文件 —— 所以反查一次。找不到回空字串，呼叫端的雲端寫入
  /// 會失敗並被吞掉，不影響本機。
  String _postIdOf(Comment c) =>
      posts.where((p) => p.comments.contains(c)).firstOrNull?.id ?? '';

  /// 把雲端的貼文併進動態牆（[BE-11] 批次 3）。
  ///
  /// **併入而非取代**：示範用的貼文還撐著「動態牆長什麼樣」這件事，
  /// 全新的平台上一篇真的貼文都沒有。同一個 ID 以雲端那份為準 ——
  /// 它帶著別人的按讚與留言，本地那份沒有。
  /// 重新從雲端讀貼文。回傳是否真的讀到了。
  ///
  /// **為什麼需要這個**：[applyCloudPosts] 原本只在登入那一刻被呼叫一次
  /// （見 `AuthGate._syncProfile`），所以 B 已經登入著、A 這時發文，
  /// **B 看不到** —— 要把 App 完全重新載入才會出現。
  /// 那是 `[QA-01]` 第 6 項「A 發文了 B 好像沒看到」的前半，
  /// 假貼文那一半先修掉了，這一半漏到 2026-09-18 才補。
  ///
  /// 空值來源（沒接後端、或既有測試）回傳 false，呼叫端據此不顯示下拉。
  ///
  /// 這不是即時訂閱。真正的即時要 `.snapshots()`，那會動到整個讀取層，
  /// 留給 `[BE-07]` 那批一起做（見 PROGRESS.md 第 5 節）。
  Future<bool> refreshCloudPosts() async {
    final src = postSource;
    if (src == null) return false;
    try {
      // **兩段。** 先把貼文本體畫出來（一趟查詢），再補留言與讚
      // （一篇各一趟，30 篇就是 60 趟）。合在一起等的話，動態牆要
      // 等最慢的那一趟才出現第一個字 —— 使用者回報的「有點慢」。
      final got = await src.recent(limit: kPostFeedLimit);
      applyCloudPosts(got);
      await fillPostDetails(got);
      return true;
    } catch (_) {
      // 讀不到就維持畫面上現有的貼文 —— 下拉失敗不該把動態牆清空。
      return false;
    }
  }

  /// 補上這幾篇的留言與「我按過讚沒有」，補完重畫。
  ///
  /// 失敗只影響這一塊：貼文本體已經在畫面上了，補不到留言不該讓它消失。
  Future<void> fillPostDetails(List<Post> got) async {
    final src = postSource;
    if (src == null) return;
    try {
      await src.fillDetails(got);
      notifyListeners();
    } catch (_) {/* 留著本體，不清空 */}
  }

  /// 登入後每一塊同步的結果。**開發者模式看得到。**
  ///
  /// 這幾塊全部是即發即忘、吞掉錯誤 —— 那是對的（社群讀不到不該擋住
  /// 訓練），但代價是**出問題時完全沒有跡象**。「申請送得出去、對方
  /// 看不到」查了三輪都在猜，就是因為這裡什麼都不說。
  ///
  /// 存的是「這一塊拿到幾筆」或「為什麼失敗」，不是資料本身。
  final Map<String, String> syncReport = {};

  void reportSync(String step, String result) {
    syncReport[step] = result;
    notifyListeners();
  }

  /// 重新向雲端拿一次私訊與待回應請求。
  ///
  /// **這是「沒有即時訂閱」的代償。** `lib/data/` 底下沒有任何
  /// `.snapshots()`，跨使用者的東西只在登入時載入一次 —— 對方傳了
  /// 訊息或送出申請，我這邊要登出再登入才看得到。那不是可以交付的
  /// 使用體驗，所以至少給一個下拉重新整理。
  ///
  /// 真正的解法是即時訂閱（`PROGRESS.md` 第 5 節 0c），那會動到整個讀取層。
  ///
  /// 逐塊各自 try：讀不到私訊不該連帶讓請求也刷不出來。
  Future<void> refreshInbound() async {
    final uid = myUid;
    if (uid == null) return;

    final chats = chatSource;
    if (chats != null) {
      try {
        applyCloudConversations(await chats.conversations(limit: 50));
      } catch (_) {/* 維持現有內容，不清空 */}
    }
    final teams = teamSource;
    if (teams != null) {
      try {
        applyCloudTeam(await teams.myTeam());
        applyCloudTeamRequests(
            await teams.requestsFor(uid, myTeamId: myTeam?.id));
      } catch (_) {/* 同上 */}
    }
    final mentor = mentorSource;
    if (mentor != null) {
      // **關係本身也要重讀，不只是申請。** B 按下「接受拜師」之後，
      // A 這一側要看到的是一段新關係 —— 那在 `bonds()` 裡，
      // 不在 `requestsFor()` 裡（那筆申請反而被刪掉了）。
      // 少了這一段，即時訂閱會發出訊號卻什麼都沒變。
      try {
        applyCloudBonds(await mentor.bonds());
        await loadMentorSide();
        // **學徒那一側也要讀。** 少了它，教官的回答永遠到不了學徒手上。
        await loadMyApprenticeSide();
      } catch (_) {/* 同上 */}
      try {
        applyCloudMentorRequests(await mentor.requestsFor(uid));
      } catch (_) {/* 同上 */}
      try {
        // **我自己送出去的**申請。與上面那一條是不同的方向，
        // 不能合成一條（安全規則證明不了 or 條件）。
        applyMySentMentorRequests(await mentor.sentRequests());
      } catch (_) {/* 同上 */}
    }
  }

  // ─────────────────────────────────────────────────────────
  // 即時訂閱（`[BE-16]`）
  // ─────────────────────────────────────────────────────────

  final List<StreamSubscription<void>> _cloudWatches = [];
  Timer? _cloudWatchDebounce;

  /// 開發者模式看得到：訂了哪幾條、被叫醒過幾次。
  ///
  /// **「完全沒有訊號」與「訂閱根本沒掛上」在畫面上長得一模一樣。**
  /// 這個專案查過三輪的那種 bug 就是這樣 —— 即發即忘、吞掉錯誤、
  /// 出事時毫無跡象。所以至少把「掛上了沒、醒過幾次」記下來。
  final Map<String, String> cloudWatchReport = {};

  /// 兩次重讀之間的最短間隔。
  ///
  /// 一個動作常常連帶好幾筆文件變動（接受申請＝建關係＋刪申請，
  /// 兩條監聽各發一次訊號）。沒有這一層，一個動作會觸發兩三趟
  /// 完整重讀，而每趟都 `notifyListeners()` 讓整個畫面重建。
  static const _cloudWatchDebounceMs = 400;

  bool get isWatchingCloud => _cloudWatches.isNotEmpty;

  /// 開始監聽雲端變動。登入同步跑完之後呼叫。
  ///
  /// **重複呼叫是安全的** —— 會先把舊的收掉。`myTeam` 換了之後
  /// 要重訂（監看「別人申請加入我的隊」需要知道是哪一隊），
  /// 所以這支本來就會被叫第二次。
  void startCloudWatch() {
    stopCloudWatch();
    cloudWatchReport.clear();

    void sub(String what, Stream<void>? stream) {
      if (stream == null) return;
      var woke = 0;
      cloudWatchReport[what] = '已訂閱';
      _cloudWatches.add(stream.listen(
        (_) {
          woke++;
          cloudWatchReport[what] = '已訂閱，叫醒 $woke 次';
          _onCloudChanged();
        },
        onError: (Object e) => cloudWatchReport[what] = '失敗：$e',
        cancelOnError: false,
      ));
    }

    sub('私訊', chatSource?.watchConversations());
    sub('團隊', teamSource?.watchTeams(myTeamId: myTeam?.id));
    sub('師徒', mentorSource?.watchMentor());

    // **貼文刻意不訂。** 動態牆已經有下拉重新整理，而按讚會改到
    // 貼文文件 —— 任何人按一個讚，所有在線的人都得重抓 50 篇貼文
    // 連同留言。以免費方案每日 5 萬次讀取算，那是會自己燒完的設計。
    // 關注也不訂：粉絲數在開啟檔案頁時才數一次，沒有「在畫面上等著
    // 看它變」的情境。
    notifyListeners();
  }

  /// 收掉所有監聽。登出、或換帳號時呼叫。
  ///
  /// **不收的話訊號會流到上一個帳號的資料上。** 監聽是綁在
  /// 建立它的那個 Source（帶著當時的 uid）上的，Source 換掉了，
  /// 舊的訂閱不會自己斷。
  void stopCloudWatch() {
    _cloudWatchDebounce?.cancel();
    _cloudWatchDebounce = null;
    for (final w in _cloudWatches) {
      w.cancel();
    }
    _cloudWatches.clear();
  }

  void _onCloudChanged() {
    _cloudWatchDebounce?.cancel();
    _cloudWatchDebounce = Timer(
      const Duration(milliseconds: _cloudWatchDebounceMs),
      () {
        _cloudWatchDebounce = null;
        // 即發即忘：重讀失敗維持畫面現狀，不清空也不擋住使用者。
        refreshInbound();
      },
    );
  }

  void applyCloudPosts(List<Post> cloud) {
    for (final p in cloud) {
      final i = posts.indexWhere((x) => x.id == p.id);
      if (i >= 0) {
        // **留言與讚先沿用畫面上那份。**
        //
        // `recent()` 只查貼文本體，留言與「我按過讚沒有」由
        // `fillDetails()` 隨後補上。中間那幾百毫秒若直接換成空的，
        // 使用者會看到留言整批消失、愛心變回空心，然後又跳回來。
        //
        // 補上之後 `_fillComments` 會先 `clear()`，所以真的被刪掉的
        // 留言不會因為這裡沿用而留著。
        if (p.comments.isEmpty) p.comments.addAll(posts[i].comments);
        p.likedByMe = p.likedByMe || posts[i].likedByMe;
        posts[i] = p;
      } else {
        posts.add(p);
      }
    }
    // 動態牆依時間由新到舊。
    posts.sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();

    // 把這一批作者的公開檔案補齊 —— 他們的階級要顯示現值，而登入時
    // 只撈得到最近活躍的前 200 位，久沒上線的作者不在裡面。
    // **不 await**：補到了會自己 notifyListeners 重畫，補不到就用
    // 貼文上那份快照墊底。動態牆不該為了階級而等網路。
    ensureProfiles([for (final p in cloud) ?p.authorUid]);
  }

  // --- 封鎖（獨立 Aggregate，不附屬於對話）---

  late List<BlockedUser> blockedUsers = demo ? buildBlockedUsers() : [];

  /// 這個人有沒有被我封鎖。
  ///
  /// **拿得到 uid 就給 uid。** 只比暱稱的話，對方改名之後
  /// 「封鎖過的人」會變回「沒封鎖過」—— 而封鎖是自保，不是社交功能。
  bool isBlocked(String name, {String? uid}) =>
      blockedUsers.any((b) => sameUser(b.name, b.uid, name, uid));

  /// 不能封鎖的理由；null 表示可以封鎖。
  ///
  /// **雙方不得為同一團隊的成員** —— 欲封鎖同隊成員者須先退出團隊。
  /// 採「禁止封鎖」而非「自動退隊」：自動退隊會使一次封鎖操作
  /// 連帶改變第三方（其餘隊友）的團隊組成。
  ///
  /// 已知代價：騷擾者為同隊隊友時，受害者須先退出團隊才能自保。
  /// 這是模型明示接受的代價，而它成立的前提正是這條 Precondition 真的擋住 ——
  /// 不擋的話，使用者付了退隊的代價卻換不到任何東西。
  String? blockBlockedReason(String name, {String? uid}) {
    if (isBlocked(name, uid: uid)) return '已經封鎖過這個人了。';
    final t = myTeam;
    if (t != null && t.members.any((m) => sameUser(m.name, m.uid, name, uid))) {
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
  bool blockUser(String name, {String? uid}) {
    if (blockBlockedReason(name, uid: uid) != null) return false;
    blockedUsers.insert(0, BlockedUser(name, now, uid: uid ?? uidOf(name)));

    // Postcondition：自動解除**雙方**的關注關係。
    //
    // **「對方關注我」那一半只解得掉本機這一份。** 雲端的關係文件是
    // `follows/{他的uid}_{我的uid}`，而安全規則只讓 `followerId` 本人刪除 ——
    // 我刪不了別人建立的關係。下次登入 `applyFollows` 會把他加回粉絲名單。
    // 見 PROGRESS 1Q，待裁決。
    final key = personKeyOf(name, uid);
    _unfollow(key);
    followers.remove(key);

    // Postcondition：自動解除師徒關係，未完成的師徒任務作廢。
    // 封鎖後該關係只剩空殼，且會繼續佔用教官的帶徒名額。
    if (myInstructor?.name == name) {
      releaseMentor(MentorReleaseReason.blocked);
    }
    notifyListeners();
    return true;
  }

  /// 取消關注的帳務處理。粉絲數為儲存欄位，非即時彙總，故得逐處維護。
  ///
  /// **不得扣成負數。** 使用者回報：已關注對方時封鎖他，對方的粉絲數
  /// 變成 −1。成因是這個計數會被 `applyPublicProfiles` 重設成對方檔案上
  /// 的值（那份只有他自己更新得了），而本機的 `following` 還留著 ——
  /// 於是「已關注」與「粉絲數 0」同時成立，一扣就變負的。
  ///
  /// 聲望早就有地板了（`applyReputation`），粉絲數漏掉。
  void _unfollow(String key) {
    if (!following.remove(key)) return;
    final now = (otherFollowerCounts[key] ?? 1) - 1;
    otherFollowerCounts[key] = now < 0 ? 0 : now;
  }

  /// 使用者已解除封鎖。
  void unblockUser(String name, {String? uid}) {
    final before = blockedUsers.length;
    blockedUsers.removeWhere((b) => sameUser(b.name, b.uid, name, uid));
    if (blockedUsers.length != before) notifyListeners();
  }

  // --- 通知 ---

  late List<AppNotification> notifications = demo ? buildNotifications() : [];

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
      authorUid: myUid,
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
        accusedUid: myUid,
      );
    }
    coins += 5; // 發文獎勵
    _bumpTasks('發文者已發布貼文', 1);
    // **這一行原本不在。**
    //
    // `interactionTotals['發文']` 因此**沒有任何增加的路徑** ——
    // 發文者已發布貼文是師徒功能五個解鎖條件之一，而它永遠是 0。
    //
    // 以前看不出來，是因為示範種子給了 18（`{分享:26, 發文:18, …}`）。
    // 1F 把那組種子從真帳號清掉之後，**師徒功能對所有真實使用者
    // 變成永遠解不開** —— 2026-09-28 雙人實測 T1 當場撞到：
    // 「就算發文了無法解鎖發文任務」。
    //
    // 按讚（3267）、留言（3284）、分享（3312）三處本來就有，
    // 只有發文這一處漏了。
    _grantInteraction('Post');
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
      if (!isMyPost(p)) _grantInteraction('Like', requestId: p.id);
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
    // **帶上 uid。** 雲端那一側本來就在存它，本機這一份漏了 ——
    // 於是離線建立的留言讀回來之前都認不出是誰的。
    final c = Comment(displayName, text.trim(), now, authorUid: myUid);
    p.comments.add(c);
    _pushSocial((src, uid) => src.addComment(p.id, c, authorUid: uid));
    final exp = isMyPost(p) ? 0 : _grantInteraction('Comment');
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
      authorUid: myUid,
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

  /// **只比暱稱。** 這是 [_isMe] 在沒有 uid 可比時的退路，
  /// 不該被直接呼叫 —— 暱稱會撞名，開放改名之後還會讓自己的舊貼文
  /// 與舊留言變成別人的。
  ///
  /// 2026-09-26 之前有五處直接呼叫它（按讚與留言的獎勵判定、
  /// 編輯貼文、編輯留言、刪除留言），而旁邊的 `isMyPost` 已經改用
  /// [_isMe] 了 —— 於是「⋯」選單開得出「編輯」，按下去 `editPost`
  /// 卻回傳假。同一個問題兩種答案。
  bool _mineByName(String author) => author == displayName;

  /// 這篇貼文是不是我發的。
  ///
  /// **以 uid 為準，暱稱只是退路。** 暱稱可以撞名、日後也會開放修改 ——
  /// 到那時候「我改了暱稱，自己的舊貼文變成別人的」會一次影響編輯、
  /// 刪除與這顆「⋯」要開哪一組選單。貼文本來就帶著 `authorUid`。
  ///
  /// 這件事原本散在畫面上各寫一次（`p.author == s.displayName`），
  /// 而動態牆那一處根本沒寫 —— 見 `showPostMenu`。
  bool isMyPost(Post p) => _isMe(p.author, p.authorUid);

  /// 這則留言是不是我留的。與 [isMyPost] 同一套判準 ——
  /// 編輯與刪除留言、以及「對自己的貼文互動不發獎勵」都讀它。
  bool isMyComment(Comment c) => _isMe(c.author, c.authorUid);

  /// 貼文已編輯。編輯前的內容與時戳寫入編輯歷史，**保留完整歷史版本**；
  /// 已編輯旗標設為真，讀者看得到「已編輯」。
  bool editPost(Post p, String text) {
    if (!isMyPost(p) || p.deleted || text.trim().isEmpty) return false;
    if (text.trim() == p.text) return false;
    p.edits.add((p.text, now));
    p.text = text.trim();
    notifyListeners();
    // **在此之前這一行不存在。** `PostSource.updatePostText` 早就寫好了，
    // Firestore 的實作也完整，就是沒有人呼叫 —— 於是編輯只改記憶體，
    // 重新整理變回舊內容，別人從頭到尾看到的是原版。
    //
    // 編輯沿用即發即忘：失敗了內容還在，使用者可以再改一次。
    // **刪除不能這樣**（見 [deletePost]）。
    _pushSocial((src, _) => src.updatePostText(p.id, p));
    return true;
  }

  /// 貼文已刪除。**軟刪除**：資料保留，因為貼文可被檢舉。
  /// 已刪除貼文的按讚與留言一併隱藏但保留，供獎勵回收與成就計數判定使用。
  /// 回傳**要顯示給使用者的訊息**；空值代表成功。
  ///
  /// ## 為什麼刪除不能即發即忘
  ///
  /// 按讚、留言、編輯失敗了都還好 —— 東西還在，再做一次就是。
  /// **刪除失敗不一樣：使用者以為東西沒了，實際上還在別人眼前。**
  /// 那正是這次要修的困惑，靜靜地失敗只是把它換個地方發生。
  ///
  /// 所以雲端寫不進去就**把本機的刪除收回**：讓貼文重新出現，並說明原因。
  /// 看到它還在、知道為什麼，比以為刪掉了好。
  Future<String?> deletePost(Post p) async {
    if (!isMyPost(p) || p.deleted) return null;
    p.deleted = true;
    notifyListeners();

    if (!await _pushSocialTracked((src, _) => src.markPostDeleted(p.id))) {
      p.deleted = false;
      notifyListeners();
      return '刪除沒有成功，貼文還在。網路恢復後再試一次。';
    }
    return null;
  }

  /// 動態牆看得到的貼文。
  List<Post> get visiblePosts => posts.where((p) => !p.deleted).toList();

  /// 留言已編輯。規則比照貼文，不另定義。
  bool editComment(Comment c, String text) {
    if (!isMyComment(c) || c.deleted || text.trim().isEmpty) return false;
    if (text.trim() == c.text) return false;
    c.edits.add((c.text, now));
    c.text = text.trim();
    notifyListeners();
    _pushSocial((src, _) => src.updateCommentText(_postIdOf(c), c));
    return true;
  }

  /// 留言已刪除。同樣是軟刪除，且不回收已發放的獎勵 ——
  /// 刪除後重新留言是新的留言 ID，屬新的一次互動。
  /// 回傳要顯示給使用者的訊息；空值代表成功。理由同 [deletePost]。
  Future<String?> deleteComment(Comment c) async {
    if (!isMyComment(c) || c.deleted) return null;
    final postId = _postIdOf(c);
    c.deleted = true;
    notifyListeners();

    if (!await _pushSocialTracked(
        (src, _) => src.markCommentDeleted(postId, c.id))) {
      c.deleted = false;
      notifyListeners();
      return '刪除沒有成功，留言還在。網路恢復後再試一次。';
    }
    return null;
  }

  /// 使用者已關注帳號 / 已取消關注。
  /// Postcondition：被關注者的粉絲數 +1 / −1。
  void toggleFollow(String name, {String? uid}) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    final key = personKeyOf(name, uid);
    if (following.contains(key)) {
      _unfollow(key);
      _pushFollow(key, nowFollowing: false);
    } else {
      following.add(key);
      _rememberFollowName(key, name);
      otherFollowerCounts[key] = (otherFollowerCounts[key] ?? 0) + 1;
      // 歷史行為計數，取消關注不扣回去。
      followTotal += 1;
      _pushFollow(key, nowFollowing: true);
    }
    notifyListeners();
  }

  /// 對方取消關注我 —— 粉絲數減少，但已解鎖的粉絲成就不撤銷。
  ///
  /// 收的是[followers] 裡的鍵（畫面上那份清單就是它）。
  void loseFollower(String key) {
    if (!followers.remove(key)) return;
    notifyListeners();
  }

  void gainFollower(String name, {String? uid}) {
    final key = personKeyOf(name, uid);
    if (followers.contains(key)) return;
    followers.insert(0, key);
    _rememberFollowName(key, name);
    peakFollowerCount = math.max(peakFollowerCount, followers.length);
    notifyListeners();
  }

  // ===========================================================================
  // 團隊
  // ===========================================================================

  /// **要跟著 [demo] 走。** 這是唯一漏掉旗標的使用者狀態集合。
  ///
  /// `resetToNewAccount()` 有清它，但那只在「讀不到存檔」時跑 ——
  /// 第二次之後的登入走的是 `applySnapshot()`，而 `myTeam` **不在快照裡**
  /// （見 `app_state_snapshot.dart`），於是每次重開都從這裡重新長出
  /// 一支「晨型人訓練隊」，隊友是三個不存在的人。
  late Team? myTeam = demo ? buildMyTeam() : null;

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
  ///
  /// [carried] 是這筆資料自己帶著的 uid（從雲端讀來時一併保留）。
  /// **有就用它，不要反查** —— 反查只看得到已載入的那 50 筆公開檔案，
  /// 對方不在裡面就回傳空值，於是整個雲端寫入被無聲跳過。
  String? _memberUid(String name, [String? carried]) =>
      carried ?? (name == displayName ? myUid : uidOf(name));

  /// 雲端寫入因為認不出對方是誰而沒送出 —— 記進 [syncReport]，
  /// 讓開發者模式看得到。畫面已經改了、雲端沒動，這是最難查的一種失敗。
  void _cannotIdentify(String what, String name) {
    reportSync('雲端寫入', '「$what」沒有送上雲端：認不出「$name」的身分，'
        '重新整理後會打回原形');
  }

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
    // **雲端說沒有，就是沒有。** 原本在這裡直接 `return`，於是本機那支
    // 示範隊伍會原封不動留著 —— 已登入但還沒加入任何隊伍的人，
    // 看到的是一支他從未加入的隊，和三個不存在的隊友。
    if (t == null || t.disbanded) {
      myTeam = null;
      teamJoinedAt = null;
      notifyListeners();
      return;
    }

    myTeam = Team(
      id: t.id,
      name: t.name,
      isPublic: t.isPublic,
      capacity: t.capacity,
      members: [
        for (final e in t.members.entries)
          TeamMember(e.value.name, e.value.rank, e.value.role, uid: e.key),
      ],
      lockedGroupSize: t.peakSize,
      // **分數以雲端為準。** 在此之前團隊分數完全沒有上雲，重開 App
      // 就回到示範資料、真帳號則每次從零開始（使用者 2026-09-28 回報）。
      contributions: {...t.contributions},
      // 限時任務的完成名單只在**今天**才算數 —— 雲端那份如果是昨天的，
      // 清空這件事沒有伺服器可以做，由第一個完成的人順手做
      // （見 `CloudTeam.timedDay`），在那之前這裡先當它是空的。
      timedCredited:
          t.timedDay == _timedDayKey() ? {...t.timedCredited} : <String>{},
    );
    // **雲端說我已經在隊上，本機那筆「已送出的申請」就該消失。**
    // 一次只能屬於一個團隊，申請被核准後它已經沒有意義了 ——
    // 留著的話畫面會同時顯示「已加入」和「等隊長回應」。
    sentApplications.clear();
    notifyListeners();
  }

  /// 限時任務完成名單屬於哪一個業務日（04:00 換日，與全域規範一致）。
  String _timedDayKey() {
    final d = businessDate(now);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 我是不是這支隊伍的隊長。
  ///
  /// **以 uid 為準，暱稱只是退路**（與 `isMyPost` 同一套判準）。
  /// 隊員本來就帶著 uid —— `applyCloudTeam` 把雲端文件的鍵原樣帶進來。
  bool get iAmLeader =>
      myTeam?.members.any(
          (m) => _isMe(m.name, m.uid) && m.role == TeamRole.leader) ??
      false;

  /// 隊長已踢除成員。隊長不得踢除自己 —— 隊長離隊須經轉讓或解散。
  /// 被踢除者**不適用 12 小時換隊冷卻期**（該次離隊非其本人所為）。
  void kickMember(TeamMember m) {
    final t = myTeam;
    if (t == null || !iAmLeader) return;
    if (m.role == TeamRole.leader) return;
    if (!t.members.contains(m)) return;
    t.members.remove(m);
    final who = _memberUid(m.name, m.uid);
    if (who == null) {
      _cannotIdentify('踢除成員', m.name);
    } else {
      _pushTeam((src, _) => src.removeMember(t.id, who));
    }
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
    final who = _memberUid(r.name, r.uid);
    final m = TeamMember(r.name, r.rank, TeamRole.member, uid: who);
    t.members.add(m);
    // 加入成員與清掉那筆申請是同一件事的兩半。
    //
    // 這兩件事沒做成的後果，正是使用者回報的那兩個症狀：
    // 申請沒刪掉 → 隊長一重新整理，那筆申請又回來了；
    // 成員沒寫進 memberUids → 申請人那邊 `myTeam()` 查不到，
    // 畫面上依然沒有隊伍，還得再申請一次。
    if (who == null) {
      _cannotIdentify('核准申請', r.name);
    } else {
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
    final who = _memberUid(r.name, r.uid);
    if (who == null) {
      _cannotIdentify('拒絕申請', r.name);
    } else {
      _pushTeam((src, _) => src.dropRequest(t.id, who));
    }
    notifyListeners();
  }

  /// 取消一封尚未回應的邀請。失效後隊長可再次邀請。
  void cancelInvite(PendingRequest r) {
    final t = myTeam;
    if (t == null || !iAmLeader) return;
    t.invites.remove(r);
    final who = _memberUid(r.name, r.uid);
    if (who == null) {
      _cannotIdentify('取消邀請', r.name);
    } else {
      _pushTeam((src, _) => src.dropRequest(t.id, who));
    }
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
    final oldUid = _memberUid(old.name, old.uid);
    final newUid = _memberUid(to.name, to.uid);
    t.members[i] = TeamMember(old.name, old.rank, TeamRole.member, uid: oldUid);
    final j = t.members.indexOf(to);
    t.members[j] = TeamMember(to.name, to.rank, TeamRole.leader, uid: newUid);
    // 兩個人的角色一起換。只寫一邊的話雲端會同時有兩位隊長、或一位都沒有。
    if (oldUid == null || newUid == null) {
      _cannotIdentify('轉讓隊長', oldUid == null ? old.name : to.name);
    } else {
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
      timedTask.doneBy(displayName, uid: myUid) && !timedRewardClaimed;

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
      timedTask.doneBy(displayName, uid: myUid) &&
      myTeam != null &&
      !myTeam!.timedCredited.contains(personKeyOf(displayName, myUid));

  /// Demo：把自己標記為完成。完成判定實際由系統訂閱 Event 自動累計，
  /// 不採自行回報 —— 可自行按鈕加分的排行榜不成立。
  void completeTimedTask() {
    if (timedTaskExpired || timedTask.doneBy(displayName, uid: myUid)) return;
    timedTask.completedBy.add(personKeyOf(displayName, myUid));
    // 完成的當下記在當時所屬的隊帳上。中途加入者僅能貢獻加入後產生的分數，
    // 轉隊也不帶走舊團隊已貢獻的分數 —— 與團隊日常分數同一條規則。
    final t = myTeam;
    if (t != null) {
      t.timedCredited.add(personKeyOf(displayName, myUid));
      _pushTeam((src, uid) => src.creditTimed(t.id, uid, _timedDayKey()));
    }
    notifyListeners();
  }
  late List<PublicTeam> publicTeams = demo ? buildPublicTeams() : [];

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
  late DateTime? teamJoinedAt =
      demo ? DateTime.now().subtract(const Duration(days: 20)) : null;

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
    sentApplications
        .add(PendingRequest(t.name, rank, expiresAt, teamId: t.id));
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
    final a = sentApplications.where((x) => x.name == teamName).firstOrNull;
    sentApplications.removeWhere((x) => x.name == teamName);
    // **優先用這筆申請自己帶著的隊伍 ID。** 反查只是退路，而且是壞的：
    // 公開隊伍清單會濾掉已滿的隊，我申請的隊一被別人填滿就反查不到，
    // 於是本機撤掉、雲端還在，下次載入那筆申請又跑出來。
    final id = a?.teamId ??
        publicTeams
            .where((t) => t.name == teamName && t.id.isNotEmpty)
            .map((t) => t.id)
            .firstOrNull;
    if (id == null) {
      _cannotIdentify('撤回申請', teamName);
    } else {
      _pushTeam((src, uid) => src.dropRequest(id, uid));
    }
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

  /// 上一次 [acceptInbound] 為什麼沒成功。
  ///
  /// **原本只回一個 `bool`**，畫面印「沒有成功」—— 而那句話對使用者
  /// 與對我都一樣沒有用。2026-09-28 雙人實測 T2 卡在這裡：
  /// B 接受了團隊邀請，畫面說成功（或沒有成功），重整之後什麼都沒有，
  /// 而**沒有任何地方說得出是哪一段斷的**。
  String? inboundFailure;

  /// 使用者已接受邀請 / 對方已接受申請。
  bool acceptInbound(InboundRequest r) {
    inboundFailure = null;
    // 這兩條原本也是「回 false、不說原因」。
    if (!inbox.contains(r)) {
      inboundFailure = '這筆請求已經不在信箱裡了（可能逾期或已處理過）。';
      return false;
    }
    if (inboundBlockedReason(r) case final why?) {
      inboundFailure = why;
      return false;
    }
    switch (r.kind) {
      case InboundKind.teamInvite:
        // **`firstWhere` 原本沒有 `orElse`** —— 找不到就丟例外，
        // 而呼叫端只看得到 `ok` 是 true 還是 false。
        //
        // 找不到是真的會發生：`publicTeams` 是「公開團隊清單」，
        // 而它要載入過才有東西。使用者若從通知直接點進信箱、
        // 沒去過團隊分頁，那份清單就是空的。
        //
        // 2026-09-28 雙人實測 T2：A 邀 B → B 接受 → **重整也沒有**。
        final t = publicTeams.where((x) => x.name == r.subject).firstOrNull;
        if (t == null) {
          inboundFailure = '找不到「${r.subject}」這支團隊。'
              '先到社群的團隊分頁看一下公開團隊清單，再回來接受。';
          notifyListeners();
          return false;
        }
        // **雲端寫得進去，才算加入成功。**
        //
        // `_joinPublicTeam()` 只動本機；雲端那一步失敗的話，
        // 畫面上加入了、重新整理就沒了 —— 那正是使用者看到的。
        if (t.id.isEmpty) {
          inboundFailure = '這支團隊還沒有雲端識別碼，加入不會被保存。'
              '請隊長重新建立團隊，或改用「申請加入」。';
          notifyListeners();
          return false;
        }
        _joinPublicTeam(t);
        _pushJoinedTeam();
      case InboundKind.mentorInvite:
        final i = instructors.where((x) => x.name == r.from).firstOrNull ??
            Instructor(
              name: r.from,
              uid: r.fromUid,
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
          uid: r.fromUid,
          rank: r.fromRank,
          ability: const {},
          recentWorkouts: const [],
        ));
    }
    // **把師徒關係寫上雲端。**
    //
    // 在此之前這裡只改記憶體 —— `MentorSource.bond()` 寫好了卻沒有人呼叫，
    // 於是兩邊各自重整之後，這段關係就不存在了。收徒那一側尤其明顯：
    // 教官看得到學徒、學徒看不到教官，而且誰都不知道為什麼。
    if (r.kind != InboundKind.teamInvite) _pushBond(r);

    // 請求已經回應完了，把雲端那筆清掉。**團隊那筆要排在入隊之後** ——
    // 安全規則允許我把自己加進名冊的條件，正是「有一筆給我的待回應請求」
    // （見 `firestore.rules` 的 teams update 規則），先刪就把自己鎖在外面了。
    _dropCloudRequest(r);

    inbox.remove(r);
    notifyListeners();
    return true;
  }

  /// 接受團隊邀請後，把自己寫進雲端的名冊。
  ///
  /// **在此之前這一步不存在。** `_joinPublicTeam()` 整個函式沒有一行雲端
  /// 寫入，而登入時是 `teams.myTeam()` 去查「我在哪支隊」—— 查不到，
  /// 於是接受邀請、重新整理，團隊就不見了。
  ///
  /// 申請被核准那條路徑不必走這裡：隊長的 `approveApplication()` 已經
  /// 把我 `putMember` 上去了，而那時我的申請也被他刪掉了 ——
  /// 再寫一次反而會被安全規則擋下（規則要求那筆請求還在）。
  void _pushJoinedTeam() {
    final t = myTeam;
    final me = myUid;
    if (t == null || me == null) return;
    final me2 = t.members.where((m) => m.uid == me).firstOrNull;
    if (me2 == null) return;
    _pushTeam((src, _) => src.putMember(t.id, me, _asCloudMember(me2)));
  }

  /// 把雲端那筆待回應請求清掉。
  ///
  /// **接受與拒絕都要做。** 在此之前兩條路徑都只從本機的 `inbox` 移除 ——
  /// 雲端那筆還在，下次登入 `applyCloudTeamRequests`／
  /// `applyCloudMentorRequests` 又把它撈回來。使用者拒絕了三次，
  /// 它出現了四次。
  ///
  /// 這與「撤回申請」那個已修的 bug 是同一句話：本機移掉、雲端還在。
  void _dropCloudRequest(InboundRequest r) {
    switch (r.kind) {
      case InboundKind.teamInvite:
        final id = myTeam?.id ??
            publicTeams
                .where((t) => t.name == r.subject && t.id.isNotEmpty)
                .map((t) => t.id)
                .firstOrNull;
        final me = myUid;
        if (id == null || me == null) return;
        _pushTeam((src, _) => src.dropRequest(id, me));
      case InboundKind.mentorInvite:
      case InboundKind.apprenticeApply:
        // `MentorSource.dropRequest` 在此之前**一個呼叫端都沒有**。
        // `data_source_wiring_test` 沒抓到它，因為 `TeamSource` 也有一支
        // 同名方法而那支有人呼叫 —— 那正是該檔案開頭寫明的撞名漏抓。
        mentorSource?.dropRequest(r.id).catchError((_) {});
    }
  }

  /// 接受師徒請求時把關係寫上雲端。
  ///
  /// **方向由請求的種類決定**：`mentorInvite` 是對方邀我當學徒（他是教官），
  /// `apprenticeApply` 是對方想拜我為師（我是教官）。搞反的話，雲端那筆
  /// 關係的師徒位置對調，而下次登入 `applyCloudBonds` 只看
  /// `apprenticeUid == me`，於是教官會把自己載入成學徒。
  void _pushBond(InboundRequest r) {
    final src = mentorSource;
    final me = myUid;
    // 對方的 uid 現在跟著請求一起來（`InboundRequest.fromUid`）。
    // 在此之前只有暱稱，要反查 —— 而反查只認得已載入的那幾位。
    final peer = r.fromUid ?? uidOf(r.from);
    if (src == null || me == null || peer == null) return;

    final mentorUid = r.kind == InboundKind.mentorInvite ? peer : me;
    final apprenticeUid = r.kind == InboundKind.mentorInvite ? me : peer;
    final mentorName = r.kind == InboundKind.mentorInvite ? r.from : displayName;
    final apprenticeName =
        r.kind == InboundKind.mentorInvite ? displayName : r.from;

    src
        .bond(CloudBond(
          // 關係 ID 由雙方 uid 組成 —— 與 `_apprenticeBondId` 同一套規則，
          // 兩邊各自算出來的必須是同一個字串。
          id: '${mentorUid}_$apprenticeUid',
          mentorUid: mentorUid,
          apprenticeUid: apprenticeUid,
          mentorName: mentorName,
          apprenticeName: apprenticeName,
          state: MentorBondState.active,
          bondedAt: now,
        ))
        // 即發即忘，與其餘社群寫入同一套 —— 失敗了下次登入以雲端為準。
        .catchError((_) {});
  }

  /// 使用者已拒絕邀請 / 對方已拒絕申請。
  /// 拒絕後該筆失效，對方可再次送出，無冷卻期（承既有裁決）。
  void declineInbound(InboundRequest r) {
    if (!inbox.remove(r)) return;
    // 拒絕也要把雲端那筆清掉，否則下次登入它又跑出來。
    _dropCloudRequest(r);
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
        TeamMember(displayName, rank, TeamRole.member, uid: myUid),
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
    final out = <String, int>{
      for (final m in t.members) personKeyOf(m.name, m.uid): each,
    };
    final l = t.members.firstWhere((m) => m.role == TeamRole.leader,
        orElse: () => t.members.first);
    final leader = personKeyOf(l.name, l.uid);
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
        accusedUid: c.peerUid,
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
  bool teammateCompletesTimedTask(String name, {String? uid}) {
    final t = myTeam;
    if (t == null || timedTaskExpired) return false;
    final m =
        t.members.where((m) => sameUser(m.name, m.uid, name, uid)).firstOrNull;
    if (m == null) return false;
    if (!timedTask.completedBy.add(personKeyOf(m.name, m.uid))) return false;
    t.timedCredited.add(personKeyOf(m.name, m.uid));
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
        accusedViolations: violationsOf(myUid, name: displayName),
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
      members: [TeamMember(displayName, rank, TeamRole.leader, uid: myUid)],
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

  late List<Instructor> instructors = demo ? buildInstructors() : [];
  Instructor? myInstructor;

  // --- 師徒上雲（[BE-14]）---

  /// 雲端的師徒關係。**空值代表不同步** —— 既有測試走這條。
  MentorSource? _mentorSource;
  MentorSource? get mentorSource => _mentorSource;
  set mentorSource(MentorSource? v) {
    _mentorSource = v;
    // 換了來源就等於換了一個人 —— 上一個帳號載過的事實不算數。
    _mentorLoaded = false;
  }

  /// 師徒關係是否已經從雲端載回來過。
  bool _mentorLoaded = false;

  /// 「我沒有教官」與「還不知道」分得開嗎。
  ///
  /// **`myInstructor == null` 有兩個意思。** 一個是事實（我還沒拜師），
  /// 一個是我們還沒讀到。在此之前拜師頁把兩者畫成同一張清單 ——
  /// 也就是在同步失敗時，對著一位有教官的人說「你沒有教官」。
  ///
  /// 那正是使用者會回報成「我的教官不見了」的那件事，而它**不會報錯**：
  /// 師徒那一塊是各自 try、吞掉錯誤的（那是對的，社群讀不到不該擋住訓練），
  /// 代價就是出問題時完全沒有跡象。
  ///
  /// 專案守則第 5 條：**填錯的數字比留白更糟，留白會被看見，錯的不會。**
  ///
  /// 沒接雲端時（示範、既有測試）本機就是全部事實，所以直接算「知道」。
  bool get mentorKnown => _mentorSource == null || _mentorLoaded;

  /// 我作為**學徒**的那一段關係在雲端的 ID。
  ///
  /// 只涵蓋學徒側。教官側（我帶的每位學徒各一段關係）目前接不上 ——
  /// 本機的 `mentorTasks`／`questions` 是**一份共用清單**，
  /// 沒有記錄「這則是哪位學徒的」，而雲端的任務與問答掛在特定關係下。
  /// 補這一段要先讓本機模型帶上學徒身分，見 PROGRESS.md 的 `[BE-15]`。
  String? get _apprenticeBondId {
    final me = myUid;
    final mentor = myInstructor;
    if (me == null || mentor == null) return null;
    // **以教官身上那個 uid 為準，反查只是退路。** 反查是拿暱稱去翻
    // `nameByUid`，而暱稱可以改；教官物件本來就帶著 uid 了。
    final mentorUid = mentor.uid ?? uidOf(mentor.name);
    if (mentorUid == null) return null;
    return '${mentorUid}_$me';
  }

  /// 本機的任務轉成雲端那一份。
  ///
  /// **識別碼用 `MentorTask.id`。** 在此之前是拿標題當 ID —— 教官指派
  /// 兩個同名任務就會落在同一份文件上，互相覆蓋。`[BE-15]` 補上了 ID 欄位。
  CloudMentorTask _asCloudTask(MentorTask t) => CloudMentorTask(
        id: t.id,
        title: t.title,
        detail: t.detail,
        state: t.state,
        rewardCoins: t.rewardCoins,
        rating: t.rating,
      );

  /// 學徒這一側動了任務（完成、領獎、評分）—— 掛在我與教官那段關係下。
  void _pushTask(MentorTask t) => _pushMentorTask(t);

  void _pushMentor(Future<void> Function(MentorSource src, String bondId) job) {
    final src = mentorSource;
    final bond = _apprenticeBondId;
    if (src == null || bond == null) return;
    job(src, bond).catchError((_) {});
  }

  /// 我作為**教官**時，與這位學徒那一段關係在雲端的 ID。
  ///
  /// 與 [_apprenticeBondId] 是同一套規則的另一側 ——
  /// 關係 ID 一律是 `教官uid_學徒uid`，兩邊各自算出來的必須一致。
  String? mentorBondIdFor(String? apprenticeUid) {
    final me = myUid;
    if (me == null || apprenticeUid == null) return null;
    return '${me}_$apprenticeUid';
  }

  /// 我帶的那些學徒的關係 ID。星等統計要跑過它們。
  Iterable<String> get myMentorBondIds =>
      apprentices.map((a) => mentorBondIdFor(a.uid)).nonNulls;

  /// 我收到的評分總數與平均（`[BE-15]`）。
  ///
  /// **在此之前 App 根本沒在記這個。** 學徒評分只會去動教官的聲望
  /// （見 [rateMentorTask]），沒有累積成星等 —— 於是拜師頁上每位教官
  /// 都寫著「0.0（0 則）」，而那不是「還沒被評過」，是這個數字從來
  /// 不存在。
  ///
  /// **由任務上的評分推導，不另存一個會漂移的數字。** 每則任務至多
  /// 一個評分，所以「幾則有評分」就是評分次數。
  ({double avg, int count}) get myRatingStats {
    final scored = mentorTasks
        .where((t) => t.apprenticeUid != null && t.rating != null)
        .map((t) => t.rating!)
        .toList();
    if (scored.isEmpty) return (avg: 0, count: 0);
    return (
      avg: scored.reduce((a, b) => a + b) / scored.length,
      count: scored.length,
    );
  }

  /// 把教官側的任務與問答從雲端讀回來（`[BE-15]`）。
  ///
  /// **在此之前 `MentorSource.tasks()` 與 `questions()` 一個呼叫端都沒有。**
  /// 學徒的提問寫進了 Firestore，教官永遠讀不到；學徒給的評分也一樣 ——
  /// 所以星等才會是 0。
  ///
  /// `data_source_wiring_test` 沒抓到這兩支：畫面上有個同名的
  /// `s.questions` 欄位，方法名撞到欄位名。
  Future<void> loadMentorSideOf(String apprenticeUid) async {
    final src = mentorSource;
    final bond = mentorBondIdFor(apprenticeUid);
    if (src == null || bond == null) return;

    try {
      for (final t in await src.tasks(bond)) {
        final at = mentorTasks.indexWhere((x) => x.id == t.id);
        final m = MentorTask(
          id: t.id,
          title: t.title,
          detail: t.detail,
          apprenticeUid: apprenticeUid,
          state: t.state,
          rewardCoins: t.rewardCoins,
          rating: t.rating,
        );
        if (at >= 0) {
          mentorTasks[at] = m;
        } else {
          mentorTasks.add(m);
        }
      }
      for (final q in await src.questions(bond)) {
        final at = questions.indexWhere((x) => x.id == q.id);
        final m = MentorQuestion(
          id: q.id,
          from: nameByUid[q.fromUid] ?? '學徒',
          apprenticeUid: apprenticeUid,
          text: q.text,
          at: q.at,
          answer: q.answer,
        );
        if (at >= 0) {
          questions[at] = m;
        } else {
          questions.add(m);
        }
      }
    } catch (_) {
      // 讀不到就維持現狀 —— 一次網路失敗不該把畫面上的任務清空。
      return;
    }
    notifyListeners();

    // 讀回來之後星等才算得出來，這時要把它發布出去。
    publishMyProfile();
  }

  /// 把我帶的每位學徒那一段都讀一次。登入後呼叫。
  Future<void> loadMentorSide() async {
    for (final a in apprentices) {
      final uid = a.uid;
      if (uid != null) await loadMentorSideOf(uid);
    }
  }

  /// 把**我當學徒**那一段讀回來（`[BE-15]` 漏掉的另一半）。
  ///
  /// ## 為什麼非有不可
  ///
  /// `loadMentorSide()` 跑的是「我帶的每位學徒」—— 一位學徒的
  /// `apprentices` 是空的，所以它什麼都不做。於是**學徒從來不會重讀
  /// 自己的問答**：他提的問題只有本機那一份，而教官的回答寫在雲端，
  /// 兩者之間沒有橋。
  ///
  /// 使用者 2026-09-29 實測：B 收得到提問（訊號那一半修好了），
  /// 而 **A 收不到回答** —— 重整幾次都一樣，因為沒有人去讀。
  ///
  /// 與 2K（教官資格的裁決回不到申請人）、2L（教官身分沒發布出去）
  /// 同一家族：**一邊接上了，另一邊沒有。**
  Future<void> loadMyApprenticeSide() async {
    final src = mentorSource;
    final bond = _apprenticeBondId;
    if (src == null || bond == null) return;

    try {
      for (final q in await src.questions(bond)) {
        final at = questions.indexWhere((x) => x.id == q.id);
        final m = MentorQuestion(
          id: q.id,
          from: displayName,
          // **空值＝這是我自己問的**（見 `isMyQuestion`）。
          // 我是學徒那一側，這一段底下的提問都是我問的。
          apprenticeUid: null,
          text: q.text,
          at: q.at,
          answer: q.answer,
        );
        if (at >= 0) {
          questions[at] = m;
        } else {
          questions.add(m);
        }
      }
      for (final t in await src.tasks(bond)) {
        final at = mentorTasks.indexWhere((x) => x.id == t.id);
        final m = MentorTask(
          id: t.id,
          title: t.title,
          detail: t.detail,
          // 同上：這一段是「我與我的教官」，任務是指派給我的。
          apprenticeUid: null,
          state: t.state,
          rewardCoins: t.rewardCoins,
          rating: t.rating,
        );
        if (at >= 0) {
          mentorTasks[at] = m;
        } else {
          mentorTasks.add(m);
        }
      }
    } catch (_) {
      // 讀不到就維持現狀 —— 一次網路失敗不該把畫面上的問答清空。
      return;
    }
    notifyListeners();
  }

  /// 以雲端的師徒關係為準（[BE-14]／[BE-15]）。
  ///
  /// **兩側都要處理。** 在此之前只看 `apprenticeUid == me`（我當學徒的
  /// 那一段）—— 教官側完全接不上，於是真實使用者當了教官之後，
  /// 學徒清單永遠是空的，而他明明收過徒。
  void applyCloudBonds(List<CloudBond> bonds) {
    final me = myUid;
    if (me == null) return;

    // --- 教官側：我帶的學徒 ---
    for (final b in bonds) {
      if (b.mentorUid != me) continue;
      // 已解除的關係不該讓學徒繼續留在名單上。
      if (b.state != MentorBondState.active) {
        apprentices.removeWhere((a) => a.uid == b.apprenticeUid);
        continue;
      }
      final name = nameByUid[b.apprenticeUid] ?? b.apprenticeName;
      final at = apprentices.indexWhere((a) => a.uid == b.apprenticeUid);
      final a = Apprentice(
        name: name,
        uid: b.apprenticeUid,
        rank: rankOf(name, uid: b.apprenticeUid),
        // 六維與近期訓練是對方的資料，這裡拿不到 —— 畫面要把
        // 「沒有資料」畫成沒有資料，不是拿我自己的頂上。
        ability: abilityOf(name, uid: b.apprenticeUid) ?? const {},
        recentWorkouts: const [],
      );
      if (at >= 0) {
        apprentices[at] = a;
      } else {
        apprentices.add(a);
      }
    }

    // --- 學徒側：我的教官 ---
    for (final b in bonds) {
      if (b.apprenticeUid != me) continue; // 只處理我當學徒的那一段
      // **在此之前這裡是 `nameByUid[...]`，查不到就 `continue`。**
      // 上面教官那一段寫的是 `nameByUid[...] ?? b.apprenticeName`——
      // 同一個決定寫在兩個地方，只有一處做對。
      //
      // 後果：`nameByUid` 是從公開檔案來的，而公開檔案是另一塊
      // 各自成敗的同步。那一塊慢了或失敗了，這裡就靜靜地跳過整段
      // 關係 —— 使用者看到的是「我的教官不見了」，而雲端好端端的。
      // 關係文件上本來就帶著 `mentorName`，不必倚賴另一塊同步。
      final name = nameByUid[b.mentorUid] ?? b.mentorName;
      if (name.isEmpty) continue;

      myInstructor = instructors.where((i) => i.name == name).firstOrNull ??
          Instructor(
            name: name,
            uid: b.mentorUid,
            // **在此之前這裡寫死 1。** 非示範帳號的 `instructors` 是空的，
            // 所以真實使用者的教官一律顯示 1 階 —— 那不是過期，是根本沒查。
            rank: rankOf(name, uid: b.mentorUid),
            reputation: kInstructorInitialReputation,
            apprentices: 0,
            apprenticeCap: kApprenticeCapInitial,
            ability: const {},
            specialties: const [],
            avgRating: 0,
            ratingCount: 0,
          );
      mentorReleasedAt = b.releasedAt;
      mentorReleaseReason = b.releasedReason;
      break;
    }
    // **空清單也算載到了。** 「雲端確實沒有關係」是一個答案，
    // 與「還沒問到」不同 —— 這支只在讀取成功之後才被呼叫。
    _mentorLoaded = true;
    notifyListeners();
  }
  late List<MentorTask> mentorTasks = demo ? buildMentorTasks() : [];

  /// 教官已指派師徒任務。
  /// Precondition：該教官的「已確認指導責任聲明版本」為現行版本。
  /// 教官已指派師徒任務。
  ///
  /// [apprenticeUid] **指派給哪位學徒**。在此之前沒有這個參數 ——
  /// 任務進一份共用清單，誰都不知道是給誰的，也就寫不上雲端
  /// （雲端的任務掛在特定師徒關係下）。
  void assignMentorTask(String title, String detail, {String? apprenticeUid}) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return;
    if (instructorDutyNeeded) return;
    final t = MentorTask(
      id: newId('mt'),
      title: title,
      detail: detail,
      apprenticeUid: apprenticeUid,
    );
    mentorTasks.insert(0, t);
    _pushMentorTask(t);
    notifyListeners();
  }

  /// 把一則任務寫上雲端，掛在**它所屬的那段關係**下。
  ///
  /// 教官指派的任務掛在「我與這位學徒」那段；學徒自己動的任務
  /// （完成、領獎、評分）掛在「我與我的教官」那段。
  void _pushMentorTask(MentorTask t) {
    final src = mentorSource;
    final bond = t.apprenticeUid == null
        ? _apprenticeBondId
        : mentorBondIdFor(t.apprenticeUid);
    if (src == null || bond == null) return;
    src.putTask(bond, _asCloudTask(t)).catchError((_) {});
  }
  late List<MentorQuestion> questions = demo ? buildQuestions() : [];
  late List<Apprentice> apprentices = demo ? buildApprentices() : [];

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
  /// **初始值取自已關注的人數**，不是 0 —— 示範帳號一開始就關注著三個人，
  /// 計數卻從零起算的話，個人頁寫「關注 3」、師徒解鎖清單寫「關注 尚未做過」，
  /// 同一件事兩個答案。不變條件：曾經關注的次數不會少於現在關注中的人數。
  ///
  /// **真帳號是 0。** 在此之前 [following] 沒跟著 [demo] 走，於是
  /// `AppState(demo: false)` 一開機就帶著三個假關注、`followTotal` 也是 3 ——
  /// 師徒解鎖清單裡的「關注」對每一個新帳號**預設就是做過了**。
  /// 這是「假資料撐著功能」的第五次（前四次見 PROGRESS 1N）。
  late int followTotal = following.length;

  /// 存檔還原用：解鎖旗標一經設定不可撤銷。
  void markMentorUnlocked() => _mentorUnlocked = true;

  bool isInstructor = false;
  InstructorStage instructorStage = InstructorStage.notApplied;

  /// AI 訓練品質評分。**空值＝還沒評過。**
  ///
  /// 在此之前這裡是寫死的 `qualityScore = 72`／`sanityScore = 68` ——
  /// 每一位申請人拿到的都是同一組數字，而那兩個數字決定他能不能申請。
  QualityScore? quality;

  /// 依訓練紀錄重算一次品質評分。**申請教官時呼叫。**
  ///
  /// 規格：重新申請時產生新的一筆教官申請並**重新評分**，不沿用舊的 ——
  /// 14 天只是最低重試間隔，數月後再申請時訓練紀錄已完全不同。
  /// 把本次訓練的開始時點往前挪 —— **只給測試用**。
  ///
  /// 獎勵有「不到 5 分鐘不發」的門檻（使用者裁決 2026-09-26），
  /// 而測試是 `startWorkout()` 之後立刻結束的，真實時間幾乎沒走。
  /// 不挪的話每一場都會被判成太短，而那不是這些測試要驗的東西。
  ///
  /// 用這個而不是 `advanceDemoClock()`：後者會動到 `now`，
  /// 在換日時點（04:00）附近會把日期一起推過去，連帶影響連續天數。
  @visibleForTesting
  void backdateSession(Duration by) {
    final w = session;
    if (w == null) return;
    w.startedAt = w.startedAt.subtract(by);
  }

  /// 我上次練這份課表是什麼時候。**依訓練歷史推導，不存欄位。**
  ///
  /// 在此之前官方課表的 `lastTrainedAt`／`lastCompletion` 是**寫死在
  /// `kPlans` 裡的**，而那份清單是平台給所有人的目錄 —— 於是一個從來
  /// 沒練過「拉日」的人會看到「上次訓練 5 天前　完成度 70%」。
  /// 使用者 2026-09-26 實測回報的正是這個。
  ///
  /// 自訂訓練那一側本來就是對的（結算時寫回 `customPlans`），
  /// 只有官方課表這一側拿了假資料頂著。
  ///
  /// 依**課表名稱**比對，因為 `HistoryEntry` 存的是名稱不是 ID。
  DateTime? lastTrainedOf(WorkoutPlan plan) =>
      _lastEntryOf(plan)?.date ?? plan.lastTrainedAt;

  /// 我上次練這份課表做了幾成。**沒有紀錄回空值**，畫面顯示「—」。
  ///
  /// 2026-09-26 之前結算的場次沒有存這個數字，所以舊紀錄仍然是空值 ——
  /// 那是誠實的：那幾場的完成度我們真的不知道。
  double? lastCompletionOf(WorkoutPlan plan) =>
      _lastEntryOf(plan)?.completion ?? plan.lastCompletion;

  /// 這份課表最近的一場。依**名稱**比對，因為訓練歷史存的是名稱不是 ID。
  ///
  /// **取日期最晚的那一場，不是清單裡的第一筆。**
  /// 原本是 `for (…) if (名稱相符) return h` —— 那依賴「訓練歷史一定是
  /// 新的在前」。2026-09-26 雲端的歷史順序真的反過來了一次
  /// （見 `store_firestore.dart` 的 `_lastHistoryLength`），
  /// 結果課表卡上的「上次訓練」顯示的是幾天前那一場、
  /// 「上次完成度」顯示「—」（舊場次沒存完成度）。
  ///
  /// 順序那個缺陷已經修了，但「最近的一場」本來就該由日期決定 ——
  /// 讓它依賴另一個地方的排序，是同一個決定寫在兩個地方。
  HistoryEntry? _lastEntryOf(WorkoutPlan plan) {
    HistoryEntry? best;
    for (final h in history) {
      if (h.planName != plan.name) continue;
      if (best == null || h.date.isAfter(best.date)) best = h;
    }
    return best;
  }

  QualityScore rescoreTrainingQuality({bool settle = false}) {
    final scored = scoreTrainingQuality(_sessionSummaries());
    quality = scored;
    // 端內規則算出來的分數**不推進初審** —— 規格要的是 AI 的評分，
    // 而 AI 失敗時申請維持在初審中等隔日重跑。
    // 只有「根本沒接雲端評分」那條路（`qualitySource` 為空）才在此結算，
    // 否則既有的一千多條測試會走不到初審通過。
    if (settle) _settleScreening();
    notifyListeners();
    return scored;
  }

  /// 還沒評過分。**畫面要據此顯示「尚未評分」，不是 0。**
  ///
  /// ## 為什麼不在打開頁面時先算一份
  ///
  /// 2026-09-26 我一度改成「讀到就算」，理由是使用者回報「練了 7 次
  /// 分數還是 0」。**那個修法違反規格的時序**，使用者當場指出來：
  ///
  /// `教官申請流程.md` 的順序是「使用者已申請教官權限」→ 系統初審
  /// （階級與累積訓練次數兩條門檻）→ 系統「分析歷史訓練品質」。
  /// 而且「本 Event 的請求識別碼 ＝ 使用者 ID ＋ **教官申請 ID**，
  /// 同一筆申請只評分一次」、「評分結果寫入教官申請 Aggregate，永久保存」。
  ///
  /// 也就是**評分屬於一筆申請，不屬於這個人**。沒有申請就沒有評分，
  /// 不是「評了但還沒看」。
  ///
  /// 原本的問題其實不是「沒算」，是**把「沒有分數」畫成了 0** ——
  /// 而 0 看起來像一個很低的分數。修法是把它畫成「尚未評分」。
  bool get qualityScored => quality != null;

  List<SessionSummary> _sessionSummaries() => [
        for (final h in history)
          SessionSummary(
            date: h.date,
            totalSets: h.totalSets,
            minutes: h.minutes,
            sets: [
              for (final e in h.exercises)
                for (final t in e.sets) t,
            ],
          ),
      ];

  /// 雲端的品質評分來源（Gemini）。**空值＝只走規則計算**，
  /// 與 `aiSource` 同一個形狀，既有測試零改動。
  QualityScoreSource? qualitySource;

  /// 評分失敗的原因。**開發者模式看得到。**
  ///
  /// 規格明訂 AI 中斷時「不直接駁回」——申請者本身無過失。所以失敗要
  /// 靜靜地退回規則，但**不能完全不說**：退回之後畫面上看到的分數
  /// 與模型算的長得一模一樣，出問題時毫無跡象。
  String? qualityScoreError;

  /// 向 Gemini 要一次評分，失敗就退回規則計算。
  ///
  /// **規則那一份是退路，不是備胎** —— 無論模型通不通，它都必須存在，
  /// 因為規格不允許因為平台的 AI 故障而駁回申請者。
  Future<QualityScore> rescoreTrainingQualityAsync() async {
    final src = qualitySource;
    if (src == null) return rescoreTrainingQuality(settle: true);

    try {
      final q = await src.score(_sessionSummaries());
      qualityScoreError = null;
      quality = q;
      _settleScreening();
      notifyListeners();
      return q;
    } catch (e) {
      // **失敗不改變申請狀態**（〈教官申請流程〉：「該教官申請維持在
      // 初審中，不通過亦不駁回」、「由排程於隔日重跑」）。
      // 申請者本身無過失，因平台的 AI 故障而駁回他，是把技術風險
      // 轉嫁給使用者。
      qualityScoreError = '$e';
      debugPrint('品質評分改用規則計算：$e');
      return rescoreTrainingQuality();
    }
  }

  /// 評分回來了 —— 初審該有結果了。
  ///
  /// **在此之前這個轉換根本沒有實作。** 申請人停在「初審中」，唯一的出路
  /// 是畫面上那顆「推進到下一階段（Demo）」—— 而那顆會跳過品質評分與測驗，
  /// 還以滿分送出考卷。使用者回報「教官申請是寫 Demo」。
  ///
  /// 規格：「[分支] 初審 / 測驗 / 管理員審核任一階段未通過
  /// → 教官資格已駁回」，而狀態值域是五值
  /// （初審中 / 待作答測驗 / 待人工審核 / 已通過 / 已駁回）。
  ///
  /// **只在「初審中」動作** —— 其餘階段重新評分不該把人踢回去。
  void _settleScreening() {
    if (instructorStage != InstructorStage.screening) return;
    instructorStage = instructorGate.passed
        ? InstructorStage.screenPassed
        : InstructorStage.rejected;
  }

  /// 這份分數是不是**暫時**的 —— 端內規則算的，還在等 AI。
  ///
  /// 使用者截圖回報：四項條件全部打勾（品質 77/60、合理性 90/40），
  /// 階段卻停在「初審中」。那不是矛盾 —— AI 評分失敗時留在初審中是規格
  /// 要求的，而畫面上那兩個分數是**端內規則算的備援值**，不是初審會採用
  /// 的那一份。打勾讓它看起來像已經通過了。
  ///
  /// 規格：「初審除階級與累積訓練次數門檻外，另須通過 **AI** 訓練品質評分」。
  bool get qualityIsProvisional =>
      quality != null && quality!.source != 'gemini' && qualityScoreError != null;

  /// 加權平均。**沒評過是 0** —— 畫面要先看 [qualityScored]，
  /// 把「沒有分數」畫成「尚未評分」而不是 0 分。
  int get qualityScore => quality?.weighted ?? 0;

  /// 「紀錄合理性」單項。受一票否決門檻檢核，與加權平均並存。
  int get sanityScore => quality?.sanity ?? 0;

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
  /// 某位教官**實際帶著幾位學徒**。
  ///
  /// ## 2026-09-29 使用者裁決：待回應的申請不再佔名額
  ///
  /// 原本的模型是「名額佔用數 ＝ 已建立的關係數 ＋ **申請中的申請數**」
  /// （〈師徒申請 Aggregate〉規則）。規格在團隊那一節特地對照過，
  /// 說兩者「刻意不一致」，理由是帶徒上限來自聲望、是稀缺的獎勵。
  ///
  /// 使用者指出的問題：**送出申請的當下數字就 +1，而對方還沒答應。**
  /// 更要緊的是那條規則讓一位申請人被**別人還沒被回應的申請**擋在門外，
  /// 而那些申請可能全部會被拒絕 —— 把「排隊」做成「佔位」，
  /// 代價落在最無辜的人身上。
  ///
  /// 超收不會因此發生：教官接受第 N+1 位的當下就被擋下
  /// （見 `inboundBlockedReason` 的 `apprenticeApply` 分支），
  /// 與團隊「超收由加入當下的 Precondition 擋下，不重複防守」同一套。
  ///
  /// [Instructor.apprentices] 是那位教官與**別人**的關係數（雲端讀來的），
  /// 所以我自己那一份要另外加 —— 它還沒反映在那個數字上。
  int apprenticeCountOf(Instructor i) =>
      i.apprentices + (myInstructor?.name == i.name ? 1 : 0);

  String? mentorApplyBlockedReason(Instructor i) {
    if (myInstructor != null) {
      return '一位學徒同時只能有一位教官，要先解除與 ${myInstructor!.name} 的師徒關係。';
    }
    // 先講「你已經送出了」再講「滿了」。
    //
    // 2026-09-29 之前我自己的申請也佔一格，順序反過來的話送出之後
    // 看到的會是「對方的帶徒名額已滿」，而那一格正是我佔的。
    // 申請不再佔名額之後這個順序仍然對：已經送出的人該看到的是
    // 「等對方回應」，而不是別人把名額佔滿了。
    if (mentorApplications.any((a) => a.name == i.name)) {
      return '已送出申請，等對方回應。';
    }
    if (apprenticeCountOf(i) >= i.apprenticeCap) return '對方的帶徒名額已滿。';
    return null;
  }

  /// 使用者已申請師徒關係。申請 7 天未回應即逾期，逾期釋放所佔用的帶徒名額。
  bool applyMentor(Instructor i) {
    // 社群功能停權（與永久停權）者不得執行社群互動 Command。
    if (communityBlocked) return false;
    if (mentorApplyBlockedReason(i) != null) return false;
    final expiresAt = now.add(const Duration(hours: 168));
    mentorApplications.add(PendingRequest(i.name, i.rank, expiresAt));
    final target = uidOf(i.name);
    final me = myUid;
    final src = mentorSource;
    if (target != null && me != null && src != null) {
      src
          .sendRequest(MentorRequest(
            id: newId('mr'),
            fromUid: me,
            toUid: target,
            fromName: displayName,
            fromRank: rank,
            // 我是學徒方 —— 這是拜師申請，不是教官的邀請。
            fromMentor: false,
            at: now,
            expiresAt: expiresAt,
          ))
          .catchError((_) {});
    }
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
    final q = MentorQuestion(from: displayName, text: text.trim(), at: now);
    questions.add(q);
    weeklyQuestionCount += 1;
    // **送到教官那邊去。** 在此之前提問只進本機清單 —— 學徒看得到自己
    // 問了什麼，教官那一側完全收不到，而雙方都不會看到任何錯誤。
    _pushMentor((src, bond) => src.ask(
          bond,
          CloudQuestion(
            id: newId('q'),
            fromUid: myUid ?? '',
            text: q.text,
            at: q.at,
          ),
        ));
    notifyListeners();
  }

  /// 教官已回答提問。
  ///
  /// **在此之前這個函式只有一個計數器** —— 回答的文字由畫面直接寫進
  /// `question.answer`，而且沒有任何雲端寫入，所以學徒永遠看不到。
  /// `MentorSource.answer()` 寫好了卻沒有人呼叫，正是 `[BE-15]`。
  bool answerQuestion(MentorQuestion q, String text) {
    final body = text.trim();
    if (body.isEmpty) return false;
    q.answer = body;
    q.answeredAt = now;
    weeklyAnswerCount += 1;

    final src = mentorSource;
    final bond = mentorBondIdFor(q.apprenticeUid);
    if (src != null && bond != null) {
      src.answer(bond, q.id, body, now).catchError((_) {});
    }
    notifyListeners();
    return true;
  }

  /// 本週已發放的師徒任務獎勵次數。**每週最多 3 次** ——
  /// 超過上限任務仍可正常完成，只是不再發經驗值與金幣。
  int mentorRewardsThisWeek = 0;

  bool get mentorRewardCapReached =>
      mentorRewardsThisWeek >= kMentorTaskRewardWeeklyCap;

  ({int exp, int coins})? claimMentorTask(MentorTask t) {
    if (t.state != MentorTaskState.done) return null;
    t.state = MentorTaskState.claimed;
    _pushTask(t);
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
    _pushTask(t);
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
  bool apprenticeRatesMe(String who, int stars,
      {bool weekly = false, String? uid}) {
    if (!isInstructor || !isValidStars(stars)) return false;
    final a = apprentices
        .where((a) => sameUser(a.name, a.uid, who, uid))
        .firstOrNull;
    if (a == null) return false;
    // **以 uid 為鍵。** 只用暱稱的話，學徒改名之後那個「每週最多 2 次」
    // 的上限會重新歸零 —— 而它是聲望的節流閥。
    final key = personKeyOf(a.name, a.uid);

    if (weekly) {
      if (!apprenticeWeeklyRated.add(key)) return false;
      _bumpReputation(kWeeklyInteractionReputationDelta[stars - 1]);
    } else {
      final n = apprenticeTaskRatings[key] ?? 0;
      // 超出上限者仍可評分，只是不計入聲望 ——
      // 該擋的是計分，不是行為。
      apprenticeTaskRatings[key] = n + 1;
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
    _pushTask(t);
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
    // 雲端那邊 release() 會把「解除」與「未完成任務作廢」包在同一批寫入，
    // 與這裡的兩步對應。
    final at = now;
    _pushMentor((src, bond) => src.release(bond, reason, at));
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
    // 雲端那一筆轉回生效中。**同一筆，不新建** —— 既有任務與問答的
    // 關係 ID 仍指向原筆。在此之前這行不存在，恢復只在本機生效：
    // 我這邊回到生效中，對方重整之後那段關係還是已解除。
    final at = now;
    _pushMentor((src, bond) => src.recover(bond, at));
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

  /// 解除 14 天重考鎖（**開發者模式專用**）。
  ///
  /// 2026-09-28 使用者測完 P3–P5 之後沒到 80%，被駁回並鎖 14 天。
  /// 他問「有沒有辦法跳過測驗進入待審核」—— **當下沒有**：
  ///
  /// - `advanceInstructorApplication()`（Demo 推進鍵）的階段清單裡
  ///   **沒有 `rejected`**，`indexOf` 回 -1 就直接 return，按了沒反應
  /// - `reapplyInstructor()` 擋在 `examRetakeLeft > 0`
  ///
  /// **開發者模式的逃生門，在最需要它的時候打不開。**
  ///
  /// 這一支只清掉時間鎖，**不改階段、不給分數** —— 解除之後仍要走
  /// 「重新申請 → 初審 → 測驗」的完整流程。14 天是真實時間，
  /// 而真實時間是測試唯一無法加速的東西。
  void clearExamRetakeLock() {
    lastExamAt = null;
    notifyListeners();
  }

  /// 抽一份考卷。**題庫不足時回空清單**（訊息見 [examBankWarning]）。
  ///
  /// 在此之前作答畫面是一個拉桿，申請人自己拉答對幾題，那個數字直接
  /// 被當成成績 —— 沒有出題，也沒有判卷。
  List<ExamQuestion> drawExam() =>
      drawExamPaper(examBank, platformConfig.i('exam', 'mcCount'));

  /// 抽簡答題。**題庫不足時回空清單。**
  List<ExamQuestion> drawShortAnswerQuestions() =>
      drawShortAnswers(examBank, platformConfig.i('exam', 'saCount'));

  /// 判卷。[answers] 是「題目 ID → 選了第幾個選項」，沒作答的算錯。
  int gradeExam(List<ExamQuestion> paper, Map<String, int> answers) =>
      gradeExamPaper(paper, answers);

  /// 這份考卷答錯了幾題必答題。
  int gradeMustPass(List<ExamQuestion> paper, Map<String, int> answers) =>
      missedMustPass(paper, answers);

  /// 使用者已作答教官測驗。
  ///
  /// 選擇題由系統即時判定，簡答題送管理員人工審核（時限 7 個工作天）——
  /// 故作答後停在「待人工審核」，不是當場放行。
  ///
  /// [correctCount] 由 [gradeExam] 算出來 —— **這支不自己判卷**，
  /// 因為既有測試直接給題數驗「答對 N 題會怎樣」，那一層與判卷無關。
  /// 這次作答**答錯了幾題必答題**。空值＝還沒考過。
  ///
  /// 與分數分開存：分數是程度，必答題是否決。混在一個數字裡的話，
  /// 「80% 但胸痛那題答錯」與「80% 關鍵題全對」會得到同一個結果。
  int? examMustPassMissed;

  bool submitExam(int correctCount,
      {int mustPassMissed = 0, List<(String, String)>? shortAnswers}) {
    if (instructorStage != InstructorStage.screenPassed &&
        instructorStage != InstructorStage.testing) {
      return false;
    }
    if (examRetakeLeft > Duration.zero) return false;
    lastExamAt = now;
    final total = platformConfig.i('exam', 'mcCount');
    examMcScore = (correctCount * 100 / total).round();
    examMustPassMissed = mustPassMissed;

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
        applicantUid: myUid,
        // AI 訓練品質評分。**目前仍是寫死的** —— 規格說它由系統依申請人的
        // 訓練紀錄算出（`02_Aggregate定義.md` 第 1475 行，Actor 為「系統」），
        // 而那個計算還沒實作。見 PROGRESS.md 第 5 節 0j。
        aiScores: const {'訓練完成率': 78, '訓練規律性': 84, '紀錄合理性': 71},
        weighted: 77.9,
        concerns: const [],
        // **簡答作答由呼叫端傳進來。** 在此之前這裡是兩題兩答的寫死內容 ——
        // 管理員看到的是申請人從來沒寫過的答案，然後據此發教官資格。
        // 空值＝沒有作答紀錄（既有測試直接叫 `submitExam(18)` 走這條）。
        answers: shortAnswers ?? const [],
        // ↓ 這一筆同時送上雲，見本函式末尾的 `_pushInstructorCase`。
        enteredAt: now,
      ),
    );
    _pushInstructorCase(instructorCases.first);
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
    // **重新評分，不沿用舊的**（規格：任何重試皆重跑 AI 訓練品質評分）。
    // 14 天只是最低重試間隔，數月後再申請時訓練紀錄已完全不同，
    // 沿用舊評分等於用過期資料判定。
    // 即發即忘：規格明訂本路徑**使用者不在場**（按完申請即離開）。
    rescoreTrainingQualityAsync();
    notifyListeners();
    return true;
  }

  /// 教官資格已駁回時攜帶的**駁回階段**：初審 / 測驗 / 管理員審核。
  ///
  /// 申訴機制未設時效上限，被駁回者申訴時管理員要看得出當初卡在哪一關。
  String? instructorRejectStage;

  int get examPassMark => platformConfig.i('exam', 'mcPass');
  /// 選擇題是否過關 —— **雙重條件**。
  ///
  /// 百分比擋不住必答題：20 題錯 4 題仍是 80%，而那 4 題可能正好是
  /// 「胸痛先休息一下」「未成年可以私下約」。
  bool get examMcPassed =>
      (examMcScore ?? 0) >= examPassMark && (examMustPassMissed ?? 0) == 0;

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
    // **把教官身分發布到公開檔案上。**
    //
    // 拜師頁跑的是 `instructors`，而那份清單由別人的公開檔案建出來
    // （`_applyInstructor` 讀 `p.isInstructor`）。不發布的話：
    // 這個人自己看到「我是教官了」，而**其他人的拜師頁上沒有他** ——
    // 也就是他當上了一個沒有人找得到的教官。
    //
    // 使用者 2026-09-29 實測撞到：B 通過審核（雲端 `state: passed`），
    // 而 B 的公開檔案 `isInstructor` 仍是 false，A 的教官清單裡沒有他。
    //
    // `myPublicProfile()` 本來就帶 `isInstructor`／`reputation`／
    // `apprentices`／`apprenticeCap`／`specialties` —— 缺的只是這一次發布。
    publishMyProfile();
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

    // 進「初審中」就評分 —— 那個狀態的定義就是「等 AI 產出訓練品質評分」。
    if (next == InstructorStage.screening) rescoreTrainingQualityAsync();

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

  late List<Conversation> conversations = demo ? buildConversations() : [];

  /// 我這一側看得到的對話。
  List<Conversation> get visibleConversations =>
      conversations.where((c) => !c.deletedByMe).toList();

  // --- 私訊上雲（[BE-14]）---

  /// 雲端的私訊。**空值代表不同步** —— 既有測試走這條。
  ChatSource? chatSource;

  /// 最近一次私訊送上雲失敗的原因。**畫面要講出來** ——
  /// 送不出去的訊息在畫面上與送出去的長得一模一樣，不講的話
  /// 使用者要等到重新載入、訊息消失了才知道，而那時已經無從追查。
  /// 讀過就清掉（[consumeChatSendError]）。
  String? chatSendError;

  String? consumeChatSendError() {
    final e = chatSendError;
    chatSendError = null;
    return e;
  }

  /// 這段對話在雲端的 ID。對方不在公開檔案裡（示範用的假使用者就是這種）
  /// 時回傳空值 —— 那段對話只存在本機。
  /// 這段對話在雲端的 ID。**優先用對話自己帶著的 uid**，
  /// 反查只是退路 —— 反查看的是已載入的公開檔案，查不到就整段跳過。
  String? _cloudConvId(Conversation c) {
    final src = chatSource;
    final me = myUid;
    final peer = c.peerUid ?? uidOf(c.peer);
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
        peerUid: peerUid,
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
              // **「已讀」問的是對方讀了沒，不是我讀了沒。**
              // 畫面只在 `fromMe && read` 時顯示已讀，所以這裡要看
              // 對方的 uid 在不在 `readBy` 裡。原本寫 `me` ——
              // 我送的訊息只要我自己開過對話就會標成已讀。
              read: m.readBy.containsKey(m.fromMeFor(me) ? peerUid : me),
              category: m.category,
              pendingReview: m.pendingReview,
            ),
        ],
      );

      final i = conversations.indexWhere((x) => x.peer == peerName);
      if (i < 0) {
        conversations.add(conv);
        continue;
      }
      // **就地更新，不換物件。**
      //
      // 原本是 `conversations[i] = conv` —— 但聊天頁是用
      // `ChatScreen(conversation: c)` 把那個物件**抓在手上**的。
      // 一換掉，開著的聊天頁手上那份就成了孤兒：之後打的字加進孤兒裡，
      // 畫面上看得到，清單與雲端都沒有；而雲端來的新訊息也永遠畫不出來。
      // 只要中途發生過任何一次重新整理，那段對話就壞在那裡。
      final live = conversations[i];
      live.deletedByMe = conv.deletedByMe;
      live.messages
        ..clear()
        ..addAll(conv.messages);
    }
    notifyListeners();
  }

  /// 開一段與這個人的對話 —— 已經有就用既有那段，沒有就開一段新的。
  ///
  /// 在此之前**沒有任何地方開得了新對話**：`conversations` 只從示範資料
  /// 或雲端來，於是「私訊」這件事只能回覆別人先發起的對話。
  ///
  /// 單方刪除過的對話會重新出現在我這一側：我主動要找他講話，
  /// 就不該還把它藏著 —— 對方那一側本來也沒被刪過。
  ///
  /// **不受新手任務閘門約束。** 規格鎖的是發文、按讚、留言、分享、關注
  /// 五項，私訊不在其中。封鎖與停權由呼叫端各自判斷。
  Conversation conversationWith(String name) {
    final i = conversations.indexWhere((c) => c.peer == name);
    if (i >= 0) {
      final c = conversations[i];
      if (c.deletedByMe) {
        c.deletedByMe = false;
        notifyListeners();
      }
      return c;
    }
    final conv = Conversation(
      id: _nextConversationId(),
      peer: name,
      // 這裡只有暱稱可用，反查是唯一的辦法 —— 但查到就釘在對話上，
      // 之後送訊息、標記已讀都不必再查一次。
      peerUid: uidOf(name),
      peerRank: rankOf(name),
      peerIsInstructor: instructors.any((x) => x.name == name),
    );
    conversations.add(conv);
    notifyListeners();
    return conv;
  }

  /// 本機對話 ID。雲端那一份的 ID 由兩個 uid 合成（見 [_cloudConvId]），
  /// 這裡只要在本機不撞號就好。
  String _nextConversationId() {
    var n = conversations.length + 1;
    while (conversations.any((c) => c.id == 'c$n')) {
      n++;
    }
    return 'c$n';
  }

  /// 使用者已刪除對話。單方刪除，對方仍可見；訊息本身不可刪除。
  void deleteConversation(Conversation c) {
    if (c.deletedByMe) return;
    c.deletedByMe = true;
    final id = _cloudConvId(c);
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

    final category = currentCategoryWith(c.peer, peerUid: c.peerUid);

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
    final peerUid = c.peerUid ?? uidOf(c.peer);
    final src = chatSource;
    final me = myUid;
    if (src != null && (peerUid == null || me == null)) {
      // 認不出對方是誰（或不知道我自己是誰）→ 訊息只存在我的記憶體裡，
      // 對方永遠收不到，而畫面上它就躺在那裡，看起來跟送出成功一模一樣。
      //
      // **`me` 為空時絕對不能硬送。** 原本寫的是 `senderUid: myUid ?? ''`，
      // 那會在雲端留下一則作者是空字串的訊息 —— 誰都認不出是我送的，
      // 於是它在雙方的畫面上都會畫成「對方傳來的」，靠左、灰色。
      _cannotIdentify('發送私訊', c.peer);
      chatSendError = me == null ? '還不知道我是誰（尚未完成登入同步）' : '認不出「${c.peer}」是誰';
    }
    if (peerUid != null && src != null && me != null) {
      src
          .send(
            peerUid,
            CloudMessage(
              id: newId('msg'),
              senderUid: me,
              text: body,
              at: now,
              category: category,
              pendingReview: v == FilterVerdict.flagged,
            ),
            myName: displayName,
            peerName: c.peer,
          )
          .catchError((Object e) {
        // **不能無聲。** 私訊送不出去，畫面上那則訊息照樣躺在那裡，
        // 看起來跟成功一模一樣 —— 直到重新載入才發現它不見了，
        // 而那時已經無從得知是哪一則、為什麼。
        chatSendError = '$e';
        reportSync('私訊送出', '失敗：$e');
        notifyListeners();
      });
    }

    if (v == FilterVerdict.flagged) {
      _openAutoFlagCase(
        targetKey: 'msg:${c.id}:${c.messages.length}',
        target: ReportTarget.message,
        content: body,
        accused: displayName,
        accusedUid: myUid,
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
    /// 被指的那個人的雲端身分。**記點與級距一律看它**（暱稱重構階段二）。
    /// 私訊對方那一路可能查不到，空值代表「這一案記不了點」。
    String? accusedUid,
  }) {
    if (reports.any(
        (r) => r.targetKey == targetKey && r.state == CaseState.pending)) {
      return;
    }
    // 自動過濾命中的也要上雲：它與使用者檢舉走同一個佇列，
    // 差別只在「來源」欄位（〈檢舉 Aggregate〉）。
    _pushReport(
      targetKey: targetKey,
      target: target,
      origin: CaseOrigin.autoFlag,
      content: content,
      reason: '自動過濾命中疑似違規',
      accused: accused,
      accusedUid: accusedUid,
    );
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
        // **這一行原本不在。** 自動開立的案件沒有 uid，
        // 於是它們永遠記不了點（`_recordViolation` 看的就是這個欄位）——
        // 管理員判成立、畫面說處罰了，而被指的人身上什麼都沒發生。
        accusedUid: accusedUid,
        accusedViolations: violationsOf(accusedUid, name: accused),
        enteredAt: now,
      ),
    );
  }

  void markRead(Conversation c) {
    final id = _cloudConvId(c);
    if (id == null) {
      // 只改記憶體的話，下次登入從雲端讀回來又會是未讀。
      if (chatSource != null) _cannotIdentify('標記已讀', c.peer);
    } else {
      chatSource!.markRead(id).catchError((_) {});
    }
    // **其餘欄位要原封不動搬過來。** 原本只帶 fromMe/text/at，
    // 於是 category 掉回預設的 normal —— 一打開陌生訊息，那段對話
    // 就跳到「一般訊息」分頁去了，而使用者只是讀了一下而已。
    // pendingReview 與 deleted 同理，那兩個是檢舉案件的依據。
    final updated = c.messages
        .map((m) => m.fromMe
            ? m
            : ChatMessage(m.fromMe, m.text, m.at,
                read: true,
                category: m.category,
                pendingReview: m.pendingReview,
                deleted: m.deleted))
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
  late List<Order> orders = demo ? buildOrders() : [];

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
        // **在這裡凍結，不在發放時回頭查商品** —— 管理員事後調整發放量
        // 不該回溯影響已成立的訂單。
        aiCredits: p.aiCredits * qty,
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
    // **真的把東西發出去。** 在此之前這裡只把訂單標成「已發放」，
    // 卻什麼都沒發 —— 使用者買了「AI 點數 ×10」，訂單顯示已發放，
    // 餘額卻一點都沒增加。
    if (o.aiCredits > 0) {
      aiPermanent += o.aiCredits;
      _logCredit(CreditChange.purchase, o.aiCredits, o.productName);
    }
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
  late List<CreditEntry> creditHistory = demo ? buildCreditHistory() : [];

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

  void _say(AiSource src, AiTurnRole role, String text,
      {AdjustSuggestion? suggestion, String? scope}) {
    aiConversations[src]!
        .add(AiTurn(role, text, now, suggestion: suggestion, scope: scope));
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
  /// 提出調整要求。
  ///
  /// [demand] 為空字串時不記錄使用者發言 —— 那是「開啟畫面即追問」
  /// 的入口（[aiOpen]），不是使用者真的說了什麼。
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
    // **空字串代表「開啟畫面就直接問」**，不是使用者說的話。
    // 原本一定要使用者先打一句才會進到追問，但那一句除了當脈絡之外
    // 沒有任何作用 —— 意圖仍限三選一。少一步就少一步。
    if (demand.trim().isNotEmpty) _say(src, AiTurnRole.user, demand);
    // 追問的作用是取得一個明確的**意圖**（三值列舉），建議才產得出來。
    // 接上 Gemini（`[BE-08]`）之後，使用者原本的那幾句話會連同意圖
    // 一起送給模型當脈絡（見 [_aiNote]）—— 但意圖本身仍限三選一，
    // 而伺服器端的逐項驗證在模型回話之後才跑，使用者寫什麼都越不過去。
    // **不說「了解。」** —— 開啟畫面就直接問了（見 [aiOpen]），
    // 前面沒有任何一句話可以「了解」。
    _say(src, AiTurnRole.ai,
        '${switch (src) {
          AiSource.beforeTraining => '這份課表',
          AiSource.planAdjust => '這份課表的動作',
          AiSource.duringTraining => '剩下的動作',
          AiSource.autoOptimize => '這份課表範本',
        }}要怎麼調？'
        '（${AdjustIntent.values.map((i) => adjustIntentNames[i]).join('／')}）');
    aiStage[src] = AiStage.clarifying;
    notifyListeners();
  }

  /// 使用者在這段對話裡自己打的話。
  ///
  /// **只取使用者說的，不含系統與 AI 的回話**，也濾掉「整體降強度」那種
  /// 單純在回答三選一的句子 —— 那已經表達成 [aiIntent] 了，再送一次
  /// 只是佔篇幅。截斷到 200 字：這是要送進 prompt 的外部輸入，
  /// 不設上限等於讓使用者決定 prompt 有多長。
  String? _aiNote(AiSource src) {
    final names = adjustIntentNames.values.toSet();
    final said = aiConversations[src]!
        .where((t) => t.role == AiTurnRole.user)
        .map((t) => t.text.trim())
        .where((t) => t.isNotEmpty && !names.contains(t))
        .join('\n');
    if (said.isEmpty) return null;
    return said.length > 200 ? said.substring(0, 200) : said;
  }

  /// 把雲端讀到的師徒申請收進待回應清單（`[BE-11]` 批次 5）。
  ///
  /// 與團隊請求同一個缺口：`MentorSource.requestsFor()` 有實作、有測試，
  /// 就是沒有人叫它 —— 送出的拜師申請寫進了 Firestore，教官永遠看不到。
  ///
  /// 方向由 `fromMentor` 決定：教官發起＝他邀我當學徒；學徒發起＝
  /// 有人想拜我為師。兩者在模型裡是不同的 [InboundKind]。
  /// 把**我自己送出去的**拜師申請讀回本機。
  ///
  /// ## 為什麼非有不可
  ///
  /// `applyMentor()` 把申請寫進了雲端，也把一筆放進 `mentorApplications`
  /// —— 但那份清單**不進存檔**，而登入時只讀「別人送給我的」
  /// （`requestsFor` 查 `toUid`）。於是重新整理之後：
  ///
  /// - 按鈕從「已申請」退回「申請師徒關係」
  /// - `mentorApplyBlockedReason()` 的「已送出」守衛跟著失效
  /// - 再按一次就再送一筆
  ///
  /// 使用者 2026-09-29 按了四次，雲端四筆。
  ///
  /// **整份取代而不是併入**：雲端是這件事的唯一事實。逾期的略過 ——
  /// 那一筆在對方那側也已經沒有效力了。
  void applyMySentMentorRequests(List<MentorRequest> cloud) {
    // **要顯示的是對方的名字，不是 `fromName`** —— 那是我自己
    // （我是送出的一方）。教官清單是唯一查得到對方階級的地方。
    PendingRequest toPending(MentorRequest r) {
      final ins = instructors.where((i) => i.uid == r.toUid).firstOrNull;
      return PendingRequest(
        ins?.name ?? nameByUid[r.toUid] ?? '（資料載入中）',
        ins?.rank ?? 0,
        r.expiresAt,
        uid: r.toUid,
      );
    }

    mentorApplications
      ..clear()
      ..addAll([
        for (final r in cloud)
          if (!r.fromMentor && !r.expiresAt.isBefore(now)) toPending(r),
      ]);
    notifyListeners();
  }

  void applyCloudMentorRequests(List<MentorRequest> cloud) {
    for (final r in cloud) {
      if (r.expiresAt.isBefore(now)) continue;
      receiveInbound(InboundRequest(
        id: r.id,
        kind: r.fromMentor
            ? InboundKind.mentorInvite
            : InboundKind.apprenticeApply,
        from: r.fromName,
        fromUid: r.fromUid,
        fromRank: r.fromRank,
        // 師徒兩向的 subject 都與 from 同值（見 `InboundRequest.subject`）。
        subject: r.fromName,
        sentAt: r.at,
      ));
    }
    notifyListeners();
  }

  /// 把雲端讀到的團隊請求分流進來（`[BE-11]` 批次 4）。
  ///
  /// **在此之前 `TeamSource.requestsFor()` 沒有任何呼叫端** —— 送出的
  /// 申請確實寫進了 Firestore，但收件的那一方從來不去讀，於是隊長
  /// 永遠看不到有人申請加入。與 `openTeams()` 一模一樣的缺口。
  ///
  /// 兩個方向進不同的地方，因為模型本來就分得很清楚：
  ///   · `isInvite` ＝ 隊長邀我入隊 → 我的待回應請求（[inbox]）
  ///   · 否則 ＝ 別人申請加入我的隊 → 那一隊自己的 [Team.applications]
  ///
  /// `InboundKind` 沒有「有人申請加入我的團隊」這個值，**那是對的** ——
  /// 它掛在團隊底下，不是掛在我身上；我卸任隊長之後那些申請仍屬於那支隊。
  void applyCloudTeamRequests(List<TeamRequest> cloud) {
    final t = myTeam;
    final me = myUid;

    // **我送出的申請以雲端為準，整份換掉。**
    //
    // `sentApplications` 不進存檔，重新載入就空了 —— 使用者看到的是
    // 「申請被自動取消」，其實雲端那筆還在，隊長也還看得到。
    // 反過來，隊長已經拒絕的那筆雲端已經沒有了，本機也該跟著消失，
    // 所以是整份換掉而不是補進去：存在本機只會兩邊對不齊。
    if (me != null) {
      sentApplications
        ..clear()
        ..addAll([
          for (final r in cloud)
            if (!r.isInvite && r.uid == me && !r.expiresAt.isBefore(now))
              // 這份清單裡的 name 是**隊名**（見 applyToTeam）。
              PendingRequest(r.teamName, r.rank, r.expiresAt,
                  uid: r.uid, teamId: r.teamId),
        ]);
    }

    for (final r in cloud) {
      if (r.expiresAt.isBefore(now)) continue; // 逾期的不收
      if (r.uid == me && !r.isInvite) continue; // 上面已經處理過
      if (r.isInvite) {
        receiveInbound(InboundRequest(
          id: 'ti-${r.teamId}',
          kind: InboundKind.teamInvite,
          from: r.name,
          fromUid: r.uid,
          fromRank: r.rank,
          // 團隊邀請的 subject 是**團隊名**，from 才是隊長。
          subject: r.teamName,
          sentAt: r.expiresAt.subtract(kInboundTtl),
        ));
      } else if (t != null && r.teamId == t.id) {
        // **以 uid 去重，不比暱稱。**
        //
        // 兩道閘門都會**靜默丟掉**那一筆申請，而「雲端讀到了卻不顯示」
        // 與「根本沒讀到」在畫面上長得一模一樣 —— T2 那條查了三輪
        // 就是這個形狀。用暱稱比的話：撞名的人申請會被當成重複而消失，
        // 改過暱稱的人退隊再申請也會對不上。
        //
        // 沒有 uid 的（示範資料）退回比暱稱。
        bool same(String? otherUid, String otherName) =>
            otherUid != null && r.uid.isNotEmpty
                ? otherUid == r.uid
                : otherName == r.name;
        if (t.applications.any((a) => same(a.uid, a.name))) continue;
        if (t.members.any((m) => same(m.uid, m.name))) continue;
        // **uid 一定要帶著。** 核准時要用它寫回雲端，靠名稱反查會失敗。
        t.applications
            .add(PendingRequest(r.name, r.rank, r.expiresAt, uid: r.uid));
      }
    }
    notifyListeners();
  }

  /// 把雲端讀到的公開團隊併進清單（`[BE-11]` 批次 4）。
  ///
  /// **在此之前 `TeamSource.openTeams()` 沒有任何呼叫端** —— 方法寫好了、
  /// 測試也有，就是沒有人叫它。於是真實帳號的「找團隊」永遠是空的：
  /// `publicTeams` 只從示範資料來，而那份對真實帳號是空清單。
  ///
  /// **排除自己已經在的那一隊** —— 它顯示在「我的團隊」，
  /// 再出現在「可加入的公開團隊」裡只會讓人以為自己沒加入。
  void applyPublicTeams(List<CloudTeam> cloud) {
    final mine = myTeam?.id;
    publicTeams
      ..clear()
      ..addAll([
        for (final t in cloud)
          if (t.id != mine && !t.disbanded)
            PublicTeam(
              t.name,
              t.members.length,
              t.capacity,
              id: t.id,
              isPublic: t.isPublic,
              peakSize: t.peakSize,
              members: [
                for (final e in t.members.entries)
                  TeamMember(e.value.name, e.value.rank, e.value.role,
                      uid: e.key),
              ],
            ),
      ]);
    notifyListeners();
  }

  /// 使用者執行「還原被替換的動作」（`01_Command清單.md`）。
  ///
  /// 三個 Precondition 一個都不能少（〈訓練紀錄流程〉）：
  /// 該動作為「AI 已替換動作」的結果、**該動作尚無任何已完成的組**、
  /// 且本次訓練尚未結算。
  ///
  /// **逐個還原，非整批**；且**不改動已落地的自訂訓練** ——
  /// 承既有裁決「訓練中的調整只改一次性的快照」。
  ///
  /// 已知風險（規格明載）：走到這條路的原因多半是器材不足，還原的原動作
  /// 有可能是他當下做不了的。**模型不阻擋**，由使用者自行判斷。
  bool restoreReplacedExercise(int index) {
    // 結算後 `session` 即為空值 —— 「本次訓練尚未結算」這個 Precondition
    // 由它表達，不另設旗標。
    final ss = session;
    if (ss == null) return false;
    if (index < 0 || index >= ss.exercises.length) return false;

    final pe = ss.exercises[index];
    final original = pe.replacedFrom;
    if (original == null) return false;

    // 做過任何一組就不給還原 —— 那些成績記在現在這個動作名下。
    final done = index < ss.records.length &&
        ss.records[index].any((r) => r.state == SetState.done);
    if (done) return false;

    ss.exercises[index] = PlanExercise(
      exercise: original,
      // 還原含各組的目標重量與次數（規格 Postcondition）。
      planned: [...(pe.replacedPlanned ?? pe.planned)],
      restSeconds: pe.restSeconds,
    );
    notifyListeners();
    return true;
  }

  /// 動作名稱的相鄰二字集合 —— 用來衡量「是不是同一類動作」。
  ///
  /// 「三頭肌下壓」→ `{三頭, 頭肌, 肌下, 下壓}`。
  /// 與「三頭肌伸展」重疊 2 個，與「二頭肌屈臂」只重疊 1 個。
  /// **器材那一段不算** —— 我們要找的正是「同一個動作換個器材」。
  static Set<String> _nameBigrams(String name) {
    final base = name.split(' · ').first.replaceAll(RegExp(r'[\s()（）]'), '');
    return {for (var i = 0; i + 1 < base.length; i++) base.substring(i, i + 2)};
  }

  /// 這個動作的替代候選 —— 同肌群、且目前器材做得到。
  ///
  /// **候選由前端算，不把 527 筆動作庫送進 prompt。** 那樣 prompt 會
  /// 爆炸，而且模型可能回一個不存在的動作；改成只送候選、要模型從中
  /// 挑一個，驗證就變成「挑的在不在候選裡」——滴水不漏。
  ///
  /// 依據是「持有器材明細」（`02_Aggregate定義.md` §1324）。
  ///
  /// ## 排序為什麼不能只看相對強度
  ///
  /// 2026-09-28 使用者打「今天沒有滑輪機可以用」，
  /// **三頭肌下壓 · 滑輪機** 被換成 **二頭肌屈臂 · 槓鈴** ——
  /// 推變成拉。那不是模型亂挑：候選清單是我們給的，而**送過去的
  /// 前五個全是二頭動作**。
  ///
  /// 原因是六維裡「手」是一維，三頭與二頭同屬 `Dim.arms`（依模型自己
  /// 的粒度那確實是同肌群），而排序只比相對強度 —— 二頭在 2.1、
  /// 三頭在 2.2，原動作 1.9。**差 0.1 就讓三頭訓練變成二頭訓練。**
  /// 候選池裡本來有 16 個三頭動作，一個都沒進前五。
  ///
  /// 所以先比名稱相似度（[_nameBigrams]），再比相對強度。
  /// 中文的動作名稱本來就把目標肌肉寫在裡面，那是現成的訊號。
  ///
  /// **這是權宜之計。** 真正乾淨的做法是動作庫多一個「細部肌群」欄位，
  /// 但那要動 CSV 與匯入腳本，且屬於資料決策。記在 `PROGRESS.md` 0S。
  List<Exercise> swapCandidatesFor(Exercise e, {int limit = 5}) {
    final have = availableEquipment;
    final want = _nameBigrams(e.name);
    int alike(Exercise x) => _nameBigrams(x.name).intersection(want).length;
    final pool = [
      for (final x in platformExercises)
        if (x.id != e.id &&
            x.dim == e.dim &&
            x.type == e.type &&
            () {
              final need = requiredEquipment(x.equipment);
              return need.isEmpty || need.every(have.contains);
            }())
          x,
    ];
    pool.sort((a, b) {
      // 名字越像的越前面 —— 同一個動作換個器材會排到第一。
      final byName = alike(b).compareTo(alike(a));
      if (byName != 0) return byName;
      // 一樣像，才比相對強度 —— 換動作不該順便換掉訓練強度。
      return (a.relativeIntensity - e.relativeIntensity)
          .abs()
          .compareTo((b.relativeIntensity - e.relativeIntensity).abs());
    });
    // [limit] 原本**寫了沒用** —— 函式回傳全部，兩個呼叫端各自
    // `.take(5)`。參數騙人比沒有參數更糟：它看起來已經把關了。
    return pool.take(limit).toList();
  }

  /// 送給模型的脈絡（`[BE-08]` 方案 A）。
  ///
  /// **這是 AI 能不能勝過一條規則的關鍵。** 在此之前模型只收得到動作
  /// 名稱與目標組數 —— 它知道的不比 `ai_adjust.dart` 那組規則多，
  /// 所以也做不出比它好的事。有了歷來成績，它才說得出
  /// 「你上次這個重量第三組只完成 6 下」這種規則講不出的話。
  ///
  /// **不含身分**：沒有暱稱、uid、電子郵件、生日。體重與性別有送 ——
  /// DOTS 標準化本來就靠它們。
  /// 測試接縫：`_aiContext` 是私有的，但**送出去的東西該長什麼樣**
  /// 正是要釘住的事（2026-09-28 漏送完成度就是這樣才發現的）。
  @visibleForTesting
  AdjustContext aiContextForTest(List<PlanExercise> target,
          {bool swap = false}) =>
      _aiContext(target, swap: swap);

  AdjustContext _aiContext(List<PlanExercise> target, {bool swap = false}) {
    final stats = exerciseStats;
    return AdjustContext(
      bodyweightKg: bodyweightKg,
      isMale: isMale,
      experience: experience,
      goal: commonGoal,
      equipment: ownedEquipment.toList(),
      recent: {
        for (final pe in target)
          if (stats[pe.exercise.id]?.trend.isNotEmpty ?? false)
            pe.exercise.name: [
              // 只取最近五次。再多對模型沒有幫助，卻讓 prompt 變長。
              for (final t in stats[pe.exercise.id]!.trend.reversed.take(5))
                (weight: t.weight, reps: t.reps),
            ].reversed.toList(),
      },
      // **最近幾場的完成度。** 一個 16 組只做 2 組的人需要的是減量，
      // 而那件事寫在完成度裡，不在重量與次數裡（見 `AdjustContext.sessions`）。
      // 只取最近五場 —— 再多對判斷沒有幫助，卻讓 prompt 變長。
      sessions: [
        for (final h in history.take(5))
          (plan: h.planName, completion: h.completion, minutes: h.minutes),
      ],
      candidates: {
        for (final pe in target)
          if (swap)
            pe.exercise.name: [
              for (final c in swapCandidatesFor(pe.exercise)) c.name,
            ],
      },
    );
  }

  /// 開啟調整畫面 —— 直接進到追問，不要求使用者先打一句話。
  ///
  /// **只在對話還是空的、且尚未開始時才動作。** 否則回到已經進行到
  /// 一半的對話會被重新問一次。
  void aiOpen(AiSource src) {
    if (aiStage[src] != AiStage.idle) return;
    if (aiConversations[src]!.isNotEmpty) return;
    aiRequest(src, '');
  }

  /// 從使用者的回答解析出意圖。**認不出來就回空值，不猜。**
  ///
  /// 原本認不出來時一律取「整體降強度」，理由是「三者中最保守，
  /// 猜錯的代價最小」。那個推論是錯的：使用者打「早安」也會換來一份
  /// 降強度的課表**並且被扣一點**，而他從頭到尾沒要求調整強度。
  /// 猜錯的代價不是保守與否，是**做了他沒要求的事還收了錢**。
  /// 值域原文的完全比對。四顆方向鍵送來的就是這個 ——
  /// 那不需要問模型，也不該因為模型掛掉而失敗。
  static AdjustIntent? _exactIntent(String answer) {
    final a = answer.trim();
    for (final i in AdjustIntent.values) {
      if (a == adjustIntentNames[i]) return i;
    }
    return null;
  }

  static AdjustIntent? parseIntent(String answer) {
    final a = answer.trim();
    for (final i in AdjustIntent.values) {
      if (a.contains(adjustIntentNames[i]!)) return i;
    }
    // 寬鬆比對。**三個方向都要有**：`easier` 原本是預設值，所以一條
    // 都沒有 —— 改掉預設之後，「想降強度」這種最自然的說法反而會
    // 變成「我看不懂」。
    //
    // **曖昧的詞一律不收。** 移除了原本的 `難`（「今天這個太難」是想
    // 降強度，判成升強度剛好相反）、`少` 與 `減`（「減強度」「少做一點
    // 重量」講的都不是組數）。認不出來就再問一次，那不丟臉；
    // 猜錯方向讓人照著練才是問題。
    // 換動作要排在最前面 —— 「換掉臥推」含「換」，而不含其他方向的詞，
    // 但先比對強度類的話，未來加詞容易誤判。
    //
    // **器材缺席要認得出來。** 使用者實測打「今天沒有啞鈴可以用」，
    // 而原本的條件只有 `沒有器材` 與 `器材不` —— 沒有人會說
    // 「我沒有器材」，他會說沒有**哪一樣**器材。系統回「我看不出你想
    // 往哪個方向調」，但那句話講得再清楚不過了。
    //
    // 器材名稱直接取自值域（`kEquipmentItems`），不自己再列一份 ——
    // 管理員在後台加了品項，這裡要跟著認得。
    //
    // **泛稱也要認得。** 2026-09-28 使用者打「我沒有任何器材」，
    // 而條件寫的是 `contains('沒有器材')` —— 中間插一個「任何」，
    // 整串比對就失效了。上一次的結論「沒有人會說我沒有器材」只對了
    // 一半：他確實不會單講「器材」，但他會講「任何器材」「所有器材」。
    //
    // 所以泛稱走與具體品項**同一條路**（否定詞 ＋ 名稱），
    // 而不是再加一串寫死的整句比對 —— 那種寫法下次換個副詞又會漏。
    const generic = ['器材', '設備', '裝備', '器械'];
    final missing = a.contains('沒有') || a.contains('沒') ||
        a.contains('壞') || a.contains('不能用') || a.contains('被占') ||
        a.contains('用不到') || a.contains('沒帶');
    if (missing &&
        (kEquipmentItems.any((e) => a.contains(e)) ||
            generic.any((g) => a.contains(g)))) {
      return AdjustIntent.swap;
    }
    if (a.contains('換') || a.contains('替代') || a.contains('做不了') ||
        a.contains('器材不')) {
      return AdjustIntent.swap;
    }
    // **2026-09-27 擴充了說法**（使用者：「希望能先判斷是否符合 4 個調整
    // 方向其中一項，不要什麼都擋」）。
    //
    // 擴充的原則沒變：**只收指向唯一方向的說法**。
    // 每加一個詞都要問「有沒有另一個方向的人也會這樣講」——
    // 有的話就不收，寧可再問一次。猜錯方向讓人照著練才是問題。
    //
    // 順序有意義：升在降之前（「不要太輕」含『輕』但講的是升），
    // 組數最後（「組」最容易被其他句子夾帶）。
    if (a.contains('升') || a.contains('加重') || a.contains('加強') ||
        // 「太輕」「不夠重」「重一點」—— 都只有升這一個解釋。
        a.contains('太輕') || a.contains('重一點') || a.contains('不夠重') ||
        a.contains('挑戰') || a.contains('加碼') || a.contains('更強') ||
        a.contains('狀況很好') || a.contains('狀態很好')) {
      return AdjustIntent.harder;
    }
    if (a.contains('降') || a.contains('輕') || a.contains('簡單') ||
        a.contains('緩') || a.contains('累') ||
        // 「太重」「吃力」「痠」「狀況不好」—— 沒有人用這些字要求加重。
        a.contains('太重') || a.contains('吃力') || a.contains('痠') ||
        a.contains('酸') || a.contains('疲') || a.contains('狀況不好') ||
        a.contains('狀態不好') || a.contains('保守') || a.contains('撐不住')) {
      return AdjustIntent.easier;
    }
    // 時間不夠 → 減少組數。這是最常見卻認不出來的那一類：
    // 使用者講的是「我只有 30 分鐘」，而不是「減少組數」。
    if (a.contains('時間不夠') || a.contains('趕時間') || a.contains('沒時間') ||
        a.contains('縮短') || a.contains('快點做完') || a.contains('提早')) {
      return AdjustIntent.trim;
    }
    if (a.contains('組')) {
      return AdjustIntent.trim;
    }
    return null;
  }

  /// **此刻**與某人的關係算一般訊息還是陌生訊息。
  ///
  /// 三種關係的定義只有這一份（`classifyMessage`），發送時與分區時共用。
  /// **「一般訊息」要的是互相關注**，不是我單方追蹤 ——
  /// 規格：「可直接發送私訊的對象：互相關注者、具師徒關係者、同團隊成員」。
  MessageCategory currentCategoryWith(String peer, {String? peerUid}) =>
      classifyMessage(
        mutualFollow: isFollowing(peer, uid: peerUid) &&
            isFollower(peer, uid: peerUid),
        mentorBond: myInstructor?.name == peer ||
            apprentices.any((a) => a.name == peer),
        sameTeam: myTeam?.members.any((m) => m.name == peer) ?? false,
      );

  /// 這段對話在清單裡歸哪一區。
  ///
  /// **訊息的分類於發送當下固定，規格明訂不回溯改寫**（〈聊天私訊流程〉）。
  /// 但「對話歸哪一區」是 Read Model 的事 —— 使用者回報
  /// 「追蹤後沒有從陌生訊息更新到一般訊息」，而在那之前 `bucket` 讀的是
  /// **最後一則訊息**的分類，所以關係轉正之後要等對方再傳一則才會移動。
  ///
  /// 改成「此刻的關係算一般 **或** 最後一則本來就是一般」——
  /// **只升不降**：曾經是隊友、後來退隊，那段對話不該被丟回陌生訊息區。
  MessageCategory bucketOf(Conversation c) =>
      currentCategoryWith(c.peer, peerUid: c.peerUid) == MessageCategory.normal ||
              c.bucket == MessageCategory.normal
          ? MessageCategory.normal
          : MessageCategory.stranger;

  /// 本次調整的意圖與建議，逐來源各一份。
  final Map<AiSource, AdjustIntent> aiIntent = {};
  final Map<AiSource, AdjustSuggestion> aiSuggestion = {};

  /// 這一輪有沒有真的扣過點。
  ///
  /// **[aiFail] 不能無條件退點。** 扣點的時機是「成功產出建議時」，
  /// 而失敗可能發生在那之前 —— 畫面上的「模擬逾時」就顯示在
  /// `analyzing` 階段，接了外部 API 之後網路錯誤也一樣。
  /// 沒扣卻退，使用者每失敗一次就白賺一點。
  final Map<AiSource, bool> aiCharged = {};

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

  /// 目前掛著優化建議的課表 ID。
  ///
  /// **這是使用者自己的資料，不是課表目錄的。**
  /// 在此之前只有 `platformPlans[i].hasOptimizationSuggestion` 這一個
  /// 記號，而那份清單是平台目錄 —— `applyPlatformData()` 每次登入都
  /// **整份重建**，記號當場蒸發；存檔也不含它，重新整理一樣沒了。
  ///
  /// 2026-09-28 使用者實測：訂閱後看不到「新的優化建議」標籤（P86）。
  /// 產生是產生了，只是活不過下一次重新整理。
  String? optimizedPlanId;

  /// 把 [optimizedPlanId] 的記號貼回課表目錄上。
  ///
  /// **`applyPlatformData()` 之後與載入存檔之後都要跑一次** ——
  /// 那兩個時機各自會把目錄換成一份沒有記號的新清單。
  void applyOptimizationMark() {
    final id = optimizedPlanId;
    if (id == null) return;
    final i = platformPlans.indexWhere((p) => p.id == id);
    if (i < 0) {
      // 課表被管理員下架了 —— 記號跟著失效，不要留一個指向空氣的 ID。
      optimizedPlanId = null;
      return;
    }
    if (platformPlans[i].hasOptimizationSuggestion) return;
    platformPlans[i] = _copyPlan(platformPlans[i], suggestion: true);
    if (currentPlan?.id == id) currentPlan = platformPlans[i];
  }

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
  ///
  /// **「最近練過」要從訓練歷史推**，不是讀 `WorkoutPlan.lastTrainedAt`。
  /// 那個欄位在 0k③（2026-09-26）之後對官方課表**永遠是空值** ——
  /// 當時把寫死在平台目錄裡的假日期移除了（那是「**我**上次練它是什麼
  /// 時候」，每個人各自不同，不該長在共用目錄上），但沒有回頭看誰在讀它。
  /// 於是這裡的排序整段失效，永遠退回「第一份官方課表」。
  WorkoutPlan? _autoOptimizeTarget() {
    final existing = aiOptimizePlan;
    if (existing != null) return existing;
    final official = platformPlans.where(
        (p) => p.source == PlanSource.official && p.exercises.isNotEmpty);
    if (official.isEmpty) return null;
    final used = official.where((p) => lastTrainedOf(p) != null).toList()
      ..sort((a, b) => lastTrainedOf(b)!.compareTo(lastTrainedOf(a)!));
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
    optimizedPlanId = plan.id;
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

  /// 直接打一次意圖分類，把結果或錯誤原樣回傳。**開發者模式的診斷鍵。**
  ///
  /// 在此之前要診斷 AI 通不通，得先開一場訓練、進調整畫面、打一句話，
  /// 然後回到設定頁看一個只在判定過之後才出現的欄位 ——
  /// 中間任何一步走岔，看到的都是「沒找到在哪看」。
  ///
  /// 這顆按鈕把那一串縮成一次點擊。
  Future<String> probeAiClassify([String say = '我等一下要趕去接小孩']) async {
    final ai = aiSource;
    if (ai == null) return 'aiSource 沒有接上（本機或測試環境）';
    final t = DateTime.now();
    try {
      final got = await ai.classify(say);
      final ms = DateTime.now().difference(t).inMilliseconds;
      return got.intent == null
          ? 'AI 回「判不出來」（${ms}ms）'
          : 'AI → ${adjustIntentNames[got.intent!]}（${ms}ms）';
    } catch (e) {
      final ms = DateTime.now().difference(t).inMilliseconds;
      return '失敗（${ms}ms）：$e';
    }
  }

  /// 最近一次診斷的結果。開發者模式顯示。
  String? aiProbeResult;

  /// 跑一次診斷並記下結果。
  Future<String> runAiProbe() async {
    aiProbeResult = '測試中…';
    notifyListeners();
    final r = await probeAiClassify();
    aiProbeResult = r;
    notifyListeners();
    return r;
  }

  /// 上一次意圖是誰判的。**開發者模式看得到。**
  ///
  /// 「AI 判的」與「AI 掛了退回關鍵字比對」在畫面上長得一模一樣 ——
  /// 而靜默退回在這個專案咬過五次。至少記下來。
  String? intentDecidedBy;

  /// 使用者已確認需求 → 系統呼叫 AI API 分析（AI 僅產出建議，不套用）。
  ///
  /// **2026-09-27 起先給 AI 判斷方向**（使用者裁決 B）。
  /// 端內的 [parseIntent] 只當 AI 掛掉時的備援 —— 它很保守，
  /// 曖昧一律不收，所以使用者打一句再自然不過的話常常換來一段
  /// 「我看不出你想往哪個方向調」。
  ///
  /// **保守的原則沒有變**：模型也被要求「只在明確指向唯一方向時才回答，
  /// 否則回 null」。交給模型是為了聽懂更多說法，
  /// 不是為了「無論如何給個答案」。
  /// 這一輪 AI 判讀有沒有掛掉。決定判不出來時要講哪一句話。
  bool aiUnavailable = false;

  /// 掛掉的原因是不是**額度用完**。
  ///
  /// 使用者實測拿到兩種：`429 You exceeded your current quota` 與
  /// `503 high demand`。**它們對使用者的意義完全不同** ——
  /// 忙線等一下再試就好，額度用完是今天不必再試了。
  /// 說同一句「AI 暫時忙不過來」，他會一直重試一件不會成功的事。
  bool aiQuotaExhausted = false;

  /// 這一段錯誤訊息是不是在講額度。
  ///
  /// 字串比對是醜的，但錯誤從 Worker 一路包到這裡本來就只剩字串，
  /// 而「429」與「quota」兩個線索同時出現時不會認錯。
  static bool looksLikeQuota(String e) =>
      e.contains('429') || e.toLowerCase().contains('quota');

  /// 正在請 AI 判讀方向。畫面靠它顯示「判讀中」。
  final Map<AiSource, bool> aiClassifying = {};

  Future<void> aiConfirmDemand(AiSource src, String answer) async {
    if (aiStage[src] != AiStage.clarifying) return;
    _say(src, AiTurnRole.user, answer);

    // 這一輪 AI 有沒有掛掉。影響的是**判不出來時要說哪一句話** ——
    // 「你講的不在四個方向裡」與「AI 暫時忙線」是兩件完全不同的事，
    // 而在此之前它們的回話一模一樣。
    aiUnavailable = false;
    aiQuotaExhausted = false;

    // 使用者直接點了那四顆方向鍵 —— 不必問模型。
    var intent = _exactIntent(answer);
    if (intent != null) {
      intentDecidedBy = '選項';
    } else {
      final ai = aiSource;
      if (ai != null) {
        // **先把畫面更新出來再去等網路。**
        //
        // 在此之前整段跑完才 `notifyListeners()` —— 於是使用者按下送出
        // 之後，連**他自己打的那句話**都不會出現，畫面完全靜止
        // 一秒多（AI 失敗時是二十秒）。他回報的「分析時間非常久，
        // 得不到答案」有一半是這個：不是真的那麼久，是完全沒有跡象。
        aiClassifying[src] = true;
        notifyListeners();
        try {
          intent = (await ai.classify(answer)).intent;
          intentDecidedBy = intent == null ? 'AI（判不出來）' : 'AI';
        } catch (e) {
          // **退回端內規則，而且要講出來**（只給開發者模式）。
          intentDecidedBy = '端內規則（AI 失敗：$e）';
          aiUnavailable = true;
          aiQuotaExhausted = looksLikeQuota('$e');
        } finally {
          aiClassifying[src] = false;
        }
      }
      // AI 沒接、或剛剛失敗 —— 用端內的關鍵字比對。
      intent ??= parseIntent(answer);
      intentDecidedBy ??= '端內規則';
    }

    if (intent == null) {
      // **不推進階段、不扣點、不產建議。** 寧可再問一次，也不要送出
      // 一份使用者沒要求的課表 —— 他會照著那份練。
      // **不說「我看不出你想往哪個方向調」。**
      //
      // 使用者實測打「我想多練上胸」，那句話講得再清楚不過了 ——
      // 系統看得懂，只是**不支援**。回他「我看不出」是把自己的限制
      // 說成他表達得不好。
      //
      // **數字由值域算出來，不寫死。** 原本寫「請從這三個裡挑一個」
      // 而後面列了四個 —— `AdjustIntent` 加了 `swap` 之後沒人回來改
      // 那兩個字。同一份清單同時決定「幾個」與「有哪些」，就不會再對不上。
      // **AI 掛掉與「不在四個方向裡」要講不同的話。**
      //
      // 2026-09-27 使用者實測：Gemini 回 503「模型忙線」，
      // 而畫面上顯示的是「目前只能往這 4 個方向調」——
      // 使用者只會以為是自己講錯話，不會知道系統剛剛壞了一下。
      _say(
          src,
          AiTurnRole.ai,
          aiQuotaExhausted
              ? '今天的 AI 額度已用完，沒辦法判讀你的需求。'
                  '直接挑一個方向：'
                  '${AdjustIntent.values.map((i) => adjustIntentNames[i]).join('／')}。'
                  '本次未扣點。'
              : aiUnavailable
              ? 'AI 暫時忙不過來，沒辦法判讀你的需求。'
                  '直接挑一個方向：'
                  '${AdjustIntent.values.map((i) => adjustIntentNames[i]).join('／')}。'
                  '本次未扣點。'
              : '目前只能往這 ${AdjustIntent.values.length} 個方向調：'
                  '${AdjustIntent.values.map((i) => adjustIntentNames[i]).join('／')}。'
                  '請挑一個。本次未扣點。');
      notifyListeners();
      return;
    }
    aiIntent[src] = intent;
    aiStage[src] = AiStage.analyzing;
    notifyListeners();
  }

  // --- 外部 AI（[BE-08]）---

  /// 外部的建議來源。**空值代表不接外部 API**，走端內規則 ——
  /// 既有測試全部走這條，行為與接上之前一模一樣。
  AiSuggestionSource? aiSource;

  /// 最後一次建議是誰產的。空值代表是端內規則產的。
  SuggestionOrigin? aiLastOrigin;

  /// 產生建議 —— 有接外部 API 就走它，沒接就走端內規則。
  ///
  /// **失敗一律走既有的 [aiFail]**：已扣的點數退還、維持原課表、
  /// 使用者看得到重試。那條路本來就在，這裡只是多了一個觸發它的理由。
  Future<void> aiProduceSuggestionAsync(AiSource src) async {
    final remote = aiSource;
    if (remote == null) {
      aiProduceSuggestion(src);
      return;
    }
    if (aiStage[src] != AiStage.analyzing) return;

    final target = _aiTarget(src);
    if (target.isEmpty) {
      _say(src, AiTurnRole.system, '這份課表還沒有動作，沒有東西可以調整。未扣點。');
      aiStage[src] = AiStage.idle;
      notifyListeners();
      return;
    }
    final from = src == AiSource.duringTraining ? (session?.exerciseIndex ?? 0) : 0;
    final intent = aiIntent[src] ?? AdjustIntent.easier;

    RemoteSuggestion got;
    try {
      got = await remote.suggest(
        exercises: target,
        intent: intent,
        onlyFrom: from,
        note: _aiNote(src),
        context: _aiContext(target, swap: intent == AdjustIntent.swap),
        candidates: intent == AdjustIntent.swap
            ? {
                for (final pe in target)
                  pe.exercise.name: swapCandidatesFor(pe.exercise),
              }
            : const {},
      );
    } catch (_) {
      // 逾時與服務錯誤在使用者眼裡沒有差別，都是「這次沒成功」。
      aiFail(src, AiFailReason.serviceError);
      return;
    }
    // 畫面可能在等待期間被關掉或重設。
    if (aiStage[src] != AiStage.analyzing) return;

    if (got.suggestion.changes.isEmpty || got.suggestion.isEmpty) {
      _say(src, AiTurnRole.system, '以目前的內容，這個方向沒有可調的空間。未扣點。');
      aiStage[src] = AiStage.idle;
      notifyListeners();
      return;
    }

    if (aiCostsCredit(src)) {
      spendAiCredit(aiSourceNames[src]!);
      aiCharged[src] = true;
    }
    aiLastOrigin = got.origin;
    // 伺服器退回規則時，逐筆是沒有理由的（規則只會算）。至少補上
    // 這條規則的訓練學依據 —— 使用者要的是「為什麼這樣改」，
    // 不是三行數字。
    aiSuggestion[src] = got.origin == SuggestionOrigin.rule
        ? AdjustSuggestion(
            intent: got.suggestion.intent,
            changes: got.suggestion.changes,
            rationale: adjustRationale[intent],
          )
        : got.suggestion;
    // **用標題區分來源，不另外加一個灰框。**
    //
    // 原本退回規則時會多一句「AI 分析暫時無法使用」—— 那句話對使用者
    // 沒有用（建議照樣可用），但**完全不留痕跡也不行**：靜默退回已經
    // 咬過這個專案四次，這次也是靠它才查出 `gemini-2.5-flash` 退役。
    //
    // 折衷：標題有沒有「AI」兩個字就是答案。不佔版面，也分得出來。
    final byModel = got.origin == SuggestionOrigin.gemini;
    // **帶著結構過去，不是只丟一段字串。**
    //
    // 原本這裡把整份建議拼成一大段文字（每筆之間空一行），再擠進一個
    // 寬 260 的對話泡泡 —— 使用者回報「AI 建議給的排版不好做閱讀」。
    // 而動作名、調整前後、替換動作、理由在 `AdjustChange` 裡本來就是
    // 分開的欄位，是渲染時才被拼掉的。
    //
    // `text` 仍然給一份可讀的純文字：對話紀錄要留得下來，
    // 而一段能唸出來的話比一個物件可靠。
    _say(src, AiTurnRole.ai,
        '${byModel ? 'AI ' : ''}建議如下（${adjustIntentNames[intent]}）：\n\n'
        '${aiSuggestion[src]!.changes.map((c) => '· ${c.detail}').join('\n\n')}\n'
        '${aiSuggestion[src]!.rationale == null ? '' : '\n${aiSuggestion[src]!.rationale}\n'}'
        '\n作用範圍：${aiSourceScope[src]}',
        suggestion: aiSuggestion[src],
        scope: aiSourceScope[src]);
    // **退回規則引擎時要說出來。** 不說的話，使用者看到的是一份
    // 看起來正常、其實沒經過模型的建議 —— 他只會覺得 AI 變笨了，
    // 而真正的原因躺在一個沒有人會去看的 log 裡。
    // 技術細節只給開發者模式。原始錯誤是 HTTP 狀態碼加一段 JSON，
    // 那是給我們查問題用的 —— 使用者看到 `"status": "NOT_FOUND"`
    // 只會更困惑，而且他手上那份建議本來就是可用的。
    if (developerMode && got.error != null) {
      _say(src, AiTurnRole.system, '〔開發者〕${got.error}');
    }
    aiStage[src] = AiStage.proposed;
    notifyListeners();
  }

  /// 自動優化：**系統自己判斷方向並產出建議**，不問使用者。
  ///
  /// 規格（`01_Command清單.md`〈AI 自動優化訓練流程〉）把「優化訓練強度」
  /// 的 Actor 寫成**系統** —— 流程裡只有「確認使用新訓練強度」與
  /// 「拒絕調整」兩個使用者 Command，沒有「挑方向」這一步。
  ///
  /// 2026-09-28 之前的實作把它接到訓練前調整的同一條追問流程上，
  /// 反過來問使用者要調哪個方向。那個差別不只是少一步：
  /// **訓練前調整是免費功能，自動優化是會員權益** ——
  /// 兩者都要人挑方向的話，付費買到的只是「幫你記得每三次提醒一次」。
  ///
  /// **不扣點**（會員權益），也**沒有規則退路**：判斷不出來就不掛，
  /// 下次再說。用一條 ×0.9 假裝成教練的判斷比不給更糟。
  Future<void> aiAutoPropose() async {
    const src = AiSource.autoOptimize;
    if (aiStage[src] != AiStage.idle) return;
    if (aiConversations[src]!.isNotEmpty) return;

    final target = _aiTarget(src);
    if (target.isEmpty) return;

    final remote = aiSource;
    if (remote == null) {
      // 沒接外部 AI —— 端內規則產不出「該升還是該降」的判斷，
      // 那不是一條 ×0.9 算得出來的東西。退回舊的追問流程，
      // 至少使用者挑得了方向。
      aiOpen(src);
      return;
    }

    aiStage[src] = AiStage.analyzing;
    notifyListeners();

    RemoteAutoAdjust got;
    try {
      got = await remote.suggestAuto(
        exercises: target,
        context: _aiContext(target, swap: true),
        candidates: {
          for (final pe in target)
            pe.exercise.name: swapCandidatesFor(pe.exercise),
        },
      );
    } catch (_) {
      if (aiStage[src] != AiStage.analyzing) return;
      aiStage[src] = AiStage.idle;
      _say(src, AiTurnRole.system,
          '這次沒能產出建議，稍後再試。建議標記還在，不會消失。');
      notifyListeners();
      return;
    }
    if (aiStage[src] != AiStage.analyzing) return;

    final sug = got.suggestion;
    final decided = got.intent;
    if (decided == null || sug == null || sug.changes.isEmpty || sug.isEmpty) {
      aiStage[src] = AiStage.idle;
      _say(src, AiTurnRole.ai,
          '這次看不出該往哪個方向調 —— 多練幾次、有了成績才說得出所以然。');
      notifyListeners();
      return;
    }

    aiIntent[src] = decided;
    aiLastOrigin = SuggestionOrigin.gemini;
    // 模型講得出「為什麼是這個方向」時，把那句話當成整份建議的依據 ——
    // 這正是自動優化與訓練前調整的差別：方向本身也要有理由。
    aiSuggestion[src] = got.why == null
        ? sug
        : AdjustSuggestion(
            intent: sug.intent, changes: sug.changes, rationale: got.why);
    _say(src, AiTurnRole.ai,
        'AI 建議如下（${adjustIntentNames[decided]}）：\n\n'
        '${aiSuggestion[src]!.changes.map((c) => '· ${c.detail}').join('\n\n')}\n'
        '${got.why == null ? '' : '\n${got.why}\n'}'
        '\n作用範圍：${aiSourceScope[src]}',
        suggestion: aiSuggestion[src],
        scope: aiSourceScope[src]);
    aiStage[src] = AiStage.proposed;
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
    if (aiCostsCredit(src)) {
      spendAiCredit(aiSourceNames[src]!);
      aiCharged[src] = true;
    }
    aiSuggestion[src] = suggestion;
    // 結構與純文字一起給 —— 理由見上面那一處（端內規則這條路也要表格）。
    _say(src, AiTurnRole.ai,
        '建議如下（${adjustIntentNames[intent]}）：\n\n'
        '${suggestion.changes.map((c) => '· ${c.detail}').join('\n\n')}\n'
        '${suggestion.rationale == null ? '' : '\n${suggestion.rationale}\n'}'
        '\n作用範圍：${aiSourceScope[src]}',
        suggestion: suggestion,
        scope: aiSourceScope[src]);
    aiStage[src] = AiStage.proposed;
    notifyListeners();
  }

  /// Demo：模擬 AI 逾時或服務錯誤。
  /// 失敗為已扣點後退還，與「拒絕」（根本未扣）不同。
  void aiFail(AiSource src, AiFailReason reason) {
    aiLastFailReason = reason;
    aiRetryCount += 1;
    // **只退真的扣過的那一點。** 扣點時機是「成功產出建議時」，
    // 而失敗可能發生在那之前（`analyzing` 階段的逾時、外部 API 的
    // 網路錯誤）—— 沒扣卻退，每失敗一次就白賺一點。
    final charged = aiCostsCredit(src) && (aiCharged[src] ?? false);
    if (charged) {
      // 退還不另立 Event
      aiMonthly += 1;
      _logCredit(CreditChange.refund, 1, aiSourceNames[src]!);
    }
    aiCharged[src] = false;
    _say(src, AiTurnRole.system,
        'AI 調整已失敗（${aiFailReasonNames[reason]}，已重試 $aiRetryCount 次）。'
        '維持原本次訓練課表，不套用任何調整。'
        '${charged ? '已扣的點數已退還，' : '本次未扣點，'}請稍後再試。');
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
    // 接受之後那一點就定了 —— 不該被之後任何一次失敗退掉。
    aiCharged[src] = false;

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
    optimizedPlanId = null;
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
    optimizedPlanId = null;
    platformPlans[i] = _copyPlan(plan, suggestion: false);
    if (currentPlan?.id == plan.id) currentPlan = platformPlans[i];
  }

  void aiReset(AiSource src) {
    aiConversations[src]!.clear();
    aiStage[src] = AiStage.idle;
    aiIntent.remove(src);
    aiSuggestion.remove(src);
    aiCharged[src] = false;
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

  late List<MailReward> mailbox = demo ? buildMailbox() : [];
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
  late Map<DateTime, CheckInMethod> checkInRecords =
      demo ? buildCheckInRecords() : {};

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
  /// 某一天距今幾天。
  ///
  /// **基準是營業日，不是日曆日。** 原本這裡用
  /// `DateTime(now.year, now.month, now.day)` —— 而 [makeupDaysInRange]
  /// 是從 `businessDate(now)` 往回數的。當地 00:00–03:59 那四個小時裡，
  /// 那兩個是不同的一天，於是整份補簽日曆的「距今天數」全部偏移一天：
  /// 使用者凌晨一點打開補簽頁，看到的日期與能補的日期對不起來。
  ///
  /// `clock.dart` 對 [businessDate] 的註解早就寫著這個後果
  /// （「那段時間以外完全看不出來」）—— 這是那一類漏洞的最後一處，
  /// 2026-09-19 由 02:13 的一次測試執行照出來。
  int daysAgo(DateTime d) => businessDate(now)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;

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
    // 寫回雲端 —— 不寫的話重新整理就變回「還沒申訴」，可以一直申訴。
    // 規則只讓當事人動這兩個欄位（`affectedKeys`）。
    if (punishmentSource case final src?) {
      if (myUid case final uid?) {
        src.markAppealed(uid, AppealState.pending).catchError((Object _) {});
      }
    }
    // 申訴為獨立 Aggregate，且進管理員的待審佇列。
    //
    // **案件 ID 帶著處罰的時戳。** 同一筆處罰只能申訴一次（規格），
    // 靠這個主鍵保證 —— 不是靠「送出前先查有沒有申訴過」，
    // 那在連按兩下時仍會寫出兩筆。一個人一生可能被罰好幾次，
    // 每一次各有一次申訴機會，所以不能只用 uid。
    final uid = myUid;
    final id = uid == null
        ? newId('AP-')
        : '${uid}__${p.issuedAt.millisecondsSinceEpoch}';
    final c = AppealCase(
      id: id,
      appellant: displayName,
      appellantUid: uid,
      target: AppealTarget.punishment,
      subject: punishmentKindNames[p.kind]!,
      reason: reason,
      filedAt: at,
      daysSinceIncident: at.difference(p.issuedAt).inDays,
    );
    appeals.add(c);

    // **在此之前這裡沒有任何雲端寫入。** 使用者寫了理由、按下送出、
    // 看到「已送出」，然後重新整理就沒了 —— 而且從頭到尾沒有任何
    // 管理員看得到。檢舉至少寫進了 Firestore（只是沒人讀），
    // 申訴連寫都沒寫。
    if (appealSource case final src?) {
      if (uid != null) {
        src
            .file(CloudAppeal(
              id: id,
              appellantUid: uid,
              appellantName: displayName,
              target: AppealTarget.punishment,
              subject: punishmentKindNames[p.kind]!,
              reason: reason,
              filedAt: at,
              daysSinceIncident: at.difference(p.issuedAt).inDays,
            ))
            .catchError((Object e) => reportSync('申訴', '送不出去：$e'));
      }
    }
    notifyListeners();
  }

  /// 雲端的申訴佇列。**空值代表不同步** —— 既有測試走這條。
  AppealSource? appealSource;

  /// 把雲端的申訴佇列讀進來。**只有管理員叫得動。**
  Future<void> loadAppealQueue() async {
    final src = appealSource;
    if (src == null || !isPlatformAdmin || !canReview) return;
    try {
      applyCloudAppeals(await src.queue(limit: 100));
    } catch (_) {
      // 讀不到就維持現狀。**不清空** —— 空佇列與讀取失敗長得一模一樣。
    }
  }

  void applyCloudAppeals(List<CloudAppeal> cloud) {
    for (final a in cloud) {
      final at = appeals.indexWhere((c) => c.id == a.id);
      final merged = AppealCase(
        id: a.id,
        appellant: a.appellantName,
        appellantUid: a.appellantUid,
        target: a.target,
        subject: a.subject,
        reason: a.reason,
        filedAt: a.filedAt,
        daysSinceIncident: a.daysSinceIncident,
        // 已在審視中的不要被重讀打回待審 —— 管理員可能正開著它。
        state: at >= 0 ? appeals[at].state : a.state,
        handlerName: at >= 0 ? appeals[at].handlerName : a.handlerName,
      );
      if (at >= 0) {
        appeals[at] = merged;
      } else {
        appeals.add(merged);
      }
    }
    // 等最久的排前面。
    appeals.sort((a, b) => a.filedAt.compareTo(b.filedAt));
    notifyListeners();
  }

  // ===========================================================================
  // 檢舉 → 處罰 → 申訴
  // ===========================================================================

  /// 雲端的檢舉佇列。**空值代表不同步** —— 既有測試走這條。
  ///
  /// 只有寫、沒有讀：檢舉是送出去給別人處理的，一般使用者不該讀得到
  /// 佇列本身（裡面有別人的違規內容與檢舉者身分）。
  ReportSource? reportSource;

  /// 教官申請案的雲端來源（`[BE-20]`）。
  ///
  /// **在此之前沒有這個東西**：`submitExam` 把案件放進申請人自己的
  /// `instructorCases`，而那份清單從來沒有離開過他的裝置 ——
  /// 管理員在另一台裝置上永遠看不到（見 PROGRESS 第 5 節 2I）。
  InstructorCaseSource? instructorCaseSource;

  /// 把一筆檢舉送上雲。即發即忘，但**失敗要留下痕跡** ——
  /// 使用者以為自己回報了，實際上沒有人收到，是這裡最糟的結果。
  void _pushReport({
    required String targetKey,
    required ReportTarget target,
    required CaseOrigin origin,
    required String content,
    required String reason,
    required String accused,
    String? accusedUid,
    String? note,
  }) {
    final src = reportSource;
    final me = myUid;
    if (src == null || me == null) return;
    src
        .file(CloudReport(
          id: targetKey,
          targetKey: targetKey,
          target: target,
          origin: origin,
          content: content,
          reason: reason,
          note: note,
          accused: accused,
          accusedUid: accusedUid,
          reporterUid: me,
          reporterName: displayName,
          at: now,
        ))
        .catchError((Object e) => reportSync('檢舉', '送不出去：$e'));
  }

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
    String? accusedUid,
    String? note,
  }) {
    final r = Reporter(
        name: displayName, reason: reason, note: note, at: now);

    // **併案與新案都要送。** 雲端是每位檢舉者各一筆，由管理端依
    // targetKey 分組 —— 在客戶端併案的話，第二位檢舉者必須先讀得到
    // 第一位那筆，而檢舉佇列正是一般使用者不該讀得到的東西。
    _pushReport(
      targetKey: targetKey,
      target: target,
      origin: CaseOrigin.userReport,
      content: content,
      reason: reason,
      note: note,
      accused: accused,
      // 暱稱會改、也會撞名 —— 記點一律看 uid。查不到就傳空值，
      // 案件仍然審得了，只是記不了點（管理端會標示）。
      accusedUid: accusedUid ?? uidOf(accused),
    );

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
        accusedUid: accusedUid ?? uidOf(accused),
        accusedViolations: violationsOf(accusedUid, name: accused),
        enteredAt: now,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 各使用者的累計違規次數。自己的存在 [myViolations]。
  ///
  /// **鍵是 uid，不是暱稱**（暱稱重構階段二，2026-09-28）。
  ///
  /// 在此之前這裡以暱稱為鍵，而 `_recordViolation()` 的註解早就寫著
  /// 「寫到暱稱底下的話，改名或撞名就記到別人頭上」—— 那句話講的是
  /// 雲端那一側，**本機這一份卻正是那樣做的**。
  /// 處罰級距依這個數字決定，記錯人就處罰錯人。
  ///
  /// 初值取自佇列中既有案件所記的累計次數 —— 級距一律依它決定，
  /// 若不灌入，所有人都會從 0 起跳而算成「警告」。
  /// **只灌有 uid 的**：沒有 uid 的舊案件本來就記不了點
  /// （`_recordViolation` 也是這樣擋的），灌進來只會製造一個
  /// 查得到卻寫不回去的數字。
  late final Map<String, int> _violations = {
    for (final c in reports) ?c.accusedUid: c.accusedViolations,
  };

  /// 某個人的累計違規次數。
  ///
  /// [uid] 是權威；[name] 只在**它就是我**時用得上（自己的存在
  /// [myViolations]，而自己的 uid 在沒登入的測試裡可能是空的）。
  int violationsOf(String? uid, {String? name}) {
    if (_isMe(name ?? '', uid)) return myViolations;
    return uid == null ? 0 : (_violations[uid] ?? 0);
  }

  /// 這一案該用哪個累計次數算級距。
  ///
  /// **取「現在查得到的」與「案件當初記下的」之中較大者。**
  ///
  /// 暱稱重構階段二把 `_violations` 改成以 uid 為鍵之後，
  /// **沒有 uid 的案件查出來一律是 0** —— 而級距依這個數字決定，
  /// 於是一個累犯第五次的人會被算成「警告」。
  /// `ReportCase.accusedViolations` 是檢舉建案當下記下的值，
  /// 那些案件只剩它可用。
  ///
  /// 取較大者而不是「查不到才用案件的」：兩位管理員同時裁決同一個人時，
  /// 本機查到的可能比案件當初記的還新。
  int violationsForCase(ReportCase c) => math.max(
        violationsOf(c.accusedUid, name: c.accused),
        c.accusedViolations,
      );

  /// 雲端的累計違規次數。**空值代表不同步** —— 既有測試走這條。
  ViolationSource? violationSource;

  /// 把自己的累計違規次數讀回來。
  ///
  /// **這個數字不在存檔裡，也不該在** —— 存檔是本人寫得動的，
  /// 而處罰級距靠它決定。登入時向 `violations/{uid}` 問一次。
  Future<void> loadMyViolations() async {
    final src = violationSource;
    final uid = myUid;
    if (src == null || uid == null) return;
    try {
      myViolations = await src.countOf(uid);
      notifyListeners();
    } catch (_) {
      // 讀不到就維持現狀。**往少的方向錯**比往多的方向錯好：
      // 這個數字只決定處罰級距，讀不到而少罰，勝過讀不到而多罰。
    }
  }

  /// 記一次違規並寫上雲。回傳寫完之後的次數（寫不上去就回本機推算的）。
  ///
  /// 在此之前 `_setViolations()` 對別人寫的是本機一個 Map，**哪裡都沒去** ——
  /// 管理員判了別人違規三次，對方那邊完全不知道，重開 App 還歸零。
  /// [local] 是呼叫端已經加好並寫進本機的那個數字 —— **這裡不再加一次**。
  /// （初版在這裡又加了一次，變成一次裁決記兩點。）
  Future<int> _recordViolation(ReportCase c, int local) async {
    final src = violationSource;
    final uid = c.accusedUid;
    // uid 缺席＝2026-09-25 之前送出的舊案件。審得了，但記不了點 ——
    // 寫到暱稱底下的話，改名或撞名就記到別人頭上。
    if (src == null || uid == null) return local;
    try {
      final cloud = await src.increment(uid, name: c.accused);
      _setViolations(uid, cloud, name: c.accused);
      notifyListeners();
      return cloud;
    } catch (_) {
      return local;
    }
  }

  void _setViolations(String? uid, int v, {String? name}) {
    if (_isMe(name ?? '', uid)) {
      myViolations = v;
      return;
    }
    // **沒有 uid 就不記。** 記到暱稱底下的話，那個人改名之後
    // 數字就跟著留在舊名字上，而下一個叫那個名字的人會繼承它。
    if (uid != null) _violations[uid] = v;
  }

  /// 管理員已審視檢舉。待審視 → 審視中，寫入處理中的管理員 ID。
  /// 審視中**不自動退回待審視** —— 未下判定即離開者，案件留在審視中。
  /// 每個案件對應到雲端的哪幾份文件。**一個標的可能有好幾位檢舉者。**
  final Map<String, List<String>> _reportDocIds = {};

  /// 把雲端的檢舉佇列讀進來。**只有管理員叫得動。**
  ///
  /// 在此之前使用者按的每一筆檢舉都寫進了 Firestore，而**沒有任何人讀它**
  /// —— `ReportSource` 只有 `file()`，連讀的方法都沒有。後台那一頁列的是
  /// 編出來的假案件（2026-09-24 已關掉），所以看起來一直都正常。
  Future<void> loadReportQueue() async {
    final src = reportSource;
    if (src == null || !isPlatformAdmin || !canReview) return;
    try {
      applyCloudReports(await src.queue(limit: 100));
    } catch (_) {
      // 讀不到就維持現狀。**不清空** —— 空佇列與讀取失敗長得一模一樣，
      // 而後者不該被畫成「沒有待審案件」。
    }
  }

  /// 併案：多人檢舉**同一標的**合併為同一案件（`02_Aggregate定義.md`）。
  ///
  /// 併案在這裡做而不是在資料層，因為它需要看到所有人的那幾筆 ——
  /// 而檢舉佇列正是一般使用者不該讀得到的東西。
  void applyCloudReports(List<CloudReport> cloud) {
    final byTarget = <String, List<CloudReport>>{};
    for (final r in cloud) {
      (byTarget[r.targetKey] ??= []).add(r);
    }

    for (final entry in byTarget.entries) {
      final rows = entry.value..sort((a, b) => a.at.compareTo(b.at));
      final first = rows.first;
      _reportDocIds[entry.key] = [for (final r in rows) r.id];

      final at = reports.indexWhere((c) => c.targetKey == entry.key);
      final merged = ReportCase(
        // 案件 ID 用標的 —— 併案之後「這一案」指的就是這個標的。
        id: entry.key,
        targetKey: entry.key,
        reporters: [
          for (final r in rows)
            Reporter(
                name: r.reporterName, reason: r.reason, note: r.note, at: r.at),
        ],
        target: first.target,
        origin: first.origin,
        // 內容與事由取**最早那一筆**：後來的檢舉者看到的是同一份內容。
        content: first.content,
        reason: first.reason,
        reporterCount: rows.length,
        accused: first.accused,
        accusedUid: first.accusedUid,
        accusedViolations: violationsOf(first.accusedUid, name: first.accused),
        enteredAt: first.at,
        // 已在審視中的案件不要被重讀打回待審 —— 管理員可能正開著它。
        state: at >= 0 ? reports[at].state : CaseState.pending,
        handlerName: at >= 0 ? reports[at].handlerName : null,
      );
      if (at >= 0) {
        reports[at] = merged;
      } else {
        reports.add(merged);
      }
    }
    // 等最久的排前面。
    reports.sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
    notifyListeners();
  }

  /// 裁決寫回雲端。即發即忘 —— 本機已經改了，寫失敗下次重讀會以雲端為準。
  void _pushVerdict(ReportCase c, {required bool upheld}) {
    final src = reportSource;
    final ids = _reportDocIds[c.targetKey];
    if (src == null || ids == null || ids.isEmpty) return;
    src
        .judge(ids, upheld: upheld, handlerName: admin.name)
        .catchError((Object _) {});
  }

  void reviewReport(ReportCase c) {
    if (!canReview) return;
    if (c.state != CaseState.pending) return;
    c.state = CaseState.reviewing;
    c.handlerName = admin.name;
    notifyListeners();
  }

  /// 檢舉成立 → 管理員已下架違規內容（帳號類除外）＋ 使用者已受處罰。
  /// 管理員僅判斷檢舉是否成立，**不裁量處罰種類與時長** —— 級距由階梯累犯制決定。
  UpholdOutcome upholdReport(ReportCase c) {
    if (!canReview) return const UpholdOutcome.refused('沒有內容審核權限。');
    if (c.state != CaseState.reviewing) {
      return const UpholdOutcome.refused('這一案不在審視中，不能裁決。');
    }
    c.state = CaseState.upheld;
    c.handlerName = null; // 案件轉入終止狀態時清空

    // 管理員已下架違規內容。**帳號類不走下架路徑** ——
    // 帳號不是一則內容，沒有可下架的標的。
    final removed = canTakeDownContent(c.target) ? _takeDown(c) : -1;

    // 記點。本機先加（畫面立刻反映），雲端寫完再以雲端那份為準 ——
    // 兩位管理員同時裁決同一個人時，本機推算會少算。
    final after = violationsForCase(c) + 1;
    _setViolations(c.accusedUid, after, name: c.accused);
    _issuePunishment(c, after);
    _pushVerdict(c, upheld: true);
    notifyListeners();
    _recordViolation(c, after);
    return UpholdOutcome(
      removed: removed,
      violationsAfter: after,
      // 沒有 uid 就寫不進 `violations/{uid}` —— 被檢舉者那一側
      // 永遠不會知道自己被記點（`CloudReport.accusedUid` 的註解寫著
      // 舊案件沒有這個欄位）。**那件事要講出來**。
      recordedForAccused: c.accusedUid != null,
    );
  }

  /// 管理員已下架違規內容。僅適用貼文 / 留言 / 私訊。
  ///
  /// 一律為**軟刪除**，資料保留 —— 內容本身是案件的證據，
  /// 硬刪除會使其後的申訴無從調閱當時被判違規的是什麼。
  /// 下架違規內容。
  ///
  /// **本機與雲端都要動。** 在此之前這裡只設了記憶體裡的 `deleted`：
  /// 管理員按下「成立」，自己畫面上那則消失了，雲端一個位元都沒動 ——
  /// **其他人照樣看得到**。而安全規則那一側也不允許管理員改別人的貼文，
  /// 所以就算接了寫入也會被拒絕。兩邊 2026-09-25 一起補。
  int _takeDown(ReportCase c) {
    final id = reportedId(c.targetKey);
    var hit = 0;
    switch (c.target) {
      case ReportTarget.post:
        for (final p in posts) {
          if (p.id == id) {
            p.deleted = true;
            hit++;
          }
        }
        _pushSocial((src, _) => src.markPostDeleted(id));
      case ReportTarget.comment:
        String? postId;
        for (final p in posts) {
          for (final m in p.comments) {
            if (m.id == id) {
              m.deleted = true;
              postId = p.id;
              hit++;
            }
          }
        }
        // 留言是貼文底下的子文件，要知道父層才寫得回去。
        // 找不到父層代表那則貼文不在本機這批裡 —— 只好留著本機的標記，
        // 下次重讀佇列還會看到這一案。
        if (postId case final pid?) {
          _pushSocial((src, _) => src.markCommentDeleted(pid, id));
        }
      case ReportTarget.message:
        // 檢舉入口在對話層級，鍵為對話 ID；下架的是**被檢舉的那一則**，
        // 不是整段對話 —— 一句違規不該連帶抹掉雙方所有往來。
        for (final conv in conversations) {
          if (conv.id != id) continue;
          for (final m in conv.messages) {
            if (m.text == c.content) {
              m.deleted = true;
              hit++;
            }
          }
        }
      case ReportTarget.account:
        break; // 帳號不走下架路徑，由 [upholdReport] 擋在前面
    }
    return hit;
  }

  /// 雲端的處罰狀態。**空值代表不同步** —— 既有測試走這條。
  PunishmentSource? punishmentSource;

  /// 把自己的處罰讀回來。
  ///
  /// **不在存檔裡，也不該在** —— 存檔是本人寫得動的，
  /// 被罰的人自己就能解除。登入時向 `punishments/{uid}` 問一次。
  Future<void> loadMyPunishment() async {
    final src = punishmentSource;
    final uid = myUid;
    if (src == null || uid == null) return;
    try {
      punishment = await src.of(uid);
      notifyListeners();
    } catch (_) {
      // 讀不到就維持現狀。**往「沒罰」的方向錯** ——
      // 一次讀取失敗不該把人鎖在門外。
    }
  }

  /// 開出一個處罰。
  ///
  /// **在此之前這支只在「被罰的是我自己」時才被呼叫** ——
  /// 也就是管理員只罰得到自己，判別人成立對方那邊什麼都沒發生。
  /// 現在對任何人都成立：本機那一份只在罰到自己時才動，
  /// 罰別人一律走雲端。
  void _issuePunishment(ReportCase c, int after) {
    final tier = tierForViolations(after);
    final p = Punishment(
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

    // 寫上雲。uid 缺席＝舊案件（2026-09-25 之前送出的），罰不了 ——
    // 理由同記點：寫到暱稱底下的話，撞名就罰到別人頭上。
    final src = punishmentSource;
    final uid = c.accusedUid;
    if (src != null && uid != null) {
      src.issue(uid, p, name: c.accused).catchError((Object _) {});
    }

    // 以下三件事只在**罰到自己**時才成立 —— 別人的信箱、別人的教官
    // 資格都不在這台裝置上。那幾件事要等對方登入時由雲端那份觸發。
    if (c.accused != displayName) return;

    punishment = p;
    // 已填電子郵件者，另以電子郵件通知處罰內容與 **30 天申訴期限**。
    _email('你的帳號已受處罰',
        '處罰：${punishmentKindNames[p.kind]}\n'
        '事由：${c.reason}\n'
        '你可於收到本通知起 30 天內提出申訴，同一處罰限申訴一次。');
    // 受處罰者具教官身分且處罰為**停權以上**者，教官資格一併撤銷；
    // 警告不撤銷 —— 讓剛被判定違規者繼續帶徒，處罰就沒有效果。
    if (isInstructor && isSuspension(p.kind)) {
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
    _pushVerdict(c, upheld: false);
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
    _pushAppealVerdict(c, upheld: true);

    // **後果要傳到當事人。** 撤銷處罰與退回違規次數都是改別人的文件，
    // 而那兩份都是管理員可寫、當事人唯讀 —— 在此之前這整段只在
    // `c.appellant == displayName` 時跑，也就是只撤銷得了自己的處罰。
    if (c.appellantUid case final uid?) {
      punishmentSource?.revoke(uid).catchError((Object _) {});
      violationSource?.decrement(uid).catchError((Object _) => 0);
    }

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
    _pushAppealVerdict(c, upheld: false);
    if (c.appellant == displayName) {
      punishment?.appealState = AppealState.dismissed;
      _email('申訴已駁回', '你的申訴經審視不成立，原處罰維持不變。');
    }
    notifyListeners();
  }

  /// 申訴裁決寫回雲端。即發即忘 —— 本機已經改了，寫失敗下次重讀以雲端為準。
  void _pushAppealVerdict(AppealCase c, {required bool upheld}) {
    final src = appealSource;
    if (src == null || c.appellantUid == null) return;
    src
        .judge(c.id, upheld: upheld, handlerName: admin.name)
        .catchError((Object _) {});
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

  late List<HistoryEntry> history = demo ? buildHistory() : [];

  /// 六維耐力值 —— **由 [history] 即時推導**（規格明訂衍生、不儲存）。
  ///
  /// 原本 `radar_screen` 自己編一個出來：六維點數乘上 0.72～0.94 的抖動
  /// 係數。那不只是假資料，它連語意都相反 —— 耐力值高的人是「相對重的
  /// 重量做很多下」，跟點數高低沒有那種比例關係。那是 `[QA-02c]` 的鄰居。
  ///
  /// 排除三種組：有氧（算不出 %1RM）、計時動作（無重量與次數）、
  /// 自建動作（不計入能力值，耐力值同理）。
  Map<Dim, double> get enduranceByDim {
    final rows = <EnduranceRow>[];
    for (final h in history) {
      for (final e in h.exercises) {
        final id = e.id;
        if (id == null || e.isTimed) continue;
        final x = exerciseById(id);
        final d = x.dim;
        if (d == null || x.isCustom || x.type == ExerciseType.cardio) continue;
        for (final s in e.sets) {
          rows.add((dim: d, exerciseId: id, weightKg: s.$1, reps: s.$2));
        }
      }
    }
    return enduranceOfRows(rows);
  }

  /// 每個動作的累積次數與趨勢 —— **由 [history] 即時推導**。
  ///
  /// 原本是 `mock/mock_exercise_stats.dart` 裡寫死的一張表：不管使用者
  /// 練了什麼，臥推永遠顯示「累積 41 次」、折線圖永遠從 7/12 的 50kg 開始。
  /// 那是 `[QA-02c]`。
  ///
  /// 每次呼叫重算一遍，不快取：訓練紀錄不長（一場約 6 個動作），
  /// 而快取要跟著補登、刪除、雲端回填一起失效 —— 那三條路都漏接過。
  /// **呼叫端請在 build 裡取一次就好**，不要每一列各取一次。
  Map<String, ExerciseStat> get exerciseStats => statsFrom([
        for (final h in history)
          for (final e in h.exercises)
            if (e.id != null) (date: h.date, id: e.id!, sets: e.sets),
      ]);

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
  ///
  /// **預設 true 是示範用身分的一部分**，與 `signUpCompleted` 同一個道理：
  /// 直接 `AppState()` 建出來的是那位階級 45、練過 63 場、關注著三個人的
  /// 假使用者，他當然早就做完新手任務了。原本預設 false，與那些數字
  /// 自相矛盾 —— 只是在 `[QA-02f]` 之前沒有任何畫面讀這個旗標，所以沒人發現。
  ///
  /// 真正的新帳號由 [resetToNewAccount] 設回 false，那是唯一會走到
  /// 「尚未解鎖」的路徑（`hydrate()` 讀不到存檔就會呼叫它）。
  bool socialUnlocked = true;

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

  /// 雲端的評分（`[BE-18]`）。**空值代表不同步** —— 既有測試走這條。
  RatingSource? ratingSource;

  /// 全平台的評分。**只有管理員讀得到**（安全規則擋在雲端那一側），
  /// 所以一般使用者身上這份永遠是空的。
  final List<ExperienceRating> adminRatings = [];

  /// 以雲端為準對齊我自己那一份（登入時）。
  ///
  /// **雲端有的以雲端為準，雲端沒有的留著並補送上去。**
  ///
  /// 原本這裡是「整份換掉」，理由是「在另一台裝置改過的評分才不會被
  /// 本機的舊值蓋回去」。那個理由對，但**代價被我漏算了**：
  /// 上傳失敗時雲端是空的，於是登入一次就把本機那筆也洗掉了 ——
  /// 使用者 2026-09-28 測 P127 回報「評分不見了」，那比「沒同步」更糟。
  ///
  /// 而且這裡本來就要處理一次遷移：`[BE-18]` 之前的評分只存在本機存檔裡，
  /// 雲端一筆都沒有。整份換掉等於把那些舊評分全部刪掉。
  void applyCloudRatings(List<ExperienceRating> cloud) {
    (RatingTarget, String) keyOf(ExperienceRating r) => (r.target, r.targetId);
    final fromCloud = {for (final r in cloud) keyOf(r)};
    // 本機有、雲端沒有的：留著，並補送一次。
    final orphans = [
      for (final r in experienceRatings)
        if (!fromCloud.contains(keyOf(r))) r,
    ];
    experienceRatings
      ..clear()
      ..addAll(cloud)
      ..addAll(orphans);
    for (final r in orphans) {
      _pushRating(r);
    }
    notifyListeners();
  }

  /// 管理員讀全平台的評分，填進 [adminRatings]。
  ///
  /// 分析用途、規格明訂**延遲更新**，所以是進後台時抓一批，不做即時訂閱。
  Future<void> loadAdminRatings({int limit = 500}) async {
    final src = ratingSource;
    if (src == null || !isPlatformAdmin) return;
    try {
      final rows = await src.all(limit: limit);
      adminRatings
        ..clear()
        ..addAll(rows);
      notifyListeners();
    } catch (_) {
      // 讀不到就維持現狀 —— 彙總表會顯示「還沒讀到」而不是一張空表。
    }
  }

  ExperienceRating? ratingFor(RatingTarget target, String targetId) {
    for (final r in experienceRatings) {
      // **以 uid 為準，暱稱只是退路**（舊存檔沒有 uid）。
      if (_isMe(r.rater, r.raterUid) &&
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
        raterUid: myUid,
        stars: stars,
        feedback: feedback,
        at: now,
      ));
    }
    // **即發即忘。** 這份資料的讀者是管理員、用途是分析，而規格明訂
    // 延遲更新 —— 為了一次網路失敗擋住使用者按「送出評分」，
    // 換來的是他乾脆跳過不評，那才是真正的損失。
    _pushRating(ratingFor(target, targetId)!);
    notifyListeners();
    return true;
  }

  /// 送一筆評分上雲。**失敗要留下痕跡。**
  ///
  /// 原本這裡是 `catchError((_) {})` —— 吞得乾乾淨淨。
  /// 2026-09-28 評分一筆都沒寫上去（安全規則把 `stars` 擋掉了），
  /// 而畫面說「已送出評分」、開發者模式也看不出任何異狀，
  /// 只能靠翻雲端才知道。**這是本專案第三次犯同一個錯**
  /// （前兩次：`quotaHint`、`inboundFailure`）。
  void _pushRating(ExperienceRating r) {
    final src = ratingSource;
    if (src == null) return;
    src.put(r).then((_) {
      ratingSyncError = null;
    }).catchError((Object e) {
      ratingSyncError = '$e';
      notifyListeners();
    });
  }

  /// 上一次評分寫不上雲的原因。**空值代表沒問題。**
  /// 開發者模式的同步報告會顯示它。
  String? ratingSyncError;

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
  ///
  /// 示範身分用的是寫死的 `kCurrentAdmin`（三種權限全開），
  /// 真實帳號則由 [applyAdminClaim] 依 Firebase Auth 的 custom claim 建出來。
  Admin admin = kCurrentAdmin;
  bool adminMode = false;

  /// Firebase Auth 的 `admin` custom claim。**這是唯一的判準。**
  ///
  /// `firestore.rules` 的 `isAdmin()` 看的就是 `request.auth.token.admin`，
  /// 所以畫面上的判斷必須與它同源 —— 不然會出現「後台進得去、
  /// 每個寫入都被規則擋下」那種最難查的狀態。
  ///
  /// **在此之前根本沒有這個欄位。** `admin` 是寫死的假管理員，
  /// `adminMode` 這個開關全 App 沒有任何地方切換它，後台只掛在
  /// 開發者模式的「流程示範」底下 —— 也就是任何人長按三秒都進得去，
  /// 而真正的管理員沒有入口。
  bool adminClaim = false;

  /// 我是不是平台管理員。
  bool get isPlatformAdmin =>
      adminClaim && admin.status == AdminStatus.active;

  /// 套用登入時拿到的 custom claim。
  ///
  /// [scopes] 為 claim 裡的 `adminScopes`（權限組名稱陣列）。**沒給就是三種全開**
  /// —— 規則那一側只認得 `admin == true`，分不出權限組；畫面上比規則嚴格
  /// 是可以的（少給），比規則寬鬆才是問題。
  void applyAdminClaim(bool isAdmin, {List<String>? scopes}) {
    adminClaim = isAdmin;
    if (!isAdmin) {
      adminMode = false;
      notifyListeners();
      return;
    }
    final parsed = <AdminScope>{
      for (final name in scopes ?? const <String>[])
        ?AdminScope.values.where((v) => v.name == name).firstOrNull,
    };
    admin = Admin(
      id: myUid ?? admin.id,
      name: displayName,
      scopes: parsed.isEmpty ? AdminScope.values.toSet() : parsed,
    );
    notifyListeners();
  }

  // 後台的待審佇列與名冊。**`demo ? ... : []`** —— 與 `posts`／`socialUsers`
  // 同一個開關。在此之前這七份全都沒有開關，於是真管理員會看到一批
  // 編出來的檢舉、申訴、教官審核案件，並對它們做裁決。
  // （`ratingSummaries` 是同一個毛病，2026-09-24 一起修。）
  late List<ReportCase> reports = demo ? buildReports() : [];
  late List<AppealCase> appeals = demo ? buildAppeals() : [];
  late List<InstructorCase> instructorCases =
      demo ? buildInstructorCases() : [];
  // ===========================================================================
  // 自訂訓練 Aggregate —— 使用者端的管理頁與管理員端的待審佇列讀同一份
  // ===========================================================================

  /// 自訂訓練。**示範資料裡有 3 份 `isMine: false` 的別人的課表**，
  /// 而 [resetToNewAccount] 刻意只清「我的」（它保留的是「這個世界」）——
  /// 於是那 3 份會經 [selectableCustomPlans] 的「全平台已公開」那一類
  /// 出現在課表選擇頁。這是 `[QA-02e]` 清查時漏掉的第 17 個集合。
  late List<CustomPlan> customPlans = demo ? buildCustomPlans() : [];

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
    // `CustomPlan` 身上沒有 `authorUid`，只能由暱稱反查 —— 這是退路，
    // 作者改名之後就查不到了（暱稱重構階段四的範圍）。
    return p.visibleToFollowers && isFollowing(p.author);
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


  late List<PublicPlanCase> publicPlanCases =
      demo ? buildPublicPlanCases() : [];
  late List<AdminProduct> adminProducts = demo ? buildAdminProducts() : [];
  late List<AdminOrder> adminOrders = demo ? buildAdminOrders() : [];
  /// 管理員評分彙總（`04_ReadModel清單.md`）。
  ///
  /// **`demo ? ... : []`** —— 與 `posts`／`socialUsers`／`instructors` 同一個
  /// 開關。在此之前這裡沒有開關，於是**真實的管理員會看到一張編出來的
  /// 評分表**：幾份訓練計畫、各自的平均星等與則數，全都是假的。
  ///
  /// 而這張表的用途正是回答「哪一份訓練計畫該改」。給錯的數字比給空白
  /// 更糟（守則第 5 條）—— 空白會被看見，錯的不會。
  ///
  /// **真實資料還沒接上**：使用者的評分存在 `users/{uid}` 的存檔裡，
  /// 而那棵樹依 `firestore.rules` 只有本人讀得到。要讓管理員看得到，
  /// 評分必須獨立成自己的 collection（規格本來就說它是獨立 Aggregate，
  /// 理由正是「管理員評分彙總需要逐筆下鑽查詢」）。見 `[BE-18]`。
  late final List<RatingSummary> _demoRatingSummaries =
      demo ? buildRatingSummaries() : [];

  /// 〈Read Model：管理員評分彙總〉。
  ///
  /// **讀到雲端資料就用雲端的**（`[BE-18]`）。在此之前這裡只有示範資料，
  /// 真的管理員永遠看到一張空表 —— 而評分收集了卻沒有用途。
  List<RatingSummary> get ratingSummaries => adminRatings.isEmpty
      ? _demoRatingSummaries
      : summarizeRatings(adminRatings, ratingTargetLabel);

  /// 評分對象翻成看得懂的名字。查不到就退回 ID —— 課表被下架之後
  /// 它的評分還在，那時候寫 ID 比寫「未知」有用（管理員查得回去）。
  String ratingTargetLabel(RatingTarget target, String targetId) {
    if (target == RatingTarget.noviceTask) return '新手任務';
    return planSpecById[targetId]?.name ??
        platformPlans.where((p) => p.id == targetId).firstOrNull?.name ??
        targetId;
  }

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
    // **規格也要改。** `applyPlatformData` 會用 `planSpecById` 重建整份
    // `platformPlans`（見該函式），只改上面那一份的話，下一次載入雲端資料
    // 就把這次的設定洗掉了 —— 而那看起來會像「雲端沒寫進去」。
    // 七份示範用假課表（`kPlans`）沒有對應的規格，那是正常的，跳過即可。
    if (planSpecById[p.id] case final spec?) {
      planSpecById[p.id] = spec.withConfig(
          requiredRank: requiredRank, unlockCoins: unlockCoins);
    }
    notifyListeners();
    return null;
  }

  /// 一份平台課表的規格。
  ///
  /// **`[BE-12b]`：這是第五個、也是最後一個補上寫回路徑的平台集合。**
  /// 它比另外四個晚，因為後台改的 `unlockCoins` 原本不在
  /// [PlatformPlanSpec] 上，寫回去會被靜靜丟掉。
  ///
  /// 示範用假課表（`kPlans`）沒有規格，也不該有 —— 它們不在雲端。
  /// 回一句話而不是默默成功：後台看得到那七份，改了卻不會上雲，
  /// 不講的話就是又一次「改了以為有效」。
  Future<String?> pushPlanSpec(String planId) {
    final spec = planSpecById[planId];
    if (spec == null) {
      return Future.value('這是示範用的課表，不在雲端 —— 改動只留在本機。');
    }
    return pushPlatform('plans', planId, planSpecToMap(spec));
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
  /// 順序：平台課表（四份官方 ＋ 27 份 CSV）→ 示範課表 → 空白課表。
  /// 空白課表**固定在最後** —— 它是入口不是內容，排在前面會擋住真的課表。
  late List<WorkoutPlan> platformPlans = [
    ...buildCsvPlans(),
    if (demo) ...kDemoPlans,
    ...kPlans,
  ];

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
  /// 雲端的平台資料。**空值代表不同步** —— 既有測試與示範走這條。
  ///
  /// 在此之前這個來源只有 `AuthGate` 握著（讀完就丟），所以「管理員改了
  /// 什麼」寫不回去。使用者 2026-09-28 測 P123 當場撞到。
  PlatformDataSource? platformSource;

  /// 把管理端改過的一筆寫回雲端。**回傳失敗的說明；null 表示成功。**
  ///
  /// **不即發即忘。** 關注、貼文那些可以晚一點一致，因為使用者當下看得到
  /// 自己按了什麼；後台不一樣 —— 管理員改完就走了，而下次登入會從雲端
  /// 重新載入，寫不上去的設定會**靜靜地**打回原形。那正是 P123 的症狀。
  ///
  /// 沒接雲端（測試、示範）時回 null —— 記憶體已經改好了，那就是全部。
  Future<String?> pushPlatform(
      String collection, String docId, Map<String, dynamic> data) async {
    final src = platformSource;
    if (src == null) return null;
    if (_notReallyAdmin case final why?) return why;
    try {
      await src.put(collection, docId, data).timeout(_cloudWriteTimeout);
      return null;
    } catch (e) {
      return '已改在本機，但沒有寫上雲（$e）。重新整理後會打回原形。';
    }
  }

  /// 雲端寫入等多久才放棄。
  ///
  /// **不能無限等。** Firestore 的用戶端會把寫入排進本地佇列，
  /// 被安全規則擋下時那個 Future 可能一直不完成 —— 畫面於是卡在
  /// 「等雲端回覆」，連失敗訊息都吐不出來，看起來就像什麼都沒發生。
  static const _cloudWriteTimeout = Duration(seconds: 8);

  /// 「看起來是管理員，但雲端不認」的那句話；null 表示沒這個問題。
  ///
  /// `adminMode` 是開發者模式長按三秒就開得了的旗標，而
  /// `firestore.rules` 的 `isAdmin()` 看的是帳號上的 custom claim。
  /// 兩者不一致時後台每一頁都點得下去、每一個寫入都被擋下。
  ///
  /// **這個陷阱踩過兩次**（2026-09-28 審檢舉、2026-09-29 改成就門檻），
  /// 兩次都查了很久才發現 —— 所以現在由程式自己講出來。
  /// 這個帳號寫不寫得上雲 —— 寫不上就回一句話。
  ///
  /// **判準只有 `adminClaim` 一個。** 原本還 and 了 `adminMode`，
  /// 而那個旗標全 App 沒有任何地方切換它（`toggleAdminMode()` 零個
  /// 呼叫端），且 `applyAdminClaim(false)` 會把它強制設回 false ——
  /// 兩個條件湊不齊，這整段判斷是死的。測試綠是因為它們直接
  /// `..adminMode = true`，也就是從一個 App 不會進入的狀態出發。
  String? get _notReallyAdmin => adminClaim
      ? null
      : '這個帳號沒有管理員標記，改的東西只會留在本機 —— 雲端會擋下。';

  Future<String?> _dropPlatform(String collection, String docId) async {
    final src = platformSource;
    if (src == null) return null;
    if (_notReallyAdmin case final why?) return why;
    try {
      await src.remove(collection, docId).timeout(_cloudWriteTimeout);
      return null;
    } catch (e) {
      return '已在本機移除，但沒有寫上雲（$e）。重新整理後會回來。';
    }
  }

  /// 一組平台參數的當前值，寫成雲端那一份的形狀。
  Future<String?> pushConfigGroup(String groupId) {
    final g = platformConfig.group(groupId);
    return pushPlatform('platform_config', groupId, {'params': g.values});
  }

  /// 一枚成就定義。
  Future<String?> pushAchievement(Achievement a) =>
      pushPlatform('achievement_defs', achievementDocId(a), achievementToMap(a));

  /// 一個平台動作。
  Future<String?> pushExercise(Exercise e) =>
      pushPlatform('exercises', e.id, exerciseToMap(e));

  /// 一筆每日任務池項目。
  Future<String?> pushTaskPoolItem(TaskPoolItem t) =>
      pushPlatform('daily_task_pool', t.id, taskPoolItemToMap(t));

  Future<String?> dropTaskPoolItem(TaskPoolItem t) =>
      _dropPlatform('daily_task_pool', t.id);

  void applyPlatformData(PlatformData d) {
    platformExercises = List.of(d.exercises);
    planSpecById = {for (final s in d.planSpecs) s.id: s};
    platformPlans = [
      ...buildCsvPlansFrom(d.planSpecs, d.exercises),
      if (demo) ...kDemoPlans,
      ...kPlans,
    ];
    // **整份重建會把優化建議的記號洗掉。** 它是使用者的資料，
    // 不屬於這份目錄 —— 重建完貼回去。
    applyOptimizationMark();
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

  late List<Admin> admins = demo ? buildAdmins() : [];

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

  /// 把一筆申請案送上雲。**即發即忘** —— 送出測驗這個動作不該被
  /// 一次網路失敗擋住，申請人重考要等 14 天。失敗留在
  /// [instructorCaseError]，畫面說得出來。
  void _pushInstructorCase(InstructorCase c) {
    final src = instructorCaseSource;
    final uid = c.applicantUid;
    if (src == null || uid == null) return;
    src
        .file(CloudInstructorCase(
          applicantUid: uid,
          applicant: c.applicant,
          aiScores: c.aiScores,
          weighted: c.weighted,
          concerns: c.concerns,
          answers: c.answers,
          at: c.enteredAt,
        ))
        .then((_) => instructorCaseError = null)
        .catchError((Object e) {
      instructorCaseError = '$e';
      notifyListeners();
    });
  }

  /// 申請案沒送上去時的原因。**空值＝沒問題。**
  ///
  /// 不留這一欄的話，失敗就完全無聲：申請人以為送出了，
  /// 管理員的佇列裡沒有他，而兩邊都不會知道。
  String? instructorCaseError;

  /// 把**我自己那一筆**申請的裁決讀回來。
  ///
  /// 這一支與 [loadInstructorQueue] 的差別是「誰叫得動」：
  /// 佇列只有管理員讀得到，而這一支**每個人都要跑** ——
  /// 它回答的是「我的申請怎麼了」。
  ///
  /// ## 為什麼非有不可
  ///
  /// `instructorStage` **不進存檔**（`app_state_snapshot.dart` 零筆引用），
  /// 而裁決只寫在雲端那份文件上。在此之前兩者之間沒有任何橋 ——
  /// 管理員按了「通過」，申請人重新整理之後看到的是「你還沒申請」。
  /// 使用者 2026-09-29 實測撞到。
  ///
  /// **不進存檔是刻意的**（雲端是唯一事實，不寫第二份會漂移的副本，
  /// 同師徒關係的取捨），但那個取捨要成立，就必須有人去讀雲端。
  Future<void> loadMyInstructorVerdict() async {
    final src = instructorCaseSource;
    if (src == null) return;
    try {
      final v = await src.mine();
      if (v == null) return; // 沒申請過，維持現狀
      switch (v) {
        case InstructorVerdict.passed:
          instructorStage = InstructorStage.approved;
          instructorRejectStage = null;
          _becomeInstructor();
          // **每次登入都重發一次，不只在成為教官的那一刻。**
          //
          // `_becomeInstructor()` 開頭是 `if (isInstructor) return;` ——
          // 已經是教官的人不會再跑到裡面那句發布。於是一個在「發布」
          // 這件事修好之前就當上教官的人，公開檔案會永遠停在
          // `isInstructor: false`，而別人的拜師頁上永遠沒有他。
          //
          // 這一行讓它自我修復：下次登入就補上。即發即忘、吞掉錯誤，
          // 多發一次的成本是一次寫入。
          publishMyProfile();
        case InstructorVerdict.rejected:
          instructorStage = InstructorStage.rejected;
          instructorRejectStage = '管理員審核';
        case InstructorVerdict.pending:
          // 還沒判。**要把階段補回來** —— 不補的話畫面會說「你還沒申請」，
          // 而他其實在等。
          instructorStage = InstructorStage.pendingReview;
      }
      notifyListeners();
    } catch (_) {
      // 讀不到就維持現狀，不要把「不知道」畫成「沒申請」。
    }
  }

  /// 把雲端的教官申請佇列讀進來。**只有管理員叫得動。**
  Future<void> loadInstructorQueue() async {
    final src = instructorCaseSource;
    if (src == null || !isPlatformAdmin || !canReview) return;
    try {
      applyCloudInstructorCases(await src.queue(limit: 100));
    } catch (_) {
      // 讀不到就維持現狀。**不清空** —— 空佇列與讀取失敗長得一模一樣，
      // 而後者不該被畫成「沒有待審案件」。
    }
  }

  /// 把雲端的申請案併進本機佇列。
  ///
  /// **以 uid 對齊。** 同一個人只會有一筆（文件 ID 就是 uid），
  /// 所以雲端那一份直接取代同 uid 的本機那一份 —— 包括我自己剛送出的
  /// 那一筆，那樣管理員看到的與申請人送出的是同一份內容。
  void applyCloudInstructorCases(List<CloudInstructorCase> cloud) {
    for (final c in cloud) {
      final i =
          instructorCases.indexWhere((x) => x.applicantUid == c.applicantUid);
      final built = InstructorCase(
        id: 'IC-${c.applicantUid}',
        applicant: c.applicant,
        applicantUid: c.applicantUid,
        aiScores: c.aiScores,
        weighted: c.weighted,
        concerns: c.concerns,
        answers: c.answers,
        enteredAt: c.at,
      );
      if (i >= 0) {
        instructorCases[i] = built;
      } else {
        instructorCases.insert(0, built);
      }
    }
    notifyListeners();
  }

  void decideInstructor(InstructorCase c, bool pass) {
    if (!canReview) return;
    if (c.state == CaseState.upheld || c.state == CaseState.dismissed) return;
    c.state = pass ? CaseState.upheld : CaseState.dismissed;
    // 判定的若是我的申請，我這一側的狀態也要跟著走完 ——
    // 先前這裡只改案件狀態，申請人永遠停在「待人工審核」。
    // **以 uid 判定，不比暱稱**（暱稱重構階段二）。
    // 撞名或改過名的話，原本會把教官資格發給錯的人 ——
    // 而管理員自己審自己那條路（今天實測走過）更容易踩到：
    // 兩邊的 `displayName` 本來就一樣。
    if (_isMe(c.applicant, c.applicantUid) &&
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
    // 裁決也要寫回雲端 —— 否則這筆案件會永遠留在別人的待審佇列裡，
    // 而下一位管理員會重審一次已經判過的案子。
    if (c.applicantUid case final uid?) {
      instructorCaseSource
          ?.decide(uid, passed: pass, handlerName: admin.name)
          .catchError((Object e) {
        instructorCaseError = '$e';
        notifyListeners();
      });
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

  /// 動機類健身目標（選填，最多 1 項）。值域見 [kMotiveGoals]。
  ///
  /// **註冊問卷問了，但在此之前沒有任何地方存它** —— 與生日同一個毛病。
  /// `completeSignUp` 把草稿的其他欄位一項項落地，就是漏了這一個。
  ///
  /// 空值代表沒填 —— 它本來就是選填的。
  ///
  /// **不參與訓練計畫推薦**：規格明訂比對維度為器材、經驗、常見目標三項，
  /// 「動機類與課表內容無對應關係，參與比對只會製造雜訊」（〈註冊流程〉）。
  String? motiveGoal;

  /// 生日。
  ///
  /// **註冊問卷問了，但在此之前沒有任何地方存它。** 設定頁那一列寫的是
  /// 一個寫死的日期 `1996 / 03 / 12` —— 每一位使用者看到的都是它。
  /// 使用者回報「生日也是假資料，不是我當初註冊填的」。
  ///
  /// 空值代表沒有 —— 示範身分沒有生日，就顯示「未填寫」。
  /// 不預設一個日期：一個假的生日比沒有生日糟，因為它看起來是真的。
  DateTime? birthday;
  /// 是否已完成註冊。
  ///
  /// 預設 true 是**示範用身分**的一部分：直接 `AppState()` 建出來的是
  /// 那位假使用者，已經註冊過。真正的第一次啟動由 [hydrate] 判定 ——
  /// 讀不到存檔就把它設為 false，走完整的註冊流程。
  bool signUpCompleted = true;

  /// 已同意的條款版本（〈02_Aggregate定義〉的「已同意條款版本」欄位）。
  ///
  /// **預設為現行版本，是示範用身分的一部分** —— 與 [signUpCompleted]
  /// 同一個道理：直接 `AppState()` 建出來的那位假使用者已經同意過了。
  /// 真實使用者的值由存檔決定，讀不到就是空值（見 [termsReconsentNeeded]）。
  String? agreedTermsVersion = kTermsVersion;

  /// 下次登入要不要請他重新同意條款。
  ///
  /// 規格：「條款改版後，既有使用者於下次登入時須重新同意」
  /// （〈註冊流程〉、〈02_Aggregate定義〉）。
  ///
  /// **空值代表沒同意過，也要重新同意。** 這個欄位是 2026-09-24 才加的，
  /// 在那之前的存檔一律查無版本 —— 而他們實際同意的是 v3.2（v4.0 是
  /// 2026-09-18 改的），本來就該重看。反過來把查無版本當成「已同意現行版」，
  /// 等於替他們按了同意鍵。
  ///
  /// **還沒註冊完的人不算** —— 他們本來就會在註冊流程裡遇到條款頁，
  /// 在這裡再擋一次會變成兩道。
  bool get termsReconsentNeeded =>
      signUpCompleted && agreedTermsVersion != kTermsVersion;

  /// 使用者已同意服務條款（含條款改版後的重新同意）。
  ///
  /// 〈01_Command清單〉的「同意服務條款」。註冊流程走完時也會經過這裡。
  void agreeTerms() {
    agreedTermsVersion = kTermsVersion;
    notifyListeners();
  }

  /// 10 項全數填畢方可完成註冊；獎勵為金幣 100 ＋ 補簽券 ×1，無經驗值。
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

    // 引導收尾：偏好時段與體驗評分屬於「這個人的回答」，不是平台資料。
    // 新帳號還沒被問過。
    preferredTimes = PreferredTimes.empty();
    experienceRatings.clear();

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
    _followNames.clear();
    // 新帳號沒有改過名，也沒有曾用名。
    lastRenamedAt = null;
    formerNames.clear();
    blockedUsers.clear();
    sentApplications.clear();
    // 加入／退出的時戳也要清 —— 新帳號沒有換隊冷卻，也沒有誤入窗口。
    teamJoinedAt = null;
    teamLeftAt = null;
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
    // 註冊流程裡已經按過同意 —— 記下版本，否則他下一次登入又被要求一次。
    // **排在 resetToNewAccount() 之後**，理由同下面那條暱稱：
    // 那一步歸零的是進度不是身分，但順序顛倒的話，日後有人往那裡加一行
    // 「條款版本歸位」，新註冊的人一進 App 就會再被要求同意一次。
    agreedTermsVersion = kTermsVersion;
    coins += kSignUpCoins;
    grantMakeupTickets(kSignUpMakeupTickets);
    // 暱稱。**要排在 resetToNewAccount() 之後** —— 那一步不碰 displayName
    // （它歸零的是進度，不是身分），但順序顛倒的話日後有人往那裡加一行
    // 「暱稱歸位」，新註冊的人就會又變回「你」，而且沒有任何錯誤訊息。
    final nick = signUpDraft.nickname?.trim();
    if (nick != null && nick.isNotEmpty) displayName = nick;
    if (signUpDraft.weightKg != null) bodyweightKg = signUpDraft.weightKg!;
    if (signUpDraft.heightCm != null) heightCm = signUpDraft.heightCm!;
    if (signUpDraft.gender != null) isMale = signUpDraft.gender == '男';
    // 生日在此之前是問了就丟 —— 註冊問卷第 4 題收了，沒有任何地方存。
    if (signUpDraft.birthday != null) birthday = signUpDraft.birthday;
    // 動機類目標同上。選填，所以沒填就是沒填，不給預設值。
    if (signUpDraft.motiveGoal != null) motiveGoal = signUpDraft.motiveGoal;
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

  /// 開發者模式。**預設關閉，而且不進存檔。**
  ///
  /// 示範用的東西（流程示範、模擬對方、骨架屏樣式集、退步的模擬時鐘）
  /// 對開發與展示很有用，但一般使用者看到只會困惑 —— 那些不是功能。
  ///
  /// 不寫進存檔是刻意的：它是「這一次打開 App 想看示範」的狀態，
  /// 不是使用者的偏好設定。關掉 App 就回到乾淨的樣子，
  /// 也就不會有人不小心開著它交出去。
  /// 開啟方式見「我的」頁首（長按）。
  bool developerMode = false;

  void toggleDeveloperMode() {
    developerMode = !developerMode;
    notifyListeners();
  }
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
      : ((kg * kLbPerKg).toStringAsFixed(1), 'lb');

  /// 身高的顯示值與單位。
  (String, String) heightDisplay(double cm) => metricUnits
      ? (cm.round().toString(), 'cm')
      : ((cm / kCmPerInch).toStringAsFixed(1), 'in');

  /// 換算係數。**存的一律是公制**，英制只是顯示 ——
  /// 所以進出兩個方向都得經過同一組係數，不可以在畫面那邊各乘一次。
  static const kLbPerKg = 2.20462;
  static const kCmPerInch = 2.54;

  /// 公制 → 顯示單位。[height] 為真時是身高（cm／in），否則體重（kg／lb）。
  double toDisplayUnit(double metric, bool height) => metricUnits
      ? metric
      : (height ? metric / kCmPerInch : metric * kLbPerKg);

  /// 顯示單位 → 公制。[toDisplayUnit] 的反向。
  double toMetric(double shown, bool height) => metricUnits
      ? shown
      : (height ? shown * kCmPerInch : shown / kLbPerKg);

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

  /// 真的把這個帳號刪掉。回傳 null 代表成功，否則是給使用者看的一句話。
  ///
  /// **由 `AuthGate` 注入。** 刪除要動到 Firebase Auth 帳號、Firestore 上的
  /// 使用者資料與公開檔案，那三個來源都在 `AuthGate` 手上 —— `AppState`
  /// 看不到它們，也不該為了刪帳號而認識它們。
  ///
  /// 空值代表沒接後端（既有測試與示範模式走這條）。
  Future<String?> Function()? deleteAccountJob;

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
  /// **順手裝上 [PhotoScope]。**
  ///
  /// 上傳的照片畫在 `AppImageView` 裡，而那是設計層 —— 它只拿得到一個
  /// ID，位元組得有人餵。裝在這裡的理由是「有 AppScope 的地方就有
  /// AppState」，於是每一個既有畫面與既有測試都自動拿得到，
  /// 不必每一處各包一層。
  AppScope({super.key, required AppState state, required Widget child})
      : super(
          notifier: state,
          child: PhotoScope(load: state.photoBytes, child: child),
        );

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
