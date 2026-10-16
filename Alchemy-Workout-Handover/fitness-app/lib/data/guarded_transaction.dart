import 'package:cloud_firestore/cloud_firestore.dart';

import 'http_error.dart';

/// 跑一筆交易，**判斷留在交易裡，例外丟在交易外面**。
///
/// ## 為什麼不直接 `runTransaction`
///
/// 兩個坑，都踩過（`PROGRESS.md` 3F／3G）：
///
/// 1. **守衛靜靜 `return`**：交易正常結束 → `Future` 正常完成 → 呼叫端記成
///    「成功」，而雲端一個字都沒變。人數已滿、隊伍不存在，都長這樣。
/// 2. **守衛在交易裡 `throw`**：在 Web 上，Dart 例外一旦穿過 JS 的 Promise 邊界，
///    訊息全失，只剩「Dart exception thrown from converted Future」。
///    連續六輪都讀不出原因。
///
/// 所以 [body] **不丟例外**：判斷不成立就回傳一句原因（成立回 `null`），
/// 交易跑完、回到 Dart 這一側之後才由這裡丟 [StateError]。
/// 交易裡只有「讀、判斷、寫」，沒有任何東西需要穿過邊界。
///
/// 競爭條件是真的（人數上限、計數器），**不要拿掉交易** ——
/// 要改的只有「失敗怎麼說出口」。
///
/// 要帶出交易裡算的值，用 closure 變數，不要靠 `runTransaction` 的回傳值。
Future<void> guardedTransaction(
  FirebaseFirestore db,
  String what,
  Future<String?> Function(Transaction tx) body,
) async {
  String? refused;
  // 失敗發生在哪一段：交易根本沒開始、body 裡（讀或寫）、還是 body 做完等提交時。
  // 2026-10-17 所有交易都失敗，錯誤只有一個沒有內容的物件，連是哪一段壞的都看不出來。
  var phase = '交易還沒開始（還沒進到 body）';
  try {
    await db.runTransaction<void>((tx) async {
      // 交易可能重跑；每一輪都重新決定，以最後一輪為準。
      phase = '正在跑 body（讀取或寫入暫存）';
      refused = await body(tx);
      phase = 'body 已做完，等伺服器提交';
    });
  } catch (e) {
    throw StateError('$what：交易失敗（階段：$phase；錯誤類型：${e.runtimeType}）'
        '${_detail(e)}');
  }
  final why = refused;
  if (why != null) throw StateError('$what：$why');
}

String _detail(Object e) {
  final d = describeError(e);
  return d.isEmpty ? '' : '　$d';
}
