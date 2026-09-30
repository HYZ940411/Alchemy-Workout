// 「評得下去」與「有沒有計進教官的聲望」是兩件事。
//
// 使用者 2026-09-30 問：「如果我評分了好幾個任務，那個『已評分，
// 教官聲望 ◯◯』是不是應該及時變化讓學徒看到」——問對了，
// 而查下去發現不只是顯示延遲：
//
//   · `taskRatingsThisWeek` **只在有計分的那個分支裡加一**
//   · 所以它永遠不會超過上限 2
//   · 而畫面的條件寫的是 `> 2` —— **那個分支從來沒跑到過**
//   · 於是第三則之後聲望確實不再動，toast 照樣報一個沒變的數字
//
// 「條件永遠不可能成立」在這個專案是第二次（前一次是 2H）。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一位有教官、手上有一堆已完成任務的學徒。
AppState _apprentice({int tasks = 5}) {
  final s = AppState();
  // 示範帳號預設沒有教官 —— 與 `reputation_direction_test` 同一個接法。
  s.myInstructor = s.instructors.first;
  s.mentorTasks
    ..clear()
    ..addAll([
      for (var i = 0; i < tasks; i++)
        MentorTask(
          id: 'mt-$i',
          title: '任務 $i',
          detail: '',
          state: MentorTaskState.done,
        ),
    ]);
  s.taskRatingsThisWeek = 0;
  return s;
}

void main() {
  group('評分結果要說得出真的發生了什麼', () {
    test('前幾則計進聲望', () {
      final s = _apprentice();
      for (var i = 0; i < kMentorTaskRatingWeeklyCap; i++) {
        final before = s.myInstructor!.reputation;
        expect(s.rateMentorTask(s.mentorTasks[i], 5), RateResult.counted);
        expect(s.myInstructor!.reputation, greaterThan(before),
            reason: '第 ${i + 1} 則該計分');
      }
    });

    test('超過上限之後，回 capReached 而不是假裝計了', () {
      final s = _apprentice();
      for (var i = 0; i < kMentorTaskRatingWeeklyCap; i++) {
        s.rateMentorTask(s.mentorTasks[i], 5);
      }
      final before = s.myInstructor!.reputation;

      final r = s.rateMentorTask(s.mentorTasks[kMentorTaskRatingWeeklyCap], 5);

      expect(r, RateResult.capReached,
          reason: '原本回 true，畫面因此照樣報一個聲望數字');
      expect(s.myInstructor!.reputation, before, reason: '聲望確實沒動');
      expect(s.mentorTasks[kMentorTaskRatingWeeklyCap].rating, 5,
          reason: '任務照樣算評過 —— 該擋的是計分，不是行為');
    });

    test('那個計數器永遠不會超過上限 —— 所以 `> 上限` 是死的條件', () {
      final s = _apprentice(tasks: 10);
      for (final t in s.mentorTasks) {
        s.rateMentorTask(t, 5);
      }
      expect(s.taskRatingsThisWeek, kMentorTaskRatingWeeklyCap);
      expect(s.taskRatingsThisWeek > kMentorTaskRatingWeeklyCap, isFalse,
          reason: '畫面原本靠這個判斷「額度用完了」，而它永遠不成立');
      expect(s.taskRatingCapReached, isTrue, reason: '該用的是這個');
    });

    test('改分數：評得動，但不重複計入聲望', () {
      final s = _apprentice();
      final t = s.mentorTasks.first;
      expect(s.rateMentorTask(t, 3), RateResult.counted);
      final after = s.myInstructor!.reputation;

      expect(s.rateMentorTask(t, 5), RateResult.alreadyRated);
      expect(t.rating, 5, reason: '分數要改得動');
      expect(s.myInstructor!.reputation, after, reason: '同一則不重複計分');
    });

    test('評不下去的時候回 rejected', () {
      final s = _apprentice();
      final assigned = MentorTask(id: 'mt-x', title: '還沒完成', detail: '');
      s.mentorTasks.add(assigned);
      expect(s.rateMentorTask(assigned, 5), RateResult.rejected);
      expect(s.rateMentorTask(s.mentorTasks.first, 9), RateResult.rejected);

      s.myInstructor = null;
      expect(s.rateMentorTask(s.mentorTasks.first, 5), RateResult.rejected);
    });

    test('四種結果只有 rejected 不算評過', () {
      expect(RateResult.counted.ok, isTrue);
      expect(RateResult.capReached.ok, isTrue);
      expect(RateResult.alreadyRated.ok, isTrue);
      expect(RateResult.rejected.ok, isFalse);
    });
  });
}
