import '../domain/admin.dart';

/// 一筆申訴在雲端的樣子（`[BE-13]`，2026-09-25）。
///
/// ## 在此之前：申訴送不出這台裝置
///
/// `fileAppeal()` 只把案件加進本機的 `appeals` 清單 —— 而那個清單
/// 連存檔都沒有。使用者寫了申訴理由、按下送出、看到「已送出」，
/// 然後重新整理就沒了，**而且從頭到尾沒有任何管理員看得到**。
///
/// 這與檢舉那次是同一種病的兩個位置：檢舉至少寫進了 Firestore
/// （只是沒人讀），申訴連寫都沒寫。
class CloudAppeal {
  /// `{申訴人 uid}__{處罰開出的毫秒時戳}`。
  ///
  /// **同一筆處罰只能申訴一次**（規格），由這個主鍵保證 ——
  /// 不是靠「送出前先查有沒有申訴過」，那在連按兩下時仍會寫出兩筆。
  /// 帶著處罰時戳而不是只用 uid，是因為一個人一生可能被罰好幾次，
  /// 每一次各有一次申訴機會。
  final String id;

  final String appellantUid;
  final String appellantName;
  final AppealTarget target;

  /// 申訴的對象是什麼 —— 例如「社群功能停權 7 天」。
  final String subject;
  final String reason;
  final DateTime filedAt;

  /// 從受處罰到提出申訴隔了幾天。管理端排序與判斷用。
  final int daysSinceIncident;

  final CaseState state;
  final String? handlerName;

  const CloudAppeal({
    required this.id,
    required this.appellantUid,
    required this.appellantName,
    required this.target,
    required this.subject,
    required this.reason,
    required this.filedAt,
    required this.daysSinceIncident,
    this.state = CaseState.pending,
    this.handlerName,
  });
}

abstract class AppealSource {
  /// 送出一筆申訴。**同一筆處罰只有一筆** —— 由文件 ID 保證。
  Future<void> file(CloudAppeal a);

  /// 待處理的申訴。**只有管理員叫得動。**
  Future<List<CloudAppeal>> queue({int limit});

  /// 寫回裁決。[upheld] 為真＝申訴成立、處罰撤銷。
  Future<void> judge(String id,
      {required bool upheld, required String handlerName});
}
