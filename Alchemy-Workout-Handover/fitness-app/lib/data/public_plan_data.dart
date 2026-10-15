/// 公開課表審核的雲端形狀（2026-10-15 補的缺功能）。
///
/// ## 在此之前：審核佇列只收得到「自己的」申請
///
/// `applyPublic()` 只把課表在**自己那台**標成「審核中」。管理員看到的待審清單
/// 來自他自己手上的 `customPlans` —— 其他使用者送審的課表根本沒有上雲，
/// 所以管理員實際上收不到任何人的申請；使用者那一側也永遠等不到結果。
///
/// ## 現在
///
/// `public_plans/{planId}`：使用者送審 → 管理員在佇列裡看到 → 裁決寫回 →
/// 申請人登入時讀回自己的結果；通過的對全站登入者可讀（「已公開」就是這個意思）。
enum PublicPlanReview { pending, approved, rejected, withdrawn }

class CloudPublicPlan {
  /// 課表 id，也是文件 id。
  final String id;

  final String ownerUid;
  final String ownerName;

  /// 課表內容，**原樣就是存檔裡自訂訓練那一份 JSON**（`_customPlanToJson`）——
  /// 兩邊共用同一套序列化，不會各寫一份而漂開。
  final Map<String, dynamic> plan;

  final PublicPlanReview state;
  final DateTime appliedAt;
  final String? rejectReason;
  final String? handlerName;

  const CloudPublicPlan({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.plan,
    required this.appliedAt,
    this.state = PublicPlanReview.pending,
    this.rejectReason,
    this.handlerName,
  });
}

abstract class PublicPlanSource {
  /// 送審（或修改已公開的課表後重新送審）。**一律寫成待審** —— 規則不讓擁有者自己寫成通過。
  Future<void> submitPlan(CloudPublicPlan p);

  /// 待審的課表。**只有管理員叫得動。**
  Future<List<CloudPublicPlan>> pendingPlans({int limit});

  /// 寫回裁決。**只有管理員叫得動。**
  Future<void> judgePlan(String id,
      {required bool approved, String? reason, required String handlerName});

  /// 我送過審的課表（任何狀態）—— 申請人靠它讀回裁決。
  Future<List<CloudPublicPlan>> myPlans();

  /// 全站已公開的課表（通過的）。
  Future<List<CloudPublicPlan>> approvedPlans({int limit});

  /// 擁有者下架自己的公開課表（軟刪除，資料保留）。
  Future<void> withdrawPlan(String id);
}
