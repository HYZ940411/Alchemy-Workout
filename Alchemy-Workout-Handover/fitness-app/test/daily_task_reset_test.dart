import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('每日 04:00 重置，與簽到同一個換日時點', () {
    test('同一天不重置', () {
      final s = AppState();
      expect(s.resetDailyTasksIfDue(), isFalse);
      s.advanceDemoClock(const Duration(hours: 1));
      expect(s.resetDailyTasksIfDue(), isFalse);
    });

    test('跨過換日時點才重置', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 1));
      // advanceDemoClock 已經結算過，再呼叫應為冪等。
      expect(s.resetDailyTasksIfDue(), isFalse);
    });

    test('冪等：同一當地日期重複觸發不會重置兩次', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 1));
      final before = s.mailbox.length;
      s.resetDailyTasksIfDue();
      s.resetDailyTasksIfDue();
      expect(s.mailbox.length, before);
    });
  });

  group('重置時的進度與獎勵', () {
    test('進度歸零，計數範圍限當日', () {
      final s = AppState();
      s.checkIn();
      expect(s.dailyTasks.any((t) => t.progress > 0), isTrue);
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.dailyTasks.every((t) => t.progress == 0), isTrue);
      expect(s.dailyTasks.every((t) => !t.claimed), isTrue);
    });

    test('已完成但未領取的獎勵補發至信箱，不作廢', () {
      final s = AppState();
      for (final t in s.dailyTasks) {
        t.progress = t.target;
      }
      final unclaimed = s.dailyTasks.where((t) => !t.claimed).length;
      expect(unclaimed, greaterThan(0));
      final before = s.mailbox.length;

      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, before + unclaimed);
      expect(s.mailbox.first.source, contains('每日任務未領取'));
      expect(s.mailbox.first.coins, kDailyTaskCoin,
          reason: '補發的是那一項真正的獎勵，不是一個寫死的數字');
    });

    test('已領取的不重複補發', () {
      final s = AppState();
      for (final t in s.dailyTasks) {
        t.progress = t.target;
      }
      s.claimAllTasks();
      final before = s.mailbox.length;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, before, reason: '已入帳的不該再進一次信箱');
    });

    test('未完成的不補發 —— 補的是已掙得的獎勵，不是參加獎', () {
      final s = AppState();
      for (final t in s.dailyTasks) {
        t.progress = 0;
      }
      final before = s.mailbox.length;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, before);
    });

    test('信箱獎勵可領取入帳', () {
      final s = AppState();
      for (final t in s.dailyTasks) {
        t.progress = t.target;
      }
      s.advanceDemoClock(const Duration(days: 1));
      final m = s.mailbox.firstWhere((m) => m.source.contains('每日任務未領取'));
      expect(m.claimed, isFalse);
      final coins = s.coins;
      s.claimMail(m);
      expect(m.claimed, isTrue);
      expect(s.coins, coins + m.coins, reason: '領到的要跟信箱上寫的一樣');
    });

    test('全部完成的加碼旗標一併歸零，隔天才拿得到第二次', () {
      int completeAllAndMeasure(AppState s) {
        for (final t in s.dailyTasks) {
          t.progress = t.target - 1;
        }
        final before = s.weeklyScore;
        for (final t in s.dailyTasks) {
          s.bumpTaskForTest(t.sourceEvent);
        }
        return s.weeklyScore - before;
      }

      final s = AppState();
      final day1 = completeAllAndMeasure(s);
      // 每項 10 分 ＋ 全部完成加碼 20 分。
      expect(day1, s.dailyTasks.length * 10 + 20);

      s.advanceDemoClock(const Duration(days: 1));
      final day2 = completeAllAndMeasure(s);
      expect(day2, day1, reason: '加碼分數每天各給一次，旗標必須跟著重置歸零');
    });
  });

  group('重抽', () {
    test('自任務池抽取，數量為每日抽取數量', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.dailyTasks.length,
          lessThanOrEqualTo(platformConfig.i('taskPool', 'drawCount')));
      expect(s.dailyTasks, isNotEmpty);
    });
  });
}
