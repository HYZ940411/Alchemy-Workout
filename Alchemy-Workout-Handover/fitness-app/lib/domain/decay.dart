/// 能力值退步 —— 六個各自獨立的計時器
///
/// 承〈訓練中斷流程〉與 03_能力值.md〈能力值退步參數〉：
/// 每滿 240 小時未訓練該維，該維退 5%，直到觸及退步下限。
///
/// **退步下限不是註冊初始值**（2026-08-22 改制）：
/// 下限 ＝ 本次中斷前點數所處節點的主階降 2 階、小節點保留之節點下緣，
/// 且不低於該維初始值。原規則使練到 A 級者停練夠久即退回 10 點，與從未訓練者無異。
library;

import 'dart:math' as math;

import 'ability.dart';
import 'platform_config.dart';

// --- 平台級可調參數（〈能力值設定 Aggregate〉）---

/// 每次退步的比例。
double get kDecayRatio => platformConfig.d('ability', 'decayPct');

/// 退步間隔。240 小時（10 天）—— 每週練一次者（7 天）不觸發退步。
int get kDecayIntervalHours => platformConfig.i('ability', 'decayHours');

/// 退步下限的主階降幅。
int get kFloorMajorDrop => platformConfig.i('ability', 'floorDrop');

/// 回歸任務的回復比例。
double get kRecoverRatio => platformConfig.d('ability', 'recover');

// --- 四道門檻（固定規則，非可調參數）---

/// 中斷預告 24 ／ 連練天數歸零 36 ／ 退步預告 96 ／ 能力值退步 240。
const kInterruptWarnHours = 24;
const kStreakBreakHours = 36;
const kDecayWarnHours = 96;

/// 計時起點為上次訓練日的**日界**：該日結束、次日當地 04:00。
///
/// 採日界而非時戳，使所有使用者的期限統一落在同一時點，與連簽中斷判定一致。
DateTime dayBoundaryAfter(DateTime lastTrainedDate) => DateTime(
      lastTrainedDate.year,
      lastTrainedDate.month,
      lastTrainedDate.day + 1,
      4,
    );

/// 自日界起算已過的小時數。日界未到者為 0（不倒數負值）。
int hoursSinceBoundary(DateTime lastTrainedDate, DateTime now) {
  final h = now.difference(dayBoundaryAfter(lastTrainedDate)).inHours;
  return h < 0 ? 0 : h;
}

/// 該維在四道門檻上的位置。
enum DecayStage { normal, interruptWarned, streakBroken, decayWarned, decaying }

const decayStageNames = <DecayStage, String>{
  DecayStage.normal: '正常',
  DecayStage.interruptWarned: '中斷預告',
  DecayStage.streakBroken: '連練已中斷',
  DecayStage.decayWarned: '退步預告',
  DecayStage.decaying: '已退步',
};

/// 連續天數是否仍延續。**距上次的日界未超過 36 小時者續計** ——
/// 這是連續訓練與連續簽到共用的同一條判定，兩邊各寫一份就會對不起來。
bool streakContinues(DateTime lastDate, DateTime now) =>
    hoursSinceBoundary(lastDate, now) < kStreakBreakHours;

/// 補簽提醒門檻：48 小時未簽到。連簽獨有，訓練側無此門檻。
const kMakeupRemindHours = 48;

/// 連簽中斷的三道門檻位置。
///
/// **與 [DecayStage] 分開**：連簽只有 24／36／48 三道門檻，沒有「已退步」——
/// 那是能力值的階段。共用一個列舉會讓連簽的狀態停在一個它根本沒有的階段上，
/// 行為雖然對，名字卻講不通，日後照著名字寫判斷就會出事。
enum CheckInStage { normal, warned, broken, makeupReminded }

const checkInStageNames = <CheckInStage, String>{
  CheckInStage.normal: '正常',
  CheckInStage.warned: '中斷預告',
  CheckInStage.broken: '連簽已中斷',
  CheckInStage.makeupReminded: '已提醒補簽',
};

CheckInStage checkInStageOf(int hours) {
  if (hours >= kMakeupRemindHours) return CheckInStage.makeupReminded;
  if (hours >= kStreakBreakHours) return CheckInStage.broken;
  if (hours >= kInterruptWarnHours) return CheckInStage.warned;
  return CheckInStage.normal;
}

