import 'ability.dart';
import 'ai_adjust.dart';
import 'social.dart';
import 'workout_card.dart';

// --- 社群動態牆 ---

/// 貼文的可見範圍。
///
/// **2026-09-26 起一律為 `public`，選擇器已從發文頁移除**（使用者裁決）。
///
/// 這個列舉**留著不刪**，因為雲端既有的貼文文件上有這個欄位，
/// 刪掉的話舊文件解不出來。新發的貼文一律寫 `public`。
///
/// 為什麼移除而不是修好：它從來沒有生效過。動態牆只濾掉已刪除的，
/// 而 `firestore.rules` 的貼文讀取是 `allow read: if request.auth != null`
/// —— 任何登入者都讀得到每一篇，包括標「私人」的。
/// 要真的做對，「僅關注者」得讓安全規則判斷「讀的人有沒有關注作者」，
/// 而那在查詢裡做不到，得把可見名單反正規化到每一篇貼文上 ——
/// 關注一個人就要回頭改他所有的貼文。
enum PostVisibility { public, followersOnly, private }

const postVisibilityNames = <PostVisibility, String>{
  PostVisibility.public: '公開',
  PostVisibility.followersOnly: '僅關注者',
  PostVisibility.private: '私人',
};

/// 發布前的內容過濾判定（App Store 1.2 要求）—— 三值。
enum FilterVerdict { pass, blocked, flagged }


class Comment {
  /// 留言的識別碼。管理員下架違規留言時以此定位 ——
  /// 以作者＋內容比對會在同一人重複留同一句話時一次刪掉兩則。
  final String id;
  final String author;

  /// 作者的雲端身分。示範資料的假作者沒有 uid，所以可以是空值 ——
  /// 與 [Post.authorUid] 同一個約定。
  ///
  /// **雲端本來就在存它了**（`post_data_firestore.dart` 的 `addComment`
  /// 寫入 `authorUid`），只是讀回來的時候沒有欄位可以放，於是丟掉。
  /// 「這則留言是不是我的」因此只剩暱稱可比 —— 而暱稱會撞名，
  /// 開放改名之後還會讓自己的舊留言變成別人的。
  final String? authorUid;

  String text;
  final DateTime at;

  /// 軟刪除。已刪除的留言隱藏但保留 —— 供獎勵回收與成就計數判定使用。
  bool deleted;

  /// 編輯歷史：編輯前的內容與時戳。**保留完整歷史版本**，
  /// 不是只留一份最新的。
  final List<(String, DateTime)> edits;

  Comment(this.author, this.text, this.at,
      {String? id,
      this.authorUid,
      this.deleted = false,
      List<(String, DateTime)>? edits})
      : id = id ?? 'c${at.microsecondsSinceEpoch}',
        edits = edits ?? [];

  bool get edited => edits.isNotEmpty;
}

class Post {
  final String id;
  final String author;

  /// 作者的雲端身分。**示範資料的假作者沒有 uid，所以可以是空值。**
  ///
  /// 這個值本來就跟著貼文一起存在雲端（`posts/{id}.authorUid`），
  /// 只是讀回來時被丟掉了 —— 於是畫面只剩暱稱可用，而暱稱可以改。
  final String? authorUid;

  /// 發文當下作者的階級。**這不是要顯示的值。**
  ///
  /// 顯示的階級一律問 `AppState.rankOf(author, uid: authorUid)` 拿現值 ——
  /// 階級代表「這個人現在多強」，不是歷史事實。這個欄位只在公開檔案
  /// 查不到（對方久未上線、剛好沒撈到）時墊底，總比顯示 1 階好。
  ///
  /// 2026-09-23 之前反過來：這個值就是顯示值，所以作者從 11 階練到
  /// 40 階，他 11 階時發的那篇永遠寫著 11 階。
  final int authorRank;
  final int? authorReputation; // 僅教官身分者有值

  /// 可編輯 —— 編輯前的版本進 [edits]，原值不會消失。
  String text;

  /// 圖片集合。貼文支援文字與圖片，不支援影片。
  final List<String> images;
  final DateTime at;
  /// 附帶的訓練成果（分享類貼文）的**一行摘要**。舊貼文只有這個；
  /// 新貼文另有結構化的 [workoutCard]，畫面優先畫它。
  final String? attachedWorkout;

  /// 附帶的訓練成果卡（結構化）。沒有就退回 [attachedWorkout] 那一行。
  final WorkoutCard? workoutCard;
  /// 發文者於發布時指定可見範圍：公開 / 僅關注者 / 私人。
  final PostVisibility visibility;
  /// 過濾判定為「疑似違規」者照常發布，並自動送審。
  final bool pendingReview;
  int likes;
  bool likedByMe;
  final List<Comment> comments;

  /// 已發布 → 已刪除（終止狀態）。**軟刪除，資料保留** ——
  /// 貼文可被檢舉，硬刪除會使案件失去證據。
  bool deleted;

