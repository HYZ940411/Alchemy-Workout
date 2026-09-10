import 'dart:math' as math;

import 'ability.dart';
import 'models.dart';

/// 一組的實績：重量與次數。帶入來源的粒度為**組**，非整場訓練。
typedef ActualSet = ({double weight, int reps});

/// 帶入採**組序逐一對應**：本次第 N 組對應上次第 N 組。
///
/// - 本次組數**多於**上次時，超出的組沿用上次**最後一組**的重量。
/// - 本次組數**少於**上次時，取上次的**前 N 組**。
///
/// 帶入的是**重量**；目標次數仍取自課表。
///
/// 被排除的兩個做法各有其害：全部組帶入上次最大重量，第 1 組即從當日最重
/// 開始、無暖身，具受傷風險；全部組帶入上次最後一組，而最後一組多為力竭後
/// 下修的重量，作為全部組的預帶值會使訓練強度逐次下滑。
///
/// [lastSets] 為空（未曾記錄過該動作）時回傳空清單，由呼叫端改走推算。
List<double> carryForward(List<ActualSet> lastSets, int setCount) {
  if (lastSets.isEmpty || setCount <= 0) return const [];
  return List.generate(
    setCount,
    (i) => (i < lastSets.length ? lastSets[i] : lastSets.last).weight,
  );
}

/// 未曾記錄該動作者的建議起始重量 —— **不沿用來源課表的值**。
///
/// 由公認肌力標準依體重與性別推算：把 [measuredScore] 的四個步驟反過來走一遍
/// （點數 → DOTS → 標準化 1RM → 該動作 1RM → 目標次數下的工作重量），
/// 起點取使用者該肌群的現有點數，故新手得到的是輕的重量、老手得到的是重的。
///
/// 徒手、計時與有氧動作回傳 0：這些動作的「重量」不是可推算的量。
double suggestedWeight({
  required Exercise exercise,
  required int dimPoints,
  required double bodyweightKg,
  required bool isMale,
  required int targetReps,
}) {
  if (exercise.isBodyweight ||
      exercise.dim == null ||
      exercise.relativeIntensity <= 0) {
    return 0;
  }
  final coef = dotsCoefficient(bodyweightKg: bodyweightKg, isMale: isMale);
  if (coef <= 0) return 0;

  final dots = dimPoints / kMappingFactor + kBaseline;
  final standardized = dots / coef;
  final oneRm = standardized / exercise.relativeIntensity;

  // Epley 反解：次數超過 10 下以 10 下計，與正向計算同一個上限。
  final cap = epleyRepCap;
  final r = targetReps > cap ? cap : math.max(1, targetReps);
  final w = oneRm / (1 + r / 30.0);
  if (!w.isFinite || w <= 0) return 0;
  // 場館的槓片以 2.5 kg 為級距，推到小數點沒有意義。
  return (w / 2.5).round() * 2.5;
}
