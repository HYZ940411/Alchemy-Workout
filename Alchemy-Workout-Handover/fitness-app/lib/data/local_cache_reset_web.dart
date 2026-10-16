import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Web：關掉 Firestore → 清本機快取 → 重新載入頁面。
///
/// 順序不能換：`clearPersistence()` 只有在 `terminate()` 之後才能呼叫。
/// 任何一步失敗都不擋登出（登出已經完成），照樣重新載入 ——
/// 重新載入本身就會讓畫面回到乾淨的登入頁。
Future<void> wipeLocalCacheAndReload(FirebaseFirestore db) async {
  try {
    await db.terminate();
    await db.clearPersistence();
  } catch (_) {
    // 其他分頁還開著時 clearPersistence 會失敗；那種情況下清不掉，也不該卡住使用者。
  }
  web.window.location.reload();
}
