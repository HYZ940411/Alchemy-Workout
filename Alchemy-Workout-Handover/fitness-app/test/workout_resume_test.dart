// 練到一半重新整理網頁，那場訓練要還在，而且要自動跳回去（2026-10-16 使用者回報）。
//
// 實測：訓練進行中按重新整理，訓練不見了。原因：`AppState.session` 只活在記憶體裡，
// 不在存檔快照裡 —— 重新整理等於把整場訓練丟掉，已經勾好的組也一起沒了。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/home_shell.dart';
import 'package:fitness_app/screens/train/plan_detail_screen.dart';
import 'package:fitness_app/screens/workout_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一份有至少兩個動作的官方課表。
WorkoutPlan _plan(AppState s) => s.platformPlans.firstWhere(
    (p) => p.source == PlanSource.official && p.exercises.length >= 2);

/// 把快照走一趟 JSON —— 雲端與瀏覽器存的都是 JSON，物件裡混了不能序列化的東西
/// 在這裡就會露出來。
Map<String, dynamic> _viaJson(AppState s) =>
    jsonDecode(jsonEncode(s.toSnapshot())) as Map<String, dynamic>;

AppState _restored(Map<String, dynamic> snap) {
  final s = AppState();
  expect(s.applySnapshot(snap), isTrue);
  return s;
}

