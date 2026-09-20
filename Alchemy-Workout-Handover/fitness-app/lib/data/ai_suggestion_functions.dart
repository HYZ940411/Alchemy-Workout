/// [AiSuggestionSource] 的 Cloud Functions 實作（`[BE-08]`）。
///
/// 呼叫的是**我們自己的** `adjustPlan`，不是 Gemini —— 金鑰在
/// Secret Manager，前端從頭到尾看不到它。理由見 `ai_suggestion.dart`。
///
/// 區域與 Firestore 一致（`asia-east1`），少一趟跨區往返。
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../domain/ai_adjust.dart';
import '../domain/models.dart';
import 'ai_suggestion.dart';

class CloudAiSuggestionSource implements AiSuggestionSource {
  final FirebaseFunctions _fn;
  CloudAiSuggestionSource([FirebaseFunctions? fn])
      : _fn = fn ?? FirebaseFunctions.instanceFor(region: 'asia-east1');

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
  }) async {
    final res = await _fn.httpsCallable('adjustPlan').call<Map<String, dynamic>>({
      'intent': intent.name,
      ...encodePlan(exercises, onlyFrom),
    });
    final data = res.data;
    return RemoteSuggestion(
      originOf(data),
      decodeSuggestion(data, exercises, intent, onlyFrom),
    );
  }
}
