/// 審核時限設定 Aggregate。四類管理員審核的時限，屬平台級可調參數。
///
/// 本 Aggregate 於〈平台級設定的軟體邊界〉歸右欄：**不建 Command 與 Event**，
/// 維持後台人工維護 —— 時限是管理員端的內部工作期限，逾期僅產生
/// 「審核已逾期」、不改變案件狀態，對使用者的處理結果零影響。
library;

import 'clock.dart';

enum ReviewKind { report, appeal, instructor, publicPlan }

const reviewKindNames = <ReviewKind, String>{
  ReviewKind.report: '檢舉',
  ReviewKind.appeal: '申訴',
  ReviewKind.instructor: '教官測驗簡答題',
  ReviewKind.publicPlan: '公開訓練審核',
};

/// 四類分設而非共用同一值：其時效壓力不同。
///
/// - **申訴 72 小時為最短**：申訴期間處罰照常執行，最短的處罰級距是停權 7 天。
///   時限若接近該值，管理員看到案件時處罰已執行完畢，救濟路徑實質不存在。
/// - **公開訓練 14 天為最長**：等待期間課表仍為已發布、自己可用，無實質損失。
/// - **檢舉 7 天**：牽涉騷擾，拖延代價遠高於公開訓練審核。
const kReviewDeadlines = <ReviewKind, Duration>{
  ReviewKind.report: Duration(days: 7),
  ReviewKind.appeal: Duration(hours: 72),
  // 【注意】教官的「7 個工作天」與檢舉的「7 天」**不是同一個長度** ——
  // 前者不含例假日。模型明文警告勿於實作時混用。
  ReviewKind.instructor: Duration(days: 7),
  ReviewKind.publicPlan: Duration(days: 14),
};

/// 教官測驗簡答題的時限以**工作天**計，不含週六日。
bool _usesBusinessDays(ReviewKind k) => k == ReviewKind.instructor;

/// 自 [since] 起算，本類審核的到期時刻。
DateTime reviewDueAt(ReviewKind kind, DateTime since) {
  if (!_usesBusinessDays(kind)) {
    return since.add(kReviewDeadlines[kind]!);
  }
  var d = since;
  var left = kReviewDeadlines[kind]!.inDays;
  while (left > 0) {
    d = d.add(const Duration(days: 1));
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
      left -= 1;
    }
  }
  return d;
}

/// 審核已逾期 —— 一次性狀態判定。
/// Postcondition：**不改變案件狀態**，不自動通過、不自動駁回、不自動退回。
/// 逾期是營運指標，不是業務規則：需要被看見，而非需要被自動化。
bool isReviewOverdue(ReviewKind kind, DateTime since, {DateTime? now}) =>
    (now ?? appNow()).isAfter(reviewDueAt(kind, since));

/// 已等待時數 —— 「審核已逾期」Event 攜帶的資訊之一。
int waitedHours(DateTime since, {DateTime? now}) =>
    (now ?? appNow()).difference(since).inHours;

/// 剩餘時間的人話描述；已逾期回傳空值。
String? reviewTimeLeft(ReviewKind kind, DateTime since, {DateTime? now}) {
  final n = now ?? appNow();
  final due = reviewDueAt(kind, since);
  if (n.isAfter(due)) return null;
  final left = due.difference(n);
  if (left.inHours < 48) return '剩 ${left.inHours} 小時';
  return _usesBusinessDays(kind)
      ? '剩 ${_businessDaysBetween(n, due)} 個工作天'
      : '剩 ${left.inDays} 天';
}

int _businessDaysBetween(DateTime from, DateTime to) {
  var d = from, n = 0;
  while (d.isBefore(to)) {
    d = d.add(const Duration(days: 1));
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) n += 1;
  }
  return n;
}
