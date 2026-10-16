// 徒手動作的重量是「外加負重」，預設 0、鎖著不給調；開了「外加負重」才能調
// （使用者 2026-10-16 裁決 C）。
//
// 不整個鎖死：負重引體向上這類練法要能記，能力值的算法也把外加負重算進去
// （徒手動作代入重量 ＝ 體重 × 係數，負重另加）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/screens/train/custom_plan_edit_screen.dart';
import 'package:fitness_app/screens/workout_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/added_load_switch.dart';
import 'package:fitness_app/widgets/common.dart';

Exercise _bodyweight(AppState s) => s.platformExercises.firstWhere(
    (e) => e.isBodyweight && e.type == ExerciseType.strength);
Exercise _barbell(AppState s) => s.platformExercises.firstWhere(
    (e) => !e.isBodyweight && e.type == ExerciseType.strength);

/// 第一個動作是徒手的課表。
WorkoutPlan _plan(AppState s, {double added = 0}) => WorkoutPlan(
      id: 'bw-test',
      name: '徒手測試',
      source: PlanSource.privateCustom,
      exercises: [
        PlanExercise(
          exercise: _bodyweight(s),
          planned: [PlannedSet(added, 10), PlannedSet(added, 10)],
        ),
        PlanExercise(
          exercise: _barbell(s),
          planned: const [PlannedSet(40, 8)],
        ),
      ],
    );

