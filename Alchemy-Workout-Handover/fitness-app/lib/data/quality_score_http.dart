/// [QualityScoreSource] 的 HTTP 實作。
///
/// 與 `ai_suggestion_http.dart` 打同一個 Cloudflare Worker，
/// 不同端點（`/screen`）。金鑰在 Cloudflare 的 secret 裡，前端看不到。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/training_quality.dart';
import 'quality_score_data.dart';

class HttpQualityScoreSource implements QualityScoreSource {
  final Uri endpoint;

  /// 取得目前使用者的 Firebase ID token。回空值代表沒登入。
  /// 理由同 `HttpAiSuggestionSource`：這個類別不該知道 Firebase 的存在。
  final Future<String?> Function() idToken;

  final http.Client _client;

  HttpQualityScoreSource({
    required this.endpoint,
    required this.idToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<QualityScore> score(List<SessionSummary> sessions) async {
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw StateError('尚未登入，無法呼叫評分服務。');
    }

    final res = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          // **只送訓練數字，不送身分。** 承 `AdjustContext` 的既有裁決：
          // 暱稱、uid、電子郵件、生日一概不出這台裝置。
          body: jsonEncode({'sessions': encodeSessions(sessions)}),
        )
        // 使用者按完申請就離開了（規格：本路徑使用者不在場），
        // 所以可以等久一點 —— 但不能永遠等。
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw http.ClientException('評分服務回應 ${res.statusCode}', endpoint);
    }

    final data =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    final q = decodeQualityScore(data);
    if (q == null) {
      // **回傳不合格就當作失敗。** 不「盡量用」——三維缺一個或分數
      // 超出範圍的東西，拿去決定誰能當教官比沒有更糟。
      throw http.ClientException('評分服務回傳的內容不合格', endpoint);
    }
    return q;
  }
}

/// 送出去的形狀。Worker 那邊照這個解。
List<Map<String, Object>> encodeSessions(List<SessionSummary> sessions) => [
      for (final s in sessions)
        {
          'date': s.date.toIso8601String().split('T').first,
          'sets': s.totalSets,
          'minutes': s.minutes,
          // 攤平的 (重量, 次數)。不含動作名稱 —— 合理性看的是數字本身，
          // 而少送一樣東西就少一樣可能識別出這個人的東西。
          'reps': [
            for (final (w, r) in s.sets) [w, r],
          ],
        },
    ];

/// 解模型回來的東西。**任何一項不合格就回空值。**
///
/// 這是「伺服器端不信模型輸出」的前端那一半 —— Worker 也會驗一次。
/// 兩邊都驗不是重複，是因為兩邊被繞過的方式不同：Worker 擋的是模型，
/// 這裡擋的是「Worker 被改壞了」。
QualityScore? decodeQualityScore(Map<String, dynamic> j) {
  int? intOf(Object? v) => v is num ? v.round() : null;

  final completion = intOf(j['completion']);
  final consistency = intOf(j['consistency']);
  final sanity = intOf(j['sanity']);
  if (completion == null || consistency == null || sanity == null) return null;

  final q = QualityScore(
    completion: completion,
    consistency: consistency,
    sanity: sanity,
    concerns: [
      for (final c in (j['concerns'] as List? ?? const []))
        if (c is String && c.trim().isNotEmpty)
          // 疑慮標記會被畫在管理員的待審佇列上，限長免得一則塞爆整頁。
          c.trim().length > 60 ? c.trim().substring(0, 60) : c.trim(),
    ],
    source: 'gemini',
  );
  return q.valid ? q : null;
}
