import '../domain/community.dart';

/// 一段對話在雲端的樣子（[BE-11] 批次 5）。
///
/// 與 `AppState` 的 [Conversation] 分開，是因為那個型別有兩個
/// **每位讀者各自不同**的欄位：`peer`（對方是誰 —— 我看到的是你，你看到的是我）
/// 與 `deletedByMe`。雲端那份必須中立地記「兩位參與者」，
/// 由讀取端自己算出「對我而言對方是誰」。
class CloudConversation {
  final String id;

  /// 兩位參與者的 uid。
  final List<String> participants;

  /// uid → 暱稱。與貼文同理，存一份快照免得每次都要去查公開檔案。
  final Map<String, String> names;
  final Map<String, int> ranks;

  /// 誰是教官。教官身分會影響訊息分類與「陌生訊息」的判定。
  final Map<String, bool> instructors;

  /// **單方刪除**：哪些人已經在自己那一側刪掉這段對話。
  /// 規格明訂刪除只發生在對話層級，且只改自己這一側 —— 對方仍看得到。
  final Set<String> deletedBy;

  final DateTime lastAt;
  final List<CloudMessage> messages;

  const CloudConversation({
    required this.id,
    required this.participants,
    required this.names,
    required this.lastAt,
    this.ranks = const {},
    this.instructors = const {},
    this.deletedBy = const {},
    this.messages = const [],
  });

  /// 對 [me] 而言，對方是誰。
  String? peerOf(String me) {
    for (final p in participants) {
      if (p != me) return p;
    }
    return null;
  }
}

class CloudMessage {
  final String id;
  final String senderUid;
  final String text;
  final DateTime at;

  /// 訊息分類。**於發送當下依雙方關係判定並寫入**，其後關係變化不回溯改寫。
  final MessageCategory category;

  /// 疑似違規：照常送出，同時自動開立檢舉案。
  final bool pendingReview;

  /// 誰讀過了。`readBy[uid]` 有值即為該人的已讀時戳。
  final Map<String, DateTime> readBy;

  const CloudMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.at,
    this.category = MessageCategory.normal,
    this.pendingReview = false,
    this.readBy = const {},
  });

  /// 對 [me] 而言，這是不是我送的。
  ///
  /// **這是每位讀者各自不同的狀態，不可以存成訊息的欄位** ——
  /// 存了的話兩個人會共用同一個「這是我送的」，對話框會整段左右顛倒。
  /// 與貼文的 `likedByMe` 是同一個陷阱。
  bool fromMeFor(String me) => senderUid == me;
}

/// 私訊的存讀邊界（[BE-11] 批次 5）。
abstract class ChatSource {
  /// 這兩人的對話 ID。
  ///
  /// 放進介面而不是留在實作裡，是因為 `AppState` 要靠它把畫面上的
  /// 那段對話對應到雲端的哪一份 —— 而它不該知道 ID 是怎麼算出來的。
  String conversationIdOf(String a, String b);

  /// 我的對話。已在我這一側刪除者不列出。
  Future<List<CloudConversation>> conversations({int limit});

  /// 送出一則訊息。對話不存在時一併建立。
  Future<void> send(
    String peerUid,
    CloudMessage m, {
    required String myName,
    required String peerName,
  });

  /// 標記我讀到哪裡。
  Future<void> markRead(String conversationId);

  /// 在我這一側刪除整段對話。**對方仍看得到。**
  Future<void> deleteForMe(String conversationId);
}