  /// 編輯歷史。Read Model 須對讀者顯示「已編輯」。
  final List<(String, DateTime)> edits;
  Post({
    required this.id,
    required this.author,
    required this.authorRank,
    required this.text,
    required this.at,
    this.authorUid,
    this.authorReputation,
    this.attachedWorkout,
    this.workoutCard,
    this.visibility = PostVisibility.public,
    this.pendingReview = false,
    this.likes = 0,
    this.likedByMe = false,
    List<String>? images,
    List<Comment>? comments,
    this.deleted = false,
    List<(String, DateTime)>? edits,
  })  : images = images ?? [],
        comments = comments ?? [],
        edits = edits ?? [];

  bool get edited => edits.isNotEmpty;

  /// 可見的留言。已刪除者隱藏但仍在 [comments] 裡。
  List<Comment> get visibleComments =>
      comments.where((c) => !c.deleted).toList();
}

// --- 團隊 ---

/// 團隊僅有隊長與成員兩種角色，無副隊長。
enum TeamRole { leader, member }

const teamRoleNames = <TeamRole, String>{
  TeamRole.leader: '隊長',
  TeamRole.member: '成員',
};

class TeamMember {
  final String name;
  final int rank;
  final TeamRole role;

  /// 雲端身分。**示範資料的假隊友沒有 uid，所以可以是空值。**
  ///
  /// 在此之前這裡只有顯示名稱，要寫回雲端時再拿名稱去公開檔案裡反查
  /// uid —— 反查不到就整個跳過，而且是無聲的。踢人、轉讓隊長、核准
  /// 申請全都走那條路：只讀得到 50 筆公開檔案，對方不在裡面就
  /// **畫面上成功、雲端什麼都沒發生**，重新整理就打回原形。
  ///
  /// uid 本來就跟著雲端資料一起來的，不該丟掉再猜回來。
  final String? uid;

  const TeamMember(this.name, this.rank, this.role, {this.uid});
}

class PendingRequest {
  final String name;
  final int rank;
  final DateTime expiresAt; // 各自 7 天逾期

  /// 申請／邀請對象的雲端身分。理由同 [TeamMember.uid] ——
  /// `TeamRequest.uid` 是雲端讀來的，轉成本機這筆時不該丟掉。
  final String? uid;

  /// 這筆請求屬於哪一支隊伍。
  ///
  /// 撤回申請時要用它。在此之前是拿隊名去公開團隊清單裡反查 ——
  /// 而那份清單**會濾掉已滿的隊伍**，所以我申請的隊一旦被別人填滿，
  /// 就再也撤不回來了（本機移掉、雲端還在，下次載入又跑出來）。
  final String? teamId;

  const PendingRequest(
    this.name,
    this.rank,
    this.expiresAt, {
    this.uid,
    this.teamId,
  });
}

class Team {
  final String id;
  final String name;
  final bool isPublic;
  final List<TeamMember> members;
  final int capacity; // 上限 5 人（含隊長）

  /// **子集合：各成員的本隊已貢獻分數。** 本週期曾為本隊成員者各一筆。
  ///
  /// 不變條件「月累計日常分數 ＝ 各成員貢獻的總和」在這裡是**結構上成立**的
  /// —— [dailyScore] 直接由它加總而來，不另存一個會漂移的數字。
  /// 沒有子集合的話團隊分數是個孤兒數字：錯了無從發現，也無從回推
  /// （成員的個人月累計分數裡，哪一部分貢獻給本隊的資訊已經消失）。
  ///
  /// 成員退出時該筆**保留不刪**：分數計入即歸團隊所有，退出不扣除。
  final Map<String, int> contributions;

  /// 月累計日常分數。成員每次「個人排行榜分數已增加」時同額增量累加，
  /// **不是全體成員月累計分數的加總** —— 後者與「重新分隊期不累加」
  /// 和「中途加入者僅貢獻加入後的分數」在數學上無法同時成立。
  int get dailyScore =>
      contributions.values.fold<int>(0, (a, b) => a + b);

  /// 月累計**團隊限時分數**。每有一位成員完成今日限時任務加 10 分，
  /// 全員完成的那一刻再加 50 分；重新分隊期不累加。
  ///
  /// **這個欄位以前從來沒有人寫過**：完成限時任務只動了今日完成名單
  /// （[timedCredited]），排行榜上的團隊限時分數永遠是 0（2026-10-16 使用者回報）。
  int timedScore;
  final int dailyRankPos;
  final int timedRankPos;
  final int lockedGroupSize; // 3 / 4 / 5 人組
  final List<PendingRequest> invites;
  final List<PendingRequest> applications;

  /// 今日限時任務中，完成紀錄**記在本隊帳上**的成員。
  /// 新建立的隊為空集合：你在上一支隊伍完成的那一次，分數已經計給上一支隊伍。
  final Set<String> timedCredited;

