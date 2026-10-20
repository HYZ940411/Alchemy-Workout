import 'novice_wrapup.dart';
import 'review_deadline.dart';

// 管理員（〈管理員 Aggregate〉）
//
// 管理員為獨立 Aggregate，與使用者帳號分離 —— 管理員不必是平台使用者。

/// 權限組：至少 1 項，一位管理員可同時具備多組。
enum AdminScope { contentReview, productManage, platformConfig }

const adminScopeNames = <AdminScope, String>{
  AdminScope.contentReview: '內容審核',
  AdminScope.productManage: '商品管理',
  AdminScope.platformConfig: '平台設定',
};

/// 各權限組涵蓋的 Command 數（全案 34 個管理員 Command）。
const adminScopeCommandCount = <AdminScope, int>{
  AdminScope.contentReview: 12,
  AdminScope.productManage: 6,
  AdminScope.platformConfig: 16,
};

enum AdminStatus { active, disabled }

class Admin {
  final String id;
  final String name;
  final Set<AdminScope> scopes;
  final AdminStatus status;
  const Admin({
    required this.id,
    required this.name,
    required this.scopes,
    this.status = AdminStatus.active,
  });

  /// 每個管理員 Command 的 Precondition：狀態為生效中，且權限組涵蓋該 Command。
  bool can(AdminScope s) =>
      status == AdminStatus.active && scopes.contains(s);
}

// --- 待審佇列 ---

/// 檢舉／申訴的狀態值域四值。審視中不自動退回待審視 ——
/// 管理員未下判定即離開者，案件留在審視中。
enum CaseState { pending, reviewing, upheld, dismissed }

const caseStateNames = <CaseState, String>{
  CaseState.pending: '待審視',
  CaseState.reviewing: '審視中',
  CaseState.upheld: '已成立',
  CaseState.dismissed: '已駁回',
};

/// 檢舉理由設定 Aggregate 的值域，由管理員於後台維護，非寫死於系統。
/// 採列舉單選 ＋ 選填補充文字 —— 純自由文字無法讓待審佇列依理由篩選與排序。
const kReportReasons = <String>[
  '騷擾辱罵', '色情不雅', '暴力威脅', '廣告垃圾', '假訊息', '其他',
];

/// 一筆檢舉者紀錄。併案時新增，不覆蓋既有紀錄 ——
/// 檢舉者紀錄正是判斷是否為有組織惡意檢舉的依據。
class Reporter {
  final String name;
  final String reason;
  final String? note;
  final DateTime at;
  const Reporter({
    required this.name,
    required this.reason,
    this.note,
    required this.at,
  });
}

enum ReportTarget { post, comment, account, message }

const reportTargetNames = <ReportTarget, String>{
  ReportTarget.post: '貼文',
  ReportTarget.comment: '留言',
  ReportTarget.account: '帳號',
  ReportTarget.message: '私訊',
};

/// 被檢舉標的的識別鍵。**格式統一於此**，不由各個檢舉入口各自拼字串 ——
/// 同一則貼文自動態牆檢舉與自貼文頁檢舉必須產出同一把鍵，
/// 否則「多人檢舉同一內容合併為同一案件」會依進入的頁面而分裂成兩案。
String reportKey(ReportTarget target, String id) =>
    '${target.name}:$id';

/// 自識別鍵取回標的 ID。無前綴者視為 ID 本身（相容既有資料）。
String reportedId(String key) {
  final i = key.indexOf(':');
  return i < 0 ? key : key.substring(i + 1);
}

enum CaseOrigin { userReport, autoFlag }

const caseOriginNames = <CaseOrigin, String>{
  CaseOrigin.userReport: '使用者檢舉',
  CaseOrigin.autoFlag: '系統自動標記',
};

class ReportCase {
  final String id;

  /// 被檢舉標的的識別鍵。多人檢舉**同一標的**合併為同一案件。
  final String targetKey;

