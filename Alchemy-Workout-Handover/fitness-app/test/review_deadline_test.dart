import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/review_deadline.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('審核時限設定 Aggregate：四類分設', () {
    test('四類的時限各不相同', () {
      expect(kReviewDeadlines[ReviewKind.appeal], const Duration(hours: 72));
      expect(kReviewDeadlines[ReviewKind.report], const Duration(days: 7));
      expect(kReviewDeadlines[ReviewKind.publicPlan], const Duration(days: 14));
      // 申訴最短：申訴期間處罰照常執行，最短處罰是停權 7 天。
      expect(kReviewDeadlines[ReviewKind.appeal]!.inHours,
          lessThan(kReviewDeadlines[ReviewKind.report]!.inHours));
      // 公開訓練最長：等待期間課表仍為已發布、自己可用，無實質損失。
      expect(kReviewDeadlines[ReviewKind.publicPlan]!.inHours,
          greaterThan(kReviewDeadlines[ReviewKind.report]!.inHours));
    });

    test('檢舉的 7 天與教官的 7 個工作天不是同一個長度', () {
      // 模型明文警告勿於實作時混用。
      final monday = DateTime(2026, 9, 7); // 2026-09-07 是週一
      expect(monday.weekday, DateTime.monday);
      final reportDue = reviewDueAt(ReviewKind.report, monday);
      final instructorDue = reviewDueAt(ReviewKind.instructor, monday);
      expect(reportDue, monday.add(const Duration(days: 7)));
      // 7 個工作天跨過兩個週末 → 實際是 9 個日曆天。
      expect(instructorDue, monday.add(const Duration(days: 9)));
      expect(instructorDue.isAfter(reportDue), isTrue);
    });

    test('工作天計算跳過週六日', () {
      final friday = DateTime(2026, 9, 4);
      expect(friday.weekday, DateTime.friday);
      // 從friday起算 7 個工作天：跳過 9/5、9/6 與 9/12、9/13
      expect(reviewDueAt(ReviewKind.instructor, friday), DateTime(2026, 9, 15));
    });

    test('逾期判定以到期時刻為界', () {
      final since = DateTime(2026, 9, 1);
      final due = reviewDueAt(ReviewKind.appeal, since);
      expect(
          isReviewOverdue(ReviewKind.appeal, since,
              now: due.subtract(const Duration(minutes: 1))),
          isFalse);
      expect(
          isReviewOverdue(ReviewKind.appeal, since,
              now: due.add(const Duration(minutes: 1))),
          isTrue);
    });

    test('剩餘時間：未滿 48 小時報小時，其餘報天數', () {
      final now = DateTime(2026, 9, 1, 12);
      // 72 小時 > 48，故報天數。
      expect(reviewTimeLeft(ReviewKind.appeal, now, now: now), '剩 3 天');
      expect(reviewTimeLeft(ReviewKind.report, now, now: now), '剩 7 天');
      expect(
          reviewTimeLeft(ReviewKind.appeal,
              now.subtract(const Duration(hours: 40)),
              now: now),
          '剩 32 小時');
      // 已逾期回傳空值。
      expect(
          reviewTimeLeft(ReviewKind.appeal,
              now.subtract(const Duration(hours: 80)),
              now: now),
          isNull);
    });
  });

  group('逾期只標示，不改變案件狀態', () {
    test('三類佇列各有逾期案件，且都還留在待審清單裡', () {
      final s = AppState();

      final r = s.reports.firstWhere((c) => c.id == 'R-2041');
      expect(r.overdue, isTrue);
      expect(r.state, isNot(CaseState.dismissed));
      expect(r.state, isNot(CaseState.upheld));

      final a = s.appeals.firstWhere((c) => c.id == 'AP-312');
      expect(a.overdue, isTrue);
      expect(a.state, CaseState.reviewing, reason: '不自動退回待審視');

      final i = s.instructorCases.firstWhere((c) => c.id == 'IC-78');
      expect(i.overdue, isTrue);
      expect(i.state, CaseState.pending,
          reason: '不自動通過 —— 逾時放行等於管理員一忙即開後門');
    });

    test('未逾期者不誤標', () {
      final s = AppState();
      expect(s.appeals.firstWhere((c) => c.id == 'AP-311').overdue, isFalse);
      expect(
          s.instructorCases.firstWhere((c) => c.id == 'IC-77').overdue, isFalse);
    });

    test('已等待時數為 Event 攜帶資訊，隨時間累加', () {
      final s = AppState();
      final r = s.reports.firstWhere((c) => c.id == 'R-2041');
      expect(r.waited, greaterThanOrEqualTo(199));
    });
  });
}