void main() {
  group('存檔往返', () {
    test('練到一半 → 存檔 → 讀回，進度、動作、組紀錄都在', () {
      final s = AppState();
      final plan = _plan(s);
      s.beginWorkout(plan);
      expect(s.completeCurrentSet(), isTrue);
      expect(s.completeCurrentSet(), isTrue);
      final before = s.session!;

      final back = _restored(_viaJson(s)).session;
      expect(back, isNotNull, reason: '重新整理後訓練不見了就是這個');
      expect(back!.plan.id, plan.id);
      expect(back.plan.name, plan.name);
      expect(back.startedAt, before.startedAt);
      expect(back.doneSets, 2);
      expect(back.exerciseIndex, before.exerciseIndex);
      expect(back.setIndex, before.setIndex);
      expect(back.exercises.map((e) => e.exercise.id),
          before.exercises.map((e) => e.exercise.id));
      expect([
        for (final l in back.records)
          [for (final r in l) (r.weight, r.reps, r.state)]
      ], [
        for (final l in before.records)
          [for (final r in l) (r.weight, r.reps, r.state)]
      ]);
    });

    test('取消過的組（不實體刪除）也一起回來', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.completeCurrentSet();
      expect(s.uncheckSet(0, 0), isTrue);
      expect(s.session!.cancelled, hasLength(1));

      final back = _restored(_viaJson(s)).session!;
      expect(back.cancelled, hasLength(1));
      expect(back.cancelled.single.exerciseIndex, 0);
      expect(back.cancelled.single.setIndex, 0);
    });

    test('組間休息的倒數和器材解鎖旗標也回來', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.completeCurrentSet();
      s.sessionEquipmentUnlocked = true;
      final restEnds = s.restEndsAt;
      expect(restEnds, isNotNull, reason: '前提：完成一組後進入休息');

      final back = _restored(_viaJson(s));
      expect(back.restEndsAt, restEnds);
      expect(back.sessionEquipmentUnlocked, isTrue);
    });

    test('AI 訓練前調整過的快照，讀回來是調整後的樣子，不是來源課表', () {
      final s = AppState();
      final plan = _plan(s);
      s.beginWorkout(plan);
      final extra = s.platformExercises.firstWhere(
          (e) => !plan.exercises.any((p) => p.exercise.id == e.id));
      s.addExerciseToSession(extra, const [PlannedSet(20, 10)]);

      final back = _restored(_viaJson(s)).session!;
      expect(back.exercises, hasLength(plan.exercises.length + 1));
      expect(back.exercises.last.exercise.id, extra.id);
      expect(back.records.last, hasLength(1));
    });
  });

  group('只有「按下開始訓練」的才算進行中', () {
    test('只是選了課表（AI 訓練前調整會產生快照）→ 不進存檔', () {
      final s = AppState();
      s.startWorkout(_plan(s));
      expect(s.session, isNotNull, reason: '前提：快照已產生');
      expect(s.toSnapshot()['activeWorkout'], isNull);
      expect(_restored(_viaJson(s)).session, isNull);
    });

    test('結算之後不再留著', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);
      expect(s.workoutBegun, isFalse);
      expect(_restored(_viaJson(s)).session, isNull);
    });

    test('放棄之後不再留著', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.abandonWorkout();
      expect(_restored(_viaJson(s)).session, isNull);
    });
  });

  group('不該把別人的或壞掉的帶回來', () {
    test('換帳號：上一個人的訓練不能留給下一個人', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.endSession();
      expect(s.session, isNull);
      expect(s.workoutBegun, isFalse);
      expect(s.takeWorkoutResume(), isFalse);
    });

    test('另一個人的存檔沒有進行中的訓練 → 記憶體裡殘留的那場被清掉', () {
      final other = AppState()..displayName = '別人';
      final snapB = _viaJson(other);
      final s = AppState();
      s.beginWorkout(_plan(s));
      expect(s.applySnapshot(snapB), isTrue);
      expect(s.session, isNull);
    });

    test('組數對不上 → 整場放棄，不拼湊半場', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      final snap = _viaJson(s);
      final recs = (snap['activeWorkout'] as Map)['records'] as List;
      ((recs.first as Map)['sets'] as List).removeLast();
      expect(_restored(snap).session, isNull);
    });

    test('動作被下架（找不到）→ 整場放棄', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      final snap = _viaJson(s);
      (((snap['activeWorkout'] as Map)['exercises'] as List).first as Map)[
          'exerciseId'] = '不存在的動作';
      expect(_restored(snap).session, isNull);
    });

    test('游標超出範圍 → 整場放棄', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      final snap = _viaJson(s);
      (snap['activeWorkout'] as Map)['exerciseIndex'] = 99;
      expect(_restored(snap).session, isNull);
    });

    test('讀回來之後只帶使用者回去一次', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      final back = _restored(_viaJson(s));
      expect(back.takeWorkoutResume(), isTrue);
      expect(back.takeWorkoutResume(), isFalse);
    });

    test('自己按開始訓練不算「讀回來」，不會再被帶一次', () {
      final s = AppState();
      s.beginWorkout(_plan(s));
      expect(s.takeWorkoutResume(), isFalse,
          reason: '這條路徑已經在跳訓練頁了，再跳會疊兩層');
    });
  });

  group('畫面：重新整理後自動跳回訓練頁', () {
    Future<void> boot(WidgetTester t, Store store) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(FitnessApp(store: store));
      // 訓練頁有每秒一次的計時器，pumpAndSettle 永遠等不完。
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('練到一半重新整理 → 直接回到訓練頁', (t) async {
      final s = AppState();
      s.beginWorkout(_plan(s));
      s.completeCurrentSet();
      final store = MemoryStore();
      await store.save(_viaJson(s));

      await boot(t, store);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(find.text(_plan(s).name), findsWidgets);
    });

    testWidgets('沒有進行中的訓練 → 停在主頁', (t) async {
      final s = AppState();
      s.startWorkout(_plan(s)); // 只選了課表
      final store = MemoryStore();
      await store.save(_viaJson(s));

      await boot(t, store);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(WorkoutScreen), findsNothing);
    });
  });

  group('畫面：按下「開始訓練」', () {
    testWidgets('按下去訓練就算開始，並進存檔', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) =>
          p.source == PlanSource.official &&
          p.exercises.length >= 2 &&
          s.planUnlocked(p));
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(home: PlanDetailScreen(plan: plan)),
      ));
      await t.pumpAndSettle();
      expect(s.workoutBegun, isFalse);

      // 清單是惰性建構，按鈕在畫面下方，要先捲到才建得出來。
      await t.scrollUntilVisible(find.text('開始訓練'), 400,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('開始訓練'));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(s.workoutBegun, isTrue,
          reason: '按鈕若只產生快照，這場訓練不會進存檔，重新整理就沒了');
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(_viaJson(s)['activeWorkout'], isNotNull);
    });
  });
}
