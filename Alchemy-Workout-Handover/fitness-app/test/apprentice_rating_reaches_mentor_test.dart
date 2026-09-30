// 學徒評的分，要動得了教官的聲望 —— 而且只動一次。
//
// 在此之前 `apprenticeRatesMe()` 是唯一會動到教官自己聲望的入口，
// 而它在 `lib/` 只有一個呼叫端：設計模擬頁 `counterpart_screen.dart`。
// 正式流程裡沒有人叫它。於是學徒評了分、評分寫上了雲、星等也算得出來，
// **只有聲望（以及它連動的帶徒上限）停在原地。**
//
// 週互動評分更徹底：`rateWeeklyInteraction()` 一個字都不寫上雲，
// 只改學徒裝置上那份教官副本。而它是幅度最大的一條
// （−2／0／+4／+8／+12）。
//
// 這是 2026-09-29 那一整天第十個同型缺陷：功能做好了，
// 它做的事到不了需要它的人面前。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeMentor implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));

  final Map<String, List<CloudMentorTask>> cloudTasks = {};
  final List<(String bond, String week, int stars)> weekRatings = [];
  List<CloudBond> cloudBonds = const [];

  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async =>
      cloudTasks[bondId] ?? const [];

  @override
  Future<void> rateWeek(String bondId, String week, int stars) async =>
      weekRatings.add((bondId, week, stars));

  @override
  Future<List<CloudBond>> bonds() async => cloudBonds;

  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
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

const _mentorUid = 'u-教官';
const _appUid = 'u-學徒';
const _bondId = '${_mentorUid}_$_appUid';

CloudBond _bond({Map<String, int> weekly = const {}}) => CloudBond(
      id: _bondId,
      mentorUid: _mentorUid,
      apprenticeUid: _appUid,
      mentorName: '老王',
      apprenticeName: '小明',
      bondedAt: DateTime(2026, 9, 1),
      weeklyRatings: weekly,
    );

/// 教官那一台。
({AppState s, _FakeMentor src}) _mentor() {
  final src = _FakeMentor();
  final s = AppState(demo: false)
    ..myUid = _mentorUid
    ..isInstructor = true
    // 規格：成為教官時初始聲望 15。它的職責就是讓前幾次差評不致
    // 貼著地板 0 —— 從 0 起算的話這支測試扣不動。
    ..instructorReputation = kInstructorInitialReputation
    ..instructorDutyVersion = kInstructorDutyVersion
    ..mentorSource = src;
  return (s: s, src: src);
}

CloudMentorTask _rated(String id, int stars) => CloudMentorTask(
      id: id,
      title: '練腿',
      detail: '三組',
      state: MentorTaskState.claimed,
      rating: stars,
    );

