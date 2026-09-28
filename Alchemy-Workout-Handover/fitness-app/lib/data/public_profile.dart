import '../domain/ability.dart';

/// 一位使用者**對外可見**的那一部分（[BE-11] 批次 1）。
///
/// ## 為什麼需要這個東西
///
/// 在 `[BE-04]` 之前，整個社群層是用**暱稱字串**當識別碼的
/// （`_mine(author) => author == displayName`、`following` 存的是暱稱）。
/// 那在只有一位使用者的假資料世界裡沒問題，但跨使用者資料一旦上雲就不成立：
/// **暱稱不唯一、而且可以改**。兩個人都叫「你」的話，誰關注誰就分不出來。
///
/// 所以跨使用者資料一律以 `uid` 為鍵，而「uid 對應到誰」就由這份檔案回答。
/// 關注、貼文、團隊、師徒（批次 2–4）全部建立在它上面。
///
/// ## 為什麼不直接開放讀 `users/{uid}`
///
/// 那份文件裡有身高體重、生日、電子郵件、處罰狀態、違規次數。
/// 對外可見的只有下面這幾個欄位 —— 分成兩份文件，
/// 安全規則才寫得出「這幾個欄位大家可讀，其餘只有本人」。
/// 見 `Firestore-Schema設計.md` 第 7 節。
class PublicProfile {
  final String uid;
  final String displayName;
  final int rank;

  /// 綜合能力等級。**空值代表使用者關閉了對外可見**，不是「沒有等級」。
  final String? grade;

  /// 六維能力值。**空值代表使用者關閉了對外可見**。
  final Map<Dim, int>? ability;

  final int followers;
  final bool isInstructor;

  /// 教官聲望。非教官為空值。
  final int? reputation;

  /// 目前帶幾位學徒。非教官為 0。
  ///
  /// **這個數字要對外公開，「帶徒名額已滿」才擋得住。** 少了它，
  /// 拜師頁只能假設每位教官都還有空位 —— 使用者申請下去才發現滿了，
  /// 而且是在雲端那一側才擋，畫面上先成功了一次。
  final int apprentices;

  /// 帶徒名額上限。非教官為 0。由對方的歷史最高聲望推導，
  /// 所以**必須跟著檔案一起公開**，這一側算不出來。
  final int apprenticeCap;

  /// 收到的平均星等。**[ratingCount] 為 0 時這個數字沒有意義** ——
  /// 畫面要呈現「尚無評分」，不是 0.0 顆星。
  final double avgRating;

  /// 收到幾則評分。由教官自己統計自己那些師徒任務上的評分後發布 ——
  /// 別人算不出來（讀不到那些關係底下的任務）。
  final int ratingCount;

  /// 教官專長（1–3 項）。非教官為空集合。
  final List<String> specialties;

  // --- 排行榜（使用者裁決 B，2026-09-28）---
  //
  // 在此之前排行榜的名次是**示範資料做的**：`leaderboardWindow()` 第一行
  // 就是「不是示範帳號就回空清單」，真帳號從來沒有過名次。
  //
  // 要跟別人比就得讀得到別人的分數，而公開檔案是這個模型裡唯一
  // 「登入者皆可讀」的集合 —— 所以分數放這裡。
  //
  // **這不能防作弊**：分數仍由裝置算出來再自己寫上來。真正的把關
  // 要等 `[BE-07]` 把評分搬上 Cloud Functions。

  /// 本週的個人排行榜分數。
  final int weeklyScore;

  /// 本月的個人排行榜分數。
  final int monthlyScore;

  /// 本週期鎖定的階級組別（每 10 階一組）。**排行榜只跟同組別比。**
  ///
  /// 存的是「本週期鎖定的那一組」而不是現在的階級 ——
  /// 週期內升階不改變本週期的組別（見 `AppState.lockedRankGroup`）。
  final int weeklyGroup;
  final int monthlyGroup;

