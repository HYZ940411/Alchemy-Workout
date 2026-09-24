import '../domain/community.dart';

/// 一段師徒關係在雲端的樣子（[BE-11] 批次 6）。
class CloudBond {
  final String id;
  final String mentorUid;
  final String apprenticeUid;
  final String mentorName;
  final String apprenticeName;

  /// **二值、且都不是終止狀態。** 已解除者三天內可恢復 ——
  /// 恢復是同一筆轉回生效中，不是新建一筆（見 `Firestore-Schema設計.md` §2.11）。
  final MentorBondState state;

  final DateTime bondedAt;
  final DateTime? releasedAt;
  final MentorReleaseReason? releasedReason;

  const CloudBond({
    required this.id,
    required this.mentorUid,
    required this.apprenticeUid,
    required this.mentorName,
    required this.apprenticeName,
    required this.bondedAt,
    this.state = MentorBondState.active,
    this.releasedAt,
    this.releasedReason,
  });

  bool get isActive => state == MentorBondState.active;

  /// 還能不能恢復。解除滿三天之後就不能了。
  bool recoverableAt(DateTime now) {
    final r = releasedAt;
    if (state != MentorBondState.released || r == null) return false;
    return now.difference(r) <= kMentorReleaseCooldown;
  }

  /// 對 [me] 而言，另一方是誰。
  String peerNameFor(String me) =>
      me == mentorUid ? apprenticeName : mentorName;
}

class CloudMentorTask {
  final String id;
  final String title;
  final String detail;
  final MentorTaskState state;
  final int rewardCoins;

  /// 學徒對該次任務的評分（1–5）。空值＝尚未評分。
  final int? rating;

  const CloudMentorTask({
    required this.id,
    required this.title,
    required this.detail,
    this.state = MentorTaskState.assigned,
    this.rewardCoins = kMentorTaskCoin,
    this.rating,
  });
}

class CloudQuestion {
  final String id;

  /// 提問者的 uid。**存 uid 不存「是不是學徒問的」** ——
  /// 後者是每位讀者各自的判斷，與私訊的 `fromMe` 同理。
  final String fromUid;
  final String text;
  final DateTime at;

  /// 回答內容。空值＝尚未回答。
  final String? answer;
  final DateTime? answeredAt;

  const CloudQuestion({
    required this.id,
    required this.fromUid,
    required this.text,
    required this.at,
    this.answer,
    this.answeredAt,
  });

  bool get answered => answer != null;
}

/// 師徒申請。依〈師徒申請 Aggregate〉，學徒與教官**兩個方向共用同一個結構**。
class MentorRequest {
  final String id;
  final String fromUid;
  final String toUid;
  final String fromName;
  final int fromRank;

  /// 真表示「教官邀請學徒」，假表示「學徒申請拜師」。
  final bool fromMentor;
  final DateTime at;
  final DateTime expiresAt;

  const MentorRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.fromName,
    required this.fromRank,
    required this.fromMentor,
    required this.at,
    required this.expiresAt,
  });
}

/// 師徒的存讀邊界（[BE-11] 批次 6）。
abstract class MentorSource {
  /// 與我有關的所有師徒關係（不論我是教官還是學徒，也不論是否已解除）。
  Future<List<CloudBond>> bonds();

  /// 建立師徒關係。
  ///
  /// **不變條件：同一學徒同時至多一筆生效中。** 已有生效中關係時
  /// 這個方法不做任何事 —— 由實作檢查，不靠呼叫端記得。
  Future<void> bond(CloudBond b);

  /// 解除。**未完成的任務一律轉為已作廢**（規格明訂），一併處理。
  Future<void> release(String bondId, MentorReleaseReason reason, DateTime at);

  /// 恢復。同一筆轉回生效中；超過三天的不處理。
  Future<void> recover(String bondId, DateTime now);

  Future<List<CloudMentorTask>> tasks(String bondId);
  Future<void> putTask(String bondId, CloudMentorTask t);

  Future<List<CloudQuestion>> questions(String bondId);
  Future<void> ask(String bondId, CloudQuestion q);
  Future<void> answer(String bondId, String questionId, String text, DateTime at);


  /// 有變動時發一次訊號（`[BE-16]`）。**訊號不帶內容。**
  ///
  /// 收到的人去跑既有的重讀路徑，不在這裡再解析一次文件 ——
  /// 理由見 `cloud_watch.dart`。
  ///
  /// **查詢條件與上面那支 `bonds()／requestsFor()` 完全一樣。** 這不是巧合，
  /// 是刻意的：那組條件已經通過線上的安全規則與索引，照抄就不會
  /// 出現「畫面成功、雲端拒絕」那種無聲的失敗。條件一改就要重新
  /// 確認規則與 `firestore.indexes.json`。
  Stream<void> watchMentor();

  /// 等我回應的師徒申請。
  Future<List<MentorRequest>> requestsFor(String uid);
  Future<void> sendRequest(MentorRequest r);
  Future<void> dropRequest(String requestId);
}
