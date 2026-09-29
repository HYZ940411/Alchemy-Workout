import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/screens/train/rest_countdown.dart';
import 'package:fitness_app/theme.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan _plan(List<PlanExercise> exercises) => WorkoutPlan(
      id: 'test',
      name: '測試課表',
      source: PlanSource.privateCustom,
      equipmentTier: '健身房',
      exercises: exercises,
    );

void main() {
  group('組間休息秒數的取值優先序（訓練紀錄流程 · 組間休息已開始）', () {
    final s = AppState();

    test('第一順位：課表指定值蓋過動作預設', () {
      final pe = PlanExercise(
        exercise: ex('bench'), // 動作預設 150
        planned: const [PlannedSet(60, 8)],
        restSeconds: 120,
      );
      expect(s.restSecondsFor(pe), 120);
    });

    test('第二順位：課表未指定則用該動作的預設組間休息秒數', () {
      final pe = PlanExercise(
        exercise: ex('squat'),
        planned: const [PlannedSet(80, 5)],
      );
      expect(ex('squat').defaultRestSeconds, 180);
      expect(s.restSecondsFor(pe), 180);
    });

    test('第三順位：兩者皆未設定則退回全站預設 90 秒', () {
      final pe = PlanExercise(
        exercise: ex('crunch'), // 動作層級未設定
        planned: const [PlannedSet(10, 15)],
      );
      expect(ex('crunch').defaultRestSeconds, isNull);
      expect(s.restSecondsFor(pe), kDefaultRestSeconds);
      expect(kDefaultRestSeconds, 90);
    });

    test('休息秒數為動作層級，不逐組設定 —— 同動作各組取值相同', () {
      final pe = PlanExercise(
        exercise: ex('deadlift'),
        planned: const [PlannedSet(100, 5), PlannedSet(100, 5)],
      );
      // 模型未給「逐組覆寫」的位置，取值只由（課表 × 動作）決定。
      expect(s.restSecondsFor(pe), 180);
    });
  });

  group('組間休息的起訖', () {
    test('完成一組後起算休息，總秒數取自剛完成的那個動作', () {
      final s = AppState();
      s.startWorkout(_plan([
        PlanExercise(
          exercise: ex('squat'), // 180
          planned: const [PlannedSet(80, 5), PlannedSet(80, 5)],
        ),
      ]));
      expect(s.restRemaining, 0);

      expect(s.completeCurrentSet(), isTrue);
      expect(s.restTotalSeconds, 180);
      expect(s.restRemaining, greaterThan(170));
    });

    test('最後一組之後沒有休息', () {
      final s = AppState();
      s.startWorkout(_plan([
        PlanExercise(
          exercise: ex('squat'),
          planned: const [PlannedSet(80, 5)], // 全課表只有這一組
        ),
      ]));
      expect(s.completeCurrentSet(), isTrue);
      expect(s.restEndsAt, isNull);
      expect(s.restRemaining, 0);
    });

    test('取消該組不起算休息', () {
      final s = AppState();
      s.startWorkout(_plan([
        PlanExercise(
          exercise: ex('bench'),
          planned: const [PlannedSet(60, 8), PlannedSet(60, 8)],
        ),
      ]));
      s.completeCurrentSet();
      expect(s.restEndsAt, isNotNull);
      s.cancelCurrentSet();
      expect(s.restEndsAt, isNull);
    });

    test('「組間休息已結束」為多對一：跳過與計時結束都收束到同一狀態', () {
      final s = AppState();
      final plan = _plan([
        PlanExercise(
          exercise: ex('bench'),
          planned: const [PlannedSet(60, 8), PlannedSet(60, 8)],
        ),
      ]);

      s.startWorkout(plan);
      s.completeCurrentSet();
      s.skipRest(); // 使用者觸發
      expect(s.restEndsAt, isNull);

      s.startWorkout(plan);
      s.completeCurrentSet();
      s.endRestByTimer(); // 系統觸發
      expect(s.restEndsAt, isNull);
    });
  });

  group('全屏倒數的呈現（§8.10 全屏大型 · R-28）', () {
    Future<void> pumpRest(
      WidgetTester t, {
      required int seconds,
      VoidCallback? onSkip,
      VoidCallback? onFinished,
    }) async {
      await t.pumpWidget(MaterialApp(
        home: RestCountdownScreen(
          endsAt: DateTime.now().add(Duration(seconds: seconds)),
          totalSeconds: 90,
          onFinished: onFinished ?? () {},
          onSkip: onSkip ?? () {},
        ),
      ));
      await t.pump();
    }

    testWidgets('數字用 Display 64／72 —— 全 App 唯一的例外用例', (t) async {
      await pumpRest(t, seconds: 88);
      // **用 Key 定位，不用字面值。** 原本寫的是 `find.text('88')`，
      // 而倒數讀的是真實時鐘 —— 從建構到 pump 之間只要超過一秒就變成 87，
      // 整條測試隨機轉紅（2026-09-29 全量測試撞到，單獨重跑三次紅兩次）。
      // 這條要驗的是字級，跟數字是幾無關。
      final n = t.widget<Text>(find.byKey(restSecondsKey));
      expect(n.style!.fontSize, 64);
      expect(n.style!.height! * 64, 72);
      expect(n.style!.color, C.textPrimary);
    });

    testWidgets('倒數顯示的是剩餘秒數，且一開始就看得到完整秒數', (t) async {
      await pumpRest(t, seconds: 88);
      final shown = int.parse(t.widget<Text>(find.byKey(restSecondsKey)).data!);
      // 進位而非捨去（見 `_remaining` 的註解），所以起始值就是 88；
      // 容許慢一拍是因為這裡讀的是真實時鐘 —— 但**不容許差得更多**，
      // 否則「顯示剩餘秒數」這件事就沒被驗到了。
      expect(shown, anyOf(88, 87));
    });

    testWidgets('圓環直徑 240、跳過按鈕最小高 48', (t) async {
      await pumpRest(t, seconds: 60);
      expect(t.getSize(find.byKey(restRingKey)), const Size(240, 240));
      expect(Sz.buttonMinHeight, 48);
    });

    testWidgets('跳過鈕觸發使用者側的「組間休息已結束」', (t) async {
      var skipped = false;
      await pumpRest(t, seconds: 60, onSkip: () => skipped = true);
      await t.tap(find.text('跳過休息'));
      expect(skipped, isTrue);
    });

    testWidgets('倒數歸零觸發系統側的「組間休息已結束」，且只觸發一次', (t) async {
      var finished = 0;
      await pumpRest(t, seconds: 0, onFinished: () => finished++);
      await t.pump(const Duration(milliseconds: 32));
      await t.pump(const Duration(milliseconds: 32));
      await t.pump(const Duration(milliseconds: 32));
      expect(finished, 1);
    });

    testWidgets('全屏層吃掉點擊 —— 底下的東西按不到', (t) async {
      var behind = 0;
      await t.pumpWidget(MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => behind++,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: RestCountdownScreen(
                endsAt: DateTime.now().add(const Duration(seconds: 60)),
                totalSeconds: 90,
                onFinished: () {},
                onSkip: () {},
              ),
            ),
          ],
        ),
      ));
      await t.pump();

      // 圓環正中央 —— 底層在該處是有反應的，全屏層必須把它擋住。
      await t.tapAt(t.getCenter(find.byKey(restRingKey)));
      await t.pump();
      expect(behind, 0);

      // 跳過鈕本身仍要能按 —— 吸收不能把自己也吃掉。
      var skipped = false;
      await t.pumpWidget(MaterialApp(
        home: RestCountdownScreen(
          endsAt: DateTime.now().add(const Duration(seconds: 60)),
          totalSeconds: 90,
          onFinished: () {},
          onSkip: () => skipped = true,
        ),
      ));
      await t.pump();
      await t.tap(find.text('跳過休息'));
      expect(skipped, isTrue);
    });
  });
}
