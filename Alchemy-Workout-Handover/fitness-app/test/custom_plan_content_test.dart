import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/train/custom_plan_edit_screen.dart';
import 'package:fitness_app/screens/train/custom_plans_screen.dart';
import 'package:fitness_app/widgets/common.dart';

import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

CustomPlan planOf(AppState s, String name) =>
    s.customPlans.firstWhere((p) => p.name == name);

List<PlanExercise> _content() => [
      PlanExercise(
        exercise: ex('squat'),
        planned: const [PlannedSet(80, 8), PlannedSet(85, 6), PlannedSet(90, 4)],
      ),
      PlanExercise(
        exercise: ex('plank'),
        planned: const [PlannedSet(0, 60)],
      ),
    ];

void main() {
  group('自訂訓練存的是課表本身', () {
    test('存進去的內容原封不動取得回來', () {
      final s = AppState();
      s.addPlan('新課表', _content());
      final p = planOf(s, '新課表');
      expect(p.exercises.length, 2);
      expect(p.exercises.first.planned.map((x) => x.targetWeight),
          [80, 85, 90], reason: '每一組可各自設定不同的目標重量');
      expect(p.exercises.first.planned.map((x) => x.targetReps), [8, 6, 4]);
      expect(p.totalSets, 4);
    });

    test('動作數量與內容摘要皆為推導值，不另存一份', () {
      final s = AppState();
      s.addPlan('新課表', _content());
      final p = planOf(s, '新課表');
      expect(p.exerciseCount, p.exercises.length);
      p.exercises = [..._content(), ..._content()];
      expect(p.exerciseCount, 4, reason: '改內容，數量跟著動');
      expect(p.contents.length, 4);
    });

    test('假資料的課表也都有真的內容', () {
      final s = AppState();
      for (final p in s.customPlans) {
        expect(p.exercises, isNotEmpty, reason: '${p.name} 沒有課表內容');
        expect(p.totalSets, greaterThan(0));
      }
    });
  });

  group('修改既有課表', () {
    test('改名不動內容', () {
      final s = AppState();
      final p = planOf(s, '我的核心日');
      final before = [...p.exercises];
      s.editPlan(p, name: '我的核心日 v2', exercises: before);
      expect(p.name, '我的核心日 v2');
      expect(p.exercises.length, before.length);
    });

    test('換內容後，練的就是新內容', () {
      final s = AppState();
      final p = planOf(s, '我的核心日');
      s.editPlan(p, name: p.name, exercises: _content());
      expect(p.toWorkoutPlan().exercises.first.exercise.id, 'squat');
      expect(p.toWorkoutPlan().totalSets, 4);
    });
  });

  group('自訂訓練可以拿來訓練', () {
    test('轉為課表後可開始訓練，內容一致', () {
      final s = AppState();
      final p = planOf(s, '週末全身循環');
      final w = p.toWorkoutPlan();
      s.startWorkout(w);
      expect(s.session, isNotNull);
      expect(s.session!.exercises.length, p.exercises.length);
      expect(s.session!.plan.totalSets, p.totalSets);
    });

    test('已公開者算「已公開的自訂訓練」，未公開者算「未公開」', () {
      final s = AppState();
      expect(planOf(s, '週末全身循環').state, CustomPlanState.public);
      expect(planOf(s, '週末全身循環').toWorkoutPlan().source,
          PlanSource.publishedCustom);
      expect(planOf(s, '我的核心日').toWorkoutPlan().source,
          PlanSource.privateCustom);
    });

    test('課表選擇頁列得出可選用的自訂訓練', () {
      final s = AppState();
      final names = s.selectableCustomPlans.map((p) => p.name).toSet();
      expect(names, contains('我的核心日'), reason: '自己已發布的');
      expect(names, contains('週末全身循環'), reason: '全平台已公開的');
      expect(names, isNot(contains('新的推日草案')),
          reason: '已儲存為未啟用狀態，要能練得先發布');
    });

    test('他人的課表須開了對關注者可見且我確實關注了作者', () {
      final s = AppState();
      final other = CustomPlan(
        id: 'x1',
        name: '關注者限定',
        exercises: _content(),
        myUses: 0,
        state: CustomPlanState.published,
        author: '深蹲王',
        isMine: false,
        visibleToFollowers: true,
      );
      s.customPlans.add(other);
      expect(s.isFollowing('深蹲王'), isTrue);
      expect(s.selectableCustomPlans, contains(other));

      other.visibleToFollowers = false;
      expect(s.selectableCustomPlans, isNot(contains(other)),
          reason: '關掉開關就不該再出現');

      other.visibleToFollowers = true;
      s.toggleFollow('深蹲王'); // 取消關注
      expect(s.isFollowing('深蹲王'), isFalse);
      expect(s.selectableCustomPlans, isNot(contains(other)),
          reason: '不是關注者就看不到');
    });

    test('被名額鎖定的課表不可選用', () {
      final s = AppState();
      final locked = s.customPlans
          .where((p) => p.isMine && s.planQuotaLocked(p))
          .toList();
      for (final p in locked) {
        expect(s.selectableCustomPlans, isNot(contains(p)));
      }
    });
  });

  group('另存為自訂訓練帶得走內容', () {
    test('訓練歷史另存後，每一組的實績成為新課表的目標', () {
      final s = AppState();
      // 先騰出一個名額。
      s.deletePlan(s.customPlans.firstWhere((p) => p.isMine));
      final h = s.history.first;
      expect(s.saveHistoryAsPlan(h), isTrue);
      final p = s.customPlans.firstWhere((p) => p.name == h.planName);
      expect(p.exercises.length, h.exercises.length);
      expect(p.totalSets, h.totalSets);
      expect(p.exercises.first.planned.first.targetWeight,
          h.exercises.first.sets.first.$1);
      expect(p.exercises.first.planned.first.targetReps,
          h.exercises.first.sets.first.$2);
    });
  });

  group('編輯器讀得回原內容（畫面）', () {
    testWidgets('打開既有課表，動作與組數都在，不是空的', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      await t.tap(find.text('自訂訓練'));
      await t.pumpAndSettle();

      final list = find
          .descendant(
              of: find.byType(CustomPlansScreen),
              matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(find.text('我的核心日'), 300, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '修改').first);
      await t.pumpAndSettle();

      expect(find.byType(CustomPlanEditScreen), findsOneWidget);
      // 原內容是棒式與捲腹 —— 讀不回來的話這裡會是空的，
      // 而使用者一存就把整份課表洗掉。
      expect(find.textContaining('棒式'), findsWidgets);
      await t.drag(find.byType(CustomPlanEditScreen), const Offset(0, -400));
      await t.pumpAndSettle();
      expect(find.textContaining('捲腹'), findsWidgets);
      expect(t.widget<AppButton>(find.widgetWithText(AppButton, '儲存')).onPressed,
          isNotNull);
    });
  });
}
