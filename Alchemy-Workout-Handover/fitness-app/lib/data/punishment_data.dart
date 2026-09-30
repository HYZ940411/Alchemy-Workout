import '../domain/commerce.dart';

/// 處罰狀態（`[BE-13]`，2026-09-25）。
///
/// ## 為什麼要上雲
///
/// 在此之前 `AppState.punishment` **只活在記憶體裡**（連存檔都沒有），
/// 而且 `_issuePunishment()` 只在「被罰的是我自己」時才跑 ——
/// 也就是**管理員只罰得到自己**。判別人成立，對方那邊什麼都沒發生。
///
/// 存檔也不是正確的家：存檔是本人寫得動的，被罰的人自己就能清掉。
/// 所以與累計違規次數同一個形狀：**管理員可寫、當事人唯讀**。
///
/// 唯一的例外是申訴 —— 那是當事人發起的，所以 `appealed` 與
/// `appealState` 這兩個欄位當事人改得動（規則用 `affectedKeys` 限住，
/// 與貼文的 `likeCount` 同一個手法）。
abstract class PunishmentSource {
  /// 這個人目前的處罰。沒有回空值。
  ///
  /// 當事人讀自己的，或管理員讀別人的。其餘一律被規則拒絕。
  Future<Punishment?> of(String uid);

  /// 下處罰。**只有管理員叫得動。**
  Future<void> issue(String uid, Punishment p, {required String name});

  /// 標記已申訴。**當事人自己叫的** —— 只動得了申訴那兩個欄位。
  Future<void> markAppealed(String uid, AppealState state);

  /// 撤銷處罰（申訴成立）。**只有管理員叫得動。**
  ///
  /// 直接刪掉那份文件 —— 「沒有處罰」的樣子就是文件不存在，
  /// 與會員權益的「從未訂閱過」同一個處理（見 `store_firestore.dart`）。
  /// 留一個 `kind: none` 的話，之後每個讀的地方都要多認一種值。
  Future<void> revoke(String uid);
}