  /// 名額僅由**已加入的成員**計算 —— 待回應的邀請不佔名額。
  /// 超收已由「使用者已加入團隊」當下的 Precondition 擋下，
  /// 再讓待回應佔名額是重複防守，且隊長發出 4 封邀請後團隊立即形同滿員。
  bool get isFull => members.length >= capacity;

  Team({
    required this.id,
    required this.name,
    required this.isPublic,
    required this.members,
    this.capacity = 5,
    Map<String, int>? contributions,
    this.timedScore = 0,
    this.dailyRankPos = 0,
    this.timedRankPos = 0,
    this.lockedGroupSize = 3,
    // **不可以是 `const []`。** 兩份清單都會被 `add`／`remove`
    // （收到申請、核准、拒絕、撤回），而 `const` 清單不可修改 ——
    // 任何沒有明確傳入這兩個參數的 Team（`createTeam()` 建的、
    // `applyCloudTeam()` 從雲端載入的）一收到申請就拋
    // `Cannot add to an unmodifiable list`。
    //
    // 與 `buildSocialUsers()` 當初那個 bug 一模一樣，寫法比照
    // 同建構子裡的 `contributions` 與 `timedCredited`。
    List<PendingRequest>? invites,
    List<PendingRequest>? applications,
    Set<String>? timedCredited,
  })  : contributions = contributions ?? {},
        invites = invites ?? [],
        applications = applications ?? [],
        timedCredited = timedCredited ?? {};
}

class PublicTeam {
  final String id;
  final String name;
  final int size;
  final int capacity;
  final bool viaFollowing; // 關注對象所屬的公開團隊，優先呈現

  /// 可見性值域：公開 / 私密。私密團隊不可被搜尋，也不接受加入申請 ——
  /// 僅能經隊長邀請加入。可事後變更：團隊性質本會隨時間改變。
  final bool isPublic;
  final String intro;
  final List<TeamMember> members;

  /// 兩個獨立分數，衡量不同的事：日常＝成員的訓練努力程度，
  /// 限時＝團隊的動員參與率。兩者不合併，兩個排行榜各自維護。
  final int dailyScore;
  final int timedScore;

  /// 本週期**曾經達到過的最高成員數**，單調遞增，不隨成員退出而降級。
  /// 取週期內最高值可同時排除兩個漏洞：3 人隊招滿後仍留在 3 人組比賽、
  /// 5 人隊結算前臨時踢人把整月成績包裝成 3 人組。
  final int peakSize;

  const PublicTeam(
    this.name,
    this.size,
    this.capacity, {
    this.id = '',
    this.viaFollowing = false,
    this.isPublic = true,
    this.intro = '',
    this.members = const [],
    this.dailyScore = 0,
    this.timedScore = 0,
    int? peakSize,
  }) : peakSize = peakSize ?? size;

  bool get isFull => size >= capacity;

  /// 排行榜資格：本週期**曾經**達到人數下限 3 人者保留排名與獎勵資格，
  /// 即使結算當下已跌破。真正該排除的只有「本月從未成局」的隊伍。
  bool get rankEligible => peakSize >= kTeamMinSize;

  /// 分組。與資格判定刻意同一個時點，模型內部不用兩套人數認定邏輯。
  int get groupSize => peakSize.clamp(kTeamMinSize, capacity);
}

/// 團隊排行榜的人數下限。未達者不參與排名，也不領獎勵。
const int kTeamMinSize = 3;

/// 團隊人數上限（含隊長）。
const int kTeamCapacity = 5;

/// 排行榜的兩個榜別。分數不合併，對應兩種獨立的排行獎勵。
enum TeamBoard { daily, timed }

const teamBoardNames = <TeamBoard, String>{
  TeamBoard.daily: '日常',
  TeamBoard.timed: '限時',
};

const teamBoardHints = <TeamBoard, String>{
  TeamBoard.daily: '成員每次得分時同額增量累加，衡量訓練努力程度',
  TeamBoard.timed: '完成限時任務的成員數 × 10 分，全員完成另加 50，衡量動員參與率',
};

/// 這個榜是不是依人數分組。**只有日常榜分組，限時榜不分**（使用者 2026-10-17 裁決，
/// 照 02_Aggregate〈團隊限時排行獎勵已發放〉：限時分數已用「固定 10 分／人＋全員完成加碼 50」
/// 收斂人數差距，既有裁決未替它另開分組，獎勵層沿用同一結論）。
bool isGroupedBoard(TeamBoard b) => b == TeamBoard.daily;

