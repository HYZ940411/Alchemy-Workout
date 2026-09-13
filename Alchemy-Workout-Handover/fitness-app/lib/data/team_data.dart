import '../domain/community.dart';

/// 一支團隊在雲端的樣子（[BE-11] 批次 4）。
///
/// 與 `AppState` 的 [Team] 分開，是因為兩者的鍵不同：
/// 畫面上的成員以**暱稱**辨識，雲端一律以 **uid**。
/// 翻譯由 `AppState.nameByUid` 負責，這一層只認 uid。
class CloudTeam {
  final String id;
  final String name;
  final bool isPublic;
  final int capacity;

  /// 成員。**uid → 這個人在隊上的樣子。**
  final Map<String, CloudMember> members;

  /// 本週期曾達到過的最高人數。排行榜分組依它判定，單調遞增。
  final int peakSize;

  /// 已解散。**軟刪除** —— 解散後排行榜歷史仍要查得到這支隊伍。
  final bool disbanded;

  const CloudTeam({
    required this.id,
    required this.name,
    required this.members,
    this.isPublic = true,
    this.capacity = kTeamCapacity,
    this.peakSize = 0,
    this.disbanded = false,
  });

  bool get isFull => members.length >= capacity;

  String? get leaderUid {
    for (final e in members.entries) {
      if (e.value.role == TeamRole.leader) return e.key;
    }
    return null;
  }
}

class CloudMember {
  final String name;
  final int rank;
  final TeamRole role;
  final DateTime joinedAt;

  const CloudMember({
    required this.name,
    required this.rank,
    required this.role,
    required this.joinedAt,
  });
}

/// 邀請或申請。兩者共用同一個結構 —— 依〈團隊成員資格申請 Aggregate〉，
/// 隊長邀請與使用者申請是**同一個 Aggregate 的兩個方向**，不是兩件事。
class TeamRequest {
  final String teamId;
  final String teamName;
  final String uid;
  final String name;
  final int rank;

  /// 真表示「隊長邀請這個人」，假表示「這個人申請加入」。
  final bool isInvite;
  final DateTime expiresAt;

  const TeamRequest({
    required this.teamId,
    required this.teamName,
    required this.uid,
    required this.name,
    required this.rank,
    required this.isInvite,
    required this.expiresAt,
  });
}

/// 團隊的存讀邊界（[BE-11] 批次 4）。
abstract class TeamSource {
  /// 我所屬的隊伍。沒加入任何一支時回傳空值。
  Future<CloudTeam?> myTeam();

  /// 可以申請加入的隊伍（公開、未滿、未解散）。
  Future<List<CloudTeam>> openTeams({int limit});

  /// 建立隊伍。[t] 的 `id` 會成為文件 ID，理由同貼文。
  Future<void> create(CloudTeam t);

  /// 新增或更新一位成員（加入、升為隊長都走這裡）。
  Future<void> putMember(String teamId, String uid, CloudMember m);

  /// 移除一位成員（退出、被踢除）。
  Future<void> removeMember(String teamId, String uid);

  Future<void> setVisibility(String teamId, bool isPublic);

  /// 解散。**軟刪除** —— 排行榜歷史仍要查得到這支隊伍。
  Future<void> disband(String teamId);

  /// 送出邀請或申請。
  Future<void> sendRequest(TeamRequest r);

  /// 收回／拒絕／接受後移除該筆請求。
  Future<void> dropRequest(String teamId, String uid);

  /// 等我回應的請求：別人邀我入隊、以及（若我是隊長）別人申請加入我的隊。
  Future<List<TeamRequest>> requestsFor(String uid, {String? myTeamId});
}