  const PublicProfile({
    required this.uid,
    required this.displayName,
    required this.rank,
    this.grade,
    this.ability,
    this.followers = 0,
    this.isInstructor = false,
    this.reputation,
    this.apprentices = 0,
    this.apprenticeCap = 0,
    this.weeklyScore = 0,
    this.monthlyScore = 0,
    this.weeklyGroup = 0,
    this.monthlyGroup = 0,
    this.avgRating = 0,
    this.ratingCount = 0,
    this.specialties = const [],
  });

  /// 依規格的兩個可見度開關決定要公開什麼。
  ///
  /// **兩個開關各自獨立**：可以只公開綜合等級而不公開六維明細。
  /// **教官身分會讓兩個開關都失效** —— 學徒要挑教官，看不到能力值就無從判斷，
  /// 所以成為教官等同接受這部分公開。見〈使用者 Aggregate〉的兩個可見度欄位。
  factory PublicProfile.of({
    required String uid,
    required String displayName,
    required int rank,
    required Map<Dim, int> points,
    required bool abilityPublic,
    required bool overallGradePublic,
    required bool isInstructor,
    int followers = 0,
    int? reputation,
    int apprentices = 0,
    int apprenticeCap = 0,
    double avgRating = 0,
    int ratingCount = 0,
    List<String> specialties = const [],
    int weeklyScore = 0,
    int monthlyScore = 0,
    int weeklyGroup = 0,
    int monthlyGroup = 0,
  }) =>
      PublicProfile(
        uid: uid,
        displayName: displayName,
        rank: rank,
        grade: (overallGradePublic || isInstructor)
            ? overallGrade(points)
            : null,
        ability: (abilityPublic || isInstructor) ? Map.of(points) : null,
        followers: followers,
        isInstructor: isInstructor,
        reputation: isInstructor ? reputation : null,
        apprentices: isInstructor ? apprentices : 0,
        apprenticeCap: isInstructor ? apprenticeCap : 0,
        avgRating: isInstructor ? avgRating : 0,
        ratingCount: isInstructor ? ratingCount : 0,
        // **排行榜分數不受可見度開關影響。** 那兩個開關管的是六維與
        // 綜合等級；名次本來就是要公開比的，藏起來排行榜就不成立。
        weeklyScore: weeklyScore,
        monthlyScore: monthlyScore,
        weeklyGroup: weeklyGroup,
        monthlyGroup: monthlyGroup,
        specialties: isInstructor ? specialties : const [],
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'rank': rank,
        // 關閉可見度時**不寫這個鍵**，而不是寫 null ——
        // 寫進去等於把「他有幾點但不給你看」這件事也放上雲端，
        // 而安全規則擋不住已經在文件裡的欄位（規則的粒度是文件，不是欄位）。
        if (grade != null) 'grade': grade,
        if (ability != null)
          'ability': {for (final e in ability!.entries) e.key.name: e.value},
        'followers': followers,
        'isInstructor': isInstructor,
        if (reputation != null) 'reputation': reputation,
        if (isInstructor) 'apprentices': apprentices,
        if (isInstructor) 'apprenticeCap': apprenticeCap,
        if (isInstructor) 'avgRating': avgRating,
        if (isInstructor) 'ratingCount': ratingCount,
        if (specialties.isNotEmpty) 'specialties': specialties,
        // **一律寫出去，即使是 0。** 排行榜靠 `where(組別) + orderBy(分數)`
        // 查詢，而 Firestore 的索引只收「有這個欄位」的文件 ——
        // 少寫一次，那個人就整個從排行榜上消失。
        'weeklyScore': weeklyScore,
        'monthlyScore': monthlyScore,
        'weeklyGroup': weeklyGroup,
        'monthlyGroup': monthlyGroup,
      };

