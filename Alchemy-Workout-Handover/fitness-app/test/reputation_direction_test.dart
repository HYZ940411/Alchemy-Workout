// 聲望是「被評的人」的數字。
//
// 先前評分一律走同一個 [_bumpReputation]，於是我以**學徒**身分給教官
// 五顆星，加到的是**我自己**的聲望與帶徒上限。更糟的是連教官都不必有：
// myInstructor 為空時照樣評得下去，憑空給自己加 12 點。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一位有教官、且該週有互動的學徒。
AppState apprenticeOf(AppState s) {
  final i = s.instructors.first;
  s.myInstructor = i;
  s.weeklyQuestionCount = 1; // 該週須有互動方可評分
  return s;
}

void main() {
  group('我評我的教官', () {
    test('加的是他的聲望，不是我的', () {
      final s = apprenticeOf(AppState());
      final mine = s.instructorReputation;
      final theirs = s.myInstructor!.reputation;

      expect(s.rateWeeklyInteraction(5), isTrue);
      expect(s.myInstructor!.reputation, greaterThan(theirs));
      expect(s.instructorReputation, mine,
          reason: '我給別人五顆星，我自己的聲望沒有理由改變');
    });

    test('也不會撐大我的帶徒上限', () {
      final s = apprenticeOf(AppState());
      final cap = s.apprenticeCap;
      final peak = s.peakReputation;
      s.rateWeeklyInteraction(5);
      expect(s.peakReputation, peak);
      expect(s.apprenticeCap, cap,
          reason: '評分是給教官的，不該讓評分者多收一個徒弟');
    });

    test('沒有教官就評不了 —— 先前這裡憑空加 12 點', () {
      final s = AppState();
      s.myInstructor = null;
      expect(s.rateWeeklyInteraction(5), isFalse);
      expect(s.instructorReputation, 0);
      expect(s.peakReputation, 0);
    });

    test('任務評分同理', () {
      final s = apprenticeOf(AppState());
      final t = s.mentorTasks
          .firstWhere((x) => x.state != MentorTaskState.assigned);
      final mine = s.instructorReputation;
      final theirs = s.myInstructor!.reputation;
      expect(s.rateMentorTask(t, 5), RateResult.counted);
      expect(s.myInstructor!.reputation, greaterThan(theirs));
      expect(s.instructorReputation, mine);
    });

    test('沒有教官就評不了任務', () {
      final s = AppState();
      s.myInstructor = null;
      final t = s.mentorTasks
          .firstWhere((x) => x.state != MentorTaskState.assigned);
      expect(s.rateMentorTask(t, 5), RateResult.rejected);
    });
  });

  group('我的學徒評我', () {
    AppState instructor() {
      final s = AppState()..isInstructor = true;
      s.apprentices
        ..clear()
        ..addAll([
          const Apprentice(
              name: '小明', rank: 12, ability: {}, recentWorkouts: []),
        ]);
      return s;
    }

    test('這才是會動到我聲望的那一條', () {
      final s = instructor();
      final before = s.instructorReputation;
      expect(s.apprenticeRatesMe('小明', 5), isTrue);
      expect(s.instructorReputation, greaterThan(before));
    });

    test('一星會扣，但不低於 0', () {
      final s = instructor();
      s.instructorReputation = 1;
      s.apprenticeRatesMe('小明', 1);
      expect(s.instructorReputation, greaterThanOrEqualTo(0));
    });

    test('不是我的學徒評不了', () {
      final s = instructor();
      final before = s.instructorReputation;
      expect(s.apprenticeRatesMe('路人', 5), isFalse);
      expect(s.instructorReputation, before);
    });

    test('不是教官就沒有聲望可評', () {
      final s = AppState()..isInstructor = false;
      expect(s.apprenticeRatesMe('小明', 5), isFalse);
    });

    test('每位學徒每週最多 2 次計入聲望，超出仍可評但不計分', () {
      final s = instructor();
      final start = s.instructorReputation;
      expect(s.apprenticeRatesMe('小明', 5), isTrue);
      final after1 = s.instructorReputation;
      expect(s.apprenticeRatesMe('小明', 5), isTrue);
      final after2 = s.instructorReputation;
      expect(after2, greaterThan(after1));
      expect(s.apprenticeRatesMe('小明', 5), isTrue,
          reason: '該擋的是計分，不是行為');
      expect(s.instructorReputation, after2, reason: '第 3 次不計入聲望');
      expect(after1, greaterThan(start));
    });

    test('上限是每人 2 次，不是全部學徒合計 2 次', () {
      final s = instructor();
      s.apprentices.add(const Apprentice(
          name: '小華', rank: 15, ability: {}, recentWorkouts: []));
      s.apprenticeRatesMe('小明', 5);
      s.apprenticeRatesMe('小明', 5);
      final after = s.instructorReputation;
      s.apprenticeRatesMe('小華', 5);
      expect(s.instructorReputation, greaterThan(after),
          reason: '小明用完次數不該影響小華');
    });

    test('週互動評分每人每週一次', () {
      final s = instructor();
      expect(s.apprenticeRatesMe('小明', 5, weekly: true), isTrue);
      final after = s.instructorReputation;
      expect(s.apprenticeRatesMe('小明', 5, weekly: true), isFalse);
      expect(s.instructorReputation, after);
    });

    test('跨週之後次數重置', () {
      final s = instructor();
      s.apprenticeRatesMe('小明', 5);
      s.apprenticeRatesMe('小明', 5);
      s.apprenticeRatesMe('小明', 5); // 第 3 次不計分
      final capped = s.instructorReputation;
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.apprenticeTaskRatings, isEmpty, reason: '新的一週從零起算');
      s.apprenticeRatesMe('小明', 5);
      expect(s.instructorReputation, greaterThan(capped));
    });

    test('帶徒上限隨歷史最高聲望成長，不隨下降而縮', () {
      final s = instructor();
      for (var i = 0; i < 12; i++) {
        s.apprenticeRatesMe('小明', 5, weekly: true);
        s.advanceDemoClock(const Duration(days: 8));
      }
      final peak = s.peakReputation;
      final cap = s.apprenticeCap;
      expect(peak, greaterThan(0));
      s.instructorReputation = 0;
      expect(s.apprenticeCap, cap, reason: '上限看歷史最高，不看當下值');
    });
  });
}
