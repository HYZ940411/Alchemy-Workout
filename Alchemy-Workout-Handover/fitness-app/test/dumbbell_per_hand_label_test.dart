// 啞鈴的重量要填「每手」，畫面要寫出來（使用者裁決，2026-10-17）。
//
// 相對強度係數是照單顆啞鈴的重量校準的（啞鈴臥推新手每手 14 kg ＝ C 級 294 分）。
// 使用者若習慣填兩手加總，重量多一倍，分數直接爆表：啞鈴臥推 28 kg 算出來是 999。
// 這跟使用者最初不想要的「分數太高」是同一類問題，而且很容易發生 ——
// 畫面上一個字也沒提示。所以「每手」要寫在填重量的地方。
//
// 彈力繩動作在資料裡標成徒手型（重量欄鎖住），詳情頁不能再寫「徒手動作：是」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/screens/train/custom_plan_edit_screen.dart';
import 'package:fitness_app/screens/train/exercise_detail_screen.dart';
import 'package:fitness_app/screens/workout_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Exercise _byName(String n) => kPlatformExercises.firstWhere((e) => e.name == n);

Future<void> _openWorkout(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: WorkoutScreen()),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

WorkoutPlan _plan(Exercise e) => WorkoutPlan(
      id: 'p',
      name: 'p',
      source: PlanSource.privateCustom,
      exercises: [
        PlanExercise(exercise: e, planned: const [PlannedSet(14, 10)]),
      ],
    );

void main() {
  group('哪些動作的重量是每手', () {
    test('器材含啞鈴的都是（含「啞鈴 ＋ 平板椅」這種帶配件的）', () {
      final dumbbell = kPlatformExercises
          .where((e) => e.equipment.split(' ＋ ').first.contains('啞鈴'));
      expect(dumbbell.length, 75, reason: '動作庫的啞鈴動作數');
      for (final e in dumbbell) {
        expect(e.weightIsPerHand, isTrue, reason: e.name);
      }
    });

    test('槓鈴、壺鈴、機械、繩索、彈力繩、徒手都不是', () {
      for (final e in kPlatformExercises) {
        if (e.equipment.split(' ＋ ').first.contains('啞鈴')) continue;
        expect(e.weightIsPerHand, isFalse, reason: '${e.name}（${e.equipment}）');
      }
    });
  });

  group('不寫「每手」的後果就是這個', () {
    test('啞鈴臥推填兩手加總 28 kg ＝ 999；填每手 14 kg ＝ 294', () {
      final e = _byName('板凳臥推 · 啞鈴');
      int score(double w) => measuredScore(
          weightKg: w,
          reps: 10,
          relativeIntensity: e.relativeIntensity,
          bodyweightKg: 70,
          isMale: true);
      expect(score(14), closeTo(294, 2));
      expect(score(28), 999);
    });
  });

  group('畫面', () {
    testWidgets('訓練頁：啞鈴動作的重量單位寫「每手」', (t) async {
      final s = AppState();
      s.beginWorkout(_plan(_byName('板凳臥推 · 啞鈴')));
      await _openWorkout(t, s);
      expect(find.textContaining('每手'), findsWidgets);
    });

    testWidgets('訓練頁：槓鈴動作不寫「每手」', (t) async {
      final s = AppState();
      s.beginWorkout(_plan(_byName('板凳臥推 · 槓鈴')));
      await _openWorkout(t, s);
      expect(find.textContaining('每手'), findsNothing);
    });

    testWidgets('自訂訓練編輯頁：啞鈴動作的欄位叫「每手重量」，槓鈴叫「目標重量」', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      s.addPlan('啞鈴日', [
        PlanExercise(
            exercise: _byName('板凳臥推 · 啞鈴'),
            planned: const [PlannedSet(14, 10)]),
      ]);
      s.addPlan('槓鈴日', [
        PlanExercise(
            exercise: _byName('板凳臥推 · 槓鈴'),
            planned: const [PlannedSet(40, 10)]),
      ]);
      Future<void> open(String name) async {
        final plan = s.customPlans.firstWhere((p) => p.name == name);
        // 先清空：同型別的畫面會沿用上一份編輯中的草稿。
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(AppScope(
          state: s,
          child: MaterialApp(home: CustomPlanEditScreen(initial: plan)),
        ));
        await t.pumpAndSettle();
      }

      await open('啞鈴日');
      expect(find.text('每手重量'), findsOneWidget);
      expect(find.text('目標重量'), findsNothing);

      await open('槓鈴日');
      expect(find.text('每手重量'), findsNothing);
      expect(find.text('目標重量'), findsOneWidget);
    });

    testWidgets('動作詳情頁：彈力繩動作不再寫「徒手動作：是」，改說明不用填重量', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final band = _byName('站姿胸推 · 彈力帶');
      expect(band.isBodyweight, isTrue, reason: '前提：資料裡彈力繩標成徒手型');
      await t.pumpWidget(AppScope(
        state: AppState(),
        child: MaterialApp(home: ExerciseDetailScreen(exercise: band)),
      ));
      await t.pumpAndSettle();
      expect(find.text('彈力繩動作不用填重量，分數固定'), findsOneWidget);
      expect(find.text('估算 1RM 時以「體重 ＋ 負重」計算'), findsNothing);
    });

    testWidgets('動作詳情頁：真的徒手動作照舊；啞鈴動作提示填每手', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> open(Exercise e) async {
        await t.pumpWidget(AppScope(
          state: AppState(),
          child: MaterialApp(home: ExerciseDetailScreen(exercise: e)),
        ));
        await t.pumpAndSettle();
      }

      await open(_byName('伏地挺身'));
      expect(find.text('估算 1RM 時以「體重 ＋ 負重」計算'), findsOneWidget);

      await open(_byName('板凳臥推 · 啞鈴'));
      expect(find.text('重量請填每手的重量'), findsOneWidget);
    });
  });
}
