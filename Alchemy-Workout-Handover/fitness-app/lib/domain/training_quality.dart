import 'dart:math' as math;

import 'platform_config.dart';

/// AI 訓練品質評分（教官申請初審）。
///
/// 規格：`教官申請流程.md` 與 `02_Aggregate定義.md`〈教官申請 Aggregate〉。
/// 三個維度各 0–100 分後加權平均；**AI 僅產出評分與疑慮標記，不直接裁決**
/// —— 通過與否由 [evaluateInstructorGate] 依門檻判定。
///
/// ## 為什麼先做規則計算
///
/// 使用者裁決走 Gemini（2026-09-25）。但無論由誰評分，**規則計算都必須
/// 存在**：規格明訂 AI 服務中斷時「不直接駁回」（申請者本身無過失），
/// 所以要有東西頂著。這與 `workers/src/adjust.ts` 的 `ruleFallback()`
/// 是同一個道理。
///
/// 在此之前 `AppState.qualityScore = 72`／`sanityScore = 68` 是**寫死的**
/// —— 每一位申請人拿到的都是同一組數字。
class QualityScore {
  /// 維度一：抓偷懶。
  final int completion;

  /// 維度二：抓是否長期在練。
  final int consistency;

  /// 維度三：抓造假。**受一票否決門檻檢核。**
  final int sanity;

  /// AI 產出的疑慮項目，不直接裁決。
  final List<String> concerns;

  /// 評分來源。規則計算為 `rules`，模型產出為 `gemini` ——
  /// 管理端要分得出這筆評分是誰算的。
  final String source;

  const QualityScore({
    required this.completion,
    required this.consistency,
    required this.sanity,
    this.concerns = const [],
    this.source = 'rules',
  });

  /// 三維加權平均。權重取自〈教官初審設定〉，管理員可調。
  int get weighted {
    final c = platformConfig;
    final wc = c.i('instructorGate', 'wCompletion');
    final wr = c.i('instructorGate', 'wConsistency');
    final ws = c.i('instructorGate', 'wSanity');
    final total = wc + wr + ws;
    if (total <= 0) return 0; // 權重被調成全 0：不當機，當作 0 分交給門檻擋
    return ((completion * wc + consistency * wr + sanity * ws) / total)
        .round();
  }

  /// 三維都在 0–100 之內。**模型回來的東西一律要過這一關。**
  bool get valid =>
      _in(completion) && _in(consistency) && _in(sanity);

  static bool _in(int v) => v >= 0 && v <= 100;
}

/// 一場訓練的摘要 —— 評分只需要這些，不需要整份紀錄。
///
/// 刻意做成獨立的小結構而不是直接吃 `HistoryEntry`：
/// 送給模型的東西必須**不含身分**（承 `AdjustContext` 的既有裁決），
/// 而且這一層要能在沒有 App 的地方（Worker）重算一次。
class SessionSummary {
  final DateTime date;
  final int totalSets;
  final int minutes;

  /// 這場每一組的 (重量, 次數)。攤平，不分動作 —— 合理性看的是數字本身。
  final List<(double, int)> sets;

  const SessionSummary({
    required this.date,
    required this.totalSets,
    required this.minutes,
    required this.sets,
  });
}

/// 依訓練紀錄算出三維分數。
///
/// **看得到什麼就算什麼，看不到的不假裝。** 目前訓練紀錄裡沒有存
/// 「計畫組數」與「提前結束／逾時中斷」的旗標，所以維度一只能從
/// 每場組數的穩定度推估 —— 這是已知的不足，不是遺漏。
/// 要做滿需要 `session_plans` 與 `workout_sessions` 落地（見
/// `Firestore-Schema設計.md` §2.3），那是另一件事。
QualityScore scoreTrainingQuality(List<SessionSummary> sessions) {
  if (sessions.isEmpty) {
    // 沒有紀錄不是「品質差」，是「無從評分」—— 全給 0 交給門檻擋下，
    // 而不是給一個看起來合理的中間值。
    return const QualityScore(
      completion: 0,
      consistency: 0,
      sanity: 0,
      concerns: ['沒有任何訓練紀錄，無從評分'],
    );
  }

  final sorted = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
  final concerns = <String>[];

  return QualityScore(
    completion: _completion(sorted, concerns),
    consistency: _consistency(sorted, concerns),
    sanity: _sanity(sorted, concerns),
    concerns: concerns,
  );
}

