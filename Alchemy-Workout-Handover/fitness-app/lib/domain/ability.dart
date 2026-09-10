import 'dart:math' as math;

import 'platform_config.dart';

/// 六維能力值 —— 依肌群分維（承〈能力值 Aggregate〉）。
enum Dim { chest, back, legs, shoulders, arms, core }

const dimNames = <Dim, String>{
  Dim.chest: '胸',
  Dim.back: '背',
  Dim.legs: '腿',
  Dim.shoulders: '肩',
  Dim.arms: '手',
  Dim.core: '核心',
};

// 以下皆為平台級可調參數，存於〈能力值設定 Aggregate〉，
// 由管理員 Command「設定能力值參數」維護 —— 故讀 [platformConfig] 而非寫死。

/// 註冊時各維初始值；點數硬截斷上限。
int get kInitialPoints => platformConfig.i('ability', 'initial');
int get kMaxPoints => platformConfig.i('ability', 'cap');

/// 完成新手任務後，腿與核心的初始值（亦即其退步下限的地板）拉高至此。
/// 為初始值的提升，非點數紀錄的提升 —— 不產生「能力值已提升」。
const int kNoviceLegCoreInitial = 30;

/// 首次封頂：該維第一次訓練封頂於此點數。
int get kFirstTimeCap => platformConfig.i('ability', 'firstCap');

/// 補格門檻：本場實測值達當前點數的此比例以上才補格。
double get kCatchUpRatio => platformConfig.d('ability', 'catchUp');

/// 基準值將未訓練者的 DOTS 分數平移至接近 0，映射係數對齊六階門檻。
double get kBaseline => platformConfig.d('ability', 'baseline');
double get kMappingFactor => platformConfig.d('ability', 'mapping');

// ---------------------------------------------------------------------------
// 等級：六階 ＋ 每階 +/++ 兩個小節點，共 18 節點
// ---------------------------------------------------------------------------

class AbilityNode {
  final String label; // 例：B+
  final String major; // 例：B
  final int lower;
  final int upper;
  const AbilityNode(this.label, this.major, this.lower, this.upper);
}

/// 18 個節點。區間由當前六階門檻推導 —— 管理員調整門檻的當下，
/// 全平台使用者的等級同時改變（〈能力值設定 Aggregate〉：六階門檻調整後即時生效）。
List<AbilityNode> get kNodes {
  final bounds = subNodeBounds();
  return [
    for (var i = 0; i < bounds.length; i++)
      AbilityNode(
        _nodeLabels[i % 3] == '' ? kMajorGrades[i ~/ 3]
            : '${kMajorGrades[i ~/ 3]}${_nodeLabels[i % 3]}',
        kMajorGrades[i ~/ 3],
        bounds[i][0],
        bounds[i][1],
      ),
  ];
}

const _nodeLabels = <String>['', '+', '++'];

int nodeIndexOf(int points) {
  final p = points.clamp(0, kMaxPoints);
  for (var i = 0; i < kNodes.length; i++) {
    if (p <= kNodes[i].upper) return i;
  }
  return kNodes.length - 1;
}

AbilityNode nodeOf(int points) => kNodes[nodeIndexOf(points)];

/// 主階（S/A/B/C/D/E），六維共用同一組門檻。
String majorGradeOf(int points) => nodeOf(points).major;

/// 綜合點數 ＝ 六維算術平均（衍生值，不儲存）。
int overallPoints(Map<Dim, int> pts) {
  final sum = Dim.values.fold<int>(0, (a, d) => a + (pts[d] ?? kInitialPoints));
  return (sum / Dim.values.length).round();
}

String overallGrade(Map<Dim, int> pts) => majorGradeOf(overallPoints(pts));

/// 呈現格式：「主階 ＋ 本節點內的累積點數 ＋ 距下一節點所需點數」
/// 例：`B　+12　距 30 升 B+`
class NodeProgress {
  final String currentLabel;
  final String? nextLabel;
  final int intoNode; // 本節點內已累積
  final int toNext; // 距下一節點還差
  const NodeProgress(this.currentLabel, this.nextLabel, this.intoNode, this.toNext);

  String get display => nextLabel == null
      ? '$currentLabel　已達頂'
      : '$currentLabel　+$intoNode　距 $toNext 升 $nextLabel';
}

NodeProgress nodeProgressOf(int points) {
  final i = nodeIndexOf(points);
  final n = kNodes[i];
  final into = points - n.lower;
  if (i >= kNodes.length - 1) return NodeProgress(n.label, null, into, 0);
  final next = kNodes[i + 1];
  return NodeProgress(n.label, next.label, into, next.lower - points);
}

