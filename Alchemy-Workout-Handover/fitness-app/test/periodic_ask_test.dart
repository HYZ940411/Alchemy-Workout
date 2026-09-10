import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

const kBase = Size(393 * 3, 852 * 3);

AppState _fresh() {
  final s = AppState();
  // 兩項都剛填過，計時歸零。
  s.weightUpdatedAt = s.now;
  s.surveyUpdatedAt = s.now;
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('距上次填入體重滿 14 天者才問', () {
    test('未滿 14 天不問', () {
      final s = _fresh();
      expect(s.weightAskDue, isFalse);
      s.advanceDemoClock(const Duration(days: 13));
      expect(s.weightAskDue, isFalse);
    });

    test('滿 14 天就問', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 14));
      expect(s.weightAskDue, isTrue);
    });

    test('填了就重新計時', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 20));
      s.updateWeight(70);
      expect(s.bodyweightKg, 70);
      expect(s.weightAskDue, isFalse);
      s.advanceDemoClock(const Duration(days: 13));
      expect(s.weightAskDue, isFalse);
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.weightAskDue, isTrue);
    });

    test('跳過：沿用上次的值，該次詢問週期內不再問', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 20));
      final before = s.bodyweightKg;
      s.skipWeightAsk();
      expect(s.bodyweightKg, before, reason: '沿用上次的值');
      expect(s.weightAskDue, isFalse);
    });

    test('跳過只擋這一輪，下個週期照樣問', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 20));
      s.skipWeightAsk();
      expect(s.weightAskDue, isFalse);
      // 距上次「填入」已過很久，跳過不等於填了。
      s.advanceDemoClock(const Duration(days: 14));
      expect(s.weightAskDue, isTrue, reason: '跳過不是永久關閉');
    });
  });

  group('距上次填寫滿 90 天者才問問卷四欄位', () {
    test('週期為 90 天，不是 14 天', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 60));
      expect(s.surveyAskDue, isFalse);
      s.advanceDemoClock(const Duration(days: 30));
      expect(s.surveyAskDue, isTrue);
    });

    test('跳過：沿用原值，該週期內不再問', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 100));
      final before = (s.daysPerWeek, s.duration, s.commonGoal, s.experience);
      s.skipSurveyAsk();
      expect((s.daysPerWeek, s.duration, s.commonGoal, s.experience), before);
      expect(s.surveyAskDue, isFalse);
    });

    test('任一欄位更新後立即重新推薦並自動替換當前計畫', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 100));
      s.currentPlan = s.platformPlans.last;
      s.updateSurvey(experience: '新手（未滿 6 個月）', commonGoal: '培養運動習慣');
      expect(s.experience, '新手（未滿 6 個月）');
      expect(s.currentPlan, s.recommendCurrentPlan());
      expect(s.currentPlan, isNot(s.platformPlans.last));
      expect(s.surveyAskDue, isFalse);
    });

    test('進行中的訓練不受影響 —— 快照已與來源脫鉤', () {
      final s = _fresh();
      final plan = s.platformPlans.first;
      s.startWorkout(plan);
      final before = s.session!.plan;
      s.advanceDemoClock(const Duration(days: 100));
      s.updateSurvey(commonGoal: '減重');
      expect(s.session, isNotNull);
      expect(s.session!.plan, same(before));
    });
  });

  group('兩者皆不得為簽到的 Precondition', () {
    test('跳過體重仍可正常簽到，連續天數不中斷', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 20));
      final streak = s.checkInStreak;
      s.skipWeightAsk();
      s.checkIn();
      expect(s.checkedInToday, isTrue);
      expect(s.checkInStreak, isNot(0));
      expect(s.checkInStreak, greaterThanOrEqualTo(1));
      expect(streak, isNotNull);
    });

    test('兩項都沒回答也簽得了', () {
      final s = _fresh();
      s.advanceDemoClock(const Duration(days: 100));
      expect(s.weightAskDue, isTrue);
      expect(s.surveyAskDue, isTrue);
      final coins = s.coins;
      s.checkIn();
      expect(s.checkedInToday, isTrue);
      expect(s.coins, greaterThan(coins), reason: '簽到獎勵照發');
    });
  });

  group('簽到畫面（畫面）', () {
    testWidgets('到期時兩張卡都在，且簽到鈕沒有被擋住', (t) async {
      t.view.physicalSize = kBase;
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('每日簽到 / 每日任務'), 300);
      await t.pumpAndSettle();
      await t.tap(find.text('每日簽到 / 每日任務'));
      await t.pumpAndSettle();

      expect(find.text('順便更新體重？'), findsOneWidget);
      expect(find.text('這三個月，練法有變嗎？'), findsOneWidget);
      expect(find.text('這次跳過'), findsNWidgets(2));
      // 詢問卡在上、簽到卡在下，兩者同頁；簽到不因詢問而消失。
      await t.drag(find.text('順便更新體重？'), const Offset(0, -900));
      await t.pumpAndSettle();
      expect(find.text('今天還沒簽到'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
