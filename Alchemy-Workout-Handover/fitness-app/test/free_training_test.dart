import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan get blankPlan => kPlans.firstWhere((p) => p.source == PlanSource.blank);

void main() {
  group('空白課表（自由訓練）', () {
    test('是合法的初始狀態：總計畫組數 0、進度條不成立', () {
      final s = AppState();
      s.startWorkout(blankPlan);
      expect(s.session!.isBlank, isTrue);
      expect(s.session!.plannedSets, 0);
      expect(s.session!.progress, 0);
      expect(s.session!.exercises, isEmpty);
    });

    test('加入第一個動作後總計畫組數大於 0，進度條自該時點起成立', () {
      final s = AppState();
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('squat'), const [
        PlannedSet(80, 5),
        PlannedSet(80, 5),
        PlannedSet(80, 5),
      ]);
      expect(s.session!.plannedSets, 3);
      expect(s.session!.progress, 0);

      expect(s.completeCurrentSet(), isTrue);
      expect(s.session!.progress, closeTo(1 / 3, 1e-9));
    });

    test('總計畫組數只增不減 —— 已加入的動作與組不可移除', () {
      final s = AppState();
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('squat'), const [PlannedSet(80, 5)]);
      s.addExerciseToSession(ex('bench'), const [PlannedSet(60, 8)]);
      expect(s.session!.plannedSets, 2);

      // 完成與取消都不改變分母 —— 只有加入動作會讓它變大。
      s.completeCurrentSet();
      expect(s.session!.plannedSets, 2);
      s.cancelCurrentSet();
      expect(s.session!.plannedSets, 2);
    });

    test('加入動作只改本次訓練快照，不改來源課表', () {
      final s = AppState();
      final before = blankPlan.exercises.length;
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('squat'), const [PlannedSet(80, 5)]);
      expect(s.session!.exercises.length, 1);
      expect(blankPlan.exercises.length, before,
          reason: '本 Command 只改本次訓練課表快照，不改來源課表');
    });

    test('一般課表也能中途加練計畫外的動作 —— 兩種入口共用同一路徑', () {
      final s = AppState();
      final plan = kPlans.firstWhere((p) => p.id == 'p_push');
      final planned = plan.totalSets;
      s.startWorkout(plan);
      s.addExerciseToSession(ex('lateral'), const [PlannedSet(10, 15)]);
      expect(s.session!.plannedSets, planned + 1);
      expect(plan.totalSets, planned, reason: '來源課表不得被改動');
    });

    test('加入的組無快照帶入值 —— 目標由加入時指定', () {
      final s = AppState();
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('bench'), const [PlannedSet(72.5, 6)]);
      final rec = s.currentRecord!;
      expect(rec.weight, 72.5);
      expect(rec.reps, 6);
    });
  });

  group('空白課表的結算', () {
    test('不觸發「個人排行榜分數已增加」', () {
      final r = computeSettlement(
        kind: EndKind.completed,
        source: PlanSource.blank,
        doneSets: 6,
        plannedSets: 6,
        streakDays: 3,
        expAlreadyGrantedToday: false,
      );
      expect(r.leaderboardScore, isNull,
          reason: '無總計畫組數、完成度無從計算，且連自己都未編寫');
      // 金幣與經驗值照給。
      expect(r.coins, greaterThan(0));
      expect(r.exp, greaterThan(0));
    });

    test('逾時中斷一律套用 50% —— 不適用完成度比較', () {
      expect(
        completionFactor(EndKind.timedOut, doneSets: 0, plannedSets: 0),
        0.5,
      );
      expect(
        completionFactor(EndKind.timedOut, doneSets: 9, plannedSets: 0),
        0.5,
        reason: '空白課表無總計畫組數，不適用「做滿即算完成」的比較',
      );
    });

    test('主動結束一律判為已完成，實際走 completed 的獎勵', () {
      final s = AppState();
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('squat'), const [PlannedSet(80, 5)]);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      final r = s.finishWorkout(EndKind.completed);
      expect(r.rewards.completion, 1.0);
      expect(r.rewards.leaderboardScore, isNull);
    });
  });
}
