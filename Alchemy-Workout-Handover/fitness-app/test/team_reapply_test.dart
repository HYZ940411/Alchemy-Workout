// 使用者回報：「成員退出後，重新按申請後又看不到了」。
//
// 把那串操作原樣跑一遍，而不是讀程式碼用猜的：
// B 申請 → A 核准 → B 入隊 → B 退隊 → B 重新申請 → A 應該看得到。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);

  CloudMember member(String name, {TeamRole role = TeamRole.member}) =>
      CloudMember(name: name, rank: 20, role: role, joinedAt: DateTime(2026, 9, 13));

  TeamRequest application(String uid, String name) => TeamRequest(
        teamId: 't1',
        teamName: '鐵人小隊',
        uid: uid,
        name: name,
        rank: 20,
        isInvite: false,
        expiresAt: DateTime(2027),
      );

  Future<void> setUpTeam() => as('a').create(CloudTeam(
        id: 't1',
        name: '鐵人小隊',
        isPublic: true,
        members: {'a': member('阿昶', role: TeamRole.leader)},
      ));

  test('B 申請 → A 看得到', () async {
    await setUpTeam();
    await as('b').sendRequest(application('b', '小美'));

    final seen = await as('a').requestsFor('a', myTeamId: 't1');
    expect(seen.where((r) => !r.isInvite).map((r) => r.uid), contains('b'));
  });

  test('**退隊後重新申請，A 還是看得到**', () async {
    await setUpTeam();

    // 1. B 申請
    await as('b').sendRequest(application('b', '小美'));
    // 2. A 核准：把 B 加進隊伍，並清掉那筆申請
    await as('a').putMember('t1', 'b', member('小美'));
    await as('a').dropRequest('t1', 'b');
    expect((await as('b').myTeam())?.id, 't1', reason: 'B 真的入隊了');

    // 3. B 退隊
    await as('b').removeMember('t1', 'b');
    expect(await as('b').myTeam(), isNull, reason: 'B 真的退隊了');

    // 4. B 重新申請
    await as('b').sendRequest(application('b', '小美'));

    // 5. A 應該看得到
    final seen = await as('a').requestsFor('a', myTeamId: 't1');
    expect(
      seen.where((r) => !r.isInvite).map((r) => r.uid),
      contains('b'),
      reason: '退隊後重新申請，隊長要看得到',
    );
  });

  test('核准之後那筆申請要從雲端消失 —— 否則退隊時它會自己冒出來', () async {
    await setUpTeam();
    await as('b').sendRequest(application('b', '小美'));
    await as('a').putMember('t1', 'b', member('小美'));
    await as('a').dropRequest('t1', 'b');

    final seen = await as('a').requestsFor('a', myTeamId: 't1');
    expect(seen.where((r) => !r.isInvite), isEmpty);
  });

  test('退隊之後隊伍名單上真的沒有他', () async {
    await setUpTeam();
    await as('a').putMember('t1', 'b', member('小美'));
    await as('b').removeMember('t1', 'b');

    final t = await as('a').myTeam();
    expect(t!.members.keys, isNot(contains('b')));
  });

  // 使用者回報「0 人的團隊沒有被移除」。
  //
  // 「隊長退出即解散」原本只寫在 `AppState.leaveTeamOutcome()` 裡，而它
  // 依賴 `iAmLeader` —— 那個在 2026-09-27 之前比對的是暱稱（畫面上甚至
  // 是寫死的「你」）。判成不是隊長就不會解散：成員被移光、`disbanded`
  // 仍是 false，於是一支 0 人的隊伍繼續出現在公開團隊清單裡。
  //
  // **呼叫端算錯過一次，就不能只靠呼叫端。**
  group('最後一人離開就是解散', () {
    test('移除最後一名成員時自動標記解散', () async {
      await setUpTeam();
      await as('a').removeMember('t1', 'a');

      final doc = await db.collection('teams').doc('t1').get();
      expect(doc.data()!['disbanded'], isTrue);
      expect(doc.data()!['memberUids'], isEmpty);
    });

    test('還有人在就不解散', () async {
      await setUpTeam();
      await as('a').putMember('t1', 'b', member('小美'));
      await as('b').removeMember('t1', 'b');

      final doc = await db.collection('teams').doc('t1').get();
      expect(doc.data()!['disbanded'], isFalse);
    });

    test('解散之後不再出現在公開團隊清單', () async {
      await setUpTeam();
      await as('a').removeMember('t1', 'a');
      expect(await as('b').openTeams(), isEmpty);
    });

    // 2026-09-27 之前留下的殘留：0 人但 disbanded 仍是 false。
    // 沒有任何人會去清它 —— 而申請加入一支沒有隊長的隊伍，
    // 永遠不會有人核准。
    test('**殘留的 0 人隊伍也不列出來**', () async {
      await db.collection('teams').doc('t9').set({
        'name': '空殼隊',
        'isPublic': true,
        'capacity': 5,
        'peakSize': 3,
        'disbanded': false,
        'memberUids': <String>[],
        'members': <String, dynamic>{},
      });
      expect(await as('b').openTeams(), isEmpty);
    });

    test('正常的隊伍照樣列出來 —— 不要把好的一起濾掉', () async {
      await setUpTeam();
      final open = await as('b').openTeams();
      expect(open.map((t) => t.id), contains('t1'));
    });
  });
}