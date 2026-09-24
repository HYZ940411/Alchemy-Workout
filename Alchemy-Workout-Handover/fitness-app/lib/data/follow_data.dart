/// 關注關係的存讀邊界（[BE-11] 批次 2）。
///
/// ## 為什麼是 uid 而不是暱稱
///
/// 畫面上、`AppState` 裡的關注都以暱稱為鍵（`following` 是 `Set<String>`），
/// 但雲端**一律以 uid 為鍵** —— 暱稱不唯一、而且可以改。
/// 兩者之間的翻譯由批次 1 的 `AppState.nameByUid` 負責，
/// 這個介面只認 uid，不知道暱稱這回事。
///
/// ## 為什麼方法是非同步、而呼叫端是同步的
///
/// `AppState.toggleFollow` 是同步的 `void`，畫面按下去要立刻有反應。
/// 所以寫入採**樂觀更新 ＋ 即發即忘**：記憶體先改、畫面先動，
/// 雲端的寫入在背景進行。失敗了下次登入會以雲端為準重新對齊 ——
/// 關注關係不是金流，晚一點一致是可以接受的。
abstract class FollowSource {
  /// 我關注了誰。
  Future<void> follow(String targetUid);

  /// 我取消關注誰。
  Future<void> unfollow(String targetUid);

  /// 我關注的所有人（uid）。
  Future<Set<String>> following();

  /// 關注我的所有人（uid）。
  ///
  /// 粉絲數依〈使用者 Aggregate〉是**儲存欄位**，不變條件為
  /// 「粉絲數 ＝ 關注關係中被關注者為本人的筆數」——
  /// 這個方法就是那個不變條件的右邊，用來校正左邊。
  Future<Set<String>> followers();

  /// **某個人**現在有幾個粉絲。
  ///
  /// ## 為什麼需要它
  ///
  /// 畫面原本顯示的是 `public_profiles/{uid}.followers` 這個衍生計數，
  /// 而那份文件**只有本人寫得了**（安全規則：只有本人可寫）。所以我
  /// 關注某人，`follows/` 多了一筆、對方的 `followers` 欄位不動 ——
  /// 一重新整理，本機計數被重設成對方檔案上的舊值，我的 +1 就消失了。
  /// 使用者 2026-09-24 回報「重新追蹤刷新後顯示還是 0」，那是必然不是偶發。
  ///
  /// 這一支直接數關係本身（`follows` 才是真相來源），**不依賴對方登入**。
  /// 用聚合查詢，不把整批關係抓回來 —— 計費是每 1000 筆索引項算一次讀取。
  Future<int> followerCountOf(String uid);
}
