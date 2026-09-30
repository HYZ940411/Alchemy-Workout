// 團隊分數要存得住（使用者裁決 A，2026-09-28）。
//
// ## 為什麼有這個檔案
//
// 使用者要求「團隊的限時任務跟分數累積都要再檢查」。查下去發現不是算錯：
//
// **`CloudTeam` 完全沒有分數欄位**，本機存檔也沒有 —— 團隊的日常貢獻、
// 限時任務完成名單全部只活在記憶體裡。重開 App 就回到示範資料；
// 真帳號則每次從零開始，練完的分數下一秒就沒了。
//
// 裁決 A：上雲。這個檔案釘的是「真的送上去了」與「真的讀得回來」。
//
// ## 為什麼是累加不是覆寫
//
// 兩台裝置同時練完，覆寫會丟掉一次。而且安全規則只放行「自己那一格、
// 而且往上」（見 `firestore.rules` 的 `contribOk()`），整份覆寫寫不過去。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTeams implements TeamSource {
  final List<(String team, String uid, int delta)> scores = [];
  final List<(String team, String uid, String day)> timed = [];

  @override
  Future<void> addScore(String teamId, String uid, int delta) async =>
      scores.add((teamId, uid, delta));
  @override
  Future<void> creditTimed(String teamId, String uid, String day) async =>
      timed.add((teamId, uid, day));

  @override
  Future<CloudTeam?> myTeam() async => null;
  @override
  Future<List<CloudTeam>> openTeams({int limit = 30}) async => const [];
  @override
  Future<void> create(CloudTeam t) async {}
  @override
  Future<void> putMember(String teamId, String uid, CloudMember m) async {}
  @override
  Future<void> removeMember(String teamId, String uid) async {}
  @override
  Future<void> setVisibility(String teamId, bool isPublic) async {}
  @override
  Future<void> disband(String teamId) async {}
  @override
  Future<void> sendRequest(TeamRequest r) async {}
  @override
  Future<void> dropRequest(String teamId, String uid) async {}
  @override
  Future<List<TeamRequest>> requestsFor(String uid,
          {String? myTeamId, List<String>? errors}) async =>
      const [];
  @override
  Stream<void> watchTeams({String? myTeamId}) => const Stream.empty();
}

/// 一個已登入、在隊上、而且接了雲端的狀態。
(AppState, _FakeTeams) _joined() {
  final src = _FakeTeams();
  final s = AppState()
    ..myUid = 'u-me'
    ..teamSource = src;
  // 重新分隊期內兩個團隊分數皆不累加 —— 那不是這幾條要驗的東西。
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  // 名冊上的我要帶著 uid，否則「得分當下須為本團隊成員」那一關過不了。
  final t = s.myTeam!;
  final i = t.members.indexWhere((m) => m.name == s.displayName);
  t.members[i] = TeamMember(
      t.members[i].name, t.members[i].rank, t.members[i].role, uid: 'u-me');
  return (s, src);
}

