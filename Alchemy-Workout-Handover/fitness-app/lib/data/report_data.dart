import '../domain/admin.dart';

/// 一筆檢舉在雲端的樣子。
///
/// ## 誰讀得到
///
/// 檢舉是**送出去給別人處理**的東西，不是使用者自己的資料。
/// 一般使用者不該讀得到檢舉佇列 —— 那裡面有別人的違規內容、
/// 檢舉者的身分與累計違規次數。所以 [queue] 與 [judge] 只有管理員
/// 呼叫得動，`firestore.rules` 那一側也是同一條線
/// （`allow read: if isAdmin()`）。
///
/// **原本這裡只有 [file]**，註解寫著「讀取那一側屬於管理端，不在 App 裡」。
/// 但管理端就在 App 裡（`screens/admin/`），只是身分那一段沒接 ——
/// 2026-09-24 接上 custom claim 之後，缺的就只剩這條讀取路徑。
/// 在那之前使用者按的每一筆檢舉都寫進了 Firestore，而**沒有任何人讀它**。
///
/// 在此之前檢舉**完全沒有上雲**：使用者按了檢舉，那筆案件只進本機的
/// `reports` 清單，關掉 App 就沒了，而且從頭到尾沒有任何人看得到。
/// 對內測來說無所謂，一旦開放註冊就不行 —— 會有人貼不該貼的東西，
/// 而檢舉是唯一的回報管道。
class CloudReport {
  final String id;

  /// 被檢舉的標的。與本機的 `ReportCase.targetKey` 同一個值
  /// （例如 `post:p12`、`msg:c3:5`）—— 併案就是靠它。
  final String targetKey;
  final ReportTarget target;
  final CaseOrigin origin;

  /// 檢舉當下的內容快照。**存快照不存參照**：貼文可以被作者編輯，
  /// 案件要留下的是被檢舉的那一版。
  final String content;
  final String reason;
  final String? note;

  /// 被檢舉者的暱稱。uid 在客戶端不一定查得到（對方可能不在
  /// 已載入的公開檔案裡），所以這裡存的是當下看得到的名字。
  final String accused;

  final String reporterUid;
  final String reporterName;
  final DateTime at;

  const CloudReport({
    required this.id,
    required this.targetKey,
    required this.target,
    required this.origin,
    required this.content,
    required this.reason,
    required this.accused,
    required this.reporterUid,
    required this.reporterName,
    required this.at,
    this.note,
  });
}

abstract class ReportSource {
  /// 送出一筆檢舉。**同一個人對同一個標的只會有一筆** ——
  /// 由文件 ID 保證，不必先查有沒有重複。
  Future<void> file(CloudReport r);

  /// 待處理的檢舉。**只有管理員叫得動** —— 一般帳號會被安全規則拒絕。
  ///
  /// 回傳的是**逐筆**，不是併過案的。併案（多人檢舉同一標的合併成
  /// 一個案件）在狀態層做，因為那需要看到所有人的那幾筆，
  /// 而那正是一般使用者不該讀得到的東西。
  Future<List<CloudReport>> queue({int limit});

  /// 寫回裁決。[upheld] 為真＝成立。
  ///
  /// 同一個標的可能有好幾位檢舉者、也就是好幾份文件，
  /// 所以裁決是對**一整組 [ids]** 下的，不是對一筆。
  Future<void> judge(List<String> ids,
      {required bool upheld, required String handlerName});
}