// ---------------------------------------------------------------------------
// 能力值提升公式
// 點數 ＝ min(999, (DOTS 正規化分數 − 基準值) × 映射係數)
// ---------------------------------------------------------------------------

/// Epley 的次數上限：超過此數以此數計。反解建議重量時須用同一個上限。
int get epleyRepCap => platformConfig.i('ability', 'epley');

/// 步驟 1：以 Epley 估算 1RM，次數超過 10 下以 10 下計。
double epley1RM(double weightKg, int reps) {
  final cap = epleyRepCap;
  final r = reps > cap ? cap : reps;
  return weightKg * (1 + r / 30.0);
}

/// 步驟 3：DOTS 係數（依體重與性別），標準 DOTS 多項式。
double dotsCoefficient({required double bodyweightKg, required bool isMale}) {
  final bw = bodyweightKg.clamp(40.0, 200.0);
  late double a, b, c, d, e;
  if (isMale) {
    a = -0.000001093;
    b = 0.0007391293;
    c = -0.1918759221;
    d = 24.0900756;
    e = -307.75076;
  } else {
    a = -0.0000010706;
    b = 0.0005158568;
    c = -0.1126655495;
    d = 13.6175032;
    e = -57.96288;
  }
  final denom = a * math.pow(bw, 4) +
      b * math.pow(bw, 3) +
      c * math.pow(bw, 2) +
      d * bw +
      e;
  if (denom <= 0) return 0;
  return 500.0 / denom;
}

/// 步驟 2 + 3 + 4：由單組成績推導該肌群的標準化分數（點數尺度）。
///
/// [relativeIntensity] 為該動作的相對強度係數，將不同動作拉到同一尺度。
int measuredScore({
  required double weightKg,
  required int reps,
  required double relativeIntensity,
  required double bodyweightKg,
  required bool isMale,
}) {
  final oneRm = epley1RM(weightKg, reps);
  final standardized = oneRm * relativeIntensity;
  final dots = standardized * dotsCoefficient(bodyweightKg: bodyweightKg, isMale: isMale);
  final pts = (dots - kBaseline) * kMappingFactor;
  if (pts.isNaN) return kInitialPoints;
  return pts.round().clamp(kInitialPoints, kMaxPoints);
}

// ---------------------------------------------------------------------------
// 單次訓練的提升上限
// ---------------------------------------------------------------------------

class AbilityGain {
  final int newPoints;
  final int delta;
  final int newPending; // 待兌現實測值
  final bool cappedByFirstTime;
  final bool advancedByCatchUp;
  const AbilityGain({
    required this.newPoints,
    required this.delta,
    required this.newPending,
    this.cappedByFirstTime = false,
    this.advancedByCatchUp = false,
  });
}

/// 一場訓練對單一維度的提升。
///
/// 一、首次封頂：該維第一次訓練封頂於 450 點。
/// 二、其後每場最多前進一個小節點，落點取「下一節點上緣」與「實測值」之較小者。
/// 三、超額部分記入待兌現實測值；本場實測值達當前點數 80% 以上時自動補一格。
AbilityGain applySessionGain({
  required int current,
  required int measured,
  required int pending,
  required bool isFirstSessionForDim,
}) {
  if (isFirstSessionForDim) {
    final capped = math.min(measured, kFirstTimeCap);
    final np = math.max(current, capped).clamp(kInitialPoints, kMaxPoints);
    return AbilityGain(
      newPoints: np,
      delta: np - current,
      // 待兌現實測值為絕對分數：點數逐場前進「直到追平」它為止。
      newPending: measured > np ? measured : 0,
      cappedByFirstTime: measured > kFirstTimeCap,
    );
  }

  // 待兌現的分數只有在本場夠認真（達當前點數 80%）時才拿來補格。
  final catchUpEligible = measured >= (current * kCatchUpRatio);
  final target = math.max(measured, catchUpEligible ? pending : 0);

  final idx = nodeIndexOf(current);
  final nextUpper = idx >= kNodes.length - 1 ? kMaxPoints : kNodes[idx + 1].upper;

  var np = math.max(current, math.min(nextUpper, target));
  np = np.clamp(kInitialPoints, kMaxPoints);

  // 保留較高的實測水準作為下一場的追趕目標，追平後歸零。
  final carried = math.max(pending, measured);
  return AbilityGain(
    newPoints: np,
    delta: np - current,
    newPending: carried > np ? carried : 0,
    advancedByCatchUp: catchUpEligible && pending > current && measured <= current,
  );
}
