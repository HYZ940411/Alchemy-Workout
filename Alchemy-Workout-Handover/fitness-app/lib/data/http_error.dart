import 'dart:convert';

import 'package:http/http.dart' as http;

/// 把非 200 的回應轉成**說得出原因**的一句話。
///
/// ## 為什麼這是共用的
///
/// Worker 把真正的原因寫在回應內容裡
/// （`{"error":"分類失敗：gemini … 429: 配額用盡"}`），而呼叫端原本只取
/// 狀態碼。於是開發者模式的診斷面板永遠只寫得出「502」——
/// 而 502 可能是模型退役、金鑰沒權限、或配額用盡，三者的處置完全不同。
///
/// 2026-09-27 我在 `ai_suggestion_http.dart` 修好這件事，
/// **卻沒有套到 `quality_score_http.dart`** —— 使用者下一次截圖回報的
/// 就是「評分服務回應 502」，一樣什麼都看不出來。
///
/// 同一個決定寫在兩個地方，只做對一處。抽成一份，就沒有第二個地方可以漏。
String httpFailureReason(String what, http.Response res) {
  final body = utf8.decode(res.bodyBytes, allowMalformed: true);
  var detail = body;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['error'] is String) detail = j['error'] as String;
  } catch (_) {
    // 不是 JSON 就用原文。
  }
  detail = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
  return '$what ${res.statusCode}${detail.isEmpty ? '' : '：$detail'}';
}
