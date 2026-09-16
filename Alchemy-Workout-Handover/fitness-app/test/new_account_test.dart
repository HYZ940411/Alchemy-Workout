import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/state/app_state.dart';

/// 把註冊問卷填到可完成。
AppState signedUp() {
  final s = AppState();
  final d = s.signUpDraft
    ..nickname = '阿昶'
    ..gender = '男'
    ..birthday = DateTime(1995, 5, 5)
    ..heightCm = 175
    ..weightKg = 70
    ..daysPerWeek = 3
    ..duration = '30–60 分鐘'
    ..commonGoal = '增肌'
    ..experience = '半年以下';
  d.equipment
    ..clear()
    ..add('健身房');
  expect(d.complete, isTrue, reason: '10 項全填畢方可完成註冊');
  s.completeSignUp();
  return s;
}

void main() {
  group('使用者帳號已建立：兩個 Aggregate 一併產生', () {
    test('連續訓練 Aggregate：上次訓練日期為註冊日', () {
      final s = signedUp();
      expect(s.lastTrainedDate, s.registeredOn);
      expect(s.trainingStreakDays, 0);
      expect(s.totalWorkouts, 0);
      expect(s.totalWorkoutDays, 0);
    });

    test('能力值 Aggregate：六維為初始值，各維最後訓練日皆為註冊日', () {
      final s = signedUp();
      for (final d in Dim.values) {
        expect(s.points[d], kInitialPoints, reason: '${dimNames[d]} 不是初始值');
        expect(s.decayTimers[d]!.lastTrainedDate, s.registeredOn);
        expect(s.decayTimers[d]!.cumulative, 0);
      }
    });

    test('註冊獎勵：金幣 100 ＋ 補簽券 ×1，無經驗值', () {
      final s = signedUp();
      expect(s.coins, 100);
      expect(s.makeupTickets, 1);
      expect(s.totalExp, 0, reason: '註冊獎勵不含經驗值');
      expect(s.rank, 1, reason: '初始階級為 1');
    });

    test('不留下「階級 45、六維 10、零次訓練」這種自相矛盾的帳號', () {
      final s = signedUp();
      expect(s.checkInStreak, 0);
      expect(s.checkInTotal, 0);
      expect(s.lastCheckInDate, isNull);
      expect(s.weeklyScore, 0);
      expect(s.monthlyScore, 0);
      expect(s.punishment, isNull);
      expect(s.myViolations, 0);
    });

    test('分組留待首次計分時鎖定 —— 週期起點時他還不存在', () {
      final s = signedUp();
      expect(s.lockedRankGroup, isNull);
      expect(s.lockedMonthlyGroup, isNull);
    });

    test('推薦的訓練計畫依問卷產生', () {
      final s = signedUp();
      expect(s.currentPlan, isNotNull);
    });
  });

  group('從未訓練者走得完四道門檻', () {
    test('計時自註冊日的日界起算，跨得過 24 / 36 / 96 / 240', () {
      final s = signedUp();
      expect(hoursSinceBoundary(s.lastTrainedDate, s.now), 0);

      s.advanceDemoClock(const Duration(days: 2)); // ≥24
      expect(s.notifications.any((n) => n.sourceEvent == '中斷預告已發送'), isTrue);

      s.advanceDemoClock(const Duration(days: 1)); // ≥48 > 36
      expect(s.trainingStreakDays, 0);

      s.advanceDemoClock(const Duration(days: 2)); // ≥96
      expect(s.notifications.any((n) => n.sourceEvent == '退步預告已發送'), isTrue);
    });

    test('六維卡在下限，但滿 240 小時仍收得到回歸任務', () {
      final s = signedUp();
      // 六維皆為初始值 10 ＝ 退步下限，退步量恆為 0。
      for (final d in Dim.values) {
        expect(s.points[d], s.decayFloorFor(d),
            reason: '從未訓練者自始就在下限');
      }
      s.advanceDemoClock(Duration(hours: kDecayIntervalHours + 48));
      expect(s.returnTaskAssigned, isTrue,
          reason: '觸及下限的那一次仍照常產生 Event —— 那是回歸任務的唯一觸發源');
    });

    test('退步下限那一次只產生一次，其後不再重複', () {
      final s = signedUp();
      s.advanceDemoClock(Duration(hours: kDecayIntervalHours + 48));
      final n = s.decayLog.length;
      s.advanceDemoClock(Duration(hours: kDecayIntervalHours * 3));
      expect(s.decayLog.length, n,
          reason: '已觸及下限者不再產生「能力值已退步」，'
              '否則一年會累積 216 個沒有狀態改變的 Event');
    });

    test('完成回歸任務時累積退步量為 0，回復 0 點但獎勵照發', () {
      final s = signedUp();
      s.advanceDemoClock(Duration(hours: kDecayIntervalHours + 48));
      expect(s.completeReturnTask(), isEmpty, reason: '沒有退步量可回復');
      final r = s.claimReturnReward();
      expect(r, isNotNull, reason: '獎勵不因回復 0 點而不發');
      expect(r!.coins, greaterThan(0));
    });
  });
}
