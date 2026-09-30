/// 教官資格申請的待審案件在雲端的樣子（`[BE-20]`）。
///
/// ## 在此之前它從來沒有離開申請人的裝置
///
/// `submitExam()` 把案件 `insert` 進**申請人自己的**
/// `AppState.instructorCases`。那份清單沒有雲端來源、`firestore.rules`
/// 裡沒有對應集合、也不進存檔 —— 申請人考完試，案件留在他自己的
/// 瀏覽器記憶體裡，**管理員在另一台裝置上永遠看不到**。
///
/// 而後台那一頁看起來一直都正常，因為它列的是示範用的假案件
/// （`buildInstructorCases()`）。與 `[BE-13]` 之前的檢舉是同一個形狀：
/// 畫面做好了、流程走得通、資料沒有離開過本機。
///
/// 使用者 2026-09-29 測「審核佇列的評分細則」時，回報教官分頁是空的 ——
/// 那不是壞掉，是線上版永遠不是示範模式，所以那一頁對每一個人、
/// 在任何時候都是空的。
///
/// ## 誰讀得到
///
/// 申請案是**送出去給別人處理**的東西。裡面有申請人的簡答作答與
/// AI 評分，一般使用者不該讀得到別人的。所以：
///
/// - 申請人**只寫得了自己那一筆**（文件 ID 就是他的 uid）
/// - **只有管理員讀得到佇列**，也只有管理員改得了裁決
///
/// 兩條線與 `firestore.rules` 那一側同源。
class CloudInstructorCase {
  /// 文件 ID＝申請人的 uid。
  ///
  /// **一個人同時只會有一筆待審案件**，由主鍵保證：重考送出就覆蓋掉
  /// 上一次，不會在佇列裡留下兩筆同一個人的申請。
  final String applicantUid;
  final String applicant;

  /// AI 訓練品質評分三維度與加權平均。
  final Map<String, double> aiScores;
  final double weighted;
  final List<String> concerns;

  /// 簡答題作答：`(題目, 作答)`。
  ///
  /// **存題目全文而非題號**：審核畫面以題目全文回查題庫取出評分細則，
  /// 而題目可能被後台改寫 —— 存全文的話，管理員至少看得到申請人
  /// 當時**實際被問到的那一句**。
  final List<(String, String)> answers;

  final DateTime at;

  const CloudInstructorCase({
    required this.applicantUid,
    required this.applicant,
    required this.aiScores,
    required this.weighted,
    required this.concerns,
    required this.answers,
    required this.at,
  });
}

/// 一筆申請案的裁決結果。
enum InstructorVerdict { pending, passed, rejected }

abstract class InstructorCaseSource {
  /// 送出自己的申請案。
  Future<void> file(CloudInstructorCase c);

  /// **我自己那一筆的裁決。** 沒有申請過就回空值。
  ///
  /// 在此之前沒有這一支，於是裁決從來沒有回到申請人身上：
  /// 管理員按了「通過」，雲端寫了 `state: passed`，而申請人那一側
  /// **沒有任何東西會去讀它** —— 安全規則也只讓管理員讀。
  /// 加上 `instructorStage` 不進存檔，申請人重新整理之後
  /// 連「待人工審核」都不見了，畫面退回「你還沒申請」。
  ///
  /// 使用者 2026-09-29 實測：通過測驗、管理員也核准了，
  /// 重新整理之後沒看到自己成為教官。
  Future<InstructorVerdict?> mine();

  /// 待處理的申請案。**只有管理員叫得動。**
  Future<List<CloudInstructorCase>> queue({int limit});

  /// 寫回裁決。[passed] 為真＝通過。
  Future<void> decide(String applicantUid,
      {required bool passed, required String handlerName});
}
