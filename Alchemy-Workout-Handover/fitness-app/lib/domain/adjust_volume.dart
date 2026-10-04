import 'dart:math' as math;

import 'ai_adjust.dart';
import 'models.dart';
import 'plan_duration.dart';

/// AI 調整的**時間預算**：依使用者還剩多少時間，決定要加多少、砍多少。
///
/// ## 2026-10-04 使用者裁決
///
/// 使用者在訓練中說「請幫我根據這個課表目標增加動作（增加整體強度）」，
/// 系統回「目前只能往這 4 個方向調」。之後的三項裁決：
///
/// 1. AI **可以**在訓練中加動作 —— 比照換動作：系統先算候選清單，
///    AI 只能從清單挑
/// 2. **加多少由剩餘時間決定**：可多加的時間 ＝ 可用時間 − 剩下的組
///    要花的時間。不夠一組只加重量；夠 1～2 組在現有動作加組；
///    夠 ≥ 3 組可加一個新動作
/// 3. 減組數也照時間砍，**先砍排在後面的動作，前面的主項保留**
///
/// ## 為什麼放在 App 這一側
///
/// 這是**規則**，不是判斷 —— 給定課表與時間，答案只有一個。
/// 模型只負責填重量、挑新動作、講理由；結構由這裡決定，
/// 模型給的組數對不上這裡的安排就不收（見 `AppState` 的合併）。
/// Worker 那一側只驗證，不重算 —— 同一條規則寫兩份，就是兩份會漂移。
///
/// **時間換組數用 [setSeconds]**：與課表頁「預估訓練時長」同一個公式，
/// 畫面說「約 30 分鐘」與 AI 說「你多出 5 分鐘」才對得起來。

/// 每個既有動作最多加幾組。超過的時間就不用了 —— 一個動作從 3 組
/// 加到 8 組不是「加強度」，是換了一份課表。
const kMaxAddedSetsPerExercise = 2;

/// 新動作的組數範圍。**下限也是門檻**：多出的時間不夠 3 組，
/// 就不值得為它換器材、找位置，改在現有動作上加組。
const kNewExerciseMinSets = 3;
const kNewExerciseMaxSets = 4;

/// 估不出單組時長時的預設 —— 約 10 下加 100 秒休息。
const kFallbackSetSeconds = 150;

/// 一次調整的組數安排。**索引是原始課表的位置**，不是切片後的。
class VolumePlan {
  /// 使用者說的可用時間。**空值＝他不知道或沒說** —— 這時退回
  /// 不看時間的舊規則（加強度只加重量、減組數每個動作砍一組）。
  final int? minutes;

  /// 剩下還沒做的組，預估要花幾秒。
  final int remainingSeconds;

  /// 一組大約幾秒（剩下那些組的平均）。用來把多出的時間換成組數。
  final int typicalSetSeconds;

  /// 索引 → 要加幾組。
  final Map<int, int> addSets;

  /// 索引 → 要砍幾組。
  final Map<int, int> cutSets;

  /// 新動作要幾組。0 代表不加新動作。
  final int newExerciseSets;

  /// 加強度只加重量（或自體重動作加次數），不加量。
  final bool weightOnly;

  /// 每個動作都砍到只剩一組了，仍超出可用時間幾秒。0 代表放得進。
  final int overSeconds;

  const VolumePlan({
    required this.minutes,
    required this.remainingSeconds,
    required this.typicalSetSeconds,
    this.addSets = const {},
    this.cutSets = const {},
    this.newExerciseSets = 0,
    this.weightOnly = false,
    this.overSeconds = 0,
  });

  /// 可多加的秒數。負值代表剩下的組本來就做不完。空值代表不知道時間。
  int? get budgetSeconds =>
      minutes == null ? null : minutes! * 60 - remainingSeconds;

  /// 剩下的組在可用時間內做得完。
  bool get fits => (budgetSeconds ?? -1) >= 0;

  int get addedSetCount =>
      addSets.values.fold(0, (a, b) => a + b) + newExerciseSets;
  int get cutSetCount => cutSets.values.fold(0, (a, b) => a + b);

