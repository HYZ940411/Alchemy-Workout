// 教官申請的最後一步是管理員的，不是申請人的。
//
// 先前「待人工審核 → 已通過」由申請人自己按同一顆按鈕走完 ——
// 等於自己核准自己，而模型明訂該步驟的 Actor 是管理員，
// 且〈教官申請流程〉的失敗路徑（教官資格已駁回，攜帶駁回階段）
// 整條走不到。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 作答完、停在待人工審核的狀態。
AppState submitted() {
  final s = AppState()..instructorStage = InstructorStage.screenPassed;
  expect(s.submitExam(18), isTrue, reason: '前提：選擇題要真的過');
  expect(s.instructorStage, InstructorStage.pendingReview);
  return s;
}

InstructorCase myCase(AppState s) =>
    s.instructorCases.firstWhere((c) => c.applicant == s.displayName);

void main() {
  test('作答後真的產生一件待審案件 —— 不是等一個不存在的人', () {
    final s = submitted();
    final c = myCase(s);
    expect(c.state, CaseState.pending);
    expect(c.answers, isNotEmpty, reason: '要審的就是簡答題，沒有作答內容就無從審起');
  });

  test('申請人自己按不到「已通過」', () {
    final s = submitted();
    s.advanceInstructorApplication();
    expect(s.instructorStage, InstructorStage.pendingReview,
        reason: '最後一步的 Actor 是管理員');
    expect(s.isInstructor, isFalse);
  });

  test('管理員通過 → 成為教官', () {
    final s = submitted();
    s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(myCase(s), true));
    expect(s.instructorStage, InstructorStage.approved);
    expect(s.isInstructor, isTrue);
    expect(s.instructorRejectStage, isNull);
  });

  test('管理員駁回 → 記下駁回階段', () {
    final s = submitted();
    s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(myCase(s), false));
    expect(s.instructorStage, InstructorStage.rejected);
    expect(s.isInstructor, isFalse);
    expect(s.instructorRejectStage, '管理員審核',
        reason: '申訴無時效上限，管理員要看得出當初卡在哪一關');
  });

  test('選擇題就沒過的，當場駁回，不送人工審核', () {
    final s = AppState()..instructorStage = InstructorStage.screenPassed;
    final before = s.instructorCases.length;
    expect(s.submitExam(10), isTrue, reason: '「已作答」這件事還是發生了');
    expect(s.examMcPassed, isFalse);
    expect(s.instructorStage, InstructorStage.rejected);
    expect(s.instructorRejectStage, '測驗');
    expect(s.instructorCases.length, before,
        reason: '選擇題由系統即時判定，這一關沒過不必佔用管理員的佇列');
  });

  test('同一件不會被判兩次', () {
    final s = submitted();
    final c = myCase(s);
    s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(c, true));
    s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(c, false));
    expect(c.state, CaseState.upheld);
    expect(s.isInstructor, isTrue, reason: '已終止的案件不該還能翻案');
  });

  group('駁回之後走得出去', () {
    test('滿 14 天可再次申請，重跑初審', () {
      final s = submitted();
      s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(myCase(s), false));
      expect(s.instructorStage, InstructorStage.rejected);

      expect(s.reapplyInstructor(), isFalse, reason: '14 天內不得再申請');
      s.advanceDemoClock(const Duration(days: 15));
      expect(s.reapplyInstructor(), isTrue);
      expect(s.instructorStage, InstructorStage.screening,
          reason: '重試產生新的一筆申請，並重跑 AI 品質評分');
      expect(s.instructorRejectStage, isNull);
    });

    test('沒被駁回的人不會誤觸重新申請', () {
      final s = submitted();
      expect(s.reapplyInstructor(), isFalse);
      expect(s.instructorStage, InstructorStage.pendingReview);
    });
  });

  group('換個人來審', () {
    test('審核組的另一位不是我', () {
      final s = AppState();
      expect(s.otherReviewer.id, isNot(s.admin.id));
      expect(s.otherReviewer.can(AdminScope.contentReview), isTrue);
      expect(s.otherReviewer.status, AdminStatus.active,
          reason: '停用的管理員不能審案');
    });

    test('runAsAdmin 執行完換得回來', () {
      final s = AppState();
      final me = s.admin;
      s.runAsAdmin(s.otherReviewer, () {
        expect(s.admin.id, isNot(me.id));
      });
      expect(s.admin.id, me.id);
    });

    test('丟例外也換得回來', () {
      final s = AppState();
      final me = s.admin;
      expect(
          () => s.runAsAdmin(s.otherReviewer, () => throw StateError('x')),
          throwsStateError);
      expect(s.admin.id, me.id, reason: '中途出事就卡在別人的身分底下是更糟的事');
    });

    test('處理人欄位留的是真的審那件案子的人', () {
      final s = AppState();
      final c = s.reports.firstWhere((x) => x.state == CaseState.pending);
      final who = s.otherReviewer;
      s.runAsAdmin(who, () => s.reviewReport(c));
      expect(c.handlerName, who.name);
      expect(c.handlerName, isNot(s.admin.name));
    });

    test('權限一條都不放寬', () {
      final s = AppState();
      // 審核組只有內容審核權限，碰不了商品。
      final reviewer = s.admins.firstWhere((a) =>
          a.can(AdminScope.contentReview) && !a.can(AdminScope.productManage));
      final o = s.adminOrders.firstWhere((x) => x.state == '已付款');
      s.runAsAdmin(reviewer, () => s.shipOrder(o));
      expect(o.state, '已付款', reason: '沒有商品管理權限就出不了貨');
    });
  });
}
