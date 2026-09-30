import 'dart:typed_data';

/// 使用者上傳的照片的存讀邊界。
///
/// ## 為什麼存在 Firestore 而不是物件儲存
///
/// 2026-09-28 使用者裁決。原本的計畫是 Cloudflare R2（因為 Firebase
/// Storage 自 2026-02-03 起需要 Blaze 方案），但 R2 要先在 dashboard
/// 走一次訂閱結帳流程 —— 使用者的原話是
/// 「**所以為什麼上傳個圖片需要那麼麻煩？不能簡單化嗎？**」
///
/// 他是對的。這個專案**已經有一個存得下東西的地方**：Firestore。
/// Spark 免費層 1 GiB，一張壓好的照片約 100–250 KB，
/// 大約放得下五千張。不必開新服務、不必填卡。
///
/// **代價講在前面**：Firestore 不是 CDN。每次有人看到圖就算一次文件讀取
/// （免費層每日五萬次），而且沒有邊緣快取。那是「幾千個使用者」等級的
/// 問題，不是現在的問題。
///
/// **搬家的門留著**：貼文存的是圖片 ID 字串（本來就是），
/// 要換成 R2 只換這一層的實作。
abstract class PhotoSource {
  /// 存一張照片，回傳它的 ID。[bytes] 須已壓縮（見 `domain/photo.dart`）。
  Future<String> put(Uint8List bytes);

  /// 取一張照片。**找不到就回空值** —— 照片可能被作者刪了，
  /// 而那不該讓整個動態牆炸掉。
  Future<Uint8List?> get(String id);
}