DecayStage stageOf(int hours) {
  if (hours >= kDecayIntervalHours) return DecayStage.decaying;
  if (hours >= kDecayWarnHours) return DecayStage.decayWarned;
  if (hours >= kStreakBreakHours) return DecayStage.streakBroken;
  if (hours >= kInterruptWarnHours) return DecayStage.interruptWarned;
  return DecayStage.normal;
}

/// 該維的退步下限。
///
/// 主階降 [kFloorMajorDrop] 階、**小節點保留**：A+ → C+、A++ → C++、B → D。
/// 不採「一律回到該階基本段」（會抹平同階內的努力差異），
/// 亦不採「以 18 個節點往下數 2 格」（退幅過小）。
/// 退不滿兩階者一律取該維初始值。
int decayFloorOf(int pointsBeforeInterruption, {int? initial}) {
  final floorInitial = initial ?? kInitialPoints;
  final target = nodeIndexOf(pointsBeforeInterruption) - 3 * kFloorMajorDrop;
  if (target < 0) return floorInitial;
  return math.max(kNodes[target].lower, floorInitial);
}

/// 單一維度的退步計時器狀態（〈能力值 Aggregate〉的三個欄位）。
class DimDecay {
  /// 各維最後訓練日。**不允許空值**，六維初始皆為註冊日。
  DateTime lastTrainedDate;

  /// 下一次退步的時點。**null ＝ 計時器已停止**。
  ///
  /// 存時點而非「已退幾次」：觸及下限後計時器停止推進，
  /// 若只記次數，停止期間 wall clock 仍在走，重新啟動時會一次補退一整串。
  DateTime? nextDecayAt;

  /// 本次中斷該維累積退步量。該維恢復訓練時歸零。
  int cumulative;

  /// 已因觸及下限產生過一次「能力值已退步」者不再產生。
  bool floorReached;

  DimDecay({
    required this.lastTrainedDate,
    this.nextDecayAt,
    this.cumulative = 0,
    this.floorReached = false,
  });

  bool get stopped => nextDecayAt == null;

  /// 該維被訓練：重設計時、累積退步量歸零、下限判定重新開始。
  ///
  /// 重設計時的訓練不限於計入能力值者 —— 自建動作雖不觸發「能力值已提升」，
  /// 仍重設其所屬肌群維度的計時；有氧的所屬肌群為空值，不重設任何維度。
  void resetOn(DateTime trainedDate) {
    lastTrainedDate = trainedDate;
    nextDecayAt =
        dayBoundaryAfter(trainedDate).add(Duration(hours: kDecayIntervalHours));
    cumulative = 0;
    floorReached = false;
  }
}

/// 一次退步的結果。
class DecayStep {
  final int newPoints;
  final int lost;

  /// 本次即為觸及下限的那一次 —— 其 Event 仍照常產生（回歸任務的唯一觸發源）。
  final bool hitFloor;
  const DecayStep(this.newPoints, this.lost, this.hitFloor);
}

/// 對單一維度套用一次退步。
///
/// 退步後將低於下限者**截斷至下限**（該次即為觸及下限的那一次）。
/// 若改為「會破底就不退」，該維將永遠停在下限之上、永遠碰不到下限，計時器永不停止。
DecayStep decayOnce({
  required int current,
  required int floor,
  double? ratio,
}) {
  final r = ratio ?? kDecayRatio;
  // 向下取整而非四捨五入：低點數時 round 會算出原值，該維將卡住不動。
  var next = (current * (1 - r)).floor();
  var hit = false;
  if (next <= floor) {
    next = floor;
    hit = true;
  }
  return DecayStep(next, current - next, hit);
}

/// 完成回歸任務時該維的回復量 —— 本次中斷累積退步量的一半。
///
/// 回復不論該維是否於回歸任務中被訓練，六維各自獨立計算：
/// 被訓練的那一維本身已產生「能力值已提升」，再對它回復即重複計酬。
int recoveryFor(int cumulative, {double? ratio}) =>
    (cumulative * (ratio ?? kRecoverRatio)).round();
