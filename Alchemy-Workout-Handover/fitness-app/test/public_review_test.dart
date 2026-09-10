import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';

CustomPlan planOf(AppState s, String name) =>
    s.customPlans.firstWhere((p) => p.name == name);

/// n 個動作的最小課表，供不關心內容的測試使用。
List<PlanExercise> plannedOf(int n) => [
      for (var i = 0; i < n; i++)
        PlanExercise(
          exercise: kExercises[i % kExercises.length],
          planned: const [PlannedSet(20, 10)],
        ),
    ];

void main() {
  group('自訂訓練狀態機（使用者端）', () {
    test('已儲存 → 已發布 → 已申請公開', () {
      final s = AppState();
      final p = planOf(s, '新的推日草案');
      expect(p.state, CustomPlanState.saved);

      // 已儲存為未啟用狀態，不可選用於訓練 —— 發布才是啟用動作。
      s.publishPlan(p);
      expect(p.state, CustomPlanState.published);

      s.applyPublic(p);
      expect(p.state, CustomPlanState.pendingPublic);
      expect(p.appliedAt, isNotNull, reason: '審核時限自轉為已申請公開起算');
    });

    test('取消發布退回已儲存', () {
      final s = AppState();
      final p = planOf(s, '我的核心日');
      expect(p.state, CustomPlanState.published);
      s.unpublishPlan(p);
      expect(p.state, CustomPlanState.saved);
    });

    test('下架為軟刪除：已公開 → 已儲存，資料保留', () {
      final s = AppState();
      final p = planOf(s, '週末全身循環');
      final before = s.customPlans.length;
      s.takeDownPlan(p);
      expect(p.state, CustomPlanState.saved);
      expect(s.customPlans.length, before);
    });

    test('對關注者可見與狀態正交，但已公開時不生效', () {
      final s = AppState();
      final published = planOf(s, '我的核心日');
      s.setVisibleToFollowers(published, false);
      expect(published.visibleToFollowers, isFalse);

      final public = planOf(s, '週末全身循環');
      s.setVisibleToFollowers(public, false);
      expect(public.visibleToFollowers, isTrue,
          reason: '已公開為全平台可用，關注者本即涵蓋在內，開關不生效');

      // 已儲存（未啟用）也不可設為真。
      final saved = planOf(s, '新的推日草案');
      s.setVisibleToFollowers(saved, true);
      expect(saved.visibleToFollowers, isFalse);
    });

    test('已公開者的修改觸發重新審核，其餘狀態為自由編輯', () {
      final s = AppState();
      final public = planOf(s, '週末全身循環');
      s.editPlan(public, name: '週末全身循環 v2', exercises: plannedOf(6));
      expect(public.state, CustomPlanState.pendingPublic,
          reason: '堵「送審放正常課表 → 過審後改為危險內容」的規避漏洞');

      final saved = planOf(s, '新的推日草案');
      s.editPlan(saved, name: '推日 v2', exercises: plannedOf(4));
      expect(saved.state, CustomPlanState.saved);
    });

    test('刪除為終止狀態，且是釋放名額的唯一手段', () {
      final s = AppState();
      final before = s.myPlanCount;
      s.deletePlan(planOf(s, '新的推日草案'));
      expect(s.myPlanCount, before - 1);
      expect(s.customPlans.any((p) => p.name == '新的推日草案'), isFalse);
    });
  });

  group('申請公開 → 管理員審核 → 上架（端到端）', () {
    test('通過：已申請公開 → 已公開', () {
      final s = AppState();
      final p = planOf(s, '新的推日草案');
      s.publishPlan(p);
      s.applyPublic(p);

      // 使用者送出後，該課表立刻出現在管理員的待審佇列 —— 兩端讀同一份資料。
      expect(s.pendingPublicPlans, contains(p));

      s.approvePublicPlan(p);
      expect(p.state, CustomPlanState.public);
      expect(s.pendingPublicPlans, isNot(contains(p)));
    });

    test('駁回：退回已發布，自己仍可用，並帶駁回理由', () {
      final s = AppState();
      final p = planOf(s, '新的推日草案');
      s.publishPlan(p);
      s.applyPublic(p);

      s.rejectPublicPlan(p, '動作組合風險過高');
      expect(p.state, CustomPlanState.rejected);
      expect(p.rejectReason, '動作組合風險過高');

      // 可修改後重新申請公開，不限次數。
      s.resumePublished(p);
      expect(p.state, CustomPlanState.published);
      expect(p.rejectReason, isNull);
      s.applyPublic(p);
      expect(p.state, CustomPlanState.pendingPublic);
    });

    test('佇列同時涵蓋本人與他人的課表', () {
      final s = AppState();
      final authors = s.pendingPublicPlans.map((p) => p.author).toSet();
      expect(authors, containsAll(['你', 'CoreMax', '深蹲王']));
    });
  });

  group('公開訓練審核的 14 天時限', () {
    test('逾期只標示，不改變案件狀態', () {
      final s = AppState();
      final overdue =
          s.pendingPublicPlans.firstWhere((p) => p.author == '深蹲王');
      expect(overdue.reviewOverdue, isTrue);
      expect(overdue.reviewDaysLeft, 0);
      // 不自動通過、不自動駁回、不自動退回。
      expect(overdue.state, CustomPlanState.pendingPublic);
      expect(s.pendingPublicPlans, contains(overdue));
    });

    test('未逾期者顯示剩餘天數', () {
      final s = AppState();
      final fresh =
          s.pendingPublicPlans.firstWhere((p) => p.author == 'CoreMax');
      expect(fresh.reviewOverdue, isFalse);
      expect(fresh.reviewDaysLeft, kPublicPlanReviewDays - 2);
    });

    test('剛送出者有完整的審核天數', () {
      final s = AppState();
      final p = planOf(s, '新的推日草案');
      s.publishPlan(p);
      s.applyPublic(p);
      expect(p.reviewDaysLeft, kPublicPlanReviewDays);
      expect(p.reviewOverdue, isFalse);
    });
  });
}