  /// 檢舉者紀錄。人數即為 [reporterCount]。
  ///
  /// **一律持有可變副本**：併案時要往裡面新增一筆，
  /// 若直接沿用呼叫端傳進來的常數空清單，第二個人檢舉時就會當場炸開。
  final List<Reporter> reporters;
  final ReportTarget target;
  final CaseOrigin origin;
  final String content;
  final String reason;
  int reporterCount; // 多人檢舉同一內容合併為同一案件；併案時累加
  final String accused;

  /// 被檢舉者的雲端身分。**記點看它，不看暱稱** —— 暱稱會改，也會撞名。
  /// 2026-09-25 之前送出的案件沒有，那些案件審得了但記不了點。
  final String? accusedUid;

  final int accusedViolations; // 處罰級距依累計違規次數而定
  final DateTime enteredAt;
  CaseState state;
  String? handlerName; // 處理中的管理員
  ReportCase({
    required this.id,
    this.targetKey = '',
    List<Reporter> reporters = const [],
    required this.target,
    required this.origin,
    required this.content,
    required this.reason,
    required this.reporterCount,
    required this.accused,
    this.accusedUid,
    required this.accusedViolations,
    required this.enteredAt,
    this.state = CaseState.pending,
    this.handlerName,
  }) : reporters = List.of(reporters);

  /// 審核已逾期。時限見〈審核時限設定 Aggregate〉；逾期只標示，不改變案件狀態。
  /// 亦為「接手審核案件」的 Precondition —— 接手須該案件已發生本 Event。
  bool get overdue => isReviewOverdue(ReviewKind.report, enteredAt);

  /// 剩餘時間；已逾期為空值。
  String? get timeLeft => reviewTimeLeft(ReviewKind.report, enteredAt);

  /// 「審核已逾期」Event 攜帶的已等待時數。
  int get waited => waitedHours(enteredAt);

}

enum AppealTarget { punishment, blockedContent }

const appealTargetNames = <AppealTarget, String>{
  AppealTarget.punishment: '處罰',
  AppealTarget.blockedContent: '內容攔截',
};

class AppealCase {
  final String id;
  final String appellant;

  /// 申訴人的雲端身分。**撤銷處罰、退回違規次數都看它，不看暱稱。**
  /// 示範資料的假案件沒有，所以可以是空值。
  final String? appellantUid;
  final AppealTarget target;
  final String subject;
  final String reason;
  final DateTime filedAt;
  final int daysSinceIncident;

  /// 當時被攔截的原文。**只有內容攔截的申訴有。**
  /// 規格：「申訴時管理員須看得到當時攔截的是什麼」——
  /// 攔截的內容沒有寫進任何 Aggregate，不帶在申訴上就沒有人看得到。
  final String? content;
  CaseState state;
  String? handlerName;
  AppealCase({
    required this.id,
    required this.appellant,
    this.appellantUid,
    required this.target,
    required this.subject,
    required this.reason,
    required this.filedAt,
    required this.daysSinceIncident,
    this.content,
    this.state = CaseState.pending,
    this.handlerName,
  });

  /// 審核已逾期。時限見〈審核時限設定 Aggregate〉；逾期只標示，不改變案件狀態。
  /// 亦為「接手審核案件」的 Precondition —— 接手須該案件已發生本 Event。
  bool get overdue => isReviewOverdue(ReviewKind.appeal, filedAt);

  /// 剩餘時間；已逾期為空值。
  String? get timeLeft => reviewTimeLeft(ReviewKind.appeal, filedAt);

  /// 「審核已逾期」Event 攜帶的已等待時數。
  int get waited => waitedHours(filedAt);

}

class InstructorCase {
  final String id;
  final String applicant;

