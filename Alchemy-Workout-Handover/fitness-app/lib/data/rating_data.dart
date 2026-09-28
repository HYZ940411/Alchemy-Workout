import '../domain/novice_wrapup.dart';

/// 訓練體驗評分的存讀邊界（`[BE-18]`）。
///
/// ## 為什麼要獨立成一個集合
///
/// 規格（`02_Aggregate定義.md`〈訓練體驗評分 Aggregate〉）把它列為
/// **獨立 Aggregate**，理由是「〈管理員評分彙總〉需要逐筆下鑽查詢」，
/// 並明言**管理員是本評分的唯一讀者**。
///
/// 在此之前評分存在 `users/{uid}` 的存檔裡，而那棵樹依 `firestore.rules`
/// **只有本人讀得到** —— 於是這份資料收集了卻**沒有任何用途**：
/// 管理端的彙總表永遠是空的，而它要回答的正是「哪一份訓練計畫該改」。
///
/// ## 文件 ID
///
/// `{raterUid}_{對象類型}_{對象 ID}` —— 不變條件「唯一鍵為 評分者 ＋
/// 對象類型 ＋ 對象 ID」由 Firestore 的主鍵直接保證，重複評分在這個結構下
/// **寫不出來**，不是「靠程式碼記得檢查」。同〈關注關係〉的做法。
///
/// **不從 ID 反解欄位**：訓練計畫的 ID 本身含底線（`p_push`），
/// 拆不回去。欄位一律讀文件內容。
abstract class RatingSource {
  /// 寫一筆（新增或覆寫）。規格：評分後可修改，覆蓋原值，不另立 Event。
  Future<void> put(ExperienceRating r);

  /// 我自己評過的。登入時用來對齊本機那份。
  Future<List<ExperienceRating>> mine();

  /// **全平台的每一筆。管理員限定**（安全規則擋在雲端那一側）。
  ///
  /// 分析用途、延遲更新，所以一次抓一批就好，不做即時訂閱。
  Future<List<ExperienceRating>> all({int limit});
}

/// 文件 ID。順序有意義：評分者在前，才查得動「某人評過什麼」。
String ratingDocId(String raterUid, RatingTarget target, String targetId) =>
    '${raterUid}_${target.name}_$targetId';
