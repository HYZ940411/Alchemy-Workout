import 'dart:math' as math;

import 'models.dart';

/// 調整的意圖。對應 AI 追問「要整體降強度，還是只換掉特定動作」的兩個答案。
enum AdjustIntent {
  /// 整體降強度：重量下修、次數上調，維持訓練量但降低單組負荷。
  easier,

  /// 整體升強度：重量上調。
  harder,

  /// 減量：砍掉每個動作的最後一組。
  trim,
}

const adjustIntentNames = <AdjustIntent, String>{
  AdjustIntent.easier: '整體降強度',
  AdjustIntent.harder: '整體升強度',
  AdjustIntent.trim: '減少組數',
};

/// 一個動作的一項變更。**AI 只產出建議，不套用** —— 故建議是一份
/// 可讀、可逐條檢視的資料，不是一段已經改好的課表。
class AdjustChange {
  /// 該動作在課表中的索引。套用時以索引對位，不用名稱。
  final int exerciseIndex;
  final String exerciseName;

  /// 調整後的逐組目標。空清單代表整個動作被移除（本版不產生）。
  final List<PlannedSet> after;

  /// 調整前的逐組目標，供畫面對照。
  final List<PlannedSet> before;

  /// 這一筆為什麼這樣調。**空值代表這一次沒有理由可說** ——
  /// 端內規則產的建議就是這種：它只會算，說不出所以然。
  ///
  /// 有了它，建議才不只是一組數字。使用者自己也會把 60 改成 55，
  /// 他需要的是「為什麼是 55 不是 50」。
  final String? reason;

  const AdjustChange({
    required this.exerciseIndex,
    required this.exerciseName,
    required this.before,
    required this.after,
    this.reason,
  });

  bool get setsChanged => before.length != after.length;

  /// 一行人話。畫面直接用它，不各自拼字串。
  String get summary {
    if (setsChanged) {
      return '$exerciseName　${before.length} 組 → ${after.length} 組';
    }
    final b = before.first;
    final a = after.first;
    if (b.targetWeight == a.targetWeight && b.targetReps == a.targetReps) {
      return '$exerciseName　維持不變';
    }
    String w(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
    if (b.targetWeight == 0 && a.targetWeight == 0) {
      return '$exerciseName　${b.targetReps} 下 → ${a.targetReps} 下';
    }
    return '$exerciseName　${w(b.targetWeight)}kg × ${b.targetReps} 下'
        ' → ${w(a.targetWeight)}kg × ${a.targetReps} 下';
  }

  /// 畫面上這一筆的完整文字：一行數字，有理由就再一行。
  ///
  /// **理由縮排一格**，讀起來才分得出「改什麼」與「為什麼」。
  String get detail => reason == null ? summary : '$summary\n　　$reason';
}

/// 一份建議。
class AdjustSuggestion {
  final AdjustIntent intent;
  final List<AdjustChange> changes;
  const AdjustSuggestion({required this.intent, required this.changes});

  bool get isEmpty => changes.every((c) =>
      !c.setsChanged &&
      c.before.first.targetWeight == c.after.first.targetWeight &&
      c.before.first.targetReps == c.after.first.targetReps);
}

/// 場館的槓片以 2.5kg 為級距，推到小數點沒有意義。
double _round(double kg) => (kg / 2.5).round() * 2.5;

/// 依**當前課表**產生建議。
///
/// 這是本專案端內模擬的「AI」：模型把 LLM 放在軟體邊界之外，
/// 只規定呼叫時點、扣點、失敗退點、以及「AI 僅產出建議、不套用」。
/// 建議的內容本身不是模型的規範對象，故此處以一組明確的規則產生 ——
/// **重點是它讀的是使用者眼前這份課表**，而非一段與課表無關的固定文字。
///
/// [onlyFrom] 為起始索引，訓練中調整用它把已完成的動作排除在外。
AdjustSuggestion buildSuggestion(
  List<PlanExercise> exercises,
  AdjustIntent intent, {
  int onlyFrom = 0,
}) {
  final changes = <AdjustChange>[];
  for (var i = onlyFrom; i < exercises.length; i++) {
    final pe = exercises[i];
    if (pe.planned.isEmpty) continue;
    final before = [...pe.planned];
    late List<PlannedSet> after;

    switch (intent) {
      case AdjustIntent.easier:
        // 降重量 10%、次數 +2：維持總反覆量，降低單組負荷。
        after = [
          for (final s in before)
            PlannedSet(
              s.targetWeight == 0 ? 0 : math.max(2.5, _round(s.targetWeight * 0.9)),
              s.targetReps + 2,
            ),
        ];
      case AdjustIntent.harder:
        after = [
          for (final s in before)
            PlannedSet(
              s.targetWeight == 0 ? 0 : _round(s.targetWeight * 1.05),
              s.targetReps,
            ),
        ];
      case AdjustIntent.trim:
        // 砍最後一組，但至少留一組 —— 砍到 0 組等於刪掉這個動作，
        // 那是「移除動作」不是「減量」。
        after = before.length > 1
            ? before.sublist(0, before.length - 1)
            : before;
    }
    changes.add(AdjustChange(
      exerciseIndex: i,
      exerciseName: pe.exercise.name,
      before: before,
      after: after,
    ));
  }
  return AdjustSuggestion(intent: intent, changes: changes);
}

/// 把建議套進一份課表，回傳新的動作清單。**不就地修改傳入的清單。**
///
/// 以索引對位：課表在建議產出後若被改動（加入動作），超出範圍者略過，
/// 不硬套到別的動作上。
List<PlanExercise> applySuggestion(
  List<PlanExercise> exercises,
  AdjustSuggestion s,
) {
  final out = [...exercises];
  for (final c in s.changes) {
    if (c.exerciseIndex < 0 || c.exerciseIndex >= out.length) continue;
    final pe = out[c.exerciseIndex];
    if (pe.exercise.name != c.exerciseName) continue; // 對位不上就不套
    out[c.exerciseIndex] = PlanExercise(
      exercise: pe.exercise,
      planned: c.after,
      replacedFrom: pe.replacedFrom,
      restSeconds: pe.restSeconds,
    );
  }
  return out;
}