  static PublicProfile? fromJson(String uid, Map<String, dynamic>? j) {
    if (j == null) return null;
    final name = j['displayName'];
    if (name is! String || name.isEmpty) return null; // 認不出是誰就當它不存在

    final raw = j['ability'];
    return PublicProfile(
      uid: uid,
      displayName: name,
      rank: j['rank'] is num ? (j['rank'] as num).round() : 1,
      grade: j['grade'] is String ? j['grade'] as String : null,
      ability: raw is Map
          ? {
              for (final d in Dim.values)
                if (raw[d.name] is num) d: (raw[d.name] as num).round(),
            }
          : null,
      followers: j['followers'] is num ? (j['followers'] as num).round() : 0,
      isInstructor: j['isInstructor'] == true,
      reputation:
          j['reputation'] is num ? (j['reputation'] as num).round() : null,
      apprentices:
          j['apprentices'] is num ? (j['apprentices'] as num).round() : 0,
      apprenticeCap:
          j['apprenticeCap'] is num ? (j['apprenticeCap'] as num).round() : 0,
      weeklyScore:
          j['weeklyScore'] is num ? (j['weeklyScore'] as num).round() : 0,
      monthlyScore:
          j['monthlyScore'] is num ? (j['monthlyScore'] as num).round() : 0,
      weeklyGroup:
          j['weeklyGroup'] is num ? (j['weeklyGroup'] as num).round() : 0,
      monthlyGroup:
          j['monthlyGroup'] is num ? (j['monthlyGroup'] as num).round() : 0,
      avgRating:
          j['avgRating'] is num ? (j['avgRating'] as num).toDouble() : 0,
      ratingCount:
          j['ratingCount'] is num ? (j['ratingCount'] as num).round() : 0,
      specialties: [
        for (final s in (j['specialties'] as List? ?? const []))
          if (s is String) s,
      ],
    );
  }
}

/// 登入時先撈幾筆公開檔案。
///
/// **這只是「一開始先認得誰」，不再是上限。** 在 [PublicProfileSource.byUids]
/// 之前，這個數字就是整個 App 能認得的人數上限 —— 撈不到的人是隱形的：
/// 找不到、私訊不了，他的貼文還會顯示錯的階級。現在畫面上出現的 uid
/// 會隨用隨取，這份清單只負責「找人」頁的初始名單。
const int kProfileFetchLimit = 200;

/// [PublicProfileSource.byUids] 一次查幾個 uid。
///
/// Firestore 的 `whereIn` 上限是 30 個值，超過要自己切批。
const int kProfileByUidChunk = 30;

/// 排行榜的一頁：我第幾名，以及我上下各一段。
class LeaderboardPage {
  /// 我的名次（1 起算）。**同分並列同一名次，並列後順延跳號** ——
  /// 由「分數比我高的人數 ＋ 1」直接算出，那正是這條規則的定義。
  final int place;

  /// 視窗內的每一位，由分數高到低排。**含我自己。**
  final List<PublicProfile> rows;

  const LeaderboardPage({required this.place, required this.rows});
}

abstract class PublicProfileSource {
  /// 把我自己的公開檔案寫上去（覆寫）。
  Future<void> publish(PublicProfile me);

  /// 讀別人的公開檔案。**不含自己** —— 呼叫端要的是「平台上還有誰」。
  Future<List<PublicProfile>> others({int limit});

  /// 依 uid 直接取一批公開檔案。查無此人者不出現在結果裡。
  ///
  /// [others] 撈的是「最近活躍的前 N 位」，而畫面上會出現的人不一定在
  /// 那 N 位裡 —— 三年前發的文、剛加入的隊友、久未上線的教官都是。
  /// 這一支負責補齊：畫面需要誰，就去把誰取回來。
  Future<List<PublicProfile>> byUids(List<String> uids);

  /// 刪掉我的公開檔案。帳號刪除時用 —— 少了這一步，
  /// 帳號都沒了，別人在「找人」裡還看得到他。
  Future<void> remove();

  /// 同組別的排行榜視窗（使用者裁決 B，2026-09-28）。
  ///
  /// [myScore] 是我**這一刻**的分數 —— 不從雲端讀，雲端那份可能比我手上
  /// 這份舊（公開檔案是即發即忘地寫上去的）。
  ///
  /// 回空值代表這個榜查不到東西（查詢失敗、或索引還沒建好）。
  /// **那和「我是第 1 名」不一樣**，呼叫端要分得開。
  Future<LeaderboardPage?> leaderboard({
    required bool weekly,
    required int group,
    required int myScore,
    int window,
  });
}