  /// 某個動作調整後應該有幾組。**模型給的組數要對得上這個**，
  /// 對不上就不收、改用規則的那一筆。
  int expectedSets(int index, int current) =>
      current + (addSets[index] ?? 0) - (cutSets[index] ?? 0);
}

/// 把意圖去重、並擋掉互相矛盾的組合。
///
/// **同時要「降」又要「升」是矛盾的** —— 回空清單，讓上層再問一次。
/// 其他組合都合法：「累了而且只剩 20 分鐘」＝降強度＋減組數，
/// 「加動作而且加強度」＝加強度，「換掉臥推、其他加重」＝換動作＋加強度。
List<AdjustIntent> resolveIntents(Iterable<AdjustIntent> raw) {
  final out = <AdjustIntent>[];
  for (final i in raw) {
    if (!out.contains(i)) out.add(i);
  }
  if (out.contains(AdjustIntent.easier) && out.contains(AdjustIntent.harder)) {
    return const [];
  }
  return out;
}

/// 依時間預算安排組數。
///
/// [doneSets] 是索引 → 該動作**已經不在待做清單上**的組數（做完或略過）。
/// 那些組不算時間，也**不能被砍** —— 砍掉等於竄改紀錄。
/// [allowNewExercise] 只有訓練中才為真：規格「加入動作至本次訓練」的
/// Precondition 是本次訓練進行中。
VolumePlan planVolume({
  required List<PlanExercise> exercises,
  required List<AdjustIntent> intents,
  required int? minutes,
  required int Function(PlanExercise) restSecondsOf,
  int onlyFrom = 0,
  Map<int, int> doneSets = const {},
  bool allowNewExercise = false,
}) {
  var remaining = 0;
  var count = 0;
  var allSeconds = 0;
  var allCount = 0;
  for (var i = onlyFrom; i < exercises.length; i++) {
    final pe = exercises[i];
    final rest = restSecondsOf(pe);
    final done = doneSets[i] ?? 0;
    for (var j = 0; j < pe.planned.length; j++) {
      final sec = setSeconds(pe, pe.planned[j], rest);
      allSeconds += sec;
      allCount++;
      if (j >= done) {
        remaining += sec;
        count++;
      }
    }
  }
  final typical = count > 0
      ? remaining ~/ count
      : allCount > 0
          ? allSeconds ~/ allCount
          : kFallbackSetSeconds;

  final harder = intents.contains(AdjustIntent.harder);
  final trim = intents.contains(AdjustIntent.trim);
  final budget = minutes == null ? null : minutes * 60 - remaining;

  final add = <int, int>{};
  final cut = <int, int>{};
  var newSets = 0;
  var weightOnly = false;
  var over = 0;

  int minSetsOf(int i) => math.max(1, doneSets[i] ?? 0);

  if (trim) {
    if (budget == null) {
      // 不知道時間：舊規則 —— 每個動作砍最後一組，但至少留一組。
      for (var i = onlyFrom; i < exercises.length; i++) {
        if (exercises[i].planned.length > minSetsOf(i)) cut[i] = 1;
      }
    } else if (budget < 0) {
      // **先砍排在後面的動作，前面的主項保留**（2026-10-04 裁決 A）。
      // 一個動作砍到只剩一組，才輪到它前面那一個。
      var need = -budget;
      for (var i = exercises.length - 1; i >= onlyFrom && need > 0; i--) {
        final pe = exercises[i];
        final rest = restSecondsOf(pe);
        var len = pe.planned.length;
        while (need > 0 && len > minSetsOf(i)) {
          len--;
          need -= setSeconds(pe, pe.planned[len], rest);
          cut[i] = (cut[i] ?? 0) + 1;
        }
      }
      over = need > 0 ? need : 0;
    }
  }

  if (harder) {
    if (trim || budget == null) {
      // 同時要求減組數、或不知道時間 —— 不加量，只加重量。
      weightOnly = true;
    } else {
      var n = budget > 0 ? budget ~/ typical : 0;
      if (n < 1) {
        weightOnly = true;
      } else {
        if (allowNewExercise && n >= kNewExerciseMinSets) {
          newSets = math.min(kNewExerciseMaxSets, n);
          n -= newSets;
        }
        // 剩下的時間加在**前面的主項**上，一輪一組地分 ——
        // 與減組數「保住前面」是同一個取捨。
        final eligible = [
          for (var i = onlyFrom; i < exercises.length; i++)
            if (exercises[i].planned.isNotEmpty) i,
        ];
        var progressed = true;
        while (n > 0 && eligible.isNotEmpty && progressed) {
          progressed = false;
          for (final i in eligible) {
            if (n == 0) break;
            if ((add[i] ?? 0) >= kMaxAddedSetsPerExercise) continue;
            add[i] = (add[i] ?? 0) + 1;
            n--;
            progressed = true;
          }
        }
        if (add.isEmpty && newSets == 0) weightOnly = true;
      }
    }
  }

  return VolumePlan(
    minutes: minutes,
    remainingSeconds: remaining,
    typicalSetSeconds: typical,
    addSets: add,
    cutSets: cut,
    newExerciseSets: newSets,
    weightOnly: weightOnly,
    overSeconds: over,
  );
}

