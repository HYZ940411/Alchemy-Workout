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

import '../domain/ai_adjust.dart';
import '../domain/models.dart';
import 'ai_suggestion.dart';

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
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
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
            'intent': intent.name,
            if (note != null && note.isNotEmpty) 'note': note,
            ...encodePlan(exercises, onlyFrom),
          }),
        )
        // 使用者在等。逾時就讓它走既有的「失敗退點」流程，
        // 比讓他對著轉圈等到放棄好。
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw http.ClientException('AI 服務回應 ${res.statusCode}', endpoint);
    }
    final data =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    return RemoteSuggestion(
      originOf(data),
      decodeSuggestion(data, exercises, intent, onlyFrom),
    );
  }
}
