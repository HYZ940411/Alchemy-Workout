import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/carry_forward.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/state/app_state.dart';

List<ActualSet> _sets(List<(double, int)> l) =>
    [for (final t in l) (weight: t.$1, reps: t.$2)];

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('帶入採組序逐一對應', () {
    test('組數相同：第 N 組對應上次第 N 組', () {
      final last = _sets([(60, 8), (62.5, 7), (57.5, 8)]);
      expect(carryForward(last, 3), [60, 62.5, 57.5]);
    });

    test('本次組數多於上次：超出的組沿用上次最後一組', () {
      final last = _sets([(60, 8), (62.5, 7)]);
      expect(carryForward(last, 4), [60, 62.5, 62.5, 62.5]);
    });

    test('本次組數少於上次：取上次的前 N 組', () {
      final last = _sets([(60, 8), (62.5, 7), (65, 5), (57.5, 8)]);
      expect(carryForward(last, 2), [60, 62.5]);
    });

    test('不是「全部帶入上次最大重量」—— 第 1 組不會從當日最重開始', () {
      final last = _sets([(60, 8), (80, 3), (60, 8)]);
      expect(carryForward(last, 3).first, 60, reason: '無暖身即從最重開始有受傷風險');
    });

    test('不是「全部帶入上次最後一組」—— 強度不會逐次下滑', () {
      final last = _sets([(60, 8), (60, 8), (45, 12)]);
      expect(carryForward(last, 3), [60, 60, 45]);
    });

    test('未曾記錄（來源為空）回傳空清單，交給推算', () {
      expect(carryForward(const [], 3), isEmpty);
    });
  });

  group('未曾記錄者由 Epley ＋ DOTS 推算', () {
    final bench = ex('bench');

    test('推算值與 measuredScore 互為反解', () {
      const pts = 400;
      final w = suggestedWeight(
        exercise: bench,
        dimPoints: pts,
        bodyweightKg: 72,
        isMale: true,
        targetReps: 8,
      );
      final back = measuredScore(
        weightKg: w,
        reps: 8,
        relativeIntensity: bench.relativeIntensity,
        bodyweightKg: 72,
        isMale: true,
      );
      // 2.5 kg 級距取整會有誤差，但不該偏離一個節點。
      expect((back - pts).abs(), lessThan(30));
    });

    test('同樣的點數，體重愈重推算出的重量愈重', () {
      double at(double bw) => suggestedWeight(
            exercise: bench,
            dimPoints: 400,
            bodyweightKg: bw,
            isMale: true,
            targetReps: 8,
          );
      expect(at(90), greaterThan(at(60)));
    });

    test('次數愈多推算出的工作重量愈輕', () {
      double at(int reps) => suggestedWeight(
            exercise: bench,
            dimPoints: 400,
            bodyweightKg: 72,
            isMale: true,
            targetReps: reps,
          );
      expect(at(10), lessThan(at(3)));
    });

    test('徒手動作不推算重量', () {
      expect(
        suggestedWeight(
          exercise: ex('plank'),
          dimPoints: 400,
          bodyweightKg: 72,
          isMale: true,
          targetReps: 60,
        ),
        0,
      );
    });
  });

  group('快照的逐組帶入（端到端）', () {
    test('曾記錄過：帶入最近一次的實際重量，不是課表目標值', () {
      final s = AppState();
      // 假資料：板凳臥推最近一次為 60 / 60 / 62.5 / 60，課表目標為 60。
      final last = s.lastActualSets('bench');
      expect(last, isNotEmpty);

      final plan = s.platformPlans.firstWhere(
          (p) => p.exercises.any((e) => e.exercise.id == 'bench'));
      s.startWorkout(plan);
      final i = s.session!.exercises.indexWhere((e) => e.exercise.id == 'bench');
      final got = [for (final p in s.session!.exercises[i].planned) p.targetWeight];
      expect(got, carryForward(last, got.length));
      expect(got, contains(62.5), reason: '第 3 組的實際重量必須跟著帶進來');
    });

    test('帶入只影響快照，不改動來源課表的目標重量', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere(
          (p) => p.exercises.any((e) => e.exercise.id == 'bench'));
      final before = [
        for (final e in plan.exercises)
          [for (final p in e.planned) p.targetWeight]
      ];
      s.startWorkout(plan);
      final after = [
        for (final e in plan.exercises)
          [for (final p in e.planned) p.targetWeight]
      ];
      expect(after, before);
    });

    test('未曾記錄過該動作：不沿用來源課表的值', () {
      final s = AppState();
      // 清空歷史，使每個動作都成為「未曾記錄」。
      s.history.clear();
      final plan = s.platformPlans.firstWhere(
          (p) => p.exercises.any((e) => e.exercise.id == 'bench'));
      final planTarget = plan.exercises
          .firstWhere((e) => e.exercise.id == 'bench')
          .planned
          .first
          .targetWeight;
      s.startWorkout(plan);
      final i = s.session!.exercises.indexWhere((e) => e.exercise.id == 'bench');
      final got = s.session!.exercises[i].planned.first.targetWeight;
      expect(
        got,
        suggestedWeight(
          exercise: ex('bench'),
          dimPoints: s.points[ex('bench').dim]!,
          bodyweightKg: s.bodyweightKg,
          isMale: s.isMale,
          targetReps: plan.exercises
              .firstWhere((e) => e.exercise.id == 'bench')
              .planned
              .first
              .targetReps,
        ),
      );
      expect(got, isNot(planTarget), reason: '未曾記錄者不沿用來源課表的值');
    });
  });

  group('帶入來源的粒度為組，非整場訓練', () {
    test('提前結束的訓練中已完成的組，仍為下次的帶入來源', () {
      final s = AppState();
      s.history.clear();
      final plan = s.platformPlans.firstWhere(
          (p) => p.exercises.any((e) => e.exercise.id == 'bench'));
      s.startWorkout(plan);
      final i = s.session!.exercises.indexWhere((e) => e.exercise.id == 'bench');
      // 只做第 1 組，改成 55 kg，然後提前結束。
      s.session!.exerciseIndex = i;
      s.session!.setIndex = 0;
      s.session!.records[i][0].weight = 55;
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);

      final last = s.lastActualSets('bench');
      expect(last.length, 1, reason: '未完成的組不作為帶入來源');
      expect(last.first.weight, 55);
    });

    test('一組都沒完成的訓練不留下帶入來源', () {
      final s = AppState();
      final before = s.history.length;
      s.startWorkout(s.platformPlans.first);
      s.finishWorkout(EndKind.endedEarly);
      expect(s.history.length, before, reason: '沒有實績就沒有訓練紀錄');
    });

    test('取最近一次，不是最舊那次', () {
      final s = AppState();
      final old = HistoryEntry(
        DateTime.now().subtract(const Duration(days: 30)),
        '舊的',
        0,
        30,
        100,
        [HistoryExercise.of('bench', const [(40, 8)])],
      );
      s.history.add(old);
      expect(s.lastActualSets('bench').first.weight, isNot(40));
    });
  });
}