void main() {
  group('任務評分要算進教官的聲望', () {
    test('讀回一則評過分的任務，聲望就會動', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond()]);
      final before = m.s.instructorReputation;

      m.src.cloudTasks[_bondId] = [_rated('mt-1', 5)];
      await m.s.loadMentorSideOf(_appUid);

      expect(m.s.instructorReputation, greaterThan(before),
          reason: '學徒給了五星，教官那一台什麼也沒發生');
    });

    test('同一則評分只算一次 —— 重讀幾次都一樣', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond()]);
      m.src.cloudTasks[_bondId] = [_rated('mt-1', 5)];

      await m.s.loadMentorSideOf(_appUid);
      final once = m.s.instructorReputation;
      await m.s.loadMentorSideOf(_appUid);
      await m.s.loadMentorSideOf(_appUid);

      expect(m.s.instructorReputation, once, reason: '每重讀一次就再加一次');
    });

    test('重開 App 之後也只算一次 —— 這就是它要進存檔的理由', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond()]);
      m.src.cloudTasks[_bondId] = [_rated('mt-1', 5)];
      await m.s.loadMentorSideOf(_appUid);
      final once = m.s.instructorReputation;

      // 重開：新的 AppState，只帶著存檔。
      final snap = m.s.toSnapshot();
      final again = _mentor();
      again.s.applySnapshot(snap);
      again.s.applyCloudBonds([_bond()]);
      again.src.cloudTasks[_bondId] = [_rated('mt-1', 5)];
      await again.s.loadMentorSideOf(_appUid);

      expect(again.s.instructorReputation, once,
          reason: 'mentorTasks 不進存檔，重開之後每則評過的任務都像新的');
    });

    test('還沒評分的任務不算', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond()]);
      final before = m.s.instructorReputation;
      m.src.cloudTasks[_bondId] = [
        const CloudMentorTask(id: 'mt-2', title: '練背', detail: ''),
      ];
      await m.s.loadMentorSideOf(_appUid);
      expect(m.s.instructorReputation, before);
    });

    test('一星要扣分 —— 方向不能反', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond()]);
      final before = m.s.instructorReputation;
      m.src.cloudTasks[_bondId] = [_rated('mt-3', 1)];
      await m.s.loadMentorSideOf(_appUid);
      expect(m.s.instructorReputation, lessThan(before));
    });
  });

  group('週互動評分要到得了教官那一台', () {
    test('學徒評完，雲端就有一筆', () {
      final a = AppState(demo: false)..myUid = _appUid;
      final src = _FakeMentor();
      a
        ..mentorSource = src
        ..applyCloudBonds([_bond()]);
      expect(a.myInstructor, isNotNull, reason: '前提：關係載得進來');
      // Precondition：該週內雙方要有互動。
      a.weeklyQuestionCount = 1;

      expect(a.rateWeeklyInteraction(5), isTrue);

      expect(src.weekRatings, hasLength(1), reason: '一個字都沒寫上雲');
      final (bond, week, stars) = src.weekRatings.single;
      expect(bond, _bondId);
      expect(stars, 5);
      final (from, _) = periodOf(Board.personalWeekly, a.now);
      expect(week, weekKeyOf(from), reason: '鍵要是該週週一');
    });

    test('教官讀回關係就算進聲望', () {
      final m = _mentor();
      final before = m.s.instructorReputation;
      m.s.applyCloudBonds([
        _bond(weekly: {'2026-09-28': 5}),
      ]);
      expect(m.s.instructorReputation, greaterThan(before));
    });

    test('同一週只算一次 —— 重讀幾次都一樣', () {
      final m = _mentor();
      final b = _bond(weekly: {'2026-09-28': 5});
      m.s.applyCloudBonds([b]);
      final once = m.s.instructorReputation;
      m.s.applyCloudBonds([b]);
      m.s.applyCloudBonds([b]);
      expect(m.s.instructorReputation, once);
    });

    test('不同週各算一次', () {
      final m = _mentor();
      m.s.applyCloudBonds([
        _bond(weekly: {'2026-09-28': 5}),
      ]);
      final oneWeek = m.s.instructorReputation;
      m.s.applyCloudBonds([
        _bond(weekly: {'2026-09-28': 5, '2026-10-05': 5}),
      ]);
      expect(m.s.instructorReputation, greaterThan(oneWeek),
          reason: '第二週的評分也該算');
    });

    test('週重置清掉每週閘門，舊評分仍不會被重算', () {
      final m = _mentor();
      final b = _bond(weekly: {'2026-09-28': 5});
      m.s.applyCloudBonds([b]);
      final once = m.s.instructorReputation;

      // `apprenticeWeeklyRated` 是「這週還能不能再評」的閘門，每週清空。
      // 清空之後同一筆舊評分就會再次通過 —— 擋它的是另一份清單。
      m.s.advanceDemoClock(const Duration(days: 8));
      m.s.applyCloudBonds([b]);

      expect(m.s.instructorReputation, once);
    });

    test('週互動的幅度大於單次任務評分', () async {
      final task = _mentor();
      task.s.applyCloudBonds([_bond()]);
      final taskBefore = task.s.instructorReputation;
      task.src.cloudTasks[_bondId] = [_rated('mt-1', 5)];
      await task.s.loadMentorSideOf(_appUid);
      final byTask = task.s.instructorReputation - taskBefore;

      final week = _mentor();
      final weekBefore = week.s.instructorReputation;
      week.s.applyCloudBonds([
        _bond(weekly: {'2026-09-28': 5}),
      ]);
      final byWeek = week.s.instructorReputation - weekBefore;

      expect(byWeek, greaterThan(byTask),
          reason: '規格：兩個來源用不同的換算表，週互動幅度遠大');
    });
  });

  group('別人的評分不算到我頭上', () {
    test('我不是教官的那段關係，不動我的聲望', () {
      final m = _mentor();
      final before = m.s.instructorReputation;
      m.s.applyCloudBonds([
        CloudBond(
          id: '${_appUid}_$_mentorUid',
          mentorUid: _appUid,
          apprenticeUid: _mentorUid,
          mentorName: '小明',
          apprenticeName: '老王',
          bondedAt: DateTime(2026, 9, 1),
          weeklyRatings: const {'2026-09-28': 5},
        ),
      ]);
      expect(m.s.instructorReputation, before,
          reason: '那一段裡我是學徒，評的是別人');
    });
  });
}
