import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// 全部課表範本的內容快照。用來驗「訓練前／訓練中調整不寫回範本」。
List<List<List<(double, int)>>> allPlans(AppState s) => [
      for (final p in s.platformPlans)
        [
          for (final e in p.exercises)
            [for (final x in e.planned) (x.targetWeight, x.targetReps)]
        ]
    ];

/// 走完一輪：提出 → 確認需求 → 產出建議。
Future<void> _upToProposal(AppState s, AiSource src, String intent) async {
  s.aiRequest(src, '今天狀況不太好');
  await s.aiConfirmDemand(src, intent);
  s.aiProduceSuggestion(src);
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('建議依當前課表產生，不是固定文字', () {
    test('提到的是這份課表裡的動作', () async {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty);
      s.startWorkout(plan);
      await _upToProposal(s, AiSource.beforeTraining, '整體降強度');

      final sug = s.aiSuggestion[AiSource.beforeTraining]!;
      final names = sug.changes.map((c) => c.exerciseName).toSet();
      expect(names, plan.exercises.map((e) => e.exercise.name).toSet());
    });

    test('換一份課表，建議跟著換', () async {
      final a = AppState()..startWorkout(
          AppState().platformPlans.firstWhere((p) => p.id == 'p_push'));
      final b = AppState()..startWorkout(
          AppState().platformPlans.firstWhere((p) => p.id == 'p_leg'));
      await _upToProposal(a, AiSource.beforeTraining, '整體降強度');
      await _upToProposal(b, AiSource.beforeTraining, '整體降強度');

      final na = a.aiSuggestion[AiSource.beforeTraining]!.changes
          .map((c) => c.exerciseName).toSet();
      final nb = b.aiSuggestion[AiSource.beforeTraining]!.changes
          .map((c) => c.exerciseName).toSet();
      expect(na, isNot(nb));
    });

    test('降強度：重量下修、次數上調', () async {
      final ex = PlanExercise(
        exercise: const Exercise(
            id: 'x', name: '測試動作', dim: null, relativeIntensity: 1.0,
            equipment: '槓鈴'),
        planned: const [PlannedSet(60, 8), PlannedSet(60, 8)],
      );
      final sug = buildSuggestion([ex], AdjustIntent.easier);
      final after = sug.changes.single.after;
      expect(after.first.targetWeight, 55, reason: '60 × 0.9 ＝ 54 → 取 2.5 級距為 55');
      expect(after.first.targetReps, 10);
    });

    test('減組：砍最後一組，但至少留一組', () async {
      PlanExercise mk(int n) => PlanExercise(
            exercise: const Exercise(
                id: 'x', name: 'x', dim: null, relativeIntensity: 1.0,
                equipment: 'x'),
            planned: List.filled(n, const PlannedSet(50, 10)),
          );
      expect(buildSuggestion([mk(3)], AdjustIntent.trim)
          .changes.single.after.length, 2);
      expect(buildSuggestion([mk(1)], AdjustIntent.trim)
          .changes.single.after.length, 1, reason: '砍到 0 組等於刪掉動作');
    });

    test('徒手動作不會被加上重量', () async {
      final ex = PlanExercise(
        exercise: const Exercise(
            id: 'p', name: '棒式', dim: null, relativeIntensity: 1.0,
            isBodyweight: true, equipment: '徒手'),
        planned: const [PlannedSet(0, 60)],
      );
      for (final i in AdjustIntent.values) {
        final after = buildSuggestion([ex], i).changes.single.after;
        expect(after.first.targetWeight, 0, reason: '$i');
      }
    });
  });

  group('接受之後真的改課表', () {
    test('訓練前調整改的是快照，來源課表不動', () async {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.id == 'p_push');
      final sourceBefore = [
        for (final e in plan.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      final allBefore = allPlans(s);
      s.startWorkout(plan);
      final snapBefore = [
        for (final e in s.session!.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];

      await _upToProposal(s, AiSource.beforeTraining, '整體降強度');
      s.aiAccept(AiSource.beforeTraining);

      final snapAfter = [
        for (final e in s.session!.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      expect(snapAfter, isNot(snapBefore), reason: '快照要真的變了');

      final sourceAfter = [
        for (final e in plan.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      expect(sourceAfter, sourceBefore, reason: '來源課表不受影響');
      expect(allPlans(s), allBefore, reason: '任何一份課表範本都不該被寫入');
    });

    test('拒絕之後課表不動', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      final before = [
        for (final e in s.session!.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      await _upToProposal(s, AiSource.beforeTraining, '整體降強度');
      s.aiReject(AiSource.beforeTraining);
      final after = [
        for (final e in s.session!.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      expect(after, before);
    });

    test('選同一份課表兩次不會把調整洗掉', () async {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.id == 'p_push');
      s.startWorkout(plan);
      await _upToProposal(s, AiSource.beforeTraining, '整體降強度');
      s.aiAccept(AiSource.beforeTraining);
      final adjusted = s.session!.exercises.first.planned.first.targetWeight;

      s.startWorkout(plan); // 使用者回到詳情頁按「開始訓練」
      expect(s.session!.exercises.first.planned.first.targetWeight, adjusted,
          reason: '快照於選擇課表時產生，重複選同一份不重建');
    });

    test('訓練中調整只動尚未完成的剩餘動作', () async {
      final s = AppState();
      final plan = s.platformPlans
          .firstWhere((p) => p.exercises.length > 1 && p.id == 'p_push');
      s.startWorkout(plan);
      // 做完第一個動作的第一組。
      s.session!.records[0][0].weight = 62.5;
      s.completeCurrentSet();

      await _upToProposal(s, AiSource.duringTraining, '整體降強度');
      final sug = s.aiSuggestion[AiSource.duringTraining]!;
      expect(sug.changes.every((c) => c.exerciseIndex >= s.session!.exerciseIndex),
          isTrue, reason: '已完成的動作不在建議範圍');

      s.aiAccept(AiSource.duringTraining);
      expect(s.session!.records[0][0].weight, 62.5,
          reason: '已完成的組是實績，不可被竄改');
      expect(s.session!.records[0][0].state, SetState.done);
    });

    test('組數變少時進度百分比隨之重算，允許下降', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      final plannedBefore = s.session!.plannedSets;
      await _upToProposal(s, AiSource.beforeTraining, '減少組數');
      s.aiAccept(AiSource.beforeTraining);
      expect(s.session!.plannedSets, lessThan(plannedBefore));
    });
  });

  group('自動優化改的是來源課表範本', () {
    test('接受後範本改變，且常駐標記清除', () async {
      final s = AppState();
      final plan = s.aiOptimizePlan!;
      final before = [
        for (final e in plan.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      await _upToProposal(s, AiSource.autoOptimize, '整體降強度');
      s.aiAccept(AiSource.autoOptimize);

      final now = s.platformPlans.firstWhere((p) => p.id == plan.id);
      final after = [
        for (final e in now.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      expect(after, isNot(before));
      expect(now.hasOptimizationSuggestion, isFalse);
      expect(s.aiOptimizePlan, isNull, reason: '沒有別的課表還掛著標記');
    });

    test('拒絕後範本不變，但標記一樣清除', () async {
      final s = AppState();
      final plan = s.aiOptimizePlan!;
      final before = [
        for (final e in plan.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ];
      await _upToProposal(s, AiSource.autoOptimize, '整體降強度');
      s.aiReject(AiSource.autoOptimize);

      final now = s.platformPlans.firstWhere((p) => p.id == plan.id);
      expect([
        for (final e in now.exercises)
          [for (final p in e.planned) (p.targetWeight, p.targetReps)]
      ], before);
      expect(now.hasOptimizationSuggestion, isFalse);
    });

    test('自動優化不扣點', () async {
      final s = AppState();
      final credits = s.aiTotal;
      await _upToProposal(s, AiSource.autoOptimize, '整體降強度');
      expect(s.aiTotal, credits);
    });
  });

  group('扣點與退點的時點不變', () {
    test('產出建議時才扣點', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      final before = s.aiTotal;
      s.aiRequest(AiSource.beforeTraining, '想調整');
      expect(s.aiTotal, before, reason: '提出要求還沒扣');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      expect(s.aiTotal, before, reason: '分析中也還沒扣');
      s.aiProduceSuggestion(AiSource.beforeTraining);
      expect(s.aiTotal, before - 1);
    });

    test('沒東西可調時不扣點', () async {
      final s = AppState();
      final blank = s.platformPlans.firstWhere((p) => p.exercises.isEmpty);
      s.startWorkout(blank);
      final before = s.aiTotal;
      await _upToProposal(s, AiSource.beforeTraining, '整體降強度');
      expect(s.aiTotal, before);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.idle);
    });
  });

  _quotaSplit();
}

/// 訓練前調整的名額分流

/// 訓練前調整的名額分流（〈訓練紀錄流程〉）。
void _quotaSplit() {
  /// 讓名額空出一個位子。
  AppState withSlot() {
    final s = AppState();
    s.deletePlan(s.customPlans.firstWhere((p) => p.isMine));
    return s;
  }

  group('名額不是 Precondition，是分流條件', () {
    test('名額足夠：須先確認意願才能提出調整', () async {
      final s = withSlot();
      expect(s.customPlanSlotFree, isTrue);
      expect(s.aiPlanQuotaBlockedReason(), isNotNull);

      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(AiSource.planAdjust, '想調整');
      expect(s.aiStage[AiSource.planAdjust], AiStage.idle,
          reason: '未確認前提不出調整要求');

      s.setAiQuotaConsent(true);
      expect(s.aiPlanQuotaBlockedReason(), isNull);
      s.aiRequest(AiSource.planAdjust, '想調整');
      expect(s.aiStage[AiSource.planAdjust], AiStage.clarifying);
    });

    test('名額已滿：不擋，直接可以提出', () async {
      final s = AppState();
      expect(s.customPlanSlotFree, isFalse);
      expect(s.aiPlanQuotaBlockedReason(), isNull,
          reason: '擋下等於因為額度問題讓人練一份器材不合的課表');

      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(AiSource.planAdjust, '想調整');
      expect(s.aiStage[AiSource.planAdjust], AiStage.clarifying);
    });

    test('確認為意願確認，非當下即扣除名額', () async {
      final s = withSlot();
      // 使用者已在 AI 調整頁，快照早已產生 —— 這才是確認發生的時點。
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      final before = s.myPlanCount;
      s.setAiQuotaConsent(true);
      expect(s.myPlanCount, before, reason: '確認當下不扣名額');

      s.aiRequest(AiSource.planAdjust, '想調整');
      await s.aiConfirmDemand(AiSource.planAdjust, '整體降強度');
      s.aiProduceSuggestion(AiSource.planAdjust);
      expect(s.myPlanCount, before, reason: '產出建議時也還沒扣');

      s.aiAccept(AiSource.planAdjust);
      expect(s.myPlanCount, before + 1, reason: '成功套用後才佔用名額');
    });

    test('拒絕不佔名額 —— 失敗時名額根本沒動，不需補救', () async {
      final s = withSlot();
      final before = s.myPlanCount;
      s.setAiQuotaConsent(true);
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(AiSource.planAdjust, '想調整');
      await s.aiConfirmDemand(AiSource.planAdjust, '整體降強度');
      s.aiProduceSuggestion(AiSource.planAdjust);
      s.aiReject(AiSource.planAdjust);
      expect(s.myPlanCount, before);
    });

    test('名額已滿：只改快照，不佔名額', () async {
      final s = AppState();
      final before = s.myPlanCount;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      final snapBefore = s.session!.exercises.first.planned.first.targetWeight;

      s.aiRequest(AiSource.planAdjust, '想調整');
      await s.aiConfirmDemand(AiSource.planAdjust, '整體降強度');
      s.aiProduceSuggestion(AiSource.planAdjust);
      s.aiAccept(AiSource.planAdjust);

      expect(s.myPlanCount, before, reason: '不佔名額');
      expect(s.session!.exercises.first.planned.first.targetWeight,
          isNot(snapBefore), reason: '快照仍要被改到');
    });

    test('落地的自訂訓練為已儲存狀態，內容來自快照', () async {
      final s = withSlot();
      s.setAiQuotaConsent(true);
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(AiSource.planAdjust, '想調整');
      await s.aiConfirmDemand(AiSource.planAdjust, '整體降強度');
      s.aiProduceSuggestion(AiSource.planAdjust);
      s.aiAccept(AiSource.planAdjust);

      final landed = s.customPlans.last;
      expect(landed.state, CustomPlanState.saved);
      expect(landed.exerciseCount, s.session!.exercises.length);
      expect(landed.name, contains('AI 調整'));
    });

    test('訓練中調整不走名額分流 —— 它本來就只改快照', () async {
      final s = withSlot();
      final before = s.myPlanCount;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(AiSource.duringTraining, '想調整');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體降強度');
      s.aiProduceSuggestion(AiSource.duringTraining);
      s.aiAccept(AiSource.duringTraining);
      expect(s.myPlanCount, before);
    });
  });
}
