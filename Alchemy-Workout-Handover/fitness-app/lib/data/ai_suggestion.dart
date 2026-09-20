/// 訓練調整建議的產生邊界（`[BE-08]`）。
///
/// ## 為什麼要有這一層
///
/// 規格把 LLM 放在軟體邊界**之外**（「AI 為系統呼叫的外部 API」），
/// 只規範呼叫時點、扣點、失敗退點與「AI 僅產出建議、不套用」。
/// 那四件事在 `AppState` 裡早就做好了，缺的一直只是邊界外那一段。
///
/// 這個介面就是那條邊界。**空值代表不接外部 API**，走 `ai_adjust.dart`
/// 的端內規則 —— 既有的一千多條測試全部走這條，一行都不必改。
///
/// ## 為什麼金鑰不在這裡
///
/// 實作端（[CloudAiSuggestionSource]）呼叫的是我們自己的 Cloud Function，
/// 不是 Gemini。金鑰放 Secret Manager，前端連看都看不到 ——
/// Flutter Web 的 `main.dart.js` 會原封不動送到每一位訪客手上，
/// 金鑰寫在裡面等同公開。這是整個 `functions/` 目錄存在的理由。
library;

import '../domain/ai_adjust.dart';
import '../domain/models.dart';

/// 這一份建議是誰產的。
///
/// **兩者都是合法結果**：模型失敗時伺服器會退回規則，使用者照樣拿得到
/// 可用的建議。但分不出來的話，就查不出模型從哪一天開始失常。
enum SuggestionOrigin { gemini, rule }

class RemoteSuggestion {
  final SuggestionOrigin origin;
  final AdjustSuggestion suggestion;
  const RemoteSuggestion(this.origin, this.suggestion);
}

abstract class AiSuggestionSource {
  /// 依這份課表與方向取得建議。
  ///
  /// [onlyFrom] 之前的動作已經練完了，不送上去也不調整。
  /// 擲出例外代表這一次失敗 —— 呼叫端應走既有的「已扣點後退還」流程。
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
  });
}

/// 送出去的形狀。**只送動作名稱與逐組目標**，不送使用者是誰、
/// 不送身高體重 —— 調整建議用不到，送了就是白白擴大外洩面。
Map<String, dynamic> encodePlan(List<PlanExercise> exercises, int onlyFrom) => {
      'exercises': [
        for (var i = onlyFrom; i < exercises.length; i++)
          {
            'name': exercises[i].exercise.name,
            'sets': [
              for (final s in exercises[i].planned)
                {'weight': s.targetWeight, 'reps': s.targetReps},
            ],
          },
      ],
    };

/// 把回來的東西接回本機的型別。
///
/// **索引要加回 [onlyFrom]**：送上去的是切過的清單，伺服器回的 index
/// 是那份切片裡的位置，而 `applySuggestion` 對的是原始課表的位置。
/// 這裡沒加回去的話，訓練中調整會把建議套到已經練完的動作上。
AdjustSuggestion decodeSuggestion(
  Map<String, dynamic> data,
  List<PlanExercise> exercises,
  AdjustIntent intent,
  int onlyFrom,
) {
  final raw = (data['changes'] as List?) ?? const [];
  final changes = <AdjustChange>[];

  for (final item in raw) {
    final m = (item as Map).cast<String, dynamic>();
    final i = (m['index'] as num).toInt() + onlyFrom;
    if (i < 0 || i >= exercises.length) continue;
    final pe = exercises[i];
    // 名稱對不上就不要 —— 伺服器已經驗過一次，這裡是第二道。
    if (m['name'] != pe.exercise.name) continue;

    final after = [
      for (final s in (m['after'] as List))
        PlannedSet(
          ((s as Map)['weight'] as num).toDouble(),
          (s['reps'] as num).toInt(),
        ),
    ];
    if (after.isEmpty) continue;

    changes.add(AdjustChange(
      exerciseIndex: i,
      exerciseName: pe.exercise.name,
      before: [...pe.planned],
      after: after,
    ));
  }
  return AdjustSuggestion(intent: intent, changes: changes);
}

SuggestionOrigin originOf(Map<String, dynamic> data) =>
    data['source'] == 'gemini' ? SuggestionOrigin.gemini : SuggestionOrigin.rule;