/// 依榜別與分組排出名次。
///
/// **日常榜只跟同組別的隊伍比**：日常分數維持加總、不改人均，公平性改由
/// 依人數分級距分組承擔（3 人組 / 4 人組 / 5 人組各自排名）——
/// 與個人排行榜的階級分組同一套設計語言，不另訂補償係數。
/// **限時榜不分組**，所有符合資格的隊伍排同一張榜，[groupSize] 被忽略。
List<PublicTeam> teamRanking(
  List<PublicTeam> all,
  TeamBoard board,
  int groupSize,
) {
  final pool = all
      .where((t) =>
          t.rankEligible && (!isGroupedBoard(board) || t.groupSize == groupSize))
      .toList()
    ..sort((a, b) {
      final s = _score(b, board).compareTo(_score(a, board));
      // 同分取隊名，只為讓名次穩定 —— 名次本身不是業務事實。
      return s != 0 ? s : a.name.compareTo(b.name);
    });
  return pool;
}

int _score(PublicTeam t, TeamBoard b) =>
    b == TeamBoard.daily ? t.dailyScore : t.timedScore;

int teamScoreOf(PublicTeam t, TeamBoard b) => _score(t, b);

/// 距前三名還差幾分。已在前三名者回傳 null。
int? gapToTopThree(List<PublicTeam> ranked, int myIndex, TeamBoard board) {
  if (myIndex < 3 || ranked.length < 3) return null;
  return _score(ranked[2], board) - _score(ranked[myIndex], board);
}

/// 重新分隊期：每個週期起點起算 2 天，期間兩個團隊分數皆不累加。
/// 個人排行榜分數照常 —— 它限制的是「隊」而非「練」。
const int kRegroupDays = 2;

bool inRegroupWindow(DateTime now) => now.day <= kRegroupDays;

/// 團隊分數按月份分開存時用的月份鍵（`yyyy-MM`）。
///
/// **月份以 04:00 換日為界**，跟排行榜週期同一個時點：每月 1 日 04:00 前仍屬上個月。
/// 少了這一步，1 日凌晨 00:00–03:59 的分數會被記進下個月，與結算算的週期對不上。
String teamMonthKey(DateTime now) {
  final d = now.hour < 4 ? now.subtract(const Duration(days: 1)) : now;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}

/// 限時任務 —— 全平台統一，一個指派日只有一組（〈團隊任務流程〉）。
/// 有效時窗為指派當日（當地 04:00 換日），隔日失效、不可補做。
///
/// **任務不存成員名單**：名單屬於團隊，會隨加入、退出、踢除、重建而改變。
/// 把名單複製一份進任務裡，換隊之後畫面上就會是上一支隊伍的人。
/// 這裡只存「今天誰完成了」這個平台級事實，名單一律向團隊要。
class TimedTask {
  final String title;
  final String detail;
  final DateTime assignedOn;

  /// 今日已完成本任務的使用者。全平台共用一份 ——
  /// 完成是使用者的事實，計不計入某支隊伍是另一回事，見 [Team.timedCredited]。
  final Set<String> completedBy;

  TimedTask({
    required this.title,
    required this.detail,
    required this.assignedOn,
    Set<String>? completedBy,
  }) : completedBy = completedBy ?? {};

  /// 這個人完成了沒有。**鍵是 [personKey]**，與 `Team.timedCredited`
  /// 同一套 —— 兩者之間有一條不變條件（記在某隊帳上的必定也完成了），
  /// 用兩種鍵的話那條不變條件會在改名時無聲地失效。
  bool doneBy(String name, {String? uid}) =>
      completedBy.contains(personKey(name, uid));
}

/// 某支團隊在今日限時任務上的成績。
///
/// 完成人數只算**記在本隊帳上**的那些：中途加入者僅能貢獻加入後產生的分數，
/// 轉隊不帶走舊團隊已貢獻的分數 —— 與團隊日常分數同一條規則。
class TimedTaskTally {
  final List<TeamMember> members;
  final Set<String> credited;
  const TimedTaskTally({required this.members, required this.credited});

  int get total => members.length;
  int get doneCount =>
      members.where((m) => credited.contains(personKey(m.name, m.uid))).length;
  bool get allDone => total > 0 && doneCount == total;

  /// 團隊限時分數 ＝ 完成人數 × 10；全員完成再加固定 50。
  int get score =>
      doneCount * kTimedTaskPerMember + (allDone ? kTimedTaskAllBonus : 0);
}

/// 限時任務獎勵：經驗值 15 ＋ 金幣 10，**不含 AI 點數** ——
/// 本來源的發放頻率是全模型最高的，每日每個有隊使用者皆可能觸發。
const int kTimedRewardExp = 15;
const int kTimedRewardCoin = 10;

const int kTimedTaskPerMember = 10;
const int kTimedTaskAllBonus = 50;

// --- 師徒 / 教官 ---

/// 師徒免責聲明的版本。師徒另設一層確認，不與註冊時的服務條款合併 ——
/// 其他功能出事是使用者自己的選擇，師徒是**平台把兩個人配對起來**，
/// 還提供聲望、專長與六維能力值展示，這些都在向學徒表示「此人可信」，
/// 註冊時滑過的總則擋不住這一層。
const String kMentorDisclaimerVersion = 'v1';

