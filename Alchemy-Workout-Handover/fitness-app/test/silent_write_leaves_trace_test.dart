// 即發即忘的雲端寫入，不可以連失敗都看不出來。
//
// 2026-09-30：教官指派任務，畫面跳「已指派『◯◯』」、任務出現在清單上，
// 而雲端那段關係底下**連 `tasks` 子集合都不存在**。查的時候分不出是
// 「沒送出」還是「送了被拒」—— 因為 `catchError((_) {})` 把兩者都吞了。
//
// 這是本專案第四次犯同一個錯（前三次：`quotaHint`、`inboundFailure`、
// 評分寫不上雲）。前三次各補了一個一次性的欄位，這次做成通用的。
//
// 三種結果都要留下痕跡，**尤其是第四種「根本沒送出」** ——
// 它原本與「成功」長得一模一樣。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

class _Mentor implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));

  /// 真表示每一次 `putTask` 都炸。
  bool failing = false;
  final List<String> written = [];

  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {
    if (failing) throw StateError('permission-denied');
    written.add('$bondId/${t.id}');
  }

  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> rateWeek(String bondId, String week, int stars) async {}
  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> bond(CloudBond b) async {}
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<void> recover(String bondId, DateTime now) async {}
  @override
  Future<void> ask(String bondId, CloudQuestion q) async {}
  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {}
  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];
  @override
  Future<List<MentorRequest>> sentRequests() async => const [];
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
  @override
  Stream<void> watchMentor() => const Stream.empty();
}

AppState _instructor(_Mentor src) => AppState(demo: false)
  ..myUid = 'u-教官'
  ..isInstructor = true
  ..instructorDutyVersion = kInstructorDutyVersion
  ..mentorSource = src;

void main() {
  group('師徒任務的寫入結果看得見', () {
    test('寫成功 → 報告寫著成功', () async {
      final src = _Mentor();
      final s = _instructor(src);
      s.assignMentorTask('練腿', '三組', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);

      expect(src.written, hasLength(1), reason: '前提：這次真的寫出去了');
      expect(s.cloudWriteReport['師徒任務'], startsWith('成功'));
    });

    test('寫失敗 → 報告寫著失敗，而不是什麼都沒有', () async {
      final src = _Mentor()..failing = true;
      final s = _instructor(src);
      s.assignMentorTask('練腿', '三組', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);

      expect(src.written, isEmpty);
      expect(s.cloudWriteReport['師徒任務'], startsWith('失敗'),
          reason: '原本 catchError((_) {}) 把它吞得乾乾淨淨');
      expect(s.cloudWriteReport['師徒任務'], contains('permission-denied'),
          reason: '要說得出是什麼原因，否則還是得翻雲端才知道');
    });

    test('根本沒送出 → 也要留下痕跡', () async {
      final src = _Mentor();
      final s = _instructor(src);
      // 學徒 uid 是空的 → 關係 id 算不出來 → 原本默默 return，
      // 而畫面照樣跳「已指派」。**這一種與成功長得一模一樣。**
      s.assignMentorTask('練腿', '三組');
      await Future<void>.delayed(Duration.zero);

      expect(src.written, isEmpty);
      expect(s.cloudWriteReport['師徒任務'], startsWith('沒送出'));
    });

    test('寫到哪一段關係去，要跟寫成功一樣看得見', () async {
      // Firestore 允許往**不存在的文件**底下建子集合 —— 關係 id 算錯的話
      // 寫入照樣成功，而那些孤兒在列關係時根本不會出現。
      // 2026-09-30 就是這樣：教官報「成功」，學徒在正確的關係底下讀到 0 則。
      final src = _Mentor();
      final s = _instructor(src);
      s.assignMentorTask('練腿', '三組', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);

      expect(s.cloudWriteReport['師徒任務 → '], 'u-教官_u-學徒');
      expect(src.written.single, startsWith('u-教官_u-學徒/'),
          reason: '報告上寫的，就要是真的寫進去的那一個');
    });

    test('本機那一份照樣存在 —— 寫不上雲不該讓畫面也空了', () async {
      final src = _Mentor()..failing = true;
      final s = _instructor(src);
      s.assignMentorTask('練腿', '三組', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);
      expect(s.mentorTasks.where((t) => t.title == '練腿'), hasLength(1));
    });

    test('報告會被後來的結果覆蓋，不會一直卡在舊訊息上', () async {
      final src = _Mentor()..failing = true;
      final s = _instructor(src);
      s.assignMentorTask('第一個', '', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);
      expect(s.cloudWriteReport['師徒任務'], startsWith('失敗'));

      src.failing = false;
      s.assignMentorTask('第二個', '', apprenticeUid: 'u-學徒');
      await Future<void>.delayed(Duration.zero);
      expect(s.cloudWriteReport['師徒任務'], startsWith('成功'));
    });
  });
}
