import 'dart:math' as math;

import 'platform_config.dart';

/// 階級（1–99），由經驗值決定，衡量投入程度。單調遞增，永不下降。
const int kMaxRank = 99;

/// 累計經驗值門檻公式：C(n) ＝ 滿階經驗值 × ((n − 1) / 98)^曲線指數，n 為階級（2–99）。
/// 兩者為平台級可調參數，由 Command「設定階級門檻」維護。
double get kFullRankExp => platformConfig.d('rank', 'fullExp');
double get kCurveExponent => platformConfig.d('rank', 'exponent');

int expThresholdForRank(int rank) {
  if (rank <= 1) return 0;
  final n = rank.clamp(2, kMaxRank);
  return (kFullRankExp * math.pow((n - 1) / (kMaxRank - 1), kCurveExponent)).round();
}

/// 由累計經驗值推導當前階級。
int rankForExp(int totalExp) {
  var rank = 1;
  for (var n = 2; n <= kMaxRank; n++) {
    if (totalExp >= expThresholdForRank(n)) {
      rank = n;
    } else {
      break;
    }
  }
  return rank;
}

class RankProgress {
  final int rank;
  final int intoRank; // 本階已累積
  final int spanOfRank; // 本階所需
  final bool isMax;
  const RankProgress(this.rank, this.intoRank, this.spanOfRank, this.isMax);

  double get ratio => isMax || spanOfRank <= 0 ? 1.0 : (intoRank / spanOfRank).clamp(0.0, 1.0);
  int get toNext => isMax ? 0 : spanOfRank - intoRank;
}

RankProgress rankProgressOf(int totalExp) {
  final rank = rankForExp(totalExp);
  if (rank >= kMaxRank) return const RankProgress(kMaxRank, 0, 0, true);
  final cur = expThresholdForRank(rank);
  final next = expThresholdForRank(rank + 1);
  return RankProgress(rank, totalExp - cur, next - cur, false);
}

/// 排行榜分組：每 10 階一組，共 10 組（1–10、11–20、…、91–99）。
int rankGroupOf(int rank) => ((rank - 1) ~/ 10).clamp(0, 9);

String rankGroupLabel(int group) {
  final lo = group * 10 + 1;
  final hi = group == 9 ? 99 : group * 10 + 10;
  return '$lo–$hi 階';
}