/// 秒數 → 「約 N 分鐘」用的整數分鐘，至少 1。
int minutesOf(int seconds) => math.max(1, (seconds / 60).round());

/// 從一句話裡讀出「還有幾分鐘」。讀不出來回空值。
///
/// [bareNumber] 為真時，單獨一個數字也當成分鐘 —— 那是在回答
/// 「你還有多少時間？」，「20」就是 20 分鐘。
int? parseMinutes(String text, {bool bareNumber = false}) {
  var t = text.trim();
  // 全形數字轉半形。
  t = String.fromCharCodes(t.runes.map((r) =>
      r >= 0xFF10 && r <= 0xFF19 ? r - 0xFF10 + 0x30 : r));

  int? ok(num v) {
    final m = v.round();
    return m >= 1 && m <= 600 ? m : null;
  }

  final halfHours = RegExp(r'(\d+|[一兩二三四五六七八九十]+)\s*個半小時').firstMatch(t);
  if (halfHours != null) {
    final h = _num(halfHours.group(1)!);
    if (h != null) return ok(h * 60 + 30);
  }
  if (t.contains('半小時') || t.contains('半個小時')) return 30;

  final hours =
      RegExp(r'(\d+(?:\.\d+)?|[一兩二三四五六七八九十]+)\s*(?:個)?\s*(?:小時|hr|hour|h\b)')
          .firstMatch(t);
  if (hours != null) {
    final h = _num(hours.group(1)!);
    if (h != null) return ok(h * 60);
  }

  final mins = RegExp(
          r'(\d+|[零一兩二三四五六七八九十]+)\s*(?:分鐘|分|min|mins|minutes)')
      .firstMatch(t);
  if (mins != null) {
    final m = _num(mins.group(1)!);
    if (m != null) return ok(m);
  }

  if (bareNumber) {
    final bare = RegExp(r'^(\d+)$').firstMatch(t);
    if (bare != null) return ok(int.parse(bare.group(1)!));
  }
  return null;
}

/// 「不知道還有多久」的說法。這時不再追問，退回不看時間的舊規則。
bool minutesUnknown(String text) {
  const words = ['不知道', '不確定', '不清楚', '不一定', '不限', '隨便', '都可以', '沒差'];
  return words.any(text.contains);
}

/// 阿拉伯數字或中文數字（到 99）。
num? _num(String s) {
  final d = num.tryParse(s);
  if (d != null) return d;
  const digits = {
    '零': 0, '一': 1, '兩': 2, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (s == '十') return 10;
  final ten = s.indexOf('十');
  if (ten >= 0) {
    final hi = ten == 0 ? 1 : digits[s.substring(0, ten)];
    final loS = s.substring(ten + 1);
    final lo = loS.isEmpty ? 0 : digits[loS];
    if (hi == null || lo == null) return null;
    return hi * 10 + lo;
  }
  return s.length == 1 ? digits[s] : null;
}
