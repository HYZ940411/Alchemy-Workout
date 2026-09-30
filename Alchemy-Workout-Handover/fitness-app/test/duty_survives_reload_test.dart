// 確認過的聲明，重新整理之後還算數；而做不到的 Command 不可以說做到了。
//
// 2026-09-30 的根因，找了四輪才找到：
//
//   · `instructorDutyVersion` 與 `mentorDisclaimerVersion` **不進存檔**
//   · 於是每次重新整理，`instructorDutyNeeded` 就回到 true
//   · `assignMentorTask()` 撞上守衛，靜靜 `return`
//   · 而它回 `void` —— 畫面不管做了沒都跳「已指派『◯◯』」
//
// 所以使用者看到的是：toast 說成功、本機清單沒東西、雲端沒東西、
// 連寫入報告都沒有一行。**四個地方同時沉默。**

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

AppState _instructor() => AppState(demo: false)
  ..myUid = 'u-教官'
  ..isInstructor = true;

AppState _apprentice() => AppState(demo: false)
  ..myUid = 'u-學徒'
  ..myInstructor = Instructor(
    name: '老王',
    uid: 'u-教官',
    rank: 40,
    reputation: 100,
    apprentices: 1,
    apprenticeCap: 4,
    ability: const {},
    specialties: const ['增肌'],
    avgRating: 0,
    ratingCount: 0,
  );

void main() {
  group('指導責任聲明要留得住', () {
    test('前提：沒確認就指派不出去', () {
      final s = _instructor();
      expect(s.instructorDutyNeeded, isTrue);
      expect(s.assignMentorTask('練腿', '', apprenticeUid: 'u-學徒'), isFalse);
      expect(s.mentorTasks, isEmpty);
    });

    test('確認之後指派得出去', () {
      final s = _instructor()..confirmInstructorDuty();
      expect(s.assignMentorTask('練腿', '', apprenticeUid: 'u-學徒'), isTrue);
    });

    test('重新整理之後還算數 —— 這就是整件事的根因', () {
      final before = _instructor()..confirmInstructorDuty();
      final after = _instructor()..applySnapshot(before.toSnapshot());

      expect(after.instructorDutyNeeded, isFalse,
          reason: '不進存檔的話，每次重新整理就退回「還沒確認」');
      expect(after.assignMentorTask('練腿', '', apprenticeUid: 'u-學徒'), isTrue);
    });

    test('沒確認過的人，重新整理之後仍然要確認', () {
      final before = _instructor();
      final after = _instructor()..applySnapshot(before.toSnapshot());
      expect(after.instructorDutyNeeded, isTrue);
    });
  });

  group('師徒免責聲明要留得住', () {
    test('前提：沒確認就提問不出去', () {
      final s = _apprentice();
      expect(s.mentorDisclaimerNeeded, isTrue);
      expect(s.askQuestion('深蹲膝蓋會痛'), isFalse);
      expect(s.questions, isEmpty);
    });

    test('重新整理之後還算數', () {
      final before = _apprentice()..confirmMentorDisclaimer();
      final after = _apprentice()..applySnapshot(before.toSnapshot());

      expect(after.mentorDisclaimerNeeded, isFalse);
      expect(after.askQuestion('深蹲膝蓋會痛'), isTrue);
    });
  });

  group('做不到的 Command 要說得出做不到', () {
    test('指派：回否，而且說得出原因', () {
      final s = _instructor();
      expect(s.assignMentorTask('練腿', '', apprenticeUid: 'u-學徒'), isFalse);
      expect(s.assignBlockedReason, contains('指導責任聲明'));
    });

    test('提問：回否，而且說得出原因', () {
      final s = _apprentice();
      expect(s.askQuestion('深蹲膝蓋會痛'), isFalse);
      expect(s.askBlockedReason, contains('免責聲明'));
    });

    test('標記完成：回否，而且說得出原因', () {
      final s = _apprentice();
      final t = MentorTask(id: 'mt-1', title: '練腿', detail: '');
      s.mentorTasks.add(t);
      expect(s.completeMentorTask(t), isFalse);
      expect(s.completeBlockedReason, contains('免責聲明'));
      expect(t.state, MentorTaskState.assigned, reason: '沒做就不該改狀態');
    });

    test('成功的時候回真 —— 否則畫面永遠報錯', () {
      final s = _apprentice()..confirmMentorDisclaimer();
      final t = MentorTask(id: 'mt-1', title: '練腿', detail: '');
      s.mentorTasks.add(t);
      expect(s.completeMentorTask(t), isTrue);
      expect(t.state, MentorTaskState.done);
    });
  });
}