/// 維度一「訓練完成率」—— 抓偷懶。
///
/// 現有紀錄能看到的是**每場的組數**。一場只做 2 組就結束、或場與場之間
/// 組數忽多忽少，都是「開了課表卻沒做完」的跡象。
int _completion(List<SessionSummary> s, List<String> concerns) {
  final sets = [for (final x in s) x.totalSets];
  final avg = sets.reduce((a, b) => a + b) / sets.length;

  // 一場低於 6 組視為沒做完（三個動作各兩組是常見課表的下限）。
  const floor = 6;
  final short = sets.where((n) => n < floor).length;
  final shortRatio = short / sets.length;
  if (shortRatio > 0.3) {
    concerns.add('${(shortRatio * 100).round()}% 的訓練不足 $floor 組');
  }

  // 平均組數 12 組給滿分，線性到 0。
  final byAvg = (avg / 12 * 100).clamp(0, 100).toDouble();
  // 未完成的比例直接扣。
  return (byAvg * (1 - shortRatio)).round().clamp(0, 100);
}

/// 維度二「訓練規律性」—— 抓是否長期在練，而不是集中衝量後消失。
int _consistency(List<SessionSummary> s, List<String> concerns) {
  if (s.length < 2) {
    concerns.add('訓練場次過少，規律性無從判斷');
    return 0;
  }

  final span = s.last.date.difference(s.first.date).inDays + 1;
  final weeks = math.max(span / 7, 1.0);
  final perWeek = s.length / weeks;

  // 每週 3 次給滿分。
  final byRate = (perWeek / 3 * 100).clamp(0, 100).toDouble();

  // 間隔的離散程度：標準差越大代表越不規律。
  final gaps = <int>[];
  for (var i = 1; i < s.length; i++) {
    gaps.add(s[i].date.difference(s[i - 1].date).inDays);
  }
  final gapAvg = gaps.reduce((a, b) => a + b) / gaps.length;
  final variance =
      gaps.map((g) => math.pow(g - gapAvg, 2)).reduce((a, b) => a + b) /
          gaps.length;
  final sd = math.sqrt(variance);
  // 標準差 0 天＝完全規律；7 天以上視為毫無規律。
  final bySpread = ((1 - sd / 7) * 100).clamp(0, 100).toDouble();

  if (sd > 5) {
    concerns.add('訓練間隔很不平均（標準差 ${sd.toStringAsFixed(1)} 天）');
  }

  return ((byRate + bySpread) / 2).round().clamp(0, 100);
}

/// 維度三「紀錄合理性」—— 抓造假。**這一維受一票否決門檻檢核。**
///
/// 四個訊號：每組耗時過短、重量超出人體合理範圍、重量突然暴增、
/// 多次訓練的數字完全雷同。
int _sanity(List<SessionSummary> s, List<String> concerns) {
  var score = 100;

  // ① 每組耗時過短 —— 一組（含休息）少於 30 秒不合理。
  var tooFast = 0;
  for (final x in s) {
    if (x.totalSets == 0) continue;
    if (x.minutes * 60 / x.totalSets < 30) tooFast++;
  }
  if (tooFast > 0) {
    score -= (tooFast / s.length * 40).round();
    concerns.add('$tooFast 場的每組平均耗時低於 30 秒');
  }

  // ② 重量超出人體合理範圍 —— 單一動作超過 500 公斤。
  final absurd = s
      .expand((x) => x.sets)
      .where((t) => t.$1 > 500 || t.$2 > 100)
      .length;
  if (absurd > 0) {
    score -= 30;
    concerns.add('有 $absurd 組的重量或次數超出人體合理範圍');
  }

  // ③ 多次訓練的數字完全雷同 —— 照抄預帶值的樣子。
  //
  // **看「最常見的那一份佔多少」，不看「有幾種」。**
  // 第一版用「相異數 ≤ 場次/3」，那會把**三分化課表**判成造假：
  // 推／拉／腿輪著練，二十場自然只有三種組合。而那是正常訓練。
  //
  // 真正的訊號是規格說的「數字**完全雷同**」—— 同一份數字一再出現。
  // 所以改看最高重複率：超過六成的場次是同一份數字才標記。
  if (s.length >= 5) {
    final counts = <String, int>{};
    for (final x in s) {
      final key = x.sets.map((t) => '${t.$1}x${t.$2}').join('|');
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final most = counts.values.reduce(math.max);
    if (most / s.length > 0.6) {
      score -= 30;
      concerns.add('$most／${s.length} 場訓練的重量與次數完全相同，疑似照抄預帶值');
    }
  }

  // ④ 重量突然暴增 —— 場均重量較前一場成長超過一倍。
  var jumps = 0;
  for (var i = 1; i < s.length; i++) {
    final prev = _avgWeight(s[i - 1]);
    final now = _avgWeight(s[i]);
    if (prev > 0 && now > prev * 2) jumps++;
  }
  if (jumps > 0) {
    score -= (jumps * 10).clamp(0, 30);
    concerns.add('$jumps 次訓練的平均重量較前一場成長超過一倍');
  }

  return score.clamp(0, 100);
}

double _avgWeight(SessionSummary s) {
  if (s.sets.isEmpty) return 0;
  return s.sets.map((t) => t.$1).reduce((a, b) => a + b) / s.sets.length;
}
