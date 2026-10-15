// T11：隊長在「這次登入之後」才建隊，別人申請加入時他看不到。
//
// 即時訂閱「別人申請加入我的隊」需要知道是哪一隊（`watchTeams(myTeamId:)`），
// 而 `startCloudWatch()` 只在登入同步結束時叫一次 —— 那時他還沒有隊，
// 於是訂閱裡那一條根本沒掛上。之後不論是自己建隊或是被核准入隊，
// 這條訂閱都不會補上，申請送進雲端也沒有訊號，要登出再登入才看得到。
//
// 既有的測試都是「先有隊、再載入」，所以全綠。這支測的是真實順序：
// 先登入 → 才建隊 → 對方申請。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  /// 等訂閱訊號 → 去抖（400ms）→ 重讀跑完。
  Future<void> settle() => Future<void>.delayed(const Duration(seconds: 1));

  TeamRequest applicationTo(String teamId) => TeamRequest(
        teamId: teamId,
        teamName: '鐵人小隊',
        uid: 'uid-b',
        name: '阿乙',
        rank: 12,
        isInvite: false,
        expiresAt: DateTime.now().add(const Duration(hours: 100)),
      );

  /// 阿甲先登入（還沒有隊、掛上訂閱），然後才建隊。
  Future<AppState> leaderWhoCreatesTeamAfterLogin() async {
    final src = FirestoreTeams(uid: 'uid-a', firestore: db);
    final s = AppState(demo: false)
      ..displayName = '阿甲'
      ..myUid = 'uid-a'
      ..teamSource = src;
    s.applyCloudTeam(await src.myTeam()); // 沒有隊
    s.startCloudWatch(); // 登入同步的最後一步
    expect(s.myTeam, isNull);

    expect(s.createTeam('鐵人小隊'), isTrue);
    await settle(); // 建隊寫進雲端
    return s;
  }

  test('登入後才建隊 —— 別人的申請隊長要看得到', () async {
    final a = await leaderWhoCreatesTeamAfterLogin();
    addTearDown(a.stopCloudWatch);

    await FirestoreTeams(uid: 'uid-b', firestore: db)
        .sendRequest(applicationTo(a.myTeam!.id));
    await settle();

    expect(a.myTeam!.applications.map((x) => x.name), ['阿乙'],
        reason: '建隊之後沒有重新掛上「我這一隊的申請」那條訂閱');
  });

  test('被核准入隊（隊是別人建的）也一樣 —— 補掛訂閱後新的申請看得到', () async {
    final src = FirestoreTeams(uid: 'uid-a', firestore: db);
    final a = AppState(demo: false)
      ..displayName = '阿甲'
      ..myUid = 'uid-a'
      ..teamSource = src;
    a.applyCloudTeam(await src.myTeam());
    a.startCloudWatch();
    addTearDown(a.stopCloudWatch);

    // 在雲端憑空出現一支以阿甲為隊長的隊（例如在另一台裝置建的）。
    await src.create(CloudTeam(
      id: 't-remote',
      name: '鐵人小隊',
      members: {
        'uid-a': CloudMember(
          name: '阿甲',
          rank: 20,
          role: TeamRole.leader,
          joinedAt: DateTime(2026, 9, 20),
        ),
      },
    ));
    await settle();
    expect(a.myTeam?.id, 't-remote');

    await FirestoreTeams(uid: 'uid-b', firestore: db)
        .sendRequest(applicationTo('t-remote'));
    await settle();
    expect(a.myTeam!.applications.map((x) => x.name), ['阿乙']);
  });
}
