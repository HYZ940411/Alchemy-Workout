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

  /// 各成員對本隊的日常貢獻。**uid → 分數。**
  ///
  /// 在此之前團隊分數完全沒有上雲，也沒有進本機存檔 —— 重開 App 就
  /// 回到示範資料，真帳號則每次從零開始，練完的分數下一秒就沒了
  /// （使用者 2026-09-28 回報，裁決 A：上雲）。
  ///
  /// **不存 `dailyScore`**：那是這份 Map 的加總，另存一個數字就會漂移
  /// （見 `Team.dailyScore` 的說明）。
  final Map<String, int> contributions;

  /// 今日限時任務中，完成紀錄記在本隊帳上的成員（uid）。
  final Set<String> timedCredited;

  /// [timedCredited] 屬於哪一個業務日（`yyyy-MM-dd`，04:00 換日）。
  ///
  /// **換日要清空，而清空這件事沒有伺服器可以做**（免費方案沒有排程）。
  /// 所以改由「第一個在新的一天完成的人」順手清掉 —— 他看到日期不同，
  /// 就把名單換成只有自己。空字串代表還沒有人完成過。
  final String timedDay;

  /// 月累計團隊限時分數，與 [timedPeriod]（`yyyy-MM`）成對：月份不同就當 0。
  /// 換月要歸零，而那件事同樣沒有伺服器可以做，由「本月第一個得分的人」順手做。
  final int timedScore;
  final String timedPeriod;

  /// **按月份分開存的完整紀錄**（`[QA-05]`，使用者裁決 D，2026-10-17）。
  ///
  /// 上面的 [contributions]／[timedScore] 只是「本月」那一份的視圖（由資料層依月份挑出來），
  /// 這兩個才是雲端真正存的東西：管理員每月初按「結算上月團隊排行榜」時，要讀得到**上個月**的最終分數。
  /// 月份鍵見 [teamMonthKey]。沒有「換月重設」，新月份只是多一個鍵。
  final Map<String, Map<String, int>> contribByMonth;
  final Map<String, int> timedByMonth;

  const CloudTeam({
    required this.id,
    required this.name,
    required this.members,
    this.isPublic = true,
    this.capacity = kTeamCapacity,
    this.peakSize = 0,
    this.disbanded = false,
    this.contributions = const {},
    this.timedCredited = const {},
    this.timedDay = '',
    this.timedScore = 0,
    this.timedPeriod = '',
    this.contribByMonth = const {},
    this.timedByMonth = const {},
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

  /// 把 [delta] 分加到某位成員對本隊的貢獻上。
  ///
  /// **是累加不是覆寫。** 兩台裝置同時練完各自送一次，覆寫會丟掉一次；
  /// 而且安全規則只放行「自己那一格、而且往上」，覆寫寫不過去。
  Future<void> addScore(String teamId, String uid, int delta);

  /// 把某位成員記進今日限時任務的完成名單。
  ///
  /// [day] 是業務日字串。雲端那份如果屬於別的日子就整份換掉 ——
  /// 換日清空沒有伺服器可以做，由第一個完成的人順手做。
  Future<void> creditTimed(String teamId, String uid, String day);


  /// 有變動時發一次訊號（`[BE-16]`）。**訊號不帶內容。**
  ///
  /// 收到的人去跑既有的重讀路徑，不在這裡再解析一次文件 ——
  /// 理由見 `cloud_watch.dart`。
  ///
  /// **查詢條件與上面那支 `myTeam()／requestsFor()` 完全一樣。** 這不是巧合，
  /// 是刻意的：那組條件已經通過線上的安全規則與索引，照抄就不會
  /// 出現「畫面成功、雲端拒絕」那種無聲的失敗。條件一改就要重新
  /// 確認規則與 `firestore.indexes.json`。
  ///
  /// [myTeamId] 用來監看「別人申請加入我的隊」——
  /// 那批請求掛在隊伍底下，不掛在我身上，所以要知道是哪一隊。
  Stream<void> watchTeams({String? myTeamId});

  /// 等我回應的請求：別人邀我入隊、以及（若我是隊長）別人申請加入我的隊。
  /// [errors] 若有傳，實作把**每一段失敗的原因**塞進去。
  /// 這裡有兩段獨立查詢（邀請、申請），呼叫端是即發即忘 ——
  /// 沒有這個出口，一段壞掉在畫面上就只是「什麼都沒有」。
  Future<List<TeamRequest>> requestsFor(
    String uid, {
    String? myTeamId,
    List<String>? errors,
  });
}
