import 'platform_config.dart';

/// 訓練的終止方式（承〈訓練紀錄流程〉的三種終止 Event）。
enum EndKind { completed, endedEarly, timedOut }

const endKindNames = <EndKind, String>{
  EndKind.completed: '已完成訓練',
  EndKind.endedEarly: '已提前結束',
  EndKind.timedOut: '逾時中斷',
};

/// 課表來源（決定排行榜的課表來源係數）。
enum PlanSource { official, publishedCustom, privateCustom, blank }

const planSourceNames = <PlanSource, String>{
  PlanSource.official: '官方訓練計畫',
  PlanSource.publishedCustom: '已公開的自訂訓練',
  PlanSource.privateCustom: '未公開的自訂訓練',
  PlanSource.blank: '空白課表',
};

/// 完成度係數：完成 100%、提前結束 70%、逾時中斷 50%。
/// 逾時中斷但已完成組數等於總計畫組數者給 100%。
double completionFactor(EndKind kind, {required int doneSets, required int plannedSets}) {
  switch (kind) {
    case EndKind.completed:
      return 1.0;
    case EndKind.endedEarly:
      return 0.7;
    case EndKind.timedOut:
      return (plannedSets > 0 && doneSets >= plannedSets) ? 1.0 : 0.5;
  }
}

/// 課表來源係數（防刷分）。空白課表不計入個人排行榜分數。
double? planSourceFactor(PlanSource s) {
  switch (s) {
    case PlanSource.official:
      return 1.0;
    case PlanSource.publishedCustom:
      return 0.75;
    case PlanSource.privateCustom:
      return 0.5;
    case PlanSource.blank:
      return null; // 不觸發「個人排行榜分數已增加」
  }
}

/// 連續訓練獎勵加成：每連續一天 +1%，上限 30%。僅套用於訓練獎勵金幣。
double streakBonus(int streakDays) {
  final b = streakDays * 0.01;
  return b > 0.30 ? 0.30 : b;
}

// --- 固定數額（皆為平台級可調參數，此處取模型已定案值） ---
// 四者為〈獎勵定義〉的平台級可調參數，由 Command「設定獎勵定義」維護。
// 調整不改動既有發放紀錄。
int get kTrainingExp => platformConfig.i('reward', 'trainExp'); // 當日僅發一次
int get kTrainingCoinBase => platformConfig.i('reward', 'trainCoin');
int get kCheckInExp => platformConfig.i('reward', 'checkInExp');
int get kCheckInCoin => platformConfig.i('reward', 'checkInCoin');

// 回歸任務獎勵（2026-08-10 定案）。約為單次訓練獎勵（30/30）的 1.67 倍 ——
// 比日常訓練更有感，作為「歡迎回來」的誠意。
// 能力值的回復另由「能力值已部分回復」定義，不在本額度範圍。
int get kReturnTaskExp => platformConfig.i('reward', 'returnExp');
int get kReturnTaskCoin => platformConfig.i('reward', 'returnCoin');
int get kReturnTaskCredit => platformConfig.i('reward', 'returnCredit');
const int kLeaderboardBase = 100; // 訓練結算基準分
/// 每日任務單項的金幣獎勵。
const int kDailyTaskCoin = 2;

/// 三項每日任務全部領取後的加碼金幣。
///
/// 2×3 ＋ 4 ＝ **一天 10 金幣**，與〈02_Aggregate定義〉的
/// 「每日任務 300／月」相符。在此之前這個 4 是寫死在 `claimAllTasks()`
/// 裡的字面量，而且只掛在「領取全部」那顆按鈕上。
const int kDailyTaskAllDoneCoin = 4;
const int kDailyTaskScorePerItem = 10; // 每日任務進度 10 分／項
const int kDailyTaskAllBonusScore = 20; // 全部完成加碼 20 分

class SettlementRewards {
  final int exp;

  /// 本場**實發**金幣。訓練獎勵每日最多發放一次，金幣以當日最高完成度為準，
  /// 後續訓練完成度更高時只補發差額 —— 故實發可能小於本場應得，甚至為 0。
  final int coins;

  /// 本場**應得**金幣（完成度 × 加成後的全額）。當日上限即取此值的最大者。
  final int coinsEntitled;

  final int coinsBeforeBonus;
  final double bonusRate;

  /// 本場**實發**排行榜分數（空白課表為 null）。同樣每日只計一次、取當日最高並補差額。
  final int? leaderboardScore;

  /// 本場**應得**排行榜分數（空白課表為 null）。
  final int? leaderboardScoreEntitled;

  final double completion;

  const SettlementRewards({
    required this.exp,
    required this.coins,
    required this.coinsEntitled,
    required this.coinsBeforeBonus,
    required this.bonusRate,
    required this.leaderboardScore,
    required this.leaderboardScoreEntitled,
    required this.completion,
  });

  /// 本場應得但因當日上限而未全額發放（含完全沒發的情形）。
  bool get coinsCapped => coins < coinsEntitled;

  bool get scoreCapped =>
      leaderboardScoreEntitled != null && leaderboardScore! < leaderboardScoreEntitled!;
}

/// 訓練結算的三個數值指標，各自的規則不同：
/// 能力值不受終止方式影響、經驗值固定 30、金幣與排行榜分數受完成度影響。
SettlementRewards computeSettlement({
  required EndKind kind,
  required PlanSource source,
  required int doneSets,
  required int plannedSets,
  required int streakDays,
  required bool expAlreadyGrantedToday,
  int coinsGrantedToday = 0,
  int scoreGrantedToday = 0,
}) {
  final completion = completionFactor(kind, doneSets: doneSets, plannedSets: plannedSets);
  final bonus = streakBonus(streakDays);

  final baseCoins = kTrainingCoinBase * completion;
  final coinsEntitled = (baseCoins * (1 + bonus)).round();
  // 補差額：當日已發 x、本場應得 y，實發 max(0, y − x)。
  // 不採「當日第一次結算即發、之後一律不發」—— 那只懲罰誠實訓練者，
  // 刷取者每場皆完成度 100%，第一場就拿滿，不受影響。
  final coins = coinsEntitled > coinsGrantedToday ? coinsEntitled - coinsGrantedToday : 0;

  final sf = planSourceFactor(source);
  final scoreEntitled = sf == null ? null : (kLeaderboardBase * completion * sf).round();
  final score = scoreEntitled == null
      ? null
      : (scoreEntitled > scoreGrantedToday ? scoreEntitled - scoreGrantedToday : 0);

  return SettlementRewards(
    // 經驗值當日僅發一次，不補不追加。
    exp: expAlreadyGrantedToday ? 0 : kTrainingExp,
    coins: coins,
    coinsEntitled: coinsEntitled,
    coinsBeforeBonus: baseCoins.round(),
    bonusRate: bonus,
    leaderboardScore: score,
    leaderboardScoreEntitled: scoreEntitled,
    completion: completion,
  );
}

/// 消耗大卡的估算 —— 必須標示為估計值。
int estimateCalories({required int minutes, required double bodyweightKg}) {
  const met = 5.0; // 阻力訓練的代謝當量
  return (met * 3.5 * bodyweightKg / 200.0 * minutes).round();
}