/// 教官的指導責任聲明版本。**未確認現行版本者不得回答提問、不得指派師徒任務。**
const String kInstructorDutyVersion = 'v1';

/// 教官專長的值域（〈教官專長設定 Aggregate〉，管理員於後台維護）。
///
/// **刻意不採六大肌群**：六維能力值已在教官清單強制呈現且不可隱藏，
/// 學徒要找練胸強的教官直接看六維即可 —— 那是實績，肌群專長只是同一份
/// 資訊的自述版本。
///
/// 也刻意**排除飲食營養／傷後復健／產後恢復／動作矯正／銀髮族**：
/// 把它們做成可篩選標籤，等同平台向學徒表示該教官具備此能力，
/// 而教官資格未驗證任何專業執照。不採「證照上傳 ＋ 管理員審核」以開放這些項目，
/// 那須新增證照 Aggregate 與一整條審核流程，屬範圍擴張。
const kInstructorSpecialties = <String>[
  '增肌',
  '減脂',
  '體態雕塑',
  '提升體能',
  '肌力訓練',
  '耐力訓練',
  '徒手訓練',
  '居家訓練',
  '新手引導',
  '課表規劃',
  '動作教學',
];

/// 申請時須填寫專長：至少 1 項、至多 3 項。
const int kSpecialtyMin = 1;
const int kSpecialtyMax = 3;

/// 師徒關係狀態。已解除**非終止狀態**，3 天內可恢復。
enum MentorBondState { active, released }

/// 解除原因。是「冷卻期是否適用」的判定依據。
enum MentorReleaseReason { byInstructor, byApprentice, blocked, revoked }

const mentorReleaseReasonNames = <MentorReleaseReason, String>{
  MentorReleaseReason.byInstructor: '教官方',
  MentorReleaseReason.byApprentice: '學徒方',
  MentorReleaseReason.blocked: '封鎖',
  MentorReleaseReason.revoked: '教官資格撤銷',
};

/// 解除後的冷卻期：雙方皆不得與其他對象建立師徒關係，也是可挽回的窗口。
const Duration kMentorReleaseCooldown = Duration(days: 3);

/// 師徒任務獎勵：經驗值 20 ＋ 金幣 15，**每週最多發放 3 次**。
/// 超過上限任務仍可正常完成，只是不再發經驗值與金幣。
const int kMentorTaskExp = 20;
const int kMentorTaskCoin = 15;
const int kMentorTaskRewardWeeklyCap = 3;

/// 師徒任務評分 1~5 星對應的聲望變動。
const kMentorTaskReputationDelta = <int>[-1, 0, 1, 2, 3];

/// 每週互動評分 1~5 星對應的聲望變動 —— 幅度遠大於單次任務評分。
const kWeeklyInteractionReputationDelta = <int>[-2, 0, 4, 8, 12];

/// 每位學徒每週最多這麼多次**任務評分**計入聲望；超出者仍可完成並領獎，只是不計分。
const int kMentorTaskRatingWeeklyCap = 2;

/// 一段**已解除、還在 3 天挽回窗口內**的關係，從教官那一側看到的樣子。
///
/// 在此之前教官那一側根本沒有這個東西：`applyCloudBonds` 對非生效中的
/// 關係做的是 `apprentices.removeWhere(...)`，**學徒直接從名單上消失**。
/// 而整套解除／恢復的畫面都掛在學徒那一頁上、以 `myInstructor` 為鍵。
///
/// 後果：教官看不到關係被解除了、看不到挽回窗口、提不出恢復、
/// 也回應不了對方提出的恢復 —— 而規格寫的是
/// 「教官與學徒**任一方**皆可提出」。
class ReleasedBond {
  final String apprenticeUid;
  final String apprenticeName;
  final DateTime releasedAt;
  final MentorReleaseReason? reason;

  /// 誰提出了恢復。空值＝還沒有人提出。
  final String? restoreProposedBy;

  const ReleasedBond({
    required this.apprenticeUid,
    required this.apprenticeName,
    required this.releasedAt,
    this.reason,
    this.restoreProposedBy,
  });

  /// 還能不能挽回。滿三天就不能了。
  bool recoverableAt(DateTime now) =>
      now.difference(releasedAt) <= kMentorReleaseCooldown;

  Duration cooldownLeftAt(DateTime now) {
    final left = kMentorReleaseCooldown - now.difference(releasedAt);
    return left.isNegative ? Duration.zero : left;
  }
}

/// 學徒評一則師徒任務之後，實際發生了什麼。
///
/// **「評得下去」與「有沒有計進教官的聲望」是兩件事。** 原本這一支
/// 回 `bool`，畫面分不出來，於是不管有沒有計分都報一個聲望數字 ——
/// 而超出每週上限之後那個數字根本不會動。
enum RateResult {
  /// 評了，而且計進聲望。
  counted,

