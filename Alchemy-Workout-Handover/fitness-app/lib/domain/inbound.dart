/// 對方發起、等我回應的請求。
///
/// 這個專案先前只實作了「我送出、對方回應」的那一半 —— 每一條需要第二個人
/// 的流程，另一半都停在空氣裡。模型並不是這樣寫的：
///
/// - 〈團隊組隊流程〉的加入路徑 1 是「隊長邀請 → **使用者已接受／拒絕邀請**」，
///   Actor 是使用者，也就是**我**。這是我的 Command，先前完全不存在。
/// - 〈師徒申請 Aggregate〉的「申請方角色」欄位值域為**學徒 / 教官**，
///   明載「申請雙向皆可」。先前只有學徒申請教官那一向。
///
/// 三種都共用同一個形狀：對方送出、我接受或拒絕、7 天未回應即逾期。
library;

/// 收件請求的種類。三者的逾期時限皆為 168 小時（7 天）。
enum InboundKind {
  /// 隊長邀請我加入他的團隊。〈團隊成員資格申請 Aggregate〉，方向＝隊長邀請。
  teamInvite,

  /// 教官邀我當他的學徒。〈師徒申請 Aggregate〉，申請方角色＝教官。
  mentorInvite,

  /// 有人想拜我為師。〈師徒申請 Aggregate〉，申請方角色＝學徒；我是被申請的教官。
  apprenticeApply,
}

const inboundKindNames = <InboundKind, String>{
  InboundKind.teamInvite: '團隊邀請',
  InboundKind.mentorInvite: '教官邀請',
  InboundKind.apprenticeApply: '拜師申請',
};

/// 收件請求的逾期時限。**不做成可調參數** ——
/// 承〈師徒申請 Aggregate〉「時限不做成可調參數」與團隊邀請的既有裁決。
const Duration kInboundTtl = Duration(hours: 168);

/// 一筆等我回應的請求。
///
/// 狀態機只有「待回應」一個非終止狀態：接受、拒絕、逾期皆為終止，
/// 終止即從收件匣移除 —— 三個終止狀態在本專案的差別只在結果，不在紀錄。
class InboundRequest {
  final String id;
  final InboundKind kind;

  /// 送件方。團隊邀請為**隊長的名字**，[subject] 才是團隊名。
  final String from;

  /// 送件方的雲端身分。**示範資料的假請求沒有 uid，所以可以是空值。**
  ///
  /// 雲端的 `MentorRequest.fromUid` 與 `TeamRequest.uid` 本來就有這個值，
  /// 轉成本機這筆時不該丟掉 —— 少了它，畫面只能拿暱稱去查對方的階級，
  /// 而暱稱可以改。
  final String? fromUid;

  /// 送件當下對方的階級。**這不是要顯示的值**，只在查不到他的公開檔案
  /// 時墊底 —— 顯示的是現值（見 `AppState.rankOf`）。
  final int fromRank;

  /// 這筆請求談的對象。團隊邀請為團隊名；師徒兩向皆與 [from] 同值。
  final String subject;

  final DateTime sentAt;

  const InboundRequest({
    required this.id,
    required this.kind,
    required this.from,
    required this.fromRank,
    required this.subject,
    required this.sentAt,
    this.fromUid,
  });

  DateTime get expiresAt => sentAt.add(kInboundTtl);

  bool expiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// 還剩多久回應。已逾期者為零。
  Duration leftAt(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  String get kindName => inboundKindNames[kind]!;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'from': from,
    if (fromUid != null) 'fromUid': fromUid,
    'fromRank': fromRank,
    'subject': subject,
    'sentAt': sentAt.toIso8601String(),
  };

  static InboundRequest? fromJson(dynamic e) {
    if (e is! Map) return null;
    final kind = InboundKind.values
        .where((k) => k.name == e['kind'])
        .firstOrNull;
    final sentAt = DateTime.tryParse('${e['sentAt']}');
    if (kind == null || sentAt == null) return null;
    return InboundRequest(
      id: '${e['id']}',
      kind: kind,
      from: '${e['from']}',
      fromUid: e['fromUid'] is String ? e['fromUid'] as String : null,
      fromRank: (e['fromRank'] as num?)?.toInt() ?? 1,
      subject: '${e['subject']}',
      sentAt: sentAt,
    );
  }
}

/// 我送出的請求，對方給了什麼答覆。
///
/// 先前只有「接受」一種結果（而且只在師徒那條線上），於是拒絕與逾期
/// 這兩條分支永遠走不到 —— 送出去的申請會一直掛著。
enum RequestVerdict { accepted, rejected, expired }

const requestVerdictNames = <RequestVerdict, String>{
  RequestVerdict.accepted: '已接受',
  RequestVerdict.rejected: '已拒絕',
  RequestVerdict.expired: '已逾期',
};
