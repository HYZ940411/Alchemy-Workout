import 'dart:convert';

import 'boxed_error_stub.dart'
    if (dart.library.js_interop) 'boxed_error_web.dart';

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

/// 把一個例外變成**人看得懂的一行**。
///
/// ## 為什麼需要這一支
///
/// 在 Web 上，Dart 的例外一旦穿過 JS 的 Promise 邊界（Firestore 的
/// `runTransaction` 內部就是這樣做的），`toString()` 會變成一句樣板話：
///
/// > Error: Dart exception thrown from converted Future. Use the
/// > properties 'error' to fetch the boxed error and 'stack' to
/// > recover the stack trace.
///
/// **真正的錯誤被裝在 `error` 這個屬性裡**，而那句話自己就寫著怎麼拿。
/// 使用者 2026-09-30 連續兩輪拿到的都是這句 —— 儀器有在報，
/// 報的內容卻等於沒報。
///
/// 用動態存取取那個屬性，取不到就退回 `toString()`；
/// 整段包在 try 裡，任何平台上都不會因為這支而炸。
/// [depth] 是**明確的拆箱層數上限**，不靠身分比對擋循環。
///
/// 靠 `boxed != e` 擋的話，`a.error == b && b.error == a` 這種環仍會
/// 無限遞迴；而遞迴呼叫在 `try` 裡，堆疊爆掉會被外層默默吞掉，
/// 於是「無限遞迴」與「拆不開」在畫面上長得一樣。上限是看得見的。
String describeError(Object e, {int depth = 5}) {
  if (depth <= 0) return '$e';

  // **JS 物件要用平台專屬的取值。** Dart 的動態存取只對 Dart 物件有效，
  // 而從 JS Promise 拒絕回來的那個東西是 JS 物件 —— 動態存取會
  // `NoSuchMethodError`，於是永遠退回那句樣板話。
  //
  // 而且要**點名去讀** `code`／`name`／`message`：JS `Error` 的這些
  // 欄位不是可列舉屬性，通用的 `dartify()` 只會給出一個空物件。
  final js = jsErrorText(e);
  if (js != null) return js;

  // 讀不出 JS 欄位時，把裝在裡面的東西**原樣交回 Dart 這一側** ——
  // 它很可能本來就是個 Dart 物件，只是從 JS 那一側看不到內容
  // （`{}`、`[object Object]`）。交回來之後字串插值就會呼叫到
  // 它真正的 `toString()`。
  final boxed = jsBoxedValue(e);
  if (boxed != null && !identical(boxed, e)) {
    return describeError(boxed, depth: depth - 1);
  }

  try {
    final boxed = (e as dynamic).error;
    if (boxed != null && !identical(boxed, e)) {
      // 裝箱可能不只一層。
      return describeError(boxed as Object, depth: depth - 1);
    }
  } catch (_) {
    // 沒有那個屬性 —— 這是最常見的情況，不是錯誤。
  }
  return '$e';
}