  /// 評了，但本週計分額度已用完 —— 任務照樣算評過。
  capReached,

  /// 評了（改分數），但同一則不重複計分。
  alreadyRated,

  /// 評不下去（星數不合法、沒有教官、任務還沒完成）。
  rejected,
}

extension RateResultX on RateResult {
  bool get ok => this != RateResult.rejected;
}

/// 帶徒上限：初始 2 人，每達一個聲望門檻 +1，最大 5 人。
/// 門檻採遞增（1 : 2 : 4）—— 帶徒愈多取得聲望愈快，等差會使後段升級失控。
/// 教官初始聲望，於「使用者已成為教官」時給予。
///
/// 原理由為「第一門檻的一半」；第一門檻自 30 改為 75 後 15 不再是一半，
/// 但其職責（使新教官前幾次差評不致觸及地板 0）在緩衝更厚的情況下仍成立，
/// 故維持 15 不變。
const int kInstructorInitialReputation = 15;

const int kApprenticeCapInitial = 2;
const int kApprenticeCapMax = 5;
const kReputationThresholds = <int>[75, 150, 300];

/// 教官初始聲望。職責是讓新教官前幾次差評不致觸及地板 0。
const int kInitialReputation = 15;

/// 由聲望推導帶徒上限。**單調遞增**：聲望下降時上限不隨之降低，
/// 故實際上限另取歷史最高，見 [apprenticeCapFor]。
int apprenticeCapFor(int peakReputation) {
  final gained =
      kReputationThresholds.where((t) => peakReputation >= t).length;
  return (kApprenticeCapInitial + gained).clamp(
      kApprenticeCapInitial, kApprenticeCapMax);
}

/// 聲望地板為 0，扣分不使其低於 0。
int applyReputation(int current, int delta) =>
    (current + delta) < 0 ? 0 : current + delta;

class Instructor {
  final String name;

  /// 教官的雲端身分。**示範資料的假教官沒有 uid，所以可以是空值。**
  final String? uid;

  /// **這不是要顯示的值。** 顯示的階級一律問 `AppState.rankOf` 拿現值，
  /// 這個欄位只在查不到他的公開檔案時墊底。
  final int rank;

  /// 教官聲望。**屬於這位教官**，不是評分者的 ——
  /// 學徒給的星等改的是被評者的數字。可變：評分會改動它。
  int reputation;
  final int apprentices;
  final int apprenticeCap;
  final Map<Dim, int> ability;
  final List<String> specialties; // 教官專長，1–3 項，非肌群
  final double avgRating;
  final int ratingCount;
  Instructor({
    required this.name,
    required this.rank,
    this.uid,
    required this.reputation,
    required this.apprentices,
    required this.apprenticeCap,
    required this.ability,
    required this.specialties,
    required this.avgRating,
    required this.ratingCount,
  });
}

class MentorQuestion {
  /// 問答的識別碼。**教官要回哪一則，靠的是這個。**
  ///
  /// 在此之前沒有這個欄位，雲端的問答只能以內容比對辨識 ——
  /// 同一位學徒問了兩次同樣的話就分不出來。
  final String id;

  final String from;

  /// 提問的學徒是誰。**空值代表這是我自己問的**（我是學徒那一側），
  /// 或是示範資料。
  ///
  /// 教官同時帶多位學徒，而本機這份 `questions` 是一份共用清單 ——
  /// 沒有這個欄位就分不出「這則是哪位學徒問的」，於是教官側整個
  /// 接不上雲端（雲端的問答掛在特定師徒關係下）。那正是 `[BE-15]`。
  final String? apprenticeUid;

  final String text;
  final DateTime at;
  String? answer;

  /// 回答的時點。空值＝尚未回答。
  DateTime? answeredAt;

  MentorQuestion({
    required this.from,
    required this.text,
    required this.at,
    String? id,
    this.apprenticeUid,
    this.answer,
    this.answeredAt,
  }) : id = id ?? 'q${at.microsecondsSinceEpoch}';
}

/// 師徒任務狀態。**已作廢為終止狀態** —— 師徒關係解除或教官取消時，
/// 未完成的任務一律轉為已作廢。
///
/// 流程：已指派 → 學徒標記完成 → [submitted]（等教官發放獎勵）→ 教官發放獎勵
/// → [done]（學徒可領取）→ 學徒領取 → [claimed]。
/// 教官可在已指派與 [submitted] 時取消任務 → [voided]。
///
/// **[done] 的意思是「教官已發放、學徒可領取」，不是「學徒說做完了」。**
/// 加上 [submitted] 之前雲端已有 `done` 的舊任務，它們維持可領取，不用遷移。
enum MentorTaskState {
  assigned,
  submitted,
  done,
  claimed,
  voided;

