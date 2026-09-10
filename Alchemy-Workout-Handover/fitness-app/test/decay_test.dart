import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/train/decay_screen.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan get blankPlan =>
    kPlans.firstWhere((p) => p.source == PlanSource.blank);

void main() {
  group('退步下限：相對歷史最高的兩個主階', () {
    test('主階降 2、小節點保留', () {
      expect(decayFloorOf(750), 315, reason: 'A+ → C+');
      expect(decayFloorOf(800), 385, reason: 'A++ → C++');
      expect(decayFloorOf(480), 100, reason: 'B → D');
      // 六個主階由低至高為 E → D → C → B → A → S，故 S 降兩階是 B。
      // 規格書原本這一列寫 A++ 785（只降一階），2026-09-04 訂正為 B++ 585。
      expect(decayFloorOf(960), 585, reason: 'S++ → B++');
    });

    test('最高階也確實降兩個主階，不是一階', () {
      expect(majorGradeOf(960), 'S');
      expect(majorGradeOf(decayFloorOf(960)), 'B');
    });

    test('退不滿兩階者一律取該維初始值', () {
      expect(decayFloorOf(180), kInitialPoints, reason: 'D+ 不足兩階');
      expect(decayFloorOf(50), kInitialPoints, reason: 'E 不足兩階');
    });

    test('下限不低於該維初始值 —— 完成新手任務者腿與核心為 30', () {
      expect(decayFloorOf(180, initial: kNoviceLegCoreInitial),
          kNoviceLegCoreInitial);
    });

    test('不採「一律回到該階基本段」—— A／A+／A++ 三者下限不同', () {
      final floors = {decayFloorOf(660), decayFloorOf(750), decayFloorOf(800)};
      expect(floors.length, 3, reason: '抹平同階內的努力差異即為該方案被否決的理由');
    });
  });

  group('單次退步', () {
    test('退 5%，向下取整', () {
      expect(decayOnce(current: 750, floor: 315).newPoints, 712);
    });

    test('會低於下限者截斷至下限，該次即為觸及下限的那一次', () {
      final r = decayOnce(current: 320, floor: 315);
      expect(r.newPoints, 315);
      expect(r.hitFloor, isTrue);
      expect(r.lost, 5);
    });

    test('已在下限者仍照常產生一次 —— 無數值變化，但它是回歸任務的唯一觸發源', () {
      final r = decayOnce(current: 10, floor: 10);
      expect(r.newPoints, 10);
      expect(r.lost, 0);
      expect(r.hitFloor, isTrue);
    });

    test('複利速度對得上模型：A+ 750 者約 5.7 個月觸及 C+', () {
      var p = 750;
      var n = 0;
      while (p > 315) {
        p = decayOnce(current: p, floor: 315).newPoints;
        n++;
      }
      expect(n * kDecayIntervalHours / 24 / 30, closeTo(5.7, 0.4));
    });
  });

  group('計時基準為日界', () {
    final trained = DateTime(2026, 3, 10);

    test('自上次訓練日的次日 04:00 起算', () {
      expect(dayBoundaryAfter(trained), DateTime(2026, 3, 11, 4));
    });

    test('日界未到者為 0，不倒數負值', () {
      expect(hoursSinceBoundary(trained, DateTime(2026, 3, 10, 22)), 0);
    });

    test('每週練一次（7 天）不觸發退步，滿 10 天才退', () {
      expect(hoursSinceBoundary(trained, trained.add(const Duration(days: 8))),
          lessThan(kDecayIntervalHours));
      expect(hoursSinceBoundary(trained, trained.add(const Duration(days: 12))),
          greaterThanOrEqualTo(kDecayIntervalHours));
    });

    test('四道門檻', () {
      expect(stageOf(0), DecayStage.normal);
      expect(stageOf(24), DecayStage.interruptWarned);
      expect(stageOf(36), DecayStage.streakBroken);
      expect(stageOf(96), DecayStage.decayWarned);
      expect(stageOf(240), DecayStage.decaying);
    });
  });

  group('六個各自獨立的計時器', () {
    test('初始狀態：只有逾時的維度退步，其餘不受影響', () {
      final s = AppState();
      expect(s.decayTimers[Dim.chest]!.cumulative, 0, reason: '今天練過');
      expect(s.decayTimers[Dim.legs]!.cumulative, 0, reason: '第 5 天，僅退步預告');
      expect(s.decayTimers[Dim.shoulders]!.cumulative, greaterThan(0));
      expect(s.decayTimers[Dim.core]!.cumulative, greaterThan(0));
      expect(s.points[Dim.chest], 486, reason: '未逾時的維度一點都不該少');
    });

    test('中斷前點數 ＝ 點數 ＋ 累積退步量，中斷期間恆定，故下限不隨退步下滑', () {
      final s = AppState();
      final before = s.pointsBeforeInterruption(Dim.core);
      final floor = s.decayFloorFor(Dim.core);
      s.advanceDemoClock(const Duration(days: 30));
      expect(s.pointsBeforeInterruption(Dim.core), before);
      expect(s.decayFloorFor(Dim.core), floor);
    });

    test('觸及下限後只產生一次，且計時器停止推進', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 900));
      final td = s.decayTimers[Dim.core]!;
      expect(td.floorReached, isTrue);
      expect(td.stopped, isTrue);
      expect(s.points[Dim.core], s.decayFloorFor(Dim.core));

      final n = s.decayLog.where((e) => e.$1 == Dim.core).length;
      s.advanceDemoClock(const Duration(days: 365));
      expect(s.decayLog.where((e) => e.$1 == Dim.core).length, n,
          reason: '停止後的計時器不再推進');
    });
  });

  group('重設計時的訓練', () {
    test('訓練該維即重設計時、累積退步量歸零', () {
      final s = AppState();
      expect(s.decayTimers[Dim.core]!.cumulative, greaterThan(0));
      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('plank'), const [PlannedSet(0, 30)]);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.decayTimers[Dim.core]!.cumulative, 0);
      expect(s.decayTimers[Dim.core]!.floorReached, isFalse);
    });

    test('自建動作不加分，但仍重設其所屬肌群的計時', () {
      final s = AppState();
      final before = s.points[Dim.shoulders]!;
      expect(s.decayTimers[Dim.shoulders]!.cumulative, greaterThan(0));
      s.startWorkout(blankPlan);
      s.addExerciseToSession(
          kCustomExercises.firstWhere((e) => e.dim == Dim.shoulders),
          const [PlannedSet(10, 12)]);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.points[Dim.shoulders], before, reason: '不加分');
      expect(s.decayTimers[Dim.shoulders]!.cumulative, 0, reason: '但確實練過');
    });

    test('有氧的所屬肌群為空值，不重設任何維度', () {
      final s = AppState();
      final before = {
        for (final d in Dim.values) d: s.decayTimers[d]!.lastTrainedDate
      };
      s.startWorkout(blankPlan);
      s.addExerciseToSession(
          kCardioExercises.firstWhere((e) => e.dim == null),
          const [PlannedSet(0, 1)]);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      for (final d in Dim.values) {
        expect(s.decayTimers[d]!.lastTrainedDate, before[d]);
      }
    });
  });

  group('回歸任務與部分回復', () {
    test('「能力值已退步」是回歸任務的唯一觸發源', () {
      final s = AppState();
      expect(s.returnTaskAssigned, isTrue);
      expect(s.decayLog, isNotEmpty);
      expect(s.decayTimers[s.returnTaskDim]!.cumulative, greaterThan(0));
    });

    test('六維各自回復累積退步量的 50%，不論該維是否被訓練', () {
      final s = AppState();
      final before = {for (final d in Dim.values) d: s.points[d]!};
      final cum = {
        for (final d in Dim.values) d: s.decayTimers[d]!.cumulative
      };
      s.viewReturnTask();
      final rec = s.completeReturnTask();

      for (final d in Dim.values) {
        final want = (cum[d]! * kRecoverRatio).round();
        expect(s.points[d], before[d]! + want, reason: dimNames[d]);
        if (want > 0) expect(rec[d], want);
      }
      expect(rec.keys, contains(Dim.arms), reason: '回歸任務沒練到手，仍須回復');
    });

    test('回復後不超過退步前水準，且中斷前點數的推導式維持成立', () {
      final s = AppState();
      final before = {
        for (final d in Dim.values) d: s.pointsBeforeInterruption(d)
      };
      s.viewReturnTask();
      s.completeReturnTask();
      for (final d in Dim.values) {
        expect(s.points[d], lessThanOrEqualTo(before[d]!));
        expect(s.pointsBeforeInterruption(d), before[d]);
      }
    });

    test('時限起算時戳為空值者，逾期判定不啟動', () {
      final s = AppState();
      expect(s.returnTaskViewedAt, isNull);
      s.advanceDemoClock(const Duration(days: 60));
      expect(s.returnTaskAssigned, isTrue, reason: '沒看過就不會逾期');
    });

    test('連續 3 次逾期後停止指派，再次訓練即重新啟動', () {
      final s = AppState();
      for (var i = 0; i < 3; i++) {
        s.viewReturnTask();
        s.advanceDemoClock(const Duration(days: 10));
      }
      expect(s.returnTaskOverdueStreak, 3);
      s.advanceDemoClock(const Duration(days: 30));
      expect(s.returnTaskAssigned, isFalse, reason: '第 4 次不再指派');

      s.startWorkout(blankPlan);
      s.addExerciseToSession(ex('plank'), const [PlannedSet(0, 30)]);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.returnTaskOverdueStreak, 0);
    });
  });

  group('退步參數為平台級可調', () {
    setUp(() => platformConfig.reset());
    tearDown(() => platformConfig.reset());

    test('調小退步間隔，退步立刻變快', () {
      final a = AppState();
      final n = a.decayLog.length;
      platformConfig.group('ability').param('decayHours').value = 24;
      final b = AppState();
      expect(b.decayLog.length, greaterThan(n));
    });

    test('不變條件擋下不合法的退步參數', () {
      final g = platformConfig.group('ability');
      expect(g.invariant!({...g.values, 'decayPct': 1.0}), isNotNull);
      expect(g.invariant!({...g.values, 'decayHours': 0}), isNotNull);
      expect(g.invariant!({...g.values, 'floorDrop': 6}), isNotNull);
      // 回復比例須嚴格小於 1：Postcondition 為「不回復至退步前水準」。
      expect(g.invariant!({...g.values, 'recover': 1.0}), isNotNull);
      expect(g.invariant!(g.values), isNull);
    });
  });

  group('退步狀態頁', () {
    testWidgets('六個計時器各自列出，快轉後腿也退步', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('能力值退步狀態'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      expect(find.byType(DecayScreen), findsOneWidget);
      final page = find
          .descendant(
              of: find.byType(DecayScreen), matching: find.byType(Scrollable))
          .first;
      for (final d in Dim.values) {
        expect(find.text(dimNames[d]!), findsOneWidget);
      }
      // 肩 12 天、手 26 天、核心 46 天已退步；胸 0 天、背 2 天、腿 5 天尚未。
      expect(find.textContaining('本次中斷已退'), findsNWidgets(3));
      expect(find.text('退步預告'), findsOneWidget, reason: '腿在第 5 天');

      final btn = find.text('＋10 天');
      await t.scrollUntilVisible(btn, 200, scrollable: page);
      await t.pumpAndSettle();
      await t.tap(btn);
      await t.pumpAndSettle();

      await t.scrollUntilVisible(find.text('胸'), -200, scrollable: page);
      await t.pumpAndSettle();
      // 背與腿雙雙跨過 240 小時；胸走到第 10 天（日界 04:00 使其為 236 小時）仍未退。
      expect(find.textContaining('本次中斷已退'), findsNWidgets(5));
      expect(find.text('退步預告'), findsOneWidget, reason: '換成胸了');
    });
  });
}
