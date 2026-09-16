/// 耐力值 —— 六維能力值的附掛值。
///
/// 規格：`03_能力值.md`〈耐力的判定基準有公開錨點〉。
///
/// **耐力值 ＝ 實際反覆次數 ÷ 該重量對應的標準反覆次數。**
/// 分母的 %1RM 取「該動作的歷史最佳估算 1RM」，不可取自同一組 ——
/// 取自同一組的話 1RM 恆為該組重量的 4/3 倍、%1RM 恆為 75%，
/// 耐力值就退化成「做了幾下 ÷ 10」，那不是耐力。
///
/// 語意上很反直覺，值得記在這裡：**用很輕的重量做很多下，耐力值反而低**。
/// 規格的例子 —— 臥推最重推過 60kg × 3 下（1RM ≈ 66kg），今日以 30kg
/// 做 20 下：30/66 ＝ 45%，該強度的標準次數 30 下，耐力值 ＝ 20/30 ＝ 0.67。
///
/// 衍生值，不儲存（2026-08-19 定案）：不掛成就、無退步機制、
/// 不進綜合能力等級，唯一的讀者是雷達圖的獨立區塊。
library;

import 'ability.dart';

/// %1RM 與標準反覆次數的對照表。
///
/// 65% 以上出自 NSCA／ACSM 公開發布，65% 以下（60→40）為依趨勢的外推值。
/// 低於 40% 1RM 的組不計入 —— 該強度已非肌力訓練區間。
///
/// **規格說這 11 格是平台級可調參數**，應由管理員於後台維護。
/// 目前寫死在這裡，尚未接進 `platform_config` —— 已記於 PROGRESS.md。
const kStandardReps = <int, double>{
  100: 1,
  90: 4,
  80: 8,
  75: 10,
  70: 12,
  65: 15,
  60: 18,
  55: 22,
  50: 26,
  45: 30,
  40: 35,
};

/// 低於這個強度的組不計入耐力值。
const kEnduranceMinPct = 40;

/// 某個 %1RM 對應的標準反覆次數。對照表是 5% 一格，中間線性內插。
double standardRepsAt(double pct) {
  if (pct >= 100) return kStandardReps[100]!;
  if (pct < kEnduranceMinPct) return double.nan;

  final keys = kStandardReps.keys.toList()..sort();
  for (var i = keys.length - 1; i > 0; i--) {
    final hi = keys[i], lo = keys[i - 1];
    if (pct <= hi && pct >= lo) {
      final t = (pct - lo) / (hi - lo);
      return kStandardReps[lo]! + (kStandardReps[hi]! - kStandardReps[lo]!) * t;
    }
  }
  return kStandardReps[keys.first]!;
}

/// 攤平後的一組成績：這一組屬於哪個維度、哪個動作、幾公斤幾下。
typedef EnduranceRow = ({Dim dim, String exerciseId, double weightKg, int reps});

/// 單一組的耐力值。不合格（強度過低、沒有可靠的 1RM）回傳空值。
double? enduranceOfSet({
  required double weightKg,
  required int reps,
  required double best1RM,
}) {
  if (best1RM <= 0 || weightKg <= 0 || reps <= 0) return null;
  final pct = weightKg / best1RM * 100;
  if (pct < kEnduranceMinPct) return null;
  final standard = standardRepsAt(pct);
  if (standard.isNaN || standard <= 0) return null;
  return reps / standard;
}

/// 六維耐力值。**沒有合格組的維度不出現在結果裡**（空值，不推測）。
///
/// 彙總方式為「該維度所有合格組的平均」（2026-09-16 裁決，規格未定）。
/// 取平均而不取最佳：耐力是一種穩定特徵，不該被單一組的超水準發揮拉高。
///
/// 目前平均的是**訓練紀錄裡的全部合格組**，沒有時間窗。歷史長了之後
/// 可能需要限定近期若干週 —— 那需要一個平台參數，等後台做到再說。
Map<Dim, double> enduranceOfRows(Iterable<EnduranceRow> rows) {
  // 第一遍：每個動作的歷史最佳估算 1RM。**分母必須跨全部歷史**，
  // 只看當場的話就回到了「取自同一組」那個被否決的做法。
  //
  // **只有未被截斷的組算得出可靠的 1RM。** Epley 在 [epleyRepCap] 下截斷，
  // 所以一組 20 下與一組 10 下會得到同一個估算值 —— 那個值不是這個人的
  // 極限，只是截斷點。規格明訂「僅做過高反覆、從未推過大重量者，
  // 該動作的耐力值為空值，不推測」，這就是那條規則的落點。
  //
  // 少了這道門檻，只做過 30kg × 20 下的人會拿到「分母 ＝ 自己那一組」，
  // %1RM 恆為 75%、標準次數恆為 10，耐力值直接變成 2.0 ——
  // 正是規格花了一整節否決掉的那個假高分。
  final cap = epleyRepCap;
  final best = <String, double>{};
  for (final r in rows) {
    if (r.weightKg <= 0 || r.reps <= 0) continue;
    if (r.reps > cap) continue;
    final rm = epley1RM(r.weightKg, r.reps);
    if (rm > (best[r.exerciseId] ?? 0)) best[r.exerciseId] = rm;
  }

  // 第二遍：逐組算耐力值，依維度累加。
  final sum = <Dim, double>{};
  final n = <Dim, int>{};
  for (final r in rows) {
    final rm = best[r.exerciseId];
    if (rm == null) continue;
    final e = enduranceOfSet(
      weightKg: r.weightKg,
      reps: r.reps,
      best1RM: rm,
    );
    if (e == null) continue;
    sum[r.dim] = (sum[r.dim] ?? 0) + e;
    n[r.dim] = (n[r.dim] ?? 0) + 1;
  }

  return {for (final d in sum.keys) d: sum[d]! / n[d]!};
}
