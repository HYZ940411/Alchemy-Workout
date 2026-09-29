// 一種讀失敗，不可以把另一種也吃掉。
//
// 2026-09-30：學徒讀得到提問卻讀不到任務。兩者在同一支函式、
// 同一段關係下 —— 而它們**共用一個 `try`**。提問先讀、任務後讀，
// 任務那一趟丟例外（配額用完就會）整段就靜靜結束。
//
// 畫面上，「雲端本來就沒有任務」與「這一趟讀失敗了」長得一模一樣。
// 教官那一側是同一個形狀，只是順序相反（任務先、提問後）。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

const _mentorUid = 'u-教官';
const _appUid = 'u-學徒';
const _bondId = '${_mentorUid}_$_appUid';

class _Mentor implements MentorSource {
  bool tasksFail = false;
  bool questionsFail = false;
  List<CloudMentorTask> cloudTasks = const [];
  List<CloudQuestion> cloudQuestions = const [];

  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async {
    if (tasksFail) throw StateError('quota');
    return cloudTasks;
  }

  @override
  Future<List<CloudQuestion>> questions(String bondId) async {
    if (questionsFail) throw StateError('quota');
    return cloudQuestions;
  }

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<void> rateWeek(String bondId, String week, int stars) async {}
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

/// 只記下被發布過幾次。
class _Profiles implements PublicProfileSource {
  final List<PublicProfile> published = [];

  @override
  Future<void> publish(PublicProfile me) async => published.add(me);
  @override
  Future<List<PublicProfile>> others({int limit = 50}) async => const [];
  @override
  Future<List<PublicProfile>> byUids(List<String> uids) async => const [];
  @override
  Future<void> remove() async {}
  @override
  Future<LeaderboardPage?> leaderboard({
    required bool weekly,
    required int group,
    required int myScore,
    int window = 0,
  }) async =>
      null;
}

CloudBond _bond() => CloudBond(
      id: _bondId,
      mentorUid: _mentorUid,
      apprenticeUid: _appUid,
      mentorName: '老王',
      apprenticeName: '小明',
      bondedAt: DateTime(2026, 9, 1),
    );

const _task = CloudMentorTask(id: 'mt-1', title: '練腿', detail: '三組');
final _question = CloudQuestion(
    id: 'q-1', fromUid: _appUid, text: '深蹲膝蓋會痛', at: DateTime(2026, 9, 2));

/// 學徒那一台。
AppState _apprentice(_Mentor src) => AppState(demo: false)
  ..myUid = _appUid
  ..mentorSource = src
  ..applyCloudBonds([_bond()]);

/// 教官那一台。[profiles] 給了才驗得動「有沒有發布公開檔案」。
AppState _instructor(_Mentor src, {_Profiles? profiles}) => AppState(demo: false)
  ..myUid = _mentorUid
  ..isInstructor = true
  ..instructorDutyVersion = kInstructorDutyVersion
  ..mentorSource = src
  ..profileSource = profiles
  ..applyCloudBonds([_bond()]);

void main() {
  group('學徒側：提問先讀、任務後讀', () {
    test('兩種都好的時候，兩種都讀得到', () async {
      final src = _Mentor()
        ..cloudTasks = [_task]
        ..cloudQuestions = [_question];
      final s = _apprentice(src);
      await s.loadMyApprenticeSide();
      expect(s.mentorTasks.map((t) => t.id), contains('mt-1'));
      expect(s.questions.map((q) => q.id), contains('q-1'));
    });

    test('任務那一趟失敗，提問照樣讀得到', () async {
      final src = _Mentor()
        ..tasksFail = true
        ..cloudQuestions = [_question];
      final s = _apprentice(src);
      await s.loadMyApprenticeSide();
      expect(s.questions.map((q) => q.id), contains('q-1'));
      expect(s.cloudReadReport['學徒側任務'], startsWith('失敗'));
    });

    test('提問那一趟失敗，任務照樣讀得到 —— 這就是原本壞掉的方向', () async {
      final src = _Mentor()
        ..questionsFail = true
        ..cloudTasks = [_task];
      final s = _apprentice(src);
      await s.loadMyApprenticeSide();
      expect(s.mentorTasks.map((t) => t.id), contains('mt-1'),
          reason: '先讀的那種失敗，原本會把後讀的整段吃掉');
      expect(s.cloudReadReport['學徒側提問'], startsWith('失敗'));
    });

    test('讀到幾則要說得出來 —— 「雲端沒有」與「讀失敗」不再長得一樣', () async {
      final src = _Mentor()..cloudTasks = [_task];
      final s = _apprentice(src);
      await s.loadMyApprenticeSide();
      expect(s.cloudReadReport['學徒側任務'], '讀到 1 則');
      expect(s.cloudReadReport['學徒側提問'], '讀到 0 則');
    });

    test('用的是哪一段關係要看得見 —— 兩邊對不上就什麼都讀不到', () async {
      final s = _apprentice(_Mentor());
      await s.loadMyApprenticeSide();
      expect(s.cloudReadReport['學徒側關係'], _bondId);
    });

    test('沒有教官時說「沒讀」，不是默默結束', () async {
      final s = AppState(demo: false)
        ..myUid = _appUid
        ..mentorSource = _Mentor()
        ..myInstructor = null;
      await s.loadMyApprenticeSide();
      expect(s.cloudReadReport['學徒側'], startsWith('沒讀'));
    });
  });

  group('教官側：任務先讀、提問後讀（順序相反，同一個形狀）', () {
    test('任務那一趟失敗，提問照樣讀得到', () async {
      final src = _Mentor()
        ..tasksFail = true
        ..cloudQuestions = [_question];
      final s = _instructor(src);
      await s.loadMentorSideOf(_appUid);
      expect(s.questions.map((q) => q.id), contains('q-1'),
          reason: '先讀的那種失敗，原本會把後讀的整段吃掉');
      expect(s.cloudReadReport['教官側任務'], startsWith('失敗'));
    });

    test('提問那一趟失敗，任務照樣讀得到', () async {
      final src = _Mentor()
        ..questionsFail = true
        ..cloudTasks = [_task];
      final s = _instructor(src);
      await s.loadMentorSideOf(_appUid);
      expect(s.mentorTasks.map((t) => t.id), contains('mt-1'));
      expect(s.cloudReadReport['教官側提問'], startsWith('失敗'));
    });

    test('讀到東西就發布公開檔案 —— 星等要傳得出去', () async {
      final profiles = _Profiles();
      final src = _Mentor()..cloudTasks = [_task];
      final s = _instructor(src, profiles: profiles);
      profiles.published.clear();
      await s.loadMentorSideOf(_appUid);
      expect(profiles.published, isNotEmpty, reason: '前提：讀成功就會發布');
    });

    test('兩趟都失敗時不發布公開檔案 —— 別把空的星等蓋上去', () async {
      final profiles = _Profiles();
      final src = _Mentor()
        ..tasksFail = true
        ..questionsFail = true;
      final s = _instructor(src, profiles: profiles);
      profiles.published.clear();
      await s.loadMentorSideOf(_appUid);
      expect(profiles.published, isEmpty,
          reason: '什麼都沒讀到，就沒有新的星等可以發布');
    });
  });
}
