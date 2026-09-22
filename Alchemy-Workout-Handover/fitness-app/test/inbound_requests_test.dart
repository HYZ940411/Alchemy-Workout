// 送出去的申請，收件的那一方永遠看不到。
//
// `TeamSource.requestsFor()` 與 `MentorSource.requestsFor()` 都有實作、
// 都有測試 —— **就是沒有人叫它們**。申請確實寫進了 Firestore，但登入時
// 從來不去讀，於是隊長看不到有人要加入、教官看不到有人要拜師。
//
// 與 `openTeams()`、`deliverOrder()`、`aiSource`、`myTeam` 同一種病：
// 零件都做好了，接縫沒接。這次是第八次。
//
// 另外：跨使用者的東西只在登入時載入一次（`lib/data/` 底下沒有任何
// `.snapshots()`），所以對方傳了訊息我這邊要登出再登入才看得到。
// 在即時訂閱做出來之前，至少要有 `refreshInbound()`。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  TeamRequest req({
    required bool isInvite,
    String teamId = 't-mine',
    String name = '路人甲',
    Duration left = const Duration(hours: 100),
  }) =>
      TeamRequest(
        teamId: teamId,
        teamName: '晨跑隊',
        uid: 'u-$name',
        name: name,
        rank: 12,
        isInvite: isInvite,
        expiresAt: DateTime.now().add(left),
      );

  group('隊伍的兩份請求清單必須可增長', () {
    // `Team` 的 invites 與 applications 原本預設 `const []` —— 不可修改。
    // 於是 `createTeam()` 建的隊、`applyCloudTeam()` 從雲端載入的隊，
    // **一收到申請就拋 `Cannot add to an unmodifiable list`**。
    // 與當初 `buildSocialUsers()` 那個 bug 一模一樣。

    test('自己開一隊之後，別人申請加入不會拋例外', () {
      final s = AppState(demo: false)..displayName = '我';
      expect(s.createTeam('新隊伍'), isTrue);
      expect(() => s.peerAppliesToMyTeam('路人甲', 12), returnsNormally);
      expect(s.myTeam!.applications, hasLength(1));
    });

    test('雲端載入的隊伍也一樣', () {
      final s = AppState(demo: false);
      s.applyCloudTeam(CloudTeam(
        id: 't-cloud',
        name: '雲端隊',
        members: {
          'u-me': CloudMember(
            name: '我',
            rank: 10,
            role: TeamRole.leader,
            joinedAt: DateTime(2026),
          ),
        },
      ));
      expect(() => s.myTeam!.applications.add(
            PendingRequest('路人乙', 9, DateTime.now()),
          ), returnsNormally);
    });

    test('沒傳的話預設就是可增長的空清單', () {
      final t = Team(id: 't', name: 'x', isPublic: true, members: const []);
      expect(() => t.applications.add(
            PendingRequest('甲', 1, DateTime.now())), returnsNormally);
      expect(() => t.invites.add(
            PendingRequest('乙', 1, DateTime.now())), returnsNormally);
    });
  });

  group('團隊請求要分流到正確的地方', () {
    test('別人申請加入我的隊 → 進那一隊的待回應清單', () {
      final s = AppState()..myTeam = Team(id: 't-mine', name: '我的隊', isPublic: true, members: const []);
      s.applyCloudTeamRequests([req(isInvite: false)]);

      expect(s.myTeam!.applications.map((a) => a.name), ['路人甲']);
      expect(s.inbox, isEmpty, reason: '它掛在團隊底下，不是掛在我身上');
    });

    test('隊長邀我入隊 → 進我的收件匣', () {
      final s = AppState(demo: false);
      s.applyCloudTeamRequests([req(isInvite: true, name: '隊長乙')]);

      expect(s.inbox, hasLength(1));
      expect(s.inbox.single.kind, InboundKind.teamInvite);
      expect(s.inbox.single.from, '隊長乙');
      expect(s.inbox.single.subject, '晨跑隊', reason: 'subject 是團隊名，from 才是隊長');
    });

    test('逾期的不收', () {
      final s = AppState(demo: false)..myTeam = Team(id: 't-mine', name: '我的隊', isPublic: true, members: const []);
      s.applyCloudTeamRequests([
        req(isInvite: true, left: const Duration(hours: -1)),
        req(isInvite: false, left: const Duration(hours: -1)),
      ]);
      expect(s.inbox, isEmpty);
      expect(s.myTeam!.applications, isEmpty);
    });

    test('申請別支隊伍的不會跑進我的隊', () {
      final s = AppState()..myTeam = Team(id: 't-mine', name: '我的隊', isPublic: true, members: const []);
      s.applyCloudTeamRequests([req(isInvite: false, teamId: 't-other')]);
      expect(s.myTeam!.applications, isEmpty);
    });

    test('已經是隊員的不重複收', () {
      final s = AppState()
        ..myTeam = Team(
          id: 't-mine',
          name: '我的隊',
          isPublic: true,
          members: [const TeamMember('路人甲', 12, TeamRole.member)],
        );
      s.applyCloudTeamRequests([req(isInvite: false)]);
      expect(s.myTeam!.applications, isEmpty);
    });

    test('讀兩次不會變成兩筆', () {
      final s = AppState()..myTeam = Team(id: 't-mine', name: '我的隊', isPublic: true, members: const []);
      s.applyCloudTeamRequests([req(isInvite: false)]);
      s.applyCloudTeamRequests([req(isInvite: false)]);
      expect(s.myTeam!.applications, hasLength(1));
    });
  });

  group('師徒申請', () {
    MentorRequest mreq({required bool fromMentor}) => MentorRequest(
          id: 'mr-1',
          fromUid: 'u-x',
          toUid: 'u-me',
          fromName: fromMentor ? '教官丙' : '學徒丁',
          fromRank: 30,
          fromMentor: fromMentor,
          at: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 100)),
        );

    test('教官發起 → 他邀我當學徒', () {
      final s = AppState(demo: false);
      s.applyCloudMentorRequests([mreq(fromMentor: true)]);
      expect(s.inbox.single.kind, InboundKind.mentorInvite);
      expect(s.inbox.single.from, '教官丙');
    });

    test('學徒發起 → 有人想拜我為師', () {
      final s = AppState(demo: false);
      s.applyCloudMentorRequests([mreq(fromMentor: false)]);
      expect(s.inbox.single.kind, InboundKind.apprenticeApply);
    });

    test('師徒兩向的 subject 都與 from 同值', () {
      final s = AppState(demo: false);
      s.applyCloudMentorRequests([mreq(fromMentor: true)]);
      expect(s.inbox.single.subject, s.inbox.single.from);
    });
  });

  group('沒有即時訂閱，至少要刷得動', () {
    test('沒登入時 refreshInbound 不做事也不拋例外', () async {
      final s = AppState()..myUid = null;
      await s.refreshInbound();
    });

    test('沒接來源時不拋例外', () async {
      final s = AppState()
        ..myUid = 'u-me'
        ..chatSource = null
        ..teamSource = null
        ..mentorSource = null;
      await s.refreshInbound();
    });
  });
}
