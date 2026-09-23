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

  /// 教官專長（1–3 項）。非教官為空集合。
  final List<String> specialties;

  const PublicProfile({
    required this.uid,
    required this.displayName,
    required this.rank,
    this.grade,
    this.ability,
    this.followers = 0,
    this.isInstructor = false,
    this.reputation,
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
    List<String> specialties = const [],
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
        if (specialties.isNotEmpty) 'specialties': specialties,
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
}