  /// 還沒走到終點、關係解除時要作廢的（已指派與等教官發放）。
  /// 已發放（[done]）與已領取的獎勵已經放行，不作廢。
  bool get isOpen => this == assigned || this == submitted;
}

class MentorTask {
  /// 任務的識別碼。
  ///
  /// 在此之前沒有這個欄位，雲端「暫以標題辨識」—— 教官指派兩個同名
  /// 任務就會互相覆蓋。
  final String id;

  final String title;
  final String detail;

  /// 這則任務指派給哪位學徒。**空值代表這是指派給我的**（我是學徒那一側），
  /// 或是示範資料。理由同 [MentorQuestion.apprenticeUid]。
  final String? apprenticeUid;

  MentorTaskState state;
  final int rewardCoins;

  /// 學徒對該次任務的評分（1~5）。null ＝ 尚未評分。
  int? rating;

  /// 指派的時點。**「本週互動摘要」的任務指派數就是數這個。**
  /// 空值＝這則是加上這個欄位之前就存在的，不算進任何一週。
  DateTime? assignedAt;

  /// 學徒標記完成的時點（任務進入 [MentorTaskState.submitted] 的時點）。完成數同樣數這個。
  /// **不是教官發放獎勵的時點。**
  DateTime? doneAt;

  MentorTask({
    required this.title,
    required this.detail,
    String? id,
    this.apprenticeUid,
    this.state = MentorTaskState.assigned,
    this.rewardCoins = kMentorTaskCoin,
    this.rating,
    this.assignedAt,
    this.doneAt,
  }) : id = id ?? 't${title.hashCode}';
}

class Apprentice {
  final String name;

  /// 學徒的雲端身分。**示範資料的假學徒沒有 uid，所以可以是空值。**
  final String? uid;

  /// **這不是要顯示的值**，只在查不到他的公開檔案時墊底 —— 顯示的是現值。
  final int rank;
  final Map<Dim, int> ability;
  final List<String> recentWorkouts;
  final int scoredThisWeek; // 本週已計分次數，上限 2
  const Apprentice({
    required this.name,
    required this.rank,
    this.uid,
    required this.ability,
    required this.recentWorkouts,
    this.scoredThisWeek = 0,
  });
}

/// 教官申請的階段
enum InstructorStage {
  notApplied, screening, screenPassed, testing, pendingReview, approved, rejected
}

// --- 私訊 ---

enum MessageCategory { normal, stranger }

class ChatMessage {
  final bool fromMe;
  final String text;
  final DateTime at;
  /// **對「我送出的訊息」而言，這是「對方讀了沒」。**
  ///
  /// 畫面只在 `fromMe && read` 時顯示「已讀」（見 `chat_screen`）——
  /// 所以它從來不是「我讀了沒」。預設曾是 `true`，於是我一送出訊息
  /// 就立刻標成已讀，使用者 2026-09-24 回報。
  final bool read;

  /// 訊息分類。**於發送當下依雙方關係判定並寫入**，其後關係變化
  /// 不回溯改寫既有訊息的分類 —— 故它是訊息的欄位，不是對話的。
  final MessageCategory category;

  /// 疑似違規：照常送出，同時自動開立檢舉案（內容已標記待審）。
  final bool pendingReview;

  /// 管理員已下架違規內容。**軟刪除，資料保留** ——
  /// 訊息本身是案件的證據，硬刪除會使其後的申訴無從調閱。
  /// 使用者自己刪不掉單則訊息（刪除只發生在對話層級），本欄位僅由管理員設定。
  bool deleted;

  ChatMessage(
    this.fromMe,
    this.text,
    this.at, {
    this.read = false,
    this.category = MessageCategory.normal,
    this.pendingReview = false,
    this.deleted = false,
  });
}

class Conversation {
  final String id;
  final String peer;

  /// 對方的雲端身分。**示範資料的對話沒有，所以可以是空值。**
  ///
  /// 理由同 [TeamMember.uid]：在此之前這裡只有暱稱，要送訊息或標記
  /// 已讀時再拿暱稱去公開檔案裡反查 uid —— 反查不到就整段跳過，
  /// 而且是無聲的。同名的兩個人還會反查到同一個。
  final String? peerUid;

  final int peerRank;
  final bool peerIsInstructor;
  final MessageCategory category;
  final List<ChatMessage> messages;

