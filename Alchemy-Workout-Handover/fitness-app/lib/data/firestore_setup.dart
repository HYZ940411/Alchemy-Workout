import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_cache_reset_stub.dart'
    if (dart.library.js_interop) 'local_cache_reset_web.dart' as impl;

/// 打開 Firestore 的本機持久快取。**必須在第一次用 Firestore 之前呼叫。**
///
/// 離線緩存（規格：進入健身紀錄模式後，離線時先緩存、網路穩定後自動同步）：
/// - 手機（iOS／Android）：SDK 預設就開著；這裡明寫一次，不靠預設值。
/// - **Web：SDK 預設關閉。** 關著的時候，斷網期間的寫入只活在這個分頁的記憶體裡，
///   關掉或重新整理就沒了（2026-10-15 盤點，使用者同意補）。
///   開了之後寫入存在瀏覽器的 IndexedDB，重新開啟還在，連上網自動送出。
///   用多分頁管理：同一個帳號開兩個分頁也都能用，不會第二個分頁退回無快取。
void configureFirestorePersistence(FirebaseFirestore db) {
  db.settings = const Settings(
    persistenceEnabled: true,
    webPersistentTabManager: WebPersistentMultipleTabManager(),
  );
}

/// 登出之後：清掉這個瀏覽器上的 Firestore 本機快取並重新載入頁面。
///
/// 為什麼要清：持久快取是**綁瀏覽器、不綁帳號**的。共用電腦上，上一位的存檔、貼文、私訊
/// 若還躺在 IndexedDB 裡，下一位用同一個瀏覽器就碰得到。
/// 只在 Web 做；手機的快取在 App 沙盒裡，不需要。
///
/// 呼叫端要確認**已經同步完**才呼叫 —— 清掉快取也會清掉還沒送出的寫入。
Future<void> wipeLocalCacheAndReload(FirebaseFirestore db) =>
    impl.wipeLocalCacheAndReload(db);
