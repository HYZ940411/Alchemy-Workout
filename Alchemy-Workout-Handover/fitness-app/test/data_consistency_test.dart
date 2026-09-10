// 「存了一份、但別處另有一份講同一件事」的掃描。
//
// 這一輪的 bug 都是這個形狀：checkInStreak 與簽到日曆對不起來、
// lastCheckInDate 說從沒簽到過但有 9 天紀錄、followTotal 從 0 起算但
// 一開始就關注著三個人。共通點是**畫面照樣顯示、不會報錯**。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('連續訓練', () {
    test('上次訓練日期就是訓練歷史裡最晚的那一天', () {
      final s = AppState();
      expect(s.history, isNotEmpty);
      final latest = s.history
          .map((h) => businessDate(h.date))
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(s.lastTrainedDate, latest,
          reason: '狀態說今天練過、歷史最晚卻是昨天，而首頁還擺著一顆「開始訓練」');
    });

    test('今天還沒練 —— 首頁那顆「開始訓練」才站得住腳', () {
      final s = AppState();
      expect(s.lastTrainedDate.isBefore(businessDate(s.now)), isTrue);
    });

    test('連續訓練天數撐得起來：最近 N 天在歷史裡逐日都有', () {
      final s = AppState();
      final days = s.history.map((h) => businessDate(h.date)).toSet();
      var d = s.lastTrainedDate;
      for (var i = 0; i < s.trainingStreakDays; i++) {
        expect(days.contains(d), isTrue,
            reason: '首頁寫「連續訓練 ${s.trainingStreakDays} 天」，'
                '但訓練歷史缺了 ${d.month}/${d.day}');
        d = d.subtract(const Duration(days: 1));
      }
    });

    test('練一場之後兩者仍然一致', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.advanceDemoClock(const Duration(seconds: 45));
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);
      final latest = s.history
          .map((h) => businessDate(h.date))
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(s.lastTrainedDate, latest);
      expect(s.lastTrainedDate, businessDate(s.now));
    });
  });

  group('連續簽到', () {
    test('連續天數與簽到紀錄逐日數出來的一致', () {
      final s = AppState();
      var n = 0;
      var d = businessDate(s.now);
      if (s.checkInMethodOn(d) == null) {
        d = d.subtract(const Duration(days: 1));
      }
      while (s.checkInMethodOn(d) != null) {
        n += 1;
        d = d.subtract(const Duration(days: 1));
      }
      expect(s.checkInStreak, n);
    });

    test('歷史最長連續天數不小於當前連續天數', () {
      final s = AppState();
      expect(s.checkInLongest, greaterThanOrEqualTo(s.checkInStreak));
    });

    test('累計簽到天數不小於有紀錄的天數', () {
      final s = AppState();
      expect(s.checkInTotal, greaterThanOrEqualTo(s.checkInRecords.length));
    });
  });

  group('社群計數', () {
    test('曾經關注過的次數不少於現在關注中的人數', () {
      final s = AppState();
      expect(s.followTotal, greaterThanOrEqualTo(s.following.length));
    });

    test('歷史最高粉絲數不少於現在的粉絲數', () {
      final s = AppState();
      expect(s.peakFollowerCount, greaterThanOrEqualTo(s.followers.length));
    });

    test('互動的終身計數不少於畫面上數得出來的', () {
      final s = AppState();
      final myPosts =
          s.posts.where((p) => p.author == s.displayName && !p.deleted).length;
      expect(s.interactionTotals['發文']!, greaterThanOrEqualTo(myPosts));
    });
  });

  group('累積訓練', () {
    test('累積訓練次數不少於天數 —— 一日兩場計 2 次 1 天', () {
      final s = AppState();
      expect(s.totalWorkouts, greaterThanOrEqualTo(s.totalWorkoutDays));
    });

    test('累積訓練天數不少於歷史裡有訓練的天數', () {
      final s = AppState();
      final days = s.history.map((h) => businessDate(h.date)).toSet();
      expect(s.totalWorkoutDays, greaterThanOrEqualTo(days.length));
    });
  });

  group('團隊', () {
    test('鎖定的人數分組不小於當前成員數 —— 分組於週期起點鎖定，之後只會減員', () {
      final s = AppState();
      final t = s.myTeam;
      if (t == null) return;
      expect(t.lockedGroupSize, greaterThanOrEqualTo(t.members.length));
    });
  });
}