String _today(AppState s) {
  final d = businessDate(s.now);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  group('日常貢獻送得上雲', () {
    test('練完一場就送一次，送的是增量', () {
      final (s, src) = _joined();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.completeCurrentSet();
      // 獎勵有「不到 5 分鐘不發」的門檻，不往前挪每一場都算太短。
      s.backdateSession(const Duration(minutes: 10));
      s.finishWorkout(EndKind.completed);

      expect(src.scores, isNotEmpty, reason: '在此之前這裡什麼都不會發生');
      final total = src.scores.fold<int>(0, (a, b) => a + b.$3);
      expect(total, greaterThan(0));
      expect(src.scores.every((e) => e.$2 == 'u-me'), isTrue,
          reason: '只送自己那一格 —— 安全規則也只放行自己那一格');
      expect(s.myTeam!.contributions[s.personKeyOf(s.displayName, 'u-me')],
          isNotNull);
    });

    test('沒接雲端就什麼都不送 —— 既有測試走這條', () {
      final s = AppState()..myUid = 'u-me';
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      s.finishWorkout(EndKind.completed);
      // 不炸就算過：teamSource 是空的，本機照常累加。
      expect(s.myTeam!.dailyScore, greaterThan(0));
    });
  });

  group('限時任務送得上雲', () {
    test('完成時送出自己與今天的日期', () {
      final (s, src) = _joined();
      s.completeTimedTask();

      expect(src.timed.length, 1);
      expect(src.timed.first.$2, 'u-me');
      expect(src.timed.first.$3, _today(s),
          reason: '要帶業務日 —— 換日清空沒有伺服器可以做');
    });

    test('重複完成不重複送', () {
      final (s, src) = _joined();
      s.completeTimedTask();
      s.completeTimedTask();
      expect(src.timed.length, 1);
    });
  });

  group('讀得回來', () {
    CloudTeam cloud({
      Map<String, int> contributions = const {},
      Set<String> timedCredited = const {},
      String timedDay = '',
    }) =>
        CloudTeam(
          id: 't1',
          name: '雲端隊',
          members: {
            'u-me': CloudMember(
                name: '我', rank: 10, role: TeamRole.leader, joinedAt: DateTime(2026)),
          },
          contributions: contributions,
          timedCredited: timedCredited,
          timedDay: timedDay,
        );

    test('貢獻以雲端為準，分數跟著回來', () {
      final s = AppState()..myUid = 'u-me';
      s.applyCloudTeam(cloud(contributions: {'u-me': 120, 'u-other': 80}));

      expect(s.myTeam!.contributions['u-me'], 120);
      expect(s.myTeam!.dailyScore, 200,
          reason: '團隊分數是各成員貢獻的加總，結構上成立');
    });

    test('昨天的限時任務名單不算數', () {
      final s = AppState()..myUid = 'u-me';
      s.applyCloudTeam(
          cloud(timedCredited: {'u-me'}, timedDay: '2020-01-01'));

      expect(s.myTeam!.timedCredited, isEmpty,
          reason: '換日要清空，而清空是由第一個完成的人做 —— 在那之前先當它是空的');
    });

    test('今天的名單照常帶回來', () {
      final s = AppState()..myUid = 'u-me';
      s.applyCloudTeam(cloud(timedCredited: {'u-me'}, timedDay: _today(s)));
      expect(s.myTeam!.timedCredited, {'u-me'});
    });
  });

  group('存讀邊界本身（走 Firestore）', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);

    Future<void> makeTeam() => as('a').create(CloudTeam(
          id: 't1',
          name: '測試隊',
          members: {
            'a': CloudMember(
                name: 'A',
                rank: 1,
                role: TeamRole.leader,
                joinedAt: DateTime(2026)),
            'b': CloudMember(
                name: 'B',
                rank: 1,
                role: TeamRole.member,
                joinedAt: DateTime(2026)),
          },
        ));

    test('加分是累加，而且讀得回來', () async {
      await makeTeam();
      await as('a').addScore('t1', 'a', 30);
      await as('a').addScore('t1', 'a', 12);
      await as('b').addScore('t1', 'b', 5);

      final t = await as('a').myTeam();
      expect(t!.contributions, {'a': 42, 'b': 5},
          reason: '兩台裝置各送一次不該丟掉一次');
    });

    test('限時任務：同一天是加進去', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-09-28');
      await as('b').creditTimed('t1', 'b', '2026-09-28');

      final t = await as('a').myTeam();
      expect(t!.timedCredited, {'a', 'b'});
      expect(t.timedDay, '2026-09-28');
    });

    test('限時任務：換日是整份換掉，不是疊上去', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-09-28');
      await as('b').creditTimed('t1', 'b', '2026-09-29');

      final t = await as('a').myTeam();
      expect(t!.timedCredited, {'b'},
          reason: '清空沒有伺服器可以做，由第一個在新的一天完成的人順手做');
      expect(t.timedDay, '2026-09-29');
    });

    test('新建的隊分數從 0 起算', () async {
      await makeTeam();
      final t = await as('a').myTeam();
      expect(t!.contributions, isEmpty);
      expect(t.timedCredited, isEmpty);
      expect(t.timedDay, '');
    });
  });
}
