import '../domain/community.dart';

/// 貼文、留言、按讚的存讀邊界（[BE-11] 批次 3）。
///
/// ## 文件 ID 沿用本地產生的貼文 ID
///
/// 不讓 Firestore 配自動 ID。本地發文時已經產生了一個唯一 ID，
/// 直接拿它當文件 ID，**「本地這篇」與「雲端那篇」就是同一個識別碼** ——
/// 否則每次發文都要處理一次「暫時 ID 換成正式 ID」，而畫面上、
/// 留言裡、檢舉案件裡都握著舊的那一個。那是最容易出錯的地方，直接避開。
///
/// ## 按讚為什麼要存兩份
///
/// `likes/{uid}` 子集合是「誰按過」的真相來源（同時保證一人一次），
/// 貼文上的 `likeCount` 是給列表顯示用的**衍生但儲存**計數 ——
/// 動態牆每次都去數一遍子集合的話，一頁 20 篇就是 20 次額外查詢。
/// 見 `Firestore-Schema設計.md` 第 5.1 節。
///
/// **現階段計數由客戶端遞增**，因為還沒有 Cloud Functions（`[BE-07]`）。
/// 與金幣、能力值一樣，這是已知的可竄改點，不是疏漏。
abstract class PostSource {
  /// 發布一篇貼文。[p] 的 `id` 會成為雲端的文件 ID。
  Future<void> publish(Post p, {required String authorUid});

  /// 讀最近的貼文，已填好 `likedByMe`。
  Future<List<Post>> recent({int limit});

  /// 按讚 / 取消按讚。
  Future<void> setLike(String postId, {required bool liked});

  Future<void> addComment(String postId, Comment c,
      {required String authorUid});

  /// 貼文已編輯。編輯歷史一併覆寫 —— 規格要求保留完整歷史版本。
  Future<void> updatePostText(String postId, Post p);

  /// 貼文已刪除。**軟刪除** —— 貼文可被檢舉，硬刪除會讓案件失去證據。
  Future<void> markPostDeleted(String postId);

  /// 留言已編輯。規則比照貼文，編輯歷史一併覆寫。
  Future<void> updateCommentText(String postId, Comment c);

  /// 留言已刪除。同樣是軟刪除 —— 已刪除的留言仍供獎勵回收與成就計數判定。
  Future<void> markCommentDeleted(String postId, String commentId);
}