  /// **單方刪除**：只改我這一側的狀態，對方仍看得到這段對話。
  /// 刪除只發生在對話層級 —— 單則訊息一經發送即不可刪除。
  bool deletedByMe;
  Conversation({
    required this.id,
    required this.peer,
    required this.peerRank,
    this.peerUid,
    this.peerIsInstructor = false,
    this.category = MessageCategory.normal,
    this.deletedByMe = false,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  ChatMessage? get last => messages.isEmpty ? null : messages.last;
  int get unread =>
      messages.where((m) => !m.fromMe && !m.read).length;

  /// 對話在清單裡歸哪一區。
  ///
  /// **取最後一則訊息的分類**：分類逐則固定不回溯，一段對話因此可能
  /// 前後混雜（陌生人傳訊 → 我回覆 → 後來互相關注）。清單只能歸一區，
  /// 取最後一則才會隨關係轉正而移動到一般訊息，符合使用者的預期。
  MessageCategory get bucket => last?.category ?? category;
}


// --- AI 調整對話 ---

/// 三條 AI 路徑的來源值域。
/// AI 調整的四條路徑。
///
/// [beforeTraining] 與 [planAdjust] 皆發生於訓練開始前，但**是兩件不同的事**：
/// 前者是使用者主動要求微調強度，只改本次快照、不涉及自訂訓練名額；
/// 後者由器材不足觸發，成功後會落地為一份新的自訂訓練並佔用一個名額。
/// 併成一條的話，只想微調強度的人也會被要求先同意佔用名額。
enum AiSource { beforeTraining, planAdjust, duringTraining, autoOptimize }

const aiSourceNames = <AiSource, String>{
  AiSource.beforeTraining: '訓練前調整',
  AiSource.planAdjust: '訓練前課表調整',
  AiSource.duringTraining: '訓練中調整',
  AiSource.autoOptimize: '自動優化',
};

/// 各路徑的調整對象與作用範圍。
const aiSourceScope = <AiSource, String>{
  AiSource.beforeTraining: '本次訓練課表　·　僅本次訓練',
  AiSource.planAdjust: '本次訓練課表　·　成功後落地為一份新的自訂訓練',
  AiSource.duringTraining: '本次訓練尚未完成的剩餘動作　·　僅本次訓練',
  AiSource.autoOptimize: '長期訓練課表範本　·　往後所有訓練',
};

/// 是否走自訂訓練名額分流。**只有器材解鎖後的課表調整會落地為自訂訓練。**
bool aiUsesPlanQuota(AiSource s) => s == AiSource.planAdjust;

/// 使用者主動發起者扣點；系統發起者不扣（〈AI 功能的付費邊界〉）。
bool aiCostsCredit(AiSource s) => s != AiSource.autoOptimize;

enum AiTurnRole { user, ai, system }

class AiTurn {
  final AiTurnRole role;
  final String text;
  final DateTime at;

  /// 這一則若是「AI 已產出建議」，帶著那份**結構化**的建議。
  ///
  /// **在此之前建議被拼成一整段字串塞進 [text]** —— 動作名、調整前後、
  /// 替換動作、理由全部黏在一起，再擠進一個寬 260 的對話泡泡裡。
  /// 使用者回報「AI 建議給的排版不好做閱讀」。
  ///
  /// 而那些欄位在 `AdjustChange` 裡本來就是分開的 —— 是渲染時才被拼掉的。
  /// 帶著結構過去，畫面就排得出表格。
  ///
  /// [text] 仍然保留可讀的純文字版本：對話紀錄要留得下來，
  /// 而「一段能唸出來的話」比一個物件可靠。
  final AdjustSuggestion? suggestion;

  /// 這份建議的作用範圍（例「本次訓練課表 · 僅本次訓練」）。
  /// 與 [suggestion] 同進退。
  final String? scope;

  const AiTurn(this.role, this.text, this.at, {this.suggestion, this.scope});
}

/// AI 調整已失敗的原因值域：逾時 / 服務錯誤。
enum AiFailReason { timeout, serviceError }

const aiFailReasonNames = <AiFailReason, String>{
  AiFailReason.timeout: '逾時',
  AiFailReason.serviceError: '服務錯誤',
};

/// 對話的推進階段。
enum AiStage {
  /// 尚未提出調整要求
  idle,
  /// AI 已再次確認需求，等待使用者確認
  clarifying,
  /// 使用者已確認需求，AI 分析中
  analyzing,
  /// AI 已產出建議，等待接受或拒絕
  proposed,
  /// 已套用新強度
  applied,
  /// 使用者已拒絕調整（流程結束，不可重新提出）
  rejected,
  /// AI 調整已失敗
  failed,
  /// AI 調整已拒絕（點數不足，根本未扣點）
  denied,
}

/// 可直接發送私訊的三種關係，滿足其一即為一般訊息。
///
/// 不符者仍可發送，但歸類為**陌生訊息**；陌生訊息不設數量上限，
/// 亦不因收訊方回覆而轉換分類 —— 回覆本身不建立任何一種關係。
MessageCategory classifyMessage({
  required bool mutualFollow,
  required bool mentorBond,
  required bool sameTeam,
}) =>
    (mutualFollow || mentorBond || sameTeam)
        ? MessageCategory.normal
        : MessageCategory.stranger;