  /// 申請人的雲端身分。**判定一律看它，不看暱稱**（暱稱重構階段二）。
  ///
  /// 在此之前 `decideInstructor()` 寫的是
  /// `c.applicant == displayName` —— 撞名或改過名的話，
  /// **教官資格會發給錯的人**。
  ///
  /// 示範資料的假案件沒有，所以可以是空值 ——
  /// 與 `AppealCase.appellantUid`、`CloudReport.accusedUid` 同一個處理。
  final String? applicantUid;
  /// AI 評分三維度與加權平均
  final Map<String, double> aiScores;
  final double weighted;
  final List<String> concerns; // 疑慮標記
  final List<(String, String)> answers; // 簡答題作答內容
  final DateTime enteredAt;
  CaseState state;
  InstructorCase({
    this.applicantUid,
    required this.id,
    required this.applicant,
    required this.aiScores,
    required this.weighted,
    required this.concerns,
    required this.answers,
    required this.enteredAt,
    this.state = CaseState.pending,
  });
  /// 審核已逾期。時限見〈審核時限設定 Aggregate〉；逾期只標示，不改變案件狀態。
  /// 亦為「接手審核案件」的 Precondition —— 接手須該案件已發生本 Event。
  bool get overdue => isReviewOverdue(ReviewKind.instructor, enteredAt);

  /// 剩餘時間；已逾期為空值。
  String? get timeLeft => reviewTimeLeft(ReviewKind.instructor, enteredAt);

  /// 「審核已逾期」Event 攜帶的已等待時數。
  int get waited => waitedHours(enteredAt);

}

class PublicPlanCase {
  final String id;
  final String author;
  final List<String> exercises;
  final DateTime appliedAt;
  CaseState state;
  PublicPlanCase({
    required this.id,
    required this.author,
    required this.exercises,
    required this.appliedAt,
    this.state = CaseState.pending,
  });
}

// --- 處罰級距 ---

/// 固定階梯累犯制，依累計違規次數決定，與檢舉理由的類別無對應關係。
/// 1–2 次警告；3–4 次社群功能停權 7 天；5–6 次 30 天；7 次起永久停權。
class PunishmentTier {
  final String label;
  final int? days;
  const PunishmentTier(this.label, this.days);
}

PunishmentTier tierForViolations(int count) {
  if (count <= 2) return const PunishmentTier('警告', null);
  if (count <= 4) return const PunishmentTier('社群功能停權 7 天', 7);
  if (count <= 6) return const PunishmentTier('社群功能停權 30 天', 30);
  return const PunishmentTier('永久停權', null);
}

/// 「管理員已下架違規內容」僅適用對象類型為貼文 / 留言 / 私訊。
/// 帳號不是一則內容，沒有可下架的標的 —— 帳號類檢舉成立時直接觸發「使用者已受處罰」。
bool canTakeDownContent(ReportTarget t) => t != ReportTarget.account;

/// 受處罰者具教官身分且處罰為社群功能停權以上（累計 3 次起）時，
/// 教官資格一併撤銷；警告不撤銷。
bool revokesInstructor(int violationsAfter) => violationsAfter >= 3;

// --- 商品管理 ---

enum ListingState { listed, delisted }

const listingStateNames = <ListingState, String>{
  ListingState.listed: '已上架',
  ListingState.delisted: '已下架',
};

enum VirtualSubtype { consumable, unlock }

const virtualSubtypeNames = <VirtualSubtype, String>{
  VirtualSubtype.consumable: '消耗品',
  VirtualSubtype.unlock: '權限解鎖',
};

// --- 評分彙總 ---

enum RatingTarget { noviceTask, trainingPlan }

const ratingTargetNames = <RatingTarget, String>{
  RatingTarget.noviceTask: '新手任務',
  RatingTarget.trainingPlan: '訓練計畫',
};

