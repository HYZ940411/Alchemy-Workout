import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/plan_duration.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/platform_plans.g.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan plan(List<PlanExercise> ex) => WorkoutPlan(
      id: 'p',
      name: 'p',
      source: PlanSource.official,
      exercises: ex,
    );

void main() {
  group('預估訓練時長', () {
    test('次數型：組數 × (次數 × 每下秒數 + 組間休息)', () {
      final d = estimatePlanDuration(
        plan([
          PlanExercise(
            exercise: ex('squat'),
            planned: List.generate(5, (_) => const PlannedSet(0, 12)),
          ),
        ]),
        restSecondsOf: (_) => 60,
      );
      // 5 × (12 × 5 + 60) = 600 秒
      expect(d, const Duration(seconds: 600));
    });

    test('時間型：秒數直接算，不乘每下秒數', () {
      final d = estimatePlanDuration(
        plan([
          PlanExercise(
            exercise: ex('plank'),
            planned: List.generate(6, (_) => const PlannedSet(0, 30)),
            unit: PlanUnit.seconds,
          ),
        ]),
        restSecondsOf: (_) => 30,
      );
      // 6 × (30 + 30) = 360 秒
      expect(d, const Duration(seconds: 360));
    });

    // 同一個數字 12，單位不同就是兩個完全不同的時長。
    // 單位若在轉成 WorkoutPlan 時被丟掉，這裡會得到一樣的答案。
    test('同樣的數字，單位不同時長不同', () {
      List<PlannedSet> sets() =>
          List.generate(4, (_) => const PlannedSet(0, 30));
      final reps = estimatePlanDuration(
        plan([PlanExercise(exercise: ex('squat'), planned: sets())]),
        restSecondsOf: (_) => 60,
      );
      final secs = estimatePlanDuration(
        plan([
          PlanExercise(
              exercise: ex('squat'),
              planned: sets(),
              unit: PlanUnit.seconds),
        ]),
        restSecondsOf: (_) => 60,
      );
      expect(reps, isNot(secs));
      expect(reps, const Duration(seconds: 4 * (30 * 5 + 60)));
      expect(secs, const Duration(seconds: 4 * (30 + 60)));
    });

    test('空白課表估不出來，回傳空值 —— 不是 0 分鐘', () {
      expect(estimatePlanDuration(plan(const []), restSecondsOf: (_) => 60),
          isNull);
    });

    test('多個動作相加', () {
      final d = estimatePlanDuration(
        plan([
          PlanExercise(
              exercise: ex('squat'),
              planned: List.generate(3, (_) => const PlannedSet(0, 10))),
          PlanExercise(
              exercise: ex('bench'),
              planned: List.generate(2, (_) => const PlannedSet(0, 8))),
        ]),
        restSecondsOf: (_) => 90,
      );
      expect(d,
          const Duration(seconds: 3 * (10 * 5 + 90) + 2 * (8 * 5 + 90)));
    });

    test('休息秒數由呼叫端供給 —— 不自己算優先序', () {
      var asked = 0;
      estimatePlanDuration(
        plan([
          PlanExercise(
              exercise: ex('squat'),
              planned: List.generate(3, (_) => const PlannedSet(0, 10))),
        ]),
        restSecondsOf: (_) {
          asked++;
          return 45;
        },
      );
      expect(asked, 1, reason: '休息是動作層級，不逐組問');
    });
  });

  group('顯示文字', () {
    test('取到 5 分鐘的倍數', () {
      expect(planDurationLabel(const Duration(minutes: 37)), '約 35 分鐘');
      expect(planDurationLabel(const Duration(minutes: 33)), '約 35 分鐘');
      expect(planDurationLabel(const Duration(minutes: 32)), '約 30 分鐘');
    });

    test('再短也不顯示 0 分鐘', () {
      expect(planDurationLabel(const Duration(seconds: 30)), '約 5 分鐘');
      expect(planDurationLabel(Duration.zero), '約 5 分鐘');
    });
  });

  // 這組是拿資料來源自己寫的時長回頭校準 kSecondsPerRep 的依據。
  // 《健身計劃.csv》有幾份課表把每個動作花多久都寫了出來。
  group('與《健身計劃.csv》自己寫的時長對得上', () {
    int estimate(int sets, int amount, PlanUnit unit, int rest) =>
        estimatePlanDuration(
          plan([
            PlanExercise(
              exercise: ex('squat'),
              planned: List.generate(sets, (_) => PlannedSet(0, amount)),
              unit: unit,
            ),
          ]),
          restSecondsOf: (_) => rest,
        )!
            .inSeconds ~/
        60;

    test('深蹲 5 組 × 12 下、休息 60 秒 → CSV 寫「約 10 分鐘」', () {
      expect(estimate(5, 12, PlanUnit.reps, 60), 10);
    });

    test('臥姿抬膝 5 組 × 11 下、休息 60 秒 → CSV 寫「約 9–10 分鐘」', () {
      expect(estimate(5, 11, PlanUnit.reps, 60), inInclusiveRange(9, 10));
    });

    test('登山者式 6 組 × 30 秒、休息 30 秒 → CSV 寫「約 6 分鐘」', () {
      expect(estimate(6, 30, PlanUnit.seconds, 30), 6);
    });
  });

  // 使用者要求預估時長「應該要跟註冊時詢問的健身時長有關：
  // 30分鐘內、30~60、60~90、90以上那四個選項」。
  group('時長級距與註冊問卷同一套說法', () {
    String bucket(int minutes) =>
        planDurationBucket(Duration(minutes: minutes), kDurations);

    test('四個級距各自對得上', () {
      expect(bucket(20), '30 分鐘以下');
      expect(bucket(45), '30–60 分鐘');
      expect(bucket(75), '60–90 分鐘');
      expect(bucket(120), '90 分鐘以上');
    });

    test('邊界值歸較短的那一級', () {
      // 說「我只有 60 分鐘」的人，一份剛好 60 分鐘的課表他做得完。
      expect(bucket(30), '30–60 分鐘');
      expect(bucket(60), '30–60 分鐘');
      expect(bucket(90), '60–90 分鐘');
      // 91 分**顯示成「約 90 分鐘」**，所以也歸 60–90 —— 那正是下一條
      // 要釘的一致性。真的超出去要到 93 分（進位成 95）。
      expect(bucket(91), '60–90 分鐘');
      expect(bucket(93), '90 分鐘以上');
    });

    // 卡片上寫「約 60 分鐘」而級距歸到「60–90 分鐘」的話，
    // 兩個數字當著使用者的面互相矛盾。
    test('級距算的是顯示出來的那個數字，不是原始秒數', () {
      const d = Duration(seconds: 61 * 60); // 61 分 → 顯示「約 60 分鐘」
      expect(planDurationLabel(d), '約 60 分鐘');
      expect(planDurationBucket(d, kDurations), '30–60 分鐘');
    });

    test('值域就是註冊問卷那一份，不是另抄一份', () {
      expect(kDurations.length, 4);
      for (final m in [10, 45, 75, 200]) {
        expect(kDurations, contains(bucket(m)));
      }
    });
  });

  group('每一份平台課表都估得出時長', () {
    test('27 份課表全部有值，且落在合理區間', () {
      final s = AppState();
      for (final p in s.platformPlans) {
        // 空白課表（自由訓練）沒有預排內容，估不出來是對的 ——
        // 上面那條測試釘的就是它要回傳空值。
        if (p.source == PlanSource.blank) continue;
        final d = s.estimatedDurationOf(p);
        expect(d, isNotNull, reason: '${p.name} 估不出時長');
        expect(d!.inMinutes, greaterThan(0), reason: p.name);
        // 資料來源裡最長的那幾份寫「約 110–120 分鐘」（含暖身與收操），
        // 主訓練估到 150 分鐘以上就代表公式或資料有問題。
        expect(d.inMinutes, lessThan(150), reason: '${p.name} 估出 ${d.inMinutes} 分');
      }
    });

    test('單位有被帶進來 —— 時間型的課表不會被當成次數型算', () {
      // 27 份課表裡有時間型動作，若 unit 在轉換時被丟掉，
      // 那些動作會被當成「N 下」而乘上 5，總時長整體偏長。
      final timed = kPlatformPlans
          .expand((p) => p.items)
          .where((it) => it.unit == PlanUnit.seconds);
      expect(timed, isNotEmpty, reason: '資料來源本來就有時間型動作');

      final plans = buildCsvPlans();
      expect(
        plans.any((p) => p.exercises.any((e) => e.isTimed)),
        isTrue,
        reason: 'PlanUnit 必須一路帶到 WorkoutPlan，不可在轉換時丟掉',
      );
    });
  });
}