void main() {
  group('狀態層：鎖定是規則，不只是按鈕不給按', () {
    test('重量 0 的徒手動作：重量改不動', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      expect(s.currentRecord!.weight, 0);
      s.editCurrentSet(weight: 5);
      expect(s.currentRecord!.weight, 0, reason: '鎖著的時候輸入重量不收');
      s.editCurrentSet(weight: -3);
      expect(s.currentRecord!.weight, 0);
    });

    test('鎖定時次數照常能改', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.editCurrentSet(reps: 15);
      expect(s.currentRecord!.reps, 15);
    });

    test('打開外加負重 → 能調；關掉 → 回到 0 並再次鎖上', () {
      final s = AppState();
      final bw = _bodyweight(s);
      s.beginWorkout(_plan(s));
      s.setAddedLoad(bw, true);
      s.editCurrentSet(weight: 7.5);
      expect(s.currentRecord!.weight, 7.5);
      s.setAddedLoad(bw, false);
      expect(s.currentRecord!.weight, 0);
      s.editCurrentSet(weight: 5);
      expect(s.currentRecord!.weight, 0);
    });

    test('已經有外加負重的（例如重新整理後讀回）：不鎖，才不會把使用者記的負重卡死', () {
      final s = AppState();
      final bw = _bodyweight(s);
      s.beginWorkout(_plan(s));
      s.setAddedLoad(bw, true);
      s.editCurrentSet(weight: 10);

      // 重新整理：打開的記號不進存檔，但重量 10 還在。
      final back = AppState();
      expect(back.applySnapshot(jsonDecode(jsonEncode(s.toSnapshot()))),
          isTrue);
      expect(back.addedLoadOpen, isEmpty);
      expect(back.currentRecord!.weight, 10);
      expect(back.addedLoadLocked(bw, back.currentRecord!.weight), isFalse);
      back.editCurrentSet(weight: 12.5);
      expect(back.currentRecord!.weight, 12.5);
    });

    test('不是徒手的動作完全不受影響', () {
      final s = AppState();
      final plan = WorkoutPlan(
        id: 'bb',
        name: '槓鈴',
        source: PlanSource.privateCustom,
        exercises: [
          PlanExercise(
              exercise: _barbell(s), planned: const [PlannedSet(0, 8)]),
        ],
      );
      s.beginWorkout(plan);
      s.editCurrentSet(weight: 20);
      expect(s.currentRecord!.weight, 20);
    });

    test('結算、放棄、換帳號之後，打開的狀態不留給下一場', () {
      final s = AppState();
      final bw = _bodyweight(s);
      s.beginWorkout(_plan(s));
      s.setAddedLoad(bw, true);
      s.abandonWorkout();
      expect(s.addedLoadOpen, isEmpty);

      s.beginWorkout(_plan(s));
      s.setAddedLoad(bw, true);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);
      expect(s.addedLoadOpen, isEmpty);

      s.beginWorkout(_plan(s));
      s.setAddedLoad(bw, true);
      s.endSession();
      expect(s.addedLoadOpen, isEmpty);
    });
  });

  group('畫面', () {
    Future<void> openWorkout(WidgetTester t, AppState s) async {
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

    testWidgets('訓練頁：徒手動作的重量鎖著，打開開關才出現步進器', (t) async {
      final s = AppState();
      s.beginWorkout(_plan(s));
      await openWorkout(t, s);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byType(AddedLoadSwitch), findsOneWidget);
      // 重量的步進器沒有了，只剩次數那一組的 + / −。
      expect(find.byIcon(Icons.add), findsOneWidget);

      await t.tap(find.byType(Switch));
      await t.pump();
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byIcon(Icons.add), findsNWidgets(2));
    });

    testWidgets('訓練頁：非徒手動作沒有鎖也沒有開關', (t) async {
      final s = AppState();
      final plan = WorkoutPlan(
        id: 'bb',
        name: '槓鈴',
        source: PlanSource.privateCustom,
        exercises: [
          PlanExercise(
              exercise: _barbell(s), planned: const [PlannedSet(40, 8)]),
        ],
      );
      s.beginWorkout(plan);
      await openWorkout(t, s);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byType(AddedLoadSwitch), findsNothing);
    });

    testWidgets('訓練中加入徒手動作：重量鎖著，打開開關才能調', (t) async {
      final s = AppState();
      final plan = WorkoutPlan(
        id: 'blank',
        name: '自由訓練',
        source: PlanSource.blank,
        exercises: const [],
      );
      s.beginWorkout(plan);
      await openWorkout(t, s);
      await t.tap(find.widgetWithText(AppButton, '加入動作至本次訓練'));
      await t.pumpAndSettle();
      final name = _bodyweight(s).name;
      await t.ensureVisible(find.text(name).first);
      await t.pumpAndSettle();
      await t.tap(find.text(name).first);
      await t.pumpAndSettle();

      expect(find.byType(AddedLoadSwitch), findsOneWidget);
      // 目標重量那一列的 +。
      final plus = find.descendant(
        of: find.ancestor(
            of: find.text('目標重量'), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.add_rounded),
      );
      await t.tap(plus, warnIfMissed: false);
      await t.pump();
      expect(find.text('0.5 kg'), findsNothing, reason: '鎖著，按 + 不該動');

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(plus);
      await t.pump();
      expect(find.text('0.5 kg'), findsOneWidget);
    });

    testWidgets('自訂訓練編輯頁：徒手動作的重量鎖著，打開開關才能調', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      s.addPlan('徒手日', [
        PlanExercise(
            exercise: _bodyweight(s), planned: const [PlannedSet(0, 10)]),
      ]);
      final plan = s.customPlans.firstWhere((p) => p.name == '徒手日');
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(home: CustomPlanEditScreen(initial: plan)),
      ));
      await t.pumpAndSettle();

      expect(find.byType(AddedLoadSwitch), findsOneWidget);
      // 第一個 + 是目標重量那一列的。鎖著時按下去沒有反應。
      final plus = find.byIcon(Icons.add_rounded).first;
      await t.tap(plus, warnIfMissed: false);
      await t.pump();
      expect(find.text('0.5 kg'), findsNothing, reason: '鎖著，按 + 不該動');

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add_rounded).first);
      await t.pump();
      expect(find.text('0.5 kg'), findsOneWidget, reason: '打開外加負重後才能調');
    });
  });
}
