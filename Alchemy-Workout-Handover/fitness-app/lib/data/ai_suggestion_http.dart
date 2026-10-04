/// [AiSuggestionSource] 的 HTTP 實作（`[BE-08]`）。
///
/// 呼叫的是**我們自己的 Cloudflare Worker**，不是 Gemini ——
/// 金鑰在 Cloudflare 的 secret 裡，前端從頭到尾看不到它。
/// 理由見 `ai_suggestion.dart` 與 `workers/README.md`。
///
/// ## 為什麼 token 是用傳的，不是自己去拿
///
/// 這個類別不該知道 Firebase 的存在 —— 測試要能在沒有 Firebase 的環境
/// 跑，而 `lib/data/` 底下的其他來源也都是這個模式。呼叫端
/// （`main.dart`）把 `() => FirebaseAuth.instance.currentUser?.getIdToken()`
/// 傳進來就好。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/adjust_volume.dart';
import '../domain/ai_adjust.dart';
import '../domain/models.dart';
import 'ai_suggestion.dart';
import 'http_error.dart';

class HttpAiSuggestionSource implements AiSuggestionSource {
  /// Worker 的網址，形如 `https://alchemy-workout-ai.xxx.workers.dev`。
  final Uri endpoint;

  /// 取得目前使用者的 Firebase ID token。回空值代表沒登入。
  final Future<String?> Function() idToken;

  final http.Client _client;

  HttpAiSuggestionSource({
    required this.endpoint,
    required this.idToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<RemoteIntent> classify(String say) async {
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw StateError('尚未登入，無法呼叫 AI。');
    }

    final res = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'say': say}),
        )
        // **比 suggest 短，但要放得下 Worker 那一側的一次重試。**
        //
        // 第一版設 10 秒，而 Worker 冷啟動時要先打一趟 `listModels`
        // （逾時 10 秒）再打 generateContent —— 加起來就超過了。
        // 使用者回報「分析時間非常久，得不到答案」。
        //
        // Worker 已改成不在熱路徑上探測模型（`gemini.ts`），
        // 正常一趟約 1–3 秒；這裡留 20 秒是給「模型退役那一天」
        // 的那一次額外重試，不是給常態。
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw http.ClientException(
          httpFailureReason('AI 服務回應', res), endpoint);
    }
    final data =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    final raw = data['intent'];
    // 模型回什麼都不信，只認四個值之一。
    AdjustIntent? named(Object? v) =>
        AdjustIntent.values.where((i) => i.name == v).firstOrNull;
    final match = named(raw);
    // **多個方向**（2026-10-04 起）。舊版 Worker 沒有這個欄位 ——
    // 那時就只有 [match] 一個。
    final list = data['intents'];
    final intents = list is List
        ? resolveIntents([for (final v in list) ?named(v)])
        : null;
    final m = data['minutes'];
    return RemoteIntent(
      intents == null ? match : intents.firstOrNull,
      intents: intents,
      minutes: m is num && m >= 1 && m <= 600 ? m.round() : null,
    );
  }

  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) async {
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw StateError('尚未登入，無法呼叫 AI。');
    }

    final res = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            // `auto` 不是四個方向之一 —— 它是「請你自己判斷」的意思。
            'intent': 'auto',
            ...encodePlan(exercises, 0, context: context),
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw http.ClientException(
          httpFailureReason('自動優化', res), endpoint);
    }
    final data =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    final raw = data['intent'];
    final intent =
        AdjustIntent.values.where((i) => i.name == raw).firstOrNull;
    if (intent == null) return const RemoteAutoAdjust();
    final why = data['why'];
    return RemoteAutoAdjust(
      intent: intent,
      why: why is String && why.trim().isNotEmpty ? why.trim() : null,
      suggestion: decodeSuggestion(data, exercises, intent, 0,
          candidates: candidates),
    );
  }

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) async {
    final token = await idToken();
    if (token == null || token.isEmpty) {
      // 沒登入就不該送出去 —— Worker 也會擋，但沒必要浪費一趟往返。
      throw StateError('尚未登入，無法呼叫 AI。');
    }

    final res = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            // `intent` 留著給舊版 Worker；新版看 `intents`。
            'intent': intent.name,
            if (intents != null && intents.length > 1)
              'intents': [for (final i in intents) i.name],
            if (note != null && note.isNotEmpty) 'note': note,
            if (volume != null) 'volume': encodeVolume(volume, onlyFrom),
            if (addCandidates.isNotEmpty)
              'addCandidates': [for (final e in addCandidates) e.name],
            ...encodePlan(exercises, onlyFrom, context: context),
          }),
        )
        // 使用者在等。逾時就讓它走既有的「失敗退點」流程，
        // 比讓他對著轉圈等到放棄好。
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw http.ClientException(
          httpFailureReason('AI 服務回應', res), endpoint);
    }
    final data =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    return RemoteSuggestion(
      originOf(data),
      decodeSuggestion(data, exercises, intent, onlyFrom,
          candidates: candidates,
          intents: intents,
          addCandidates: addCandidates),
      error: errorOf(data),
    );
  }
}