/// 把逐筆評分彙總成「每個評分對象一列」（〈Read Model：管理員評分彙總〉）。
///
/// [nameOf] 把對象翻成看得懂的名字 —— 訓練計畫的名稱、新手任務的範本名。
/// 這一層不認得課表目錄，所以由呼叫端給。
///
/// **由差到好排。** 規格說這張表的用途是回答「哪一份訓練計畫該改」，
/// 而管理員一打開就該看到最該改的那一份。平均相同時樣本多的在前 ——
/// 兩份都是 2.5 星，一份 40 則一份 1 則，該先看哪一份沒有懸念。
List<RatingSummary> summarizeRatings(
  List<ExperienceRating> rows,
  String Function(RatingTarget target, String targetId) nameOf,
) {
  final byTarget = <(RatingTarget, String), List<ExperienceRating>>{};
  for (final r in rows) {
    byTarget.putIfAbsent((r.target, r.targetId), () => []).add(r);
  }

  final out = <RatingSummary>[];
  for (final e in byTarget.entries) {
    final dist = List.filled(5, 0);
    for (final r in e.value) {
      // 星等超出 1–5 的資料不該存在，真的出現就略過 ——
      // 算進去會讓平均值失真，而平均值正是這張表的主角。
      if (r.stars < 1 || r.stars > 5) continue;
      dist[r.stars - 1] += 1;
    }
    if (dist.every((n) => n == 0)) continue;
    final entries = [
      for (final r in e.value)
        if (r.stars >= 1 && r.stars <= 5) (r.stars, r.feedback, r.at),
    ]..sort((a, b) => b.$3.compareTo(a.$3)); // 新的在前
    out.add(RatingSummary(
      target: e.key.$1,
      name: nameOf(e.key.$1, e.key.$2),
      distribution: dist,
      entries: entries,
    ));
  }

  out.sort((a, b) {
    final byAvg = a.average.compareTo(b.average);
    return byAvg != 0 ? byAvg : b.count.compareTo(a.count);
  });
  return out;
}

class RatingSummary {
  final RatingTarget target;
  final String name;
  final List<int> distribution; // 1★ 至 5★ 各自的筆數
  final List<(int, String?, DateTime)> entries; // 逐筆：星等、文字回饋、時戳
  const RatingSummary({
    required this.target,
    required this.name,
    required this.distribution,
    required this.entries,
  });

  int get count => distribution.reduce((a, b) => a + b);
  double get average {
    if (count == 0) return 0;
    var sum = 0;
    for (var i = 0; i < 5; i++) {
      sum += distribution[i] * (i + 1);
    }
    return sum / count;
  }
}

/// 一次「檢舉成立」到底做了什麼。
///
/// ## 為什麼需要它
///
/// 2026-09-28 使用者雙人實測 T8：判成立之後**貼文兩邊都還在**、
/// 被檢舉者也沒有收到任何處罰，而案件從佇列裡消失了。
///
/// 而管理員按下「成立並處罰」之後，畫面只說「已處罰：警告」——
/// **那句話是照著級距印的，不是照著實際發生的事印的。**
/// 下架了幾則、記點記到誰身上，一個字都沒說。
///
/// 邏輯本身在測試裡是通的（案件從雲端讀進來、判成立、`deleted` 變 true、
/// 違規次數 +1），所以斷點在真實的雲端往返上 —— 而那裡**沒有任何回饋
/// 可以讓人分辨是哪一段斷了**。
class UpholdOutcome {
  /// 下架了幾則內容。**-1 代表帳號類**（本來就不下架）。
  /// 0 代表「找得到案件，卻找不到那則內容」—— 那正是要抓的狀況。
  final int removed;

  /// 記點後的累計違規次數。
  final int violationsAfter;

  /// 記得進被檢舉者的雲端紀錄嗎。
  /// 沒有 `accusedUid` 的舊案件寫不進 `violations/{uid}` ——
  /// 那時候被檢舉者永遠不會知道自己被記點。
  final bool recordedForAccused;

  /// 被拒絕的原因。空值代表真的執行了。
  final String? refusedWhy;

  const UpholdOutcome({
    required this.removed,
    required this.violationsAfter,
    required this.recordedForAccused,
  }) : refusedWhy = null;

  const UpholdOutcome.refused(String why)
      : removed = 0,
        violationsAfter = 0,
        recordedForAccused = false,
        refusedWhy = why;

  /// 給管理員看的一句話。**說實際發生的事，不說級距的名字。**
  String get summary {
    if (refusedWhy case final why?) return why;
    final parts = <String>[
      switch (removed) {
        -1 => '帳號類不下架內容',
        0 => '⚠ 沒有下架任何內容（找不到那則，可能不在這台裝置的清單裡）',
        final n => '已下架 $n 則',
      },
      '累計第 $violationsAfter 次違規',
      if (!recordedForAccused) '⚠ 這一案沒有對方的帳號識別，記點寫不進他的紀錄',
    ];
    return parts.join('　·　');
  }
}
