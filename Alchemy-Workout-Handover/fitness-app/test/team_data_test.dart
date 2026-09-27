// 團隊上雲（[BE-11] 批次 4）。
//
// 這批的重點是**人數上限**。〈團隊 Aggregate〉的 3–5 人是不變條件，
// 不是建議值 —— 而「檢查還有沒有空位」與「把人加進去」如果不是同一件事，
// 兩個人同時被核准就會擠出第六名成員，而且事後看不出是怎麼發生的。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/clock.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);

  CloudMember member(String name, {TeamRole role = TeamRole.member}) =>
      CloudMember(
        name: name,
        rank: 20,
        role: role,
        joinedAt: DateTime(2026, 9, 13),
      );

  CloudTeam team({
    String id = 't1',
    String name = '鐵人小隊',
    bool isPublic = true,
    Map<String, CloudMember>? members,
  }) =>
      CloudTeam(
        id: id,
        name: name,
        isPublic: isPublic,
        members: members ?? {'a': member('阿昶', role: TeamRole.leader)},
      );

  group('建立與查詢', () {
    test('建立之後隊長查得到自己的隊', () async {
      await as('a').create(team());

      final mine = await as('a').myTeam();
      expect(mine, isNotNull);
      expect(mine!.name, '鐵人小隊');
      expect(mine.leaderUid, 'a');
    });

    test('沒加入任何隊伍時回傳空值，不是錯誤', () async {
      expect(await as('z').myTeam(), isNull);
    });

    test('別人的隊不會被當成我的', () async {
      await as('a').create(team());
      expect(await as('z').myTeam(), isNull);
    });

    test('公開且未滿的隊伍出現在可申請清單', () async {
      await as('a').create(team());
      expect(await as('z').openTeams(), hasLength(1));
    });

    test('私密隊伍不出現在可申請清單', () async {
      await as('a').create(team(isPublic: false));
      expect(await as('z').openTeams(), isEmpty);
    });

    test('已滿的隊伍不出現 —— 申請了也進不去', () async {
      await as('a').create(team(members: {
        'a': member('一', role: TeamRole.leader),
        'b': member('二'),
        'c': member('三'),
        'd': member('四'),
        'e': member('五'),
      }));
      expect(await as('z').openTeams(), isEmpty);
    });
  });

  group('成員異動與人數上限', () {
    test('加入之後雙方都查得到同一支隊', () async {
      await as('a').create(team());
      await as('a').putMember('t1', 'b', member('小美'));

      final fromB = await as('b').myTeam();
      expect(fromB, isNotNull);
      expect(fromB!.members.keys, containsAll(['a', 'b']));
    });

    test('滿員後再加人不會生效', () async {
      // 人數上限是不變條件，不是建議值。
      await as('a').create(team(members: {
        'a': member('一', role: TeamRole.leader),
        'b': member('二'),
        'c': member('三'),
        'd': member('四'),
        'e': member('五'),
      }));
      await as('a').putMember('t1', 'f', member('六'));

      expect((await as('a').myTeam())!.members, hasLength(5));
    });

    test('已在隊上的人改角色不受上限限制', () async {
      // 轉讓隊長是「更新既有成員」，不是「加入第六人」。
      await as('a').create(team(members: {
        'a': member('一', role: TeamRole.leader),
        'b': member('二'),
        'c': member('三'),
        'd': member('四'),
        'e': member('五'),
      }));
      await as('a').putMember('t1', 'b', member('二', role: TeamRole.leader));

      final t = (await as('a').myTeam())!;
      expect(t.members, hasLength(5));
      expect(t.members['b']!.role, TeamRole.leader);
    });

    test('移除成員之後他就查不到這支隊了', () async {
      await as('a').create(team());
      await as('a').putMember('t1', 'b', member('小美'));
      await as('a').removeMember('t1', 'b');

      expect(await as('b').myTeam(), isNull);
      expect((await as('a').myTeam())!.members.keys, ['a']);
    });

    test('歷史最高人數不會因為有人退出而減少', () async {
      // peakSize 是「曾經達到過」，排行榜分組依它判定。
      await as('a').create(team());
      await as('a').putMember('t1', 'b', member('二'));
      await as('a').putMember('t1', 'c', member('三'));
      expect((await as('a').myTeam())!.peakSize, 3);

      await as('a').removeMember('t1', 'c');
      final t = (await as('a').myTeam())!;
      expect(t.members, hasLength(2));
      expect(t.peakSize, 3, reason: '現在只剩 2 人，但曾經有過 3 人');
    });
  });

  group('解散', () {
    test('解散是軟刪除 —— 文件還在', () async {
      await as('a').create(team());
      await as('a').disband('t1');

      final doc = await db.collection('teams').doc('t1').get();
      expect(doc.exists, isTrue, reason: '排行榜歷史仍要查得到這支隊伍');
      expect(doc.data()!['disbanded'], isTrue);
    });

    test('解散後就不算是我的隊了', () async {
      await as('a').create(team());
      await as('a').disband('t1');
      expect(await as('a').myTeam(), isNull);
    });

    test('解散後不出現在可申請清單', () async {
      await as('a').create(team());
      await as('a').disband('t1');
      expect(await as('z').openTeams(), isEmpty);
    });
  });

  group('邀請與申請', () {
    TeamRequest req(String uid, {required bool isInvite}) => TeamRequest(
          teamId: 't1',
          teamName: '鐵人小隊',
          uid: uid,
          name: uid == 'b' ? '小美' : '路人',
          rank: 20,
          isInvite: isInvite,
          // 相對於現在算，理由同 `mentor_data_test`。
          expiresAt: appNow().add(const Duration(days: 7)),
        );

    test('被邀請的人看得到邀請', () async {
      await as('a').create(team());
      await as('a').sendRequest(req('b', isInvite: true));

      final mine = await as('b').requestsFor('b');
      expect(mine, hasLength(1));
      expect(mine.first.isInvite, isTrue);
      expect(mine.first.teamName, '鐵人小隊');
    });

    test('隊長看得到別人的加入申請', () async {
      await as('a').create(team());
      await as('z').sendRequest(req('z', isInvite: false));

      final mine = await as('a').requestsFor('a', myTeamId: 't1');
      expect(mine, hasLength(1));
      expect(mine.first.isInvite, isFalse);
      expect(mine.first.uid, 'z');
    });

    test('同一人對同一隊只會有一筆待回應請求', () async {
      await as('a').create(team());
      await as('a').sendRequest(req('b', isInvite: true));
      await as('a').sendRequest(req('b', isInvite: true));

      final all = await db
          .collection('teams')
          .doc('t1')
          .collection('requests')
          .get();
      expect(all.docs, hasLength(1));
    });

    test('處理完之後請求就消失', () async {
      await as('a').create(team());
      await as('a').sendRequest(req('b', isInvite: true));
      await as('b').dropRequest('t1', 'b');

      expect(await as('b').requestsFor('b'), isEmpty);
    });

    test('不相干的人看不到別人的邀請', () async {
      await as('a').create(team());
      await as('a').sendRequest(req('b', isInvite: true));

      expect(await as('z').requestsFor('z'), isEmpty);
    });
  });
}
