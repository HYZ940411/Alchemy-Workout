import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/train/preferred_times_screen.dart';
import 'package:fitness_app/screens/train/rate_experience_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('偏好訓練時段：結構與粒度', () {
    test('粒度 30 分鐘，非整點刻度的區間不成立', () {
      expect(const TimeRange(19 * 60, 21 * 60).valid, isTrue);
      expect(const TimeRange(19 * 60 + 10, 21 * 60).valid, isFalse);
    });

    test('區間不得跨日，也不得起訖顛倒', () {
      expect(const TimeRange(23 * 60, 25 * 60).valid, isFalse);
      expect(const TimeRange(21 * 60, 19 * 60).valid, isFalse);
      expect(const TimeRange(23 * 60, kMinutesPerDay).valid, isTrue);
    });

    test('重疊與相鄰的區間合併成一段', () {
      final p = PreferredTimes([
        [
          const TimeRange(19 * 60, 20 * 60),
          const TimeRange(20 * 60, 21 * 60), // 相鄰
          const TimeRange(9 * 60, 10 * 60),
          const TimeRange(9 * 60 + 30, 11 * 60), // 重疊
        ],
        [], [], [], [], [], [],
      ]);
      expect(p.byDay[0], [
        const TimeRange(9 * 60, 11 * 60),
        const TimeRange(19 * 60, 21 * 60),
      ]);
    });

    test('七天各自獨立，某日為空即該日不發提醒', () {
      final p = PreferredTimes.empty()
          .withRange(2, const TimeRange(7 * 60, 8 * 60));
      expect(p.byDay[2].length, 1);
      expect(p.byDay[0], isEmpty);
      expect(p.filledDays, 1);
      expect(p.isEmpty, isFalse);
    });
  });

  group('跳過偏好時段的效果', () {
    test('跳過者七天皆空，在累積足夠紀錄前不發訓練提醒', () {
      // 兩條來源都要斷掉才測得到「不發」：偏好時段為空（跳過），
      // 且最近 4 週紀錄不足推算門檻。假資料的訓練紀錄已達門檻，先清掉。
      final s = AppState()..history.clear();
      expect(s.preferredTimes.isEmpty, isTrue);
      expect(s.recentWorkoutsIn4Weeks,
          lessThan(kReminderInferMinWorkouts));
      expect(s.reminderSource, contains('目前不發送訓練提醒'));
    });

    test('填了就依偏好時段發', () {
      // 紀錄不足時才輪到偏好時段 —— 假資料的訓練紀錄已達推算門檻，
      // 不清掉的話這條測到的是推算那一條。
      final s = AppState()..history.clear();
      s.setPreferredTimes(PreferredTimes.empty()
          .withRange(0, const TimeRange(19 * 60, 21 * 60)));
      expect(s.reminderSource, contains('偏好時段'));
    });

    test('最近 4 週紀錄夠多時改由系統推算，不再看偏好欄位', () {
      final s = AppState();
      final today = DateTime.now();
      for (var i = 0; i < kReminderInferMinWorkouts; i++) {
        s.history.add(HistoryEntry(
            today.subtract(Duration(days: i)), '補的', 1000, 60, 300, const []));
      }
      expect(s.reminderSource, contains('推算'));
    });
  });

  group('訓練體驗評分', () {
    test('星等必填且限 1–5', () {
      final s = AppState();
      expect(s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 0),
          isFalse);
      expect(s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 6),
          isFalse);
      expect(s.noviceRating, isNull);
      expect(s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 4),
          isTrue);
      expect(s.noviceRating!.stars, 4);
    });

    test('每人每個對象終身僅一筆 —— 再評是覆蓋，不是多一筆', () {
      final s = AppState()
        ..rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 4,
            feedback: '還行');
      s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 2);
      expect(s.experienceRatings.length, 1);
      expect(s.noviceRating!.stars, 2);
      expect(s.noviceRating!.feedback, isNull, reason: '修改覆蓋原值');
    });

    test('文字回饋選填，可為空值', () {
      final s = AppState()
        ..rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 5);
      expect(s.noviceRating!.feedback, isNull);
    });

    test('唯一鍵含對象類型與對象 ID —— 不同對象各自一筆', () {
      final s = AppState()
        ..rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 5)
        ..rateExperience(RatingTarget.trainingPlan, 'p1', 3);
      expect(s.experienceRatings.length, 2);
      expect(s.ratingFor(RatingTarget.trainingPlan, 'p1')!.stars, 3);
    });
  });

  group('走一遍收尾兩張', () {
    Future<void> openTasks(WidgetTester t) async {
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
          of: find.byType(MoreScreen), matching: find.text('新手 / 回歸任務'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
    }

    /// 走完新手任務，停在引導收尾第一步。
    Future<void> finishNovice(WidgetTester t) async {
      await openTasks(t);
      await t.tap(find.text('開始新手任務'));
      await t.pumpAndSettle();
      await t.tap(find.text('徒手深蹲'));
      await t.pumpAndSettle();
      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();
      await t.tap(find.text('完成這項任務'));
      await t.pumpAndSettle();
    }

    testWidgets('收尾第一步是偏好訓練時段，可跳過且不擋領獎', (t) async {
      await finishNovice(t);
      expect(find.byType(PreferredTimesScreen), findsOneWidget);
      expect(find.text('稍後再選'), findsOneWidget);

      await t.tap(find.text('稍後再選'));
      await t.pumpAndSettle();
      // 跳過之後獎勵照樣領得到
      expect(find.textContaining('領取獎勵'), findsOneWidget);
      expect(find.text('未填 —— 目前不發訓練提醒'), findsOneWidget);
    });

    testWidgets('加一個區間，七天中只有那天有值', (t) async {
      await finishNovice(t);
      final list = find
          .descendant(
              of: find.byType(PreferredTimesScreen),
              matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(find.text('星期三'), 200, scrollable: list);
      await t.pumpAndSettle();

      await t.tap(find.descendant(
          of: find.ancestor(
              of: find.text('星期三'), matching: find.byType(Row)).first,
          matching: find.text('＋ 新增區間')));
      await t.pumpAndSettle();
      await t.tap(find.text('加入'));
      await t.pumpAndSettle();
      expect(find.text('19:00–21:00'), findsOneWidget);

      await t.scrollUntilVisible(find.text('完成'), 200, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(find.text('完成'));
      await t.pumpAndSettle();
      expect(find.text('已填 1 天'), findsOneWidget);
    });

    testWidgets('評分可送出也可修改，星等沒選不給送', (t) async {
      await finishNovice(t);
      await t.tap(find.text('稍後再選'));
      await t.pumpAndSettle();

      await t.tap(find.text('新手任務體驗評分'));
      await t.pumpAndSettle();
      expect(find.byType(RateExperienceScreen), findsOneWidget);
      final send = find.widgetWithText(AppButton, '送出評分');
      expect(t.widget<AppButton>(send).onPressed, isNull, reason: '星等必填');

      await t.tap(find.byIcon(Icons.star_border).at(3));
      await t.pumpAndSettle();
      expect(find.text('4 星'), findsOneWidget, reason: '不可只靠圖形');
      await t.tap(send);
      await t.pumpAndSettle();
      expect(find.text('4 星　·　可修改'), findsOneWidget);

      // 再進去是修改，不是多一筆
      await t.tap(find.text('新手任務體驗評分'));
      await t.pumpAndSettle();
      expect(find.text('修改評分'), findsOneWidget);
      await t.tap(find.byIcon(Icons.star_border).first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '更新評分'));
      await t.pumpAndSettle();
      expect(find.text('5 星　·　可修改'), findsOneWidget);
    });
  });
}
