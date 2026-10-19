// 訓練中要看得到動作說明（使用者 2026-10-19 回報）。
//
// 「點選開始訓練後，裡面沒有每個動作的詳細說明，只能在開始訓練前觀看，
// 如果需要觀看需要先退出訓練才能查看。」
//
// 動作詳情頁（準備工作、動作要領、關鍵提示）原本只從動作庫、訓練歷史、課表詳情三個入口進得去，
// 訓練頁沒有。現在：目前動作的標題列有「動作說明」鈕，動作清單裡每個動作名稱也能點。
// 開的是疊在訓練頁上面的一般頁面 —— 不結束、不暫停訓練，返回就回到原來那一組。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/screens/train/exercise_detail_screen.dart';
import 'package:fitness_app/screens/train/rest_countdown.dart';
import 'package:fitness_app/screens/workout_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Exercise _byName(String n) => kPlatformExercises.firstWhere((e) => e.name == n);

WorkoutPlan _plan() => WorkoutPlan(
      id: 'info',
      name: '說明測試',
      source: PlanSource.privateCustom,
      exercises: [
        PlanExercise(
            exercise: _byName('板凳臥推 · 槓鈴'),
            planned: const [PlannedSet(40, 10), PlannedSet(40, 10)]),
        PlanExercise(
            exercise: _byName('深蹲 · 槓鈴'),
            planned: const [PlannedSet(50, 10)]),
      ],
    );

Future<void> _open(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 2400 * 3);
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

/// 詳情頁標題列的動作名稱。
Finder _detailTitle(String name) =>
    find.descendant(of: find.byType(ExerciseDetailScreen), matching: find.text(name));

void main() {
  testWidgets('目前動作的標題列有「動作說明」鈕，點下去開該動作的詳情頁', (t) async {
    final s = AppState();
    s.beginWorkout(_plan());
    await _open(t, s);
    expect(find.byKey(const ValueKey('exercise-info-current')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('exercise-info-current')));
    await t.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(_detailTitle('板凳臥推 · 槓鈴'), findsWidgets);
  });

  testWidgets('看完說明返回：訓練還在原來那一組，沒有被結束、也沒有少算', (t) async {
    final s = AppState();
    s.beginWorkout(_plan());
    s.completeCurrentSet(); // 先做完第 1 組，確認返回後進度不變
    s.skipRest(); // 休息畫面是全屏蓋住訓練頁的，這個測試看的是訓練頁
    final before = (s.session!.exerciseIndex, s.session!.setIndex, s.session!.doneSets);
    await _open(t, s);

    await t.tap(find.byKey(const ValueKey('exercise-info-current')));
    await t.pumpAndSettle();
    expect(s.session, isNotNull, reason: '開說明頁不該結束訓練');

    // 詳情頁標題列自帶返回鍵（AppBar 在能返回時自動放）。
    await t.tap(find.descendant(
      of: find.descendant(
          of: find.byType(ExerciseDetailScreen), matching: find.byType(AppBar)),
      matching: find.byType(IconButton),
    ).first);
    await t.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsNothing);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(s.session, isNotNull);
    expect((s.session!.exerciseIndex, s.session!.setIndex, s.session!.doneSets), before);
  });

  testWidgets('動作清單裡每個動作都能點名稱看說明 —— 下一個動作怎麼做，不必等輪到它', (t) async {
    final s = AppState();
    s.beginWorkout(_plan());
    await _open(t, s);

    // 第 2 個動作（深蹲）還沒輪到。
    final row = find.byKey(const ValueKey('exercise-info-1'));
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(_detailTitle('深蹲 · 槓鈴'), findsWidgets);
    expect(s.session!.exerciseIndex, 0, reason: '看說明不會跳到那個動作');
  });

  group('組間休息的全屏畫面', () {
    // 休息畫面有每秒跳動的計時器，pumpAndSettle 等不到靜止，改用固定時間的 pump。
    Future<void> settle(WidgetTester t) async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('休息時也有「看這個動作的說明」鈕，點下去不結束休息', (t) async {
      final s = AppState();
      s.beginWorkout(_plan());
      s.completeCurrentSet(); // 第 1 個動作做完第 1 組 → 進入休息
      await _open(t, s);
      expect(find.byKey(restSecondsKey), findsOneWidget, reason: '前提：正在休息');
      expect(find.byKey(restInfoKey), findsOneWidget);

      await t.tap(find.byKey(restInfoKey));
      await settle(t);
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(_detailTitle('板凳臥推 · 槓鈴'), findsWidgets);
      expect(s.restEndsAt, isNotNull, reason: '看說明不該把休息結束掉');

      await t.tap(find.descendant(
        of: find.descendant(
            of: find.byType(ExerciseDetailScreen), matching: find.byType(AppBar)),
        matching: find.byType(IconButton),
      ).first);
      await settle(t);
      expect(find.byType(ExerciseDetailScreen), findsNothing);
      expect(find.byKey(restSecondsKey), findsOneWidget, reason: '返回後還在休息');
    });

    testWidgets('做完一個動作的最後一組進入休息：說明是「接下來這個動作」的', (t) async {
      final s = AppState();
      s.beginWorkout(_plan());
      s.completeCurrentSet(); // 動作 1 第 1 組
      s.skipRest();
      s.completeCurrentSet(); // 動作 1 第 2 組（最後一組）→ 休息，接下來是深蹲
      await _open(t, s);
      expect(s.session!.exerciseIndex, 1, reason: '前提：已輪到第 2 個動作');
      expect(find.byKey(restInfoKey), findsOneWidget);

      await t.tap(find.byKey(restInfoKey));
      await settle(t);
      expect(_detailTitle('深蹲 · 槓鈴'), findsWidgets);
    });
  });
}
