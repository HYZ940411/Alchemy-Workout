// 隊長按了「同意」，雲端什麼都沒發生。
//
// 使用者回報的兩個症狀其實是同一件事的兩半：
//   · 隊長一重新整理，那筆申請又回來了 → `dropRequest()` 沒送出
//   · 申請人畫面上依然沒有隊伍，還得再申請一次 → `putMember()` 沒送出
//
// 原因是核准時要把「誰」寫回雲端，而 `PendingRequest` 只留了顯示名稱，
// uid 在 `applyCloudTeamRequests()` 轉成本機那筆時被丟掉了。呼叫端於是
// 拿名稱去公開檔案裡反查 —— **只載入 50 筆，對方不在裡面就回傳空值**，
// 然後 `if (who != null)` 把整個雲端寫入無聲跳過。畫面照樣顯示成功。
//
// uid 本來就跟著雲端資料一起來的，不該丟掉再猜回來。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  /// 隊長 B 的 AppState：已經有一支雲端上的隊，且**沒有載入任何公開檔案**
  /// —— 也就是 `uidOf('阿甲')` 必定回傳空值，這正是真實情境。
  Future<AppState> leader() async {
    final src = FirestoreTeams(uid: 'uid-b', firestore: db);
    await src.create(CloudTeam(
      id: 't1',
      name: '鐵人小隊',
      members: {
        'uid-b': CloudMember(
          name: '阿乙',
          rank: 20,
          role: TeamRole.leader,
          joinedAt: DateTime(2026, 9, 20),
        ),
      },
    ));
    final s = AppState(demo: false)
      ..displayName = '阿乙'
      ..myUid = 'uid-b'
      ..teamSource = src;
    s.applyCloudTeam(await src.myTeam());
    return s;
  }

  TeamRequest application() => TeamRequest(
        teamId: 't1',
        teamName: '鐵人小隊',
        uid: 'uid-a',
        name: '阿甲',
        rank: 12,
        isInvite: false,
        expiresAt: DateTime.now().add(const Duration(hours: 100)),
      );

  test('雲端讀來的申請保留申請人的 uid', () async {
    final s = await leader();
    s.applyCloudTeamRequests([application()]);

    expect(s.myTeam!.applications, hasLength(1));
    // 丟掉 uid 的話這裡是 null，後面兩個測試就必定失敗。
    expect(s.myTeam!.applications.first.uid, 'uid-a');
  });

  test('認不出申請人也照樣核准 —— 核准會寫進雲端的 memberUids', () async {
    final s = await leader();
    s.applyCloudTeamRequests([application()]);
    // 公開檔案一筆都沒載入：靠名稱反查必定失敗。
    expect(s.uidOf('阿甲'), isNull);

    expect(s.approveApplication(s.myTeam!.applications.first), isTrue);
    // `_pushTeam` 是即發即忘，而核准那一條裡有兩個接連的 await
    // （putMember → dropRequest），給它跑完。
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final doc = await db.collection('teams').doc('t1').get();
    expect(doc.data()!['memberUids'], contains('uid-a'));
    expect((doc.data()!['members'] as Map).containsKey('uid-a'), isTrue);
  });

  test('核准後那筆申請從雲端消失 —— 重新整理不會再跑出來', () async {
    final s = await leader();
    s.applyCloudTeamRequests([application()]);
    s.approveApplication(s.myTeam!.applications.first);
    // `_pushTeam` 是即發即忘，而核准那一條裡有兩個接連的 await
    // （putMember → dropRequest），給它跑完。
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final left = await FirestoreTeams(uid: 'uid-b', firestore: db)
        .requestsFor('uid-b', myTeamId: 't1');
    expect(left, isEmpty);
  });

  test('拒絕也一樣 —— 那筆申請要從雲端刪掉', () async {
    final s = await leader();
    s.applyCloudTeamRequests([application()]);
    s.rejectApplication(s.myTeam!.applications.first);
    // `_pushTeam` 是即發即忘，而核准那一條裡有兩個接連的 await
    // （putMember → dropRequest），給它跑完。
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final left = await FirestoreTeams(uid: 'uid-b', firestore: db)
        .requestsFor('uid-b', myTeamId: 't1');
    expect(left, isEmpty);
  });

  group('我送出的申請要從雲端讀回來', () {
    // `sentApplications` 不進存檔，重新載入就空了 —— 使用者看到的是
    // 「申請被自動取消」，其實雲端那筆還在，隊長也還看得到。

    /// 阿甲申請加入阿乙的隊，然後重新載入（＝一個全新的 AppState）。
    Future<AppState> reloadedApplicant() async {
      final asB = FirestoreTeams(uid: 'uid-b', firestore: db);
      await asB.create(CloudTeam(
        id: 't1',
        name: '鐵人小隊',
        members: {
          'uid-b': CloudMember(
            name: '阿乙',
            rank: 20,
            role: TeamRole.leader,
            joinedAt: DateTime(2026, 9, 20),
          ),
        },
      ));
      final asA = FirestoreTeams(uid: 'uid-a', firestore: db);
      await asA.sendRequest(TeamRequest(
        teamId: 't1',
        teamName: '鐵人小隊',
        uid: 'uid-a',
        name: '阿甲',
        rank: 12,
        isInvite: false,
        expiresAt: DateTime.now().add(const Duration(hours: 100)),
      ));

      final s = AppState(demo: false)
        ..displayName = '阿甲'
        ..myUid = 'uid-a'
        ..teamSource = asA;
      s.applyCloudTeam(await asA.myTeam()); // 沒有隊
      s.applyCloudTeamRequests(await asA.requestsFor('uid-a'));
      return s;
    }

    test('重新載入之後申請還在，不會像是被自動取消', () async {
      final s = await reloadedApplicant();
      expect(s.sentApplications, hasLength(1));
      expect(s.sentApplications.single.name, '鐵人小隊');
      // 撤回要用它，靠隊名反查在隊伍額滿時會失敗。
      expect(s.sentApplications.single.teamId, 't1');
    });

    test('隊長拒絕之後，重新載入那筆申請就不見了', () async {
      final s = await reloadedApplicant();
      await FirestoreTeams(uid: 'uid-b', firestore: db)
          .dropRequest('t1', 'uid-a');

      final asA = FirestoreTeams(uid: 'uid-a', firestore: db);
      s.applyCloudTeamRequests(await asA.requestsFor('uid-a'));
      expect(s.sentApplications, isEmpty);
    });

    test('撤回會把雲端那筆刪掉 —— 即使該隊已經不在公開清單裡', () async {
      final s = await reloadedApplicant();
      expect(s.publicTeams, isEmpty); // 反查必定失敗

      s.withdrawApplication('鐵人小隊');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final left = await FirestoreTeams(uid: 'uid-b', firestore: db)
          .requestsFor('uid-b', myTeamId: 't1');
      expect(left, isEmpty);
    });
  });

  test('雲端說我已經在隊上，本機那筆「已送出的申請」就該消失', () async {
    final s = AppState(demo: false)
      ..displayName = '阿甲'
      ..myUid = 'uid-a';
    s.sentApplications.add(PendingRequest(
        '鐵人小隊', 20, DateTime.now().add(const Duration(hours: 100))));

    s.applyCloudTeam(CloudTeam(
      id: 't1',
      name: '鐵人小隊',
      members: {
        'uid-a': CloudMember(
          name: '阿甲',
          rank: 12,
          role: TeamRole.member,
          joinedAt: DateTime(2026, 9, 21),
        ),
      },
    ));

    // 留著的話畫面會同時顯示「已加入」和「等隊長回應」。
    expect(s.sentApplications, isEmpty);
    expect(s.myTeam!.name, '鐵人小隊');
    // 成員也要帶著 uid，否則踢人與轉讓隊長會重蹈覆轍。
    expect(s.myTeam!.members.single.uid, 'uid-a');
  });
}
