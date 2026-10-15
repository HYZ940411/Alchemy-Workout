// 收件匣的接受與拒絕要回寫雲端（2026-09-24）。
//
// 使用者回報「私訊跟團隊好像也有跟師徒一樣的問題，發出之後沒有上雲，
// 刷新後就不見了」。查下去團隊確實有，而且是三個缺口：
//
//   1. **接受團隊邀請後沒把自己寫進雲端名冊。** `_joinPublicTeam()` 整個
//      函式一行雲端寫入都沒有，而登入時是 `teams.myTeam()` 去查「我在
//      哪支隊」—— 查不到，於是重整團隊就不見了。
//   2. **接受之後沒刪掉雲端那筆請求。**
//   3. **拒絕完全沒有回寫。** 拒絕了三次，它出現了四次。
//
// 2 與 3 是同一句話：本機移掉、雲端還在，下次載入又跑出來 ——
// 與先前修過的「撤回申請」一模一樣。
//
// `MentorSource.dropRequest` 一個呼叫端都沒有，而
// `data_source_wiring_test` **沒抓到**：`TeamSource` 也有一支同名方法，
// 而那支有人呼叫。那正是該檔案開頭寫明的撞名漏抓，這次是真的踩到。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeTeams implements TeamSource {
  @override
  Future<void> addScore(String teamId, String uid, int delta) async {}
  @override
  Future<void> creditTimed(String teamId, String uid, String day) async {}

  final List<(String team, String uid)> members = [];
  final List<(String team, String uid)> dropped = [];

  @override
  Future<void> putMember(String teamId, String uid, CloudMember m) async =>
      members.add((teamId, uid));

  @override
  Future<void> dropRequest(String teamId, String targetUid) async =>
      dropped.add((teamId, targetUid));

  @override
  Future<CloudTeam?> myTeam() async => null;
  @override
  Future<void> create(CloudTeam t) async {}
  @override
  Future<void> disband(String teamId) async {}
  @override
  Future<void> removeMember(String teamId, String uid) async {}
  @override
  Future<void> setVisibility(String teamId, bool isPublic) async {}
  @override
  Future<void> sendRequest(TeamRequest r) async {}
  @override
  Future<List<TeamRequest>> requestsFor(String uid,
          {String? myTeamId, List<String>? errors}) async =>
      const [];
  @override
  Future<List<CloudTeam>> openTeams({int limit = 30}) async => const [];
  @override
  Stream<void> watchTeams({String? myTeamId}) => const Stream.empty();
}

class _FakeMentor implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));


  /// 週互動評分。這支測試不碰它 —— 記下來就好。
  final List<(String bond, String week, int stars)> weekRatings = [];

  @override
  Future<void> rateWeek(String bondId, String week, int stars) async =>
      weekRatings.add((bondId, week, stars));

  final List<String> dropped = [];
  final List<CloudBond> bonded = [];

  @override
  Future<void> dropRequest(String requestId) async => dropped.add(requestId);
  @override
  Future<void> bond(CloudBond b) async => bonded.add(b);

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<void> recover(String bondId, DateTime now) async {}
  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
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
  Stream<void> watchMentor() => const Stream.empty();
}

InboundRequest _req(InboundKind kind, String subject,
        {String from = '對方', String uid = 'u-對方', String id = 'r1'}) =>
    InboundRequest(
      id: id,
      kind: kind,
      from: from,
      fromUid: uid,
      fromRank: 30,
      subject: subject,
      // **相對於現在，不寫死日期。** 原本是 2026-09-24 —— 請求七天逾期，
      // 10-01 之後信箱就不收它，這幾條測試在日曆翻過去那天一起紅。
      sentAt: appNow().subtract(const Duration(hours: 1)),
    );

/// 一個接好雲端、而且有一支公開團隊可以加入的狀態。
({AppState s, _FakeTeams teams, _FakeMentor mentor}) _wired() {
  final teams = _FakeTeams();
  final mentor = _FakeMentor();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..teamSource = teams
    ..mentorSource = mentor;
  s.publicTeams.add(const PublicTeam('鐵人隊', 2, 5, id: 't1'));
  return (s: s, teams: teams, mentor: mentor);
}

void main() {
  group('接受團隊邀請', () {
    test('要把自己寫進雲端名冊', () {
      final w = _wired();
      final r = _req(InboundKind.teamInvite, '鐵人隊');
      w.s.receiveInbound(r);

      expect(w.s.acceptInbound(r), isTrue);

      // 少了這一步，登入時 `teams.myTeam()` 查不到我 ——
      // 接受邀請、重新整理，團隊就不見了。
      expect(w.teams.members, [('t1', 'u-me')]);
    });

    test('要把雲端那筆邀請刪掉', () {
      final w = _wired();
      final r = _req(InboundKind.teamInvite, '鐵人隊');
      w.s.receiveInbound(r);

      w.s.acceptInbound(r);

      expect(w.teams.dropped, [('t1', 'u-me')]);
    });

    test('先寫名冊再刪請求 —— 順序顛倒會被安全規則擋下', () {
      final w = _wired();
      final r = _req(InboundKind.teamInvite, '鐵人隊');
      w.s.receiveInbound(r);

      w.s.acceptInbound(r);

      // `firestore.rules` 允許我把自己加進名冊的條件，正是
      // 「有一筆給我的待回應請求」—— 先刪就把自己鎖在外面了。
      expect(w.teams.members, isNotEmpty);
      expect(w.teams.dropped, isNotEmpty);
    });
  });

  group('接受師徒請求', () {
    test('要把雲端那筆申請刪掉', () {
      final w = _wired();
      final r = _req(InboundKind.mentorInvite, '老王', from: '老王', uid: 'u-老王');
      w.s.receiveInbound(r);

      expect(w.s.acceptInbound(r), isTrue);

      // `MentorSource.dropRequest` 在此之前一個呼叫端都沒有。
      expect(w.mentor.dropped, ['r1']);
      expect(w.mentor.bonded, hasLength(1), reason: '關係本身也要寫');
    });
  });

  group('拒絕', () {
    test('團隊邀請：雲端那筆也要刪', () {
      final w = _wired();
      final r = _req(InboundKind.teamInvite, '鐵人隊');
      w.s.receiveInbound(r);

      w.s.declineInbound(r);

      // 不刪的話下次登入 `applyCloudTeamRequests` 又把它撈回來 ——
      // 使用者拒絕了三次，它出現了四次。
      expect(w.teams.dropped, [('t1', 'u-me')]);
      expect(w.teams.members, isEmpty, reason: '拒絕不該把我加進名冊');
    });

    test('師徒請求：雲端那筆也要刪', () {
      final w = _wired();
      final r = _req(InboundKind.apprenticeApply, '小明',
          from: '小明', uid: 'u-小明', id: 'mr9');
      w.s.receiveInbound(r);

      w.s.declineInbound(r);

      expect(w.mentor.dropped, ['mr9']);
      expect(w.mentor.bonded, isEmpty, reason: '拒絕不該建立關係');
    });
  });

  group('沒接後端', () {
    test('接受與拒絕都不會炸', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.publicTeams.add(const PublicTeam('鐵人隊', 2, 5, id: 't1'));
      final a = _req(InboundKind.teamInvite, '鐵人隊');
      s.receiveInbound(a);
      expect(s.acceptInbound(a), isTrue);

      final b = _req(InboundKind.mentorInvite, '老王',
          from: '老王', uid: 'u-老王', id: 'r2');
      s.receiveInbound(b);
      s.declineInbound(b);
    });
  });
}
